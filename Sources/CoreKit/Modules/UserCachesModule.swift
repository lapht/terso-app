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

import AppKit
import Foundation

/// Finds user cache directories, excluding caches for running applications.
public struct UserCachesModule: CleanModule {
    public let id = "caches.user"
    public let title = "User Caches"
    public let requiresFDA = false

    private let runningBundleIdentifiers: @Sendable () async -> Set<String>

    public init() {
        runningBundleIdentifiers = {
            await MainActor.run {
                Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            }
        }
    }

    init(runningBundleIdentifiers: @escaping @Sendable () async -> Set<String>) {
        self.runningBundleIdentifiers = runningBundleIdentifiers
    }

    public func scan(context: ScanContext) async throws -> [CleanItem] {
        let cachesRoot = context.homeDirectory
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .standardizedFileURL
        let rootValues = try cachesRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              cachesRoot.resolvingSymlinksInPath().standardizedFileURL.path == cachesRoot.path else {
            return []
        }

        let runningIDs = await runningBundleIdentifiers()
        let cacheDirectories = try FileManager.default.contentsOfDirectory(
            at: cachesRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )

        return try cacheDirectories.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { cacheURL in
            guard !runningIDs.contains(cacheURL.lastPathComponent) else {
                return nil
            }

            let values = try cacheURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true,
                  values.isSymbolicLink != true else {
                return nil
            }

            let resolvedURL = cacheURL.resolvingSymlinksInPath().standardizedFileURL
            guard resolvedURL.path == cacheURL.standardizedFileURL.path,
                  resolvedURL.deletingLastPathComponent().path == cachesRoot.path else {
                return nil
            }

            let size = try SizeCalculator().calculate(at: resolvedURL)
            guard size.errors.isEmpty else {
                throw UserCachesScanFailure.incompleteSize(
                    path: resolvedURL.path,
                    errors: size.errors.map(\.message)
                )
            }

            return CleanItem(
                url: cacheURL,
                resolvedURL: resolvedURL,
                sizeBytes: size.bytes,
                moduleId: id,
                ruleId: id
            )
        }
    }
}

private enum UserCachesScanFailure: LocalizedError {
    case incompleteSize(path: String, errors: [String])

    var errorDescription: String? {
        switch self {
        case let .incompleteSize(path, errors):
            "Unable to calculate the complete size of \(path): \(errors.joined(separator: "; "))"
        }
    }
}
