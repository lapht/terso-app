// SPDX-License-Identifier: GPL-3.0-or-later
//
// Terso — The Auditable Mac Cleaner
// Copyright (C) 2026 Terso Contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import Foundation

/// Finds byte-identical files under user-chosen folders. Read-only.
///
/// Candidates are narrowed by size, then by a SHA-256 of their first bytes,
/// and only then compared by a full streaming SHA-256. Hard links are
/// collapsed, APFS clones are marked, symlinks and package contents are not
/// traversed, and cloud files that are not downloaded are skipped and counted.
/// This type has no deletion capability; acting on duplicates is out of scope
/// for v0.2 (see docs/design.md §11.5).
public struct DuplicateFinder: Sendable {
    public static let defaultPartialHashByteCount = 64 * 1_024
    public static let defaultReadChunkSize = 1_024 * 1_024

    public let id = "files.duplicates"
    public let title = "Duplicates"

    private let partialHashByteCount: Int64
    private let reader: DuplicateFileReader

    public init(
        partialHashByteCount: Int = defaultPartialHashByteCount,
        readChunkSize: Int = defaultReadChunkSize
    ) {
        self.init(
            partialHashByteCount: partialHashByteCount,
            reader: DuplicateFileReader(readChunkSize: readChunkSize)
        )
    }

    init(partialHashByteCount: Int, reader: DuplicateFileReader) {
        self.partialHashByteCount = Int64(max(partialHashByteCount, 1))
        self.reader = DuplicateFileReader(readChunkSize: max(reader.readChunkSize, 1), status: reader.status)
    }

    /// Scans `roots` for duplicate files.
    ///
    /// Cancelling the surrounding task stops the scan and returns the groups
    /// that were fully compared so far, with ``DuplicateScanResult/isCancelled`` set.
    /// - Throws: ``DuplicateScanError`` when no roots are given or a root is
    ///   not a real (non-symlink, non-package) directory.
    public func scan(
        roots: [URL],
        progress: (@Sendable (DuplicateScanProgress) -> Void)? = nil
    ) async throws -> DuplicateScanResult {
        let validatedRoots = try validate(roots)
        var state = ScanState()

        for root in validatedRoots where !state.isCancelled {
            collectCandidates(under: root, into: &state, progress: progress)
        }

        let buckets = Dictionary(grouping: state.candidates, by: \.status.sizeBytes)
            .filter { $0.value.count > 1 }
            .sorted { $0.key < $1.key }
        let totalToHash = buckets.reduce(0) { $0 + $1.value.count }
        var hashed = 0

        for (size, bucket) in buckets {
            if state.isCancelled || Task.isCancelled {
                state.isCancelled = true
                break
            }
            do {
                let groups = try duplicateGroups(in: bucket, sizeBytes: size, state: &state)
                state.groups.append(contentsOf: groups)
            } catch {
                state.isCancelled = true
                break
            }
            hashed += bucket.count
            progress?(DuplicateScanProgress(phase: .hashing, completedFiles: hashed, totalFiles: totalToHash))
        }

        return state.result()
    }

    // MARK: - Enumeration

    private func validate(_ roots: [URL]) throws -> [URL] {
        guard !roots.isEmpty else {
            throw DuplicateScanError.noRoots
        }
        return try roots.map { root in
            let url = root.standardizedFileURL
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
            } catch {
                throw DuplicateScanError.invalidRoot(url.path, error.localizedDescription)
            }
            guard values.isSymbolicLink != true else {
                throw DuplicateScanError.invalidRoot(url.path, "Symbolic links are not followed.")
            }
            guard values.isDirectory == true else {
                throw DuplicateScanError.invalidRoot(url.path, "Not a folder.")
            }
            guard values.isPackage != true else {
                throw DuplicateScanError.invalidRoot(url.path, "Package contents are not scanned.")
            }
            return url
        }
    }

    private func collectCandidates(
        under root: URL,
        into state: inout ScanState,
        progress: (@Sendable (DuplicateScanProgress) -> Void)?
    ) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        var enumerationIssues: [DuplicateScanIssue] = []
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { failedURL, error in
                enumerationIssues.append(DuplicateScanIssue(path: failedURL.path, message: error.localizedDescription))
                return true
            }
        )
        guard let enumerator else {
            state.issues.append(DuplicateScanIssue(path: root.path, message: "Unable to enumerate the folder."))
            return
        }

        while let enumeratedURL = enumerator.nextObject() as? URL {
            let fileURL = URL(fileURLWithPath: enumeratedURL.path)
            if Task.isCancelled {
                state.isCancelled = true
                break
            }
            let values: URLResourceValues
            do {
                values = try fileURL.resourceValues(forKeys: Set(keys))
            } catch {
                state.issues.append(DuplicateScanIssue(path: fileURL.path, message: error.localizedDescription))
                continue
            }
            if values.isSymbolicLink == true {
                continue
            }
            if values.isDirectory == true {
                if values.isPackage == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else {
                continue
            }
            let examinedBefore = state.examinedFileCount
            consider(fileURL, into: &state)
            if state.examinedFileCount != examinedBefore, state.examinedFileCount % 500 == 0 {
                progress?(DuplicateScanProgress(
                    phase: .enumerating,
                    completedFiles: state.examinedFileCount,
                    totalFiles: nil
                ))
            }
        }
        state.issues.append(contentsOf: enumerationIssues)
    }

    private func consider(_ fileURL: URL, into state: inout ScanState) {
        let status: DuplicateFileStatus
        do {
            status = try reader.status(fileURL)
        } catch {
            state.issues.append(DuplicateScanIssue(path: fileURL.path, message: Self.message(for: error)))
            return
        }
        guard status.isRegularFile else {
            return
        }
        let inode = InodeKey(device: status.device, inode: status.inode)
        guard state.seenInodes.insert(inode).inserted else {
            return
        }
        if status.isDataless {
            state.skippedDatalessFileCount += 1
            return
        }
        state.examinedFileCount += 1
        guard status.sizeBytes > 0 else {
            return
        }
        state.candidates.append(Candidate(url: fileURL, status: status))
    }

    // MARK: - Comparison

    private func duplicateGroups(
        in bucket: [Candidate],
        sizeBytes: Int64,
        state: inout ScanState
    ) throws -> [DuplicateGroup] {
        let partiallyHashed = try hashAll(bucket, limit: partialHashByteCount, state: &state)
        var groups: [DuplicateGroup] = []
        for sameStart in Self.matching(partiallyHashed) {
            let fullyHashed: [(Candidate, String)]
            if sizeBytes <= partialHashByteCount {
                fullyHashed = sameStart
            } else {
                fullyHashed = try hashAll(sameStart.map(\.0), limit: nil, state: &state)
            }
            for identical in Self.matching(fullyHashed) {
                groups.append(Self.makeGroup(identical, sizeBytes: sizeBytes))
            }
        }
        return groups
    }

    private func hashAll(
        _ candidates: [Candidate],
        limit: Int64?,
        state: inout ScanState
    ) throws -> [(Candidate, String)] {
        var hashed: [(Candidate, String)] = []
        for candidate in candidates {
            do {
                hashed.append((candidate, try reader.hash(of: candidate.url, expected: candidate.status, limit: limit)))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                state.issues.append(DuplicateScanIssue(path: candidate.url.path, message: Self.message(for: error)))
            }
        }
        return hashed
    }

    private static func matching(_ hashed: [(Candidate, String)]) -> [[(Candidate, String)]] {
        Dictionary(grouping: hashed, by: \.1)
            .values
            .filter { $0.count > 1 }
            .map { $0.sorted { $0.0.url.path < $1.0.url.path } }
    }

    private static func makeGroup(_ identical: [(Candidate, String)], sizeBytes: Int64) -> DuplicateGroup {
        var seenClones = Set<UInt64>()
        let files = identical.map { candidate, _ in
            let cloneID = DuplicateFileReader.cloneIdentifier(of: candidate.url)
            let isClone = cloneID.map { !seenClones.insert($0).inserted } ?? false
            return DuplicateFile(url: candidate.url, isClone: isClone)
        }
        return DuplicateGroup(contentHash: identical[0].1, fileSizeBytes: sizeBytes, files: files)
    }

    private static func message(for error: Error) -> String {
        (error as? DuplicateReadError)?.message ?? error.localizedDescription
    }
}

/// Invalid duplicate-scan input.
public enum DuplicateScanError: LocalizedError, Equatable {
    case noRoots
    case invalidRoot(String, String)

    public var errorDescription: String? {
        switch self {
        case .noRoots:
            "Choose at least one folder to scan for duplicates."
        case let .invalidRoot(path, reason):
            "Cannot scan \(path) for duplicates: \(reason)"
        }
    }
}

private struct InodeKey: Hashable {
    let device: Int64
    let inode: UInt64
}

private struct Candidate {
    let url: URL
    let status: DuplicateFileStatus
}

private struct ScanState {
    var candidates: [Candidate] = []
    var seenInodes = Set<InodeKey>()
    var groups: [DuplicateGroup] = []
    var issues: [DuplicateScanIssue] = []
    var examinedFileCount = 0
    var skippedDatalessFileCount = 0
    var isCancelled = false

    func result() -> DuplicateScanResult {
        DuplicateScanResult(
            groups: groups.sorted {
                ($0.reclaimableBytes, $1.contentHash) > ($1.reclaimableBytes, $0.contentHash)
            },
            examinedFileCount: examinedFileCount,
            skippedDatalessFileCount: skippedDatalessFileCount,
            issues: issues,
            isCancelled: isCancelled
        )
    }
}
