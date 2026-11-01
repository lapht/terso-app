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

/// An Electron or Chromium app whose caches live in `~/Library/Application Support`.
///
/// To add an app, append one entry to ``ElectronCachesModule/apps`` and one matching rule to
/// the newest `Rules/vYYYY.N.json` (see `docs/CONTRIBUTING.md`).
public struct ElectronApp: Sendable, Equatable {
    /// Rule ID in the rule database; also reported on every item the app produces.
    public let ruleID: String

    /// User-facing app name.
    public let name: String

    /// The app's folder, relative to `~/Library/Application Support`.
    public let supportFolder: String

    /// Bundle identifiers of the app; if any is running, its caches are skipped.
    public let bundleIdentifiers: [String]

    /// Known cache subfolders of `supportFolder`. Never a profile, storage or settings folder.
    public let cacheFolders: [String]

    public init(
        ruleID: String,
        name: String,
        supportFolder: String,
        bundleIdentifiers: [String],
        cacheFolders: [String]
    ) {
        self.ruleID = ruleID
        self.name = name
        self.supportFolder = supportFolder
        self.bundleIdentifiers = bundleIdentifiers
        self.cacheFolders = cacheFolders
    }
}

/// Finds the rebuildable caches that Electron and Chromium apps keep in Application Support.
///
/// Only the explicitly listed cache subfolders are returned, never the app folder itself, so
/// profiles, `Local Storage`, `IndexedDB`, cookies and settings can never be matched. Caches of
/// running apps are skipped and reported.
public struct ElectronCachesModule: SkippedCacheReporting {
    public static let moduleID = "caches.electron"

    /// Chromium cache folders shared by most apps.
    private static let chromiumCaches = ["Cache", "Code Cache", "GPUCache"]

    /// The apps covered by the rule database. Keep in sync with `Rules/` (a test enforces it).
    public static let apps: [ElectronApp] = [
        ElectronApp(
            ruleID: "caches.electron.slack",
            name: "Slack",
            supportFolder: "Slack",
            bundleIdentifiers: ["com.tinyspeck.slackmacgap"],
            cacheFolders: chromiumCaches + ["Service Worker/CacheStorage"]
        ),
        ElectronApp(
            ruleID: "caches.electron.discord",
            name: "Discord",
            supportFolder: "discord",
            bundleIdentifiers: ["com.hnc.Discord"],
            cacheFolders: chromiumCaches
        ),
        ElectronApp(
            ruleID: "caches.electron.teams",
            name: "Microsoft Teams",
            supportFolder: "Microsoft/Teams",
            bundleIdentifiers: ["com.microsoft.teams", "com.microsoft.teams2"],
            cacheFolders: chromiumCaches + ["Service Worker/CacheStorage"]
        ),
        ElectronApp(
            ruleID: "caches.electron.spotify",
            name: "Spotify",
            supportFolder: "Spotify",
            bundleIdentifiers: ["com.spotify.client"],
            cacheFolders: chromiumCaches
        ),
        ElectronApp(
            ruleID: "caches.electron.vscode",
            name: "Visual Studio Code",
            supportFolder: "Code",
            bundleIdentifiers: ["com.microsoft.VSCode"],
            cacheFolders: chromiumCaches + ["CachedData", "CachedExtensionVSIXs", "Service Worker/CacheStorage"]
        )
    ]

    struct CacheDirectory: Sendable, Equatable {
        let app: ElectronApp
        let url: URL
    }

    public let id = ElectronCachesModule.moduleID
    public let title = "Electron App Caches"
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

    /// The exact cache directories the deletion pipeline may accept for this module.
    ///
    /// Each cache folder is its own root, so Safety refuses the rest of an app folder.
    public static func allowedRoots(homeDirectory: URL) -> [URL] {
        cacheDirectories(homeDirectory: homeDirectory).map(\.url)
    }

    public func scan(context: ScanContext) async throws -> [CleanItem] {
        try await scanReport(context: context).items
    }

    public func scanReport(context: ScanContext) async throws -> ModuleScanReport {
        let directories = Self.cacheDirectories(homeDirectory: context.homeDirectory)
        guard !directories.isEmpty else {
            return ModuleScanReport(items: [])
        }

        let runningIDs = await runningBundleIdentifiers()
        var items: [CleanItem] = []
        var skippedBytes: [String: Int64] = [:]
        var skippedApps: [ElectronApp] = []
        for directory in directories {
            let size = try SizeCalculator().calculate(at: directory.url)
            if directory.app.bundleIdentifiers.contains(where: runningIDs.contains) {
                // Read-only estimate: skipped caches are reported, never offered for cleanup.
                if skippedBytes[directory.app.ruleID] == nil {
                    skippedApps.append(directory.app)
                }
                skippedBytes[directory.app.ruleID, default: 0] += size.bytes
                continue
            }
            guard size.errors.isEmpty else {
                throw ElectronCachesScanFailure.incompleteSize(
                    path: directory.url.path,
                    errors: size.errors.map(\.message)
                )
            }
            items.append(CleanItem(
                url: directory.url,
                resolvedURL: directory.url.resolvingSymlinksInPath().standardizedFileURL,
                sizeBytes: size.bytes,
                moduleId: id,
                ruleId: directory.app.ruleID,
                ownerName: directory.app.name
            ))
        }

        let skipped = skippedApps.map { app in
            SkippedCache(
                moduleID: id,
                bundleIdentifier: app.bundleIdentifiers.first(where: runningIDs.contains) ?? app.bundleIdentifiers[0],
                estimatedBytes: skippedBytes[app.ruleID] ?? 0,
                displayName: app.name
            )
        }
        return ModuleScanReport(items: items, skippedCaches: skipped)
    }

    // MARK: - Discovery

    /// Lists the existing cache folders, enforcing symlink discipline at every level.
    static func cacheDirectories(homeDirectory: URL) -> [CacheDirectory] {
        let supportRoot = homeDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .standardizedFileURL
        guard isPlainDirectory(supportRoot) else {
            return []
        }

        var result: [CacheDirectory] = []
        for app in apps {
            for folder in app.cacheFolders {
                let url = supportRoot
                    .appendingPathComponent(app.supportFolder, isDirectory: true)
                    .appendingPathComponent(folder, isDirectory: true)
                    .standardizedFileURL
                // Rejects a symlinked app folder, intermediate folder or cache folder.
                if isPlainDirectory(url) {
                    result.append(CacheDirectory(app: app, url: url))
                }
            }
        }
        return result
    }

    private static func isPlainDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            return false
        }
        return url.resolvingSymlinksInPath().standardizedFileURL.path == url.standardizedFileURL.path
    }
}

private enum ElectronCachesScanFailure: LocalizedError {
    case incompleteSize(path: String, errors: [String])

    var errorDescription: String? {
        switch self {
        case let .incompleteSize(path, errors):
            "Unable to complete size of \(path): \(errors.joined(separator: "; "))"
        }
    }
}
