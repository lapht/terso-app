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

import CoreKit
import Foundation

/// Read-only duplicate detection behind the Duplicates page.
protocol DuplicateScanning: Sendable {
    func scan(roots: [URL]) async throws -> DuplicateScanResult
}

extension DuplicateFinder: DuplicateScanning {
    func scan(roots: [URL]) async throws -> DuplicateScanResult {
        try await scan(roots: roots, progress: nil)
    }
}

/// One copy in a duplicate group, with the metadata the page shows for it.
/// A nil `modificationDate` means the file could not be read after the scan (moved or removed).
struct DuplicateCopy: Identifiable, Equatable, Sendable {
    let url: URL
    let sizeBytes: Int64
    let isClone: Bool
    let modificationDate: Date?

    var id: String { url.path }
}

/// A group as the page shows it, derived from `DuplicateGroup` without changing its paths or byte counts.
struct DuplicateGroupRow: Identifiable, Equatable, Sendable {
    let id: String
    let fileSizeBytes: Int64
    let reclaimableBytes: Int64
    let copies: [DuplicateCopy]

    var copyCount: Int { copies.count }
}

/// Everything a finished duplicate scan shows, including what it could not cover.
struct DuplicateScanSummary: Equatable, Sendable {
    var groups: [DuplicateGroupRow] = []
    var examinedFileCount = 0
    var skippedDatalessFileCount = 0
    var issues: [DuplicateScanIssue] = []
    var isCancelled = false

    var totalReclaimableBytes: Int64 {
        groups.reduce(0) { $0 + $1.reclaimableBytes }
    }

    var isPartial: Bool { isCancelled || !issues.isEmpty }
}

/// Runs a duplicate scan on the chosen folders only when asked. There is no selection state:
/// the page lists and reveals, nothing else (design.md §11.5).
@MainActor
final class DuplicatesViewModel: ObservableObject {
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var roots: [URL] = []
    @Published private(set) var summary = DuplicateScanSummary()

    let homeDirectory: URL
    private let scanner: any DuplicateScanning
    private let modificationDate: @Sendable (URL) -> Date?
    private var scanTask: Task<Void, Never>?

    init(
        scanner: any DuplicateScanning = DuplicateFinder(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        modificationDate: @escaping @Sendable (URL) -> Date? = DuplicatesViewModel.fileModificationDate
    ) {
        self.scanner = scanner
        self.homeDirectory = homeDirectory
        self.modificationDate = modificationDate
    }

    var canScan: Bool { !roots.isEmpty && scanTask == nil }

    func addRoots(_ urls: [URL]) {
        for url in urls.map(\.standardizedFileURL) where !roots.contains(url) {
            roots.append(url)
        }
    }

    func removeRoot(_ url: URL) {
        roots.removeAll { $0 == url }
    }

    /// Returns to the folder choice, keeping the chosen folders.
    func chooseFoldersAgain() {
        guard scanTask == nil else {
            return
        }
        summary = DuplicateScanSummary()
        phase = .idle
    }

    func startScan() {
        guard canScan else {
            return
        }
        summary = DuplicateScanSummary()
        phase = .scanning

        let scanner = self.scanner
        let roots = self.roots
        let modificationDate = self.modificationDate
        scanTask = Task { [weak self] in
            let outcome: ScanPhase
            var found = DuplicateScanSummary()
            do {
                let result = try await scanner.scan(roots: roots)
                // Reading modification dates touches the disk: keep it off the main actor.
                found = await Task.detached {
                    Self.summary(of: result, modificationDate: modificationDate)
                }.value
                outcome = .finished
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            guard let self else {
                return
            }
            self.summary = found
            self.phase = outcome
            self.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    nonisolated static func summary(
        of result: DuplicateScanResult,
        modificationDate: (URL) -> Date?
    ) -> DuplicateScanSummary {
        let groups = result.groups.map { group in
            DuplicateGroupRow(
                id: group.id,
                fileSizeBytes: group.fileSizeBytes,
                reclaimableBytes: group.reclaimableBytes,
                copies: group.files.map {
                    DuplicateCopy(
                        url: $0.url,
                        sizeBytes: group.fileSizeBytes,
                        isClone: $0.isClone,
                        modificationDate: modificationDate($0.url)
                    )
                }
            )
        }
        return DuplicateScanSummary(
            groups: groups,
            examinedFileCount: result.examinedFileCount,
            skippedDatalessFileCount: result.skippedDatalessFileCount,
            issues: result.issues,
            isCancelled: result.isCancelled
        )
    }

    nonisolated static func fileModificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
