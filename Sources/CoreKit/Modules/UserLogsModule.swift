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

import Darwin
import Foundation

/// Finds old, rotated user logs without following symbolic links.
public struct UserLogsModule: CleanModule {
    public static let defaultMinAgeSeconds: TimeInterval = 24 * 60 * 60

    public let id = "logs.user"
    public let title = "User Logs"
    public let requiresFDA = false

    private let minAgeSeconds: TimeInterval
    private let now: @Sendable () -> Date
    private let writableOpenPaths: @Sendable ([URL]) throws -> Set<String>

    public init(minAgeSeconds: TimeInterval = defaultMinAgeSeconds) {
        self.init(
            minAgeSeconds: minAgeSeconds,
            now: Date.init,
            writableOpenPaths: Self.findWritableOpenPaths
        )
    }

    init(
        minAgeSeconds: TimeInterval,
        now: @escaping @Sendable () -> Date,
        writableOpenPaths: @escaping @Sendable ([URL]) throws -> Set<String>
    ) {
        self.minAgeSeconds = minAgeSeconds
        self.now = now
        self.writableOpenPaths = writableOpenPaths
    }

    public func scan(context: ScanContext) async throws -> [CleanItem] {
        guard minAgeSeconds.isFinite, minAgeSeconds >= 0 else {
            throw UserLogsScanFailure.invalidMinimumAge(minAgeSeconds)
        }

        let logsRoot = context.homeDirectory
            .appendingPathComponent("Library/Logs", isDirectory: true)
            .standardizedFileURL
        let rootValues: URLResourceValues
        do {
            rootValues = try logsRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        guard rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              logsRoot.resolvingSymlinksInPath().standardizedFileURL.path == logsRoot.path else {
            return []
        }

        let candidates = try findCandidates(under: logsRoot)
        let writablePaths = try writableOpenPaths(candidates.map(\.url))
        let scanDate = now()

        return try candidates.compactMap { candidate in
            guard !writablePaths.contains(candidate.url.path),
                  scanDate.timeIntervalSince(candidate.modificationDate) >= minAgeSeconds else {
                return nil
            }

            let size = try SizeCalculator().calculate(at: candidate.url)
            guard size.errors.isEmpty else {
                throw UserLogsScanFailure.incompleteSize(
                    path: candidate.url.path,
                    errors: size.errors.map(\.message)
                )
            }

            return CleanItem(
                url: candidate.url,
                resolvedURL: candidate.url,
                sizeBytes: size.bytes,
                moduleId: id,
                ruleId: id
            )
        }
    }

    private func findCandidates(under logsRoot: URL) throws -> [LogCandidate] {
        var enumerationErrors: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: logsRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { failedURL, error in
                enumerationErrors.append("\(failedURL.path): \(error.localizedDescription)")
                return true
            }
        )
        guard let enumerator else {
            throw UserLogsScanFailure.cannotEnumerate(logsRoot.path)
        }

        var candidates: [LogCandidate] = []
        while let fileURL = enumerator.nextObject() as? URL {
            do {
                let values = try fileURL.resourceValues(
                    forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
                )
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                guard values.isRegularFile == true,
                      Self.matchesLogPattern(fileURL.lastPathComponent) else {
                    continue
                }

                let resolvedURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
                guard Self.isDescendant(resolvedURL, of: logsRoot),
                      resolvedURL.path == fileURL.standardizedFileURL.path else {
                    continue
                }

                let attributes = try FileManager.default.attributesOfItem(atPath: resolvedURL.path)
                guard let modificationDate = attributes[.modificationDate] as? Date else {
                    throw UserLogsScanFailure.missingModificationDate(resolvedURL.path)
                }
                candidates.append(LogCandidate(url: resolvedURL, modificationDate: modificationDate))
            } catch let failure as UserLogsScanFailure {
                throw failure
            } catch {
                throw UserLogsScanFailure.cannotInspect(fileURL.path, error.localizedDescription)
            }
        }

        guard enumerationErrors.isEmpty else {
            throw UserLogsScanFailure.enumerationFailed(logsRoot.path, enumerationErrors)
        }
        return candidates.sorted { $0.url.path < $1.url.path }
    }

    private static func matchesLogPattern(_ name: String) -> Bool {
        if name.hasSuffix(".log.gz") || name.hasSuffix(".crash") || name.hasSuffix(".diag") {
            return true
        }
        guard let suffixRange = name.range(of: ".log.", options: .backwards) else {
            return false
        }
        let sequence = name[suffixRange.upperBound...]
        return !sequence.isEmpty && sequence.allSatisfy(\.isASCII) && sequence.allSatisfy(\.isNumber)
    }

    private static func isDescendant(_ url: URL, of root: URL) -> Bool {
        let pathComponents = url.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        return pathComponents.count > rootComponents.count
            && zip(pathComponents, rootComponents).allSatisfy { $0 == $1 }
    }

    private static func findWritableOpenPaths(_ urls: [URL]) throws -> Set<String> {
        guard !urls.isEmpty else {
            return []
        }

        let candidatePaths = try Set(urls.map { try canonicalPath($0.path) })
        var writablePaths: Set<String> = []
        for batch in batches(of: urls.map(\.path)) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-nP", "-F0pafn"] + batch
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.standardError

            do {
                try process.run()
            } catch {
                throw UserLogsScanFailure.openFileInspection(error.localizedDescription)
            }

            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
                throw UserLogsScanFailure.openFileInspection(
                    "lsof exited with status \(process.terminationStatus)"
                )
            }
            let batchWritablePaths = try parseWritablePaths(outputData)
            writablePaths.formUnion(batchWritablePaths.intersection(candidatePaths))
        }
        return writablePaths
    }

    private static func canonicalPath(_ path: String) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard path.withCString({ realpath($0, &buffer) }) != nil else {
            throw UserLogsScanFailure.openFileInspection(
                "unable to resolve \(path): \(String(cString: strerror(errno)))"
            )
        }
        let pathBytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let resolvedPath = String(bytes: pathBytes, encoding: .utf8) else {
            throw UserLogsScanFailure.openFileInspection("realpath returned invalid UTF-8")
        }
        return resolvedPath
    }

    private static func batches(of paths: [String]) -> [[String]] {
        var batches: [[String]] = []
        var batch: [String] = []
        var byteCount = 0
        for path in paths {
            let pathByteCount = path.utf8.count + 1
            if byteCount + pathByteCount > 64 * 1024, !batch.isEmpty {
                batches.append(batch)
                batch = []
                byteCount = 0
            }
            batch.append(path)
            byteCount += pathByteCount
        }
        if !batch.isEmpty {
            batches.append(batch)
        }
        return batches
    }

    private static func parseWritablePaths(_ data: Data) throws -> Set<String> {
        var writablePaths: Set<String> = []
        var accessMode = ""
        for field in data.split(separator: 0) {
            guard let decodedField = String(data: Data(field), encoding: .utf8) else {
                throw UserLogsScanFailure.openFileInspection("lsof returned invalid UTF-8")
            }
            let value = decodedField.trimmingCharacters(in: .newlines)
            guard let key = value.first else {
                continue
            }
            let fieldValue = String(value.dropFirst())
            switch key {
            case "f":
                accessMode = ""
            case "a":
                accessMode = fieldValue
            case "n" where accessMode.contains("w") || accessMode.contains("u"):
                writablePaths.insert(try canonicalPath(fieldValue))
            default:
                continue
            }
        }
        return writablePaths
    }
}

private struct LogCandidate {
    let url: URL
    let modificationDate: Date
}

private enum UserLogsScanFailure: LocalizedError {
    case invalidMinimumAge(TimeInterval)
    case cannotEnumerate(String)
    case enumerationFailed(String, [String])
    case cannotInspect(String, String)
    case missingModificationDate(String)
    case incompleteSize(path: String, errors: [String])
    case openFileInspection(String)

    var errorDescription: String? {
        switch self {
        case let .invalidMinimumAge(seconds):
            "Minimum log age must be a finite, non-negative number of seconds; got \(seconds)."
        case let .cannotEnumerate(path):
            "Unable to enumerate user logs at \(path)."
        case let .enumerationFailed(path, errors):
            "Unable to completely enumerate user logs at \(path): \(errors.joined(separator: "; "))."
        case let .cannotInspect(path, message):
            "Unable to inspect user log at \(path): \(message)."
        case let .missingModificationDate(path):
            "Unable to determine the modification date for user log at \(path)."
        case let .incompleteSize(path, errors):
            "Unable to calculate the complete size of \(path): \(errors.joined(separator: "; "))."
        case let .openFileInspection(message):
            "Unable to check for user logs currently open for writing: \(message)."
        }
    }
}
