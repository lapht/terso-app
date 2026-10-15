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

/// Finds large regular files in the user's home directory without offering deletion.
public struct LargeFilesModule: CleanModule {
    public static let defaultMinimumSizeBytes: Int64 = 100 * 1_024 * 1_024

    private static let excludedSystemRoots = ["/System", "/Library", "/private"]

    public let id = "files.large"
    public let title = "Large Files"
    public let requiresFDA = false

    private let minimumSizeBytes: Int64

    public init(minimumSizeBytes: Int64 = defaultMinimumSizeBytes) {
        self.minimumSizeBytes = minimumSizeBytes
    }

    public func scan(context: ScanContext) async throws -> [CleanItem] {
        guard minimumSizeBytes >= 0 else {
            throw LargeFilesScanFailure.invalidMinimumSize(minimumSizeBytes)
        }

        let home = context.homeDirectory.standardizedFileURL
        guard !Self.isSystemPath(home) else {
            throw LargeFilesScanFailure.systemDirectory(home.path)
        }

        let homeValues: URLResourceValues
        do {
            homeValues = try home.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        } catch {
            throw LargeFilesScanFailure.cannotInspect(home.path, error.localizedDescription)
        }

        guard homeValues.isDirectory == true, homeValues.isSymbolicLink != true else {
            throw LargeFilesScanFailure.invalidHomeDirectory(home.path)
        }

        let resolvedHome = home.resolvingSymlinksInPath().standardizedFileURL
        let candidates = try findCandidates(under: home, resolvedHome: resolvedHome)
        return try candidates.compactMap { fileURL in
            let size = try SizeCalculator().calculate(at: fileURL)
            guard size.errors.isEmpty else {
                throw LargeFilesScanFailure.incompleteSize(
                    path: fileURL.path,
                    errors: size.errors.map(\.message)
                )
            }
            guard size.bytes > minimumSizeBytes else {
                return nil
            }

            return CleanItem(
                url: fileURL,
                resolvedURL: fileURL,
                sizeBytes: size.bytes,
                moduleId: id,
                ruleId: id,
                isDeletable: false,
                recommendedAction: .revealInFinder
            )
        }
    }

    private func findCandidates(under home: URL, resolvedHome: URL) throws -> [URL] {
        var enumerationErrors: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: home,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { failedURL, error in
                enumerationErrors.append("\(failedURL.path): \(error.localizedDescription)")
                return true
            }
        )
        guard let enumerator else {
            throw LargeFilesScanFailure.cannotEnumerate(home.path)
        }

        var files: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let values: URLResourceValues
            do {
                values = try fileURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
                )
            } catch {
                throw LargeFilesScanFailure.cannotInspect(fileURL.path, error.localizedDescription)
            }

            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else {
                continue
            }

            let resolvedURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
            guard Self.isDescendant(resolvedURL, of: resolvedHome),
                  resolvedURL.path == fileURL.standardizedFileURL.path,
                  !Self.isSystemPath(fileURL) else {
                continue
            }
            files.append(resolvedURL)
        }

        guard enumerationErrors.isEmpty else {
            throw LargeFilesScanFailure.enumerationFailed(home.path, enumerationErrors)
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func isSystemPath(_ url: URL) -> Bool {
        let pathComponents = url.standardizedFileURL.pathComponents
        return excludedSystemRoots.contains { root in
            let rootComponents = URL(fileURLWithPath: root).pathComponents
            return pathComponents.count >= rootComponents.count
                && zip(pathComponents, rootComponents).allSatisfy { $0 == $1 }
        }
    }

    private static func isDescendant(_ url: URL, of root: URL) -> Bool {
        let pathComponents = url.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        return pathComponents.count > rootComponents.count
            && zip(pathComponents, rootComponents).allSatisfy { $0 == $1 }
    }
}

private enum LargeFilesScanFailure: LocalizedError {
    case invalidMinimumSize(Int64)
    case systemDirectory(String)
    case invalidHomeDirectory(String)
    case cannotEnumerate(String)
    case cannotInspect(String, String)
    case enumerationFailed(String, [String])
    case incompleteSize(path: String, errors: [String])

    var errorDescription: String? {
        switch self {
        case let .invalidMinimumSize(size):
            "The minimum file size cannot be negative: \(size)."
        case let .systemDirectory(path):
            "Refusing to scan a system directory: \(path)."
        case let .invalidHomeDirectory(path):
            "The scan root is not a non-symbolic-link directory: \(path)."
        case let .cannotEnumerate(path):
            "Unable to enumerate the user's home directory at \(path)."
        case let .cannotInspect(path, message):
            "Unable to inspect \(path): \(message)"
        case let .enumerationFailed(path, errors):
            "Unable to completely enumerate \(path): \(errors.joined(separator: "; "))"
        case let .incompleteSize(path, errors):
            "Unable to calculate the complete size of \(path): \(errors.joined(separator: "; "))"
        }
    }
}
