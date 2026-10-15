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

/// Finds items in the user's Trash on the startup disk and mounted volumes.
public struct TrashBinsModule: CleanModule {
    public let id = "trash.user"
    public let title = "Trash Bins"
    public let requiresFDA = false

    private let userID: String

    public init() {
        userID = String(getuid())
    }

    init(userID: String) {
        self.userID = userID
    }

    public func scan(context: ScanContext) async throws -> [CleanItem] {
        let homeTrash = context.homeDirectory
            .appendingPathComponent(".Trash", isDirectory: true)
            .standardizedFileURL
        var trashRoots = [homeTrash]

        for volume in context.mountedVolumes where Self.isExternalVolumeMount(volume.mountPath) {
            let volumeTrash = volume.mountPath
                .appendingPathComponent(".Trashes", isDirectory: true)
                .appendingPathComponent(userID, isDirectory: true)
                .standardizedFileURL
            trashRoots.append(volumeTrash)
        }

        var items: [CleanItem] = []
        for trashRoot in trashRoots {
            guard try isSafeDirectory(trashRoot) else {
                continue
            }
            items.append(contentsOf: try findItems(in: trashRoot))
        }
        return items.sorted { $0.url.path < $1.url.path }
    }

    private func findItems(in trashRoot: URL) throws -> [CleanItem] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: trashRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        return try entries.compactMap { entry in
            let values = try entry.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true,
                  values.isDirectory == true || values.isRegularFile == true else {
                return nil
            }

            let resolvedURL = entry.resolvingSymlinksInPath().standardizedFileURL
            guard resolvedURL.path == entry.standardizedFileURL.path,
                  resolvedURL.deletingLastPathComponent().path == trashRoot.path else {
                return nil
            }

            let size = try SizeCalculator().calculate(at: resolvedURL)
            guard size.errors.isEmpty else {
                throw TrashBinsScanFailure.incompleteSize(
                    path: resolvedURL.path,
                    errors: size.errors.map(\.message)
                )
            }

            return CleanItem(
                url: entry,
                resolvedURL: resolvedURL,
                sizeBytes: size.bytes,
                moduleId: id,
                ruleId: id
            )
        }
    }

    private func isSafeDirectory(_ url: URL) throws -> Bool {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return false
        }
        return values.isDirectory == true
            && values.isSymbolicLink != true
            && url.resolvingSymlinksInPath().standardizedFileURL.path == url.path
    }

    private static func isExternalVolumeMount(_ mountPath: URL) -> Bool {
        let standardizedPath = mountPath.standardizedFileURL
        return standardizedPath.deletingLastPathComponent().lastPathComponent == "Volumes"
            && standardizedPath.lastPathComponent != "Volumes"
    }
}

private enum TrashBinsScanFailure: LocalizedError {
    case incompleteSize(path: String, errors: [String])

    var errorDescription: String? {
        switch self {
        case let .incompleteSize(path, errors):
            "Unable to calculate the complete size of \(path): \(errors.joined(separator: "; "))"
        }
    }
}
