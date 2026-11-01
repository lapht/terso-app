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

/// Finds the caches of sandboxed apps: `~/Library/Containers/<id>/Data/Library/Caches`
/// and `~/Library/Group Containers/<id>/Library/Caches`, and nothing else inside a container.
///
/// Caches of running apps are skipped and reported. Because macOS 14+ protects other apps'
/// data, the module requires Full Disk Access and fails loudly when a location cannot be
/// read: a denied location is "not scanned", never an empty result.
public struct ContainerCachesModule: SkippedCacheReporting {
    public static let moduleID = "caches.containers"

    /// Where a cache directory lives, which decides how its owner is read.
    enum Kind: Sendable, Equatable {
        case appContainer
        case groupContainer

        var ruleID: String {
            switch self {
            case .appContainer: "caches.containers.app"
            case .groupContainer: "caches.containers.group"
            }
        }
    }

    struct CacheDirectory: Sendable, Equatable {
        let identifier: String
        let kind: Kind
        let url: URL
    }

    public let id = ContainerCachesModule.moduleID
    public let title = "App Container Caches"
    public let requiresFDA = true

    private let runningApps: @Sendable () async -> [InstalledApp]
    private let installedApps: @Sendable (URL) -> [InstalledApp]
    private let membershipReader: any AppGroupMembershipReading

    public init() {
        runningApps = {
            await MainActor.run {
                NSWorkspace.shared.runningApplications.compactMap { application in
                    guard let identifier = application.bundleIdentifier,
                          let url = application.bundleURL else {
                        return nil
                    }
                    return InstalledApp(
                        name: application.localizedName ?? identifier,
                        bundleIdentifier: .known(identifier),
                        url: url
                    )
                }
            }
        }
        installedApps = { InstalledAppDiscovery.standard(homeDirectory: $0).discover().apps }
        membershipReader = CodeSignatureGroupMembershipReader()
    }

    init(
        runningApps: @escaping @Sendable () async -> [InstalledApp],
        installedApps: @escaping @Sendable (URL) -> [InstalledApp] = { _ in [] },
        membershipReader: any AppGroupMembershipReading
    ) {
        self.runningApps = runningApps
        self.installedApps = installedApps
        self.membershipReader = membershipReader
    }

    /// The exact cache directories the deletion pipeline may accept for this module.
    ///
    /// Using each `Caches` directory as its own root (not the whole container) means Safety
    /// refuses anything else inside a container. Unreadable locations yield no roots.
    public static func allowedRoots(homeDirectory: URL) -> [URL] {
        ((try? cacheDirectories(homeDirectory: homeDirectory)) ?? []).map(\.url)
    }

    public func scan(context: ScanContext) async throws -> [CleanItem] {
        try await scanReport(context: context).items
    }

    public func scanReport(context: ScanContext) async throws -> ModuleScanReport {
        let directories = try Self.cacheDirectories(homeDirectory: context.homeDirectory)
        guard !directories.isEmpty else {
            return ModuleScanReport(items: [])
        }

        let running = await runningApps()
        let runningIDs = Set(running.compactMap(\.bundleIdentifier.value))
        let known = installedApps(context.homeDirectory) + running

        var items: [CleanItem] = []
        var skipped: [SkippedCache] = []
        for directory in directories {
            let size = try SizeCalculator().calculate(at: directory.url)
            let name = ownerName(of: directory, among: known)
            if isInUse(directory, runningIDs: runningIDs, running: running) {
                // Read-only estimate: skipped caches are reported, never offered for cleanup.
                skipped.append(SkippedCache(
                    moduleID: id,
                    bundleIdentifier: directory.identifier,
                    estimatedBytes: size.bytes,
                    displayName: name
                ))
                continue
            }
            guard size.errors.isEmpty else {
                throw ContainerCachesScanFailure.incompleteSize(
                    path: directory.url.path,
                    errors: size.errors.map(\.message)
                )
            }
            items.append(CleanItem(
                url: directory.url,
                resolvedURL: directory.url.resolvingSymlinksInPath().standardizedFileURL,
                sizeBytes: size.bytes,
                moduleId: id,
                ruleId: directory.kind.ruleID,
                ownerName: name ?? directory.identifier
            ))
        }
        return ModuleScanReport(items: items, skippedCaches: skipped)
    }

    // MARK: - Discovery

    /// Lists the `Caches` directories, enforcing symlink discipline at every level.
    ///
    /// - Throws: ``ContainerCachesScanFailure/accessDenied(path:)`` when macOS refuses a read,
    ///   so the caller reports "not scanned" instead of an empty list.
    static func cacheDirectories(homeDirectory: URL) throws -> [CacheDirectory] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        return try directories(
            in: library.appendingPathComponent("Containers", isDirectory: true),
            kind: .appContainer,
            cachesSuffix: "Data/Library/Caches"
        ) + directories(
            in: library.appendingPathComponent("Group Containers", isDirectory: true),
            kind: .groupContainer,
            cachesSuffix: "Library/Caches"
        )
    }

    private static func directories(in root: URL, kind: Kind, cachesSuffix: String) throws -> [CacheDirectory] {
        let root = root.standardizedFileURL
        guard let rootValues = try readValues(of: root),
              rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              root.resolvingSymlinksInPath().standardizedFileURL.path == root.path else {
            return []
        }

        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw classify(error, path: root.path)
        }

        var result: [CacheDirectory] = []
        for container in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let caches = container
                .appendingPathComponent(cachesSuffix, isDirectory: true)
                .standardizedFileURL
            guard let values = try readValues(of: caches),
                  values.isDirectory == true,
                  values.isSymbolicLink != true,
                  // Catches a symlinked container, `Data` or `Library` as well as a symlinked `Caches`.
                  caches.resolvingSymlinksInPath().standardizedFileURL.path == caches.path else {
                continue
            }
            result.append(CacheDirectory(identifier: container.lastPathComponent, kind: kind, url: caches))
        }
        return result
    }

    /// `nil` when the location does not exist; throws when macOS denies the read.
    private static func readValues(of url: URL) throws -> URLResourceValues? {
        do {
            return try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            // A loose file where a container directory is expected: ENOTDIR, nothing to scan.
            let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
            if underlying?.code == Int(ENOTDIR) {
                return nil
            }
            throw classify(error, path: url.path)
        }
    }

    private static func classify(_ error: Error, path: String) -> Error {
        let nsError = error as NSError
        let underlying = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
        let denied = [Int(EPERM), Int(EACCES)]
        if nsError.code == CocoaError.fileReadNoPermission.rawValue
            || (nsError.domain == NSPOSIXErrorDomain && denied.contains(nsError.code))
            || (underlying.map(denied.contains) ?? false) {
            return ContainerCachesScanFailure.accessDenied(path: path)
        }
        return error
    }

    // MARK: - Ownership

    /// Whether the cache's owner is running. Group caches are in use when any running app
    /// shares the group; an unreadable signature counts as sharing (fail-closed).
    private func isInUse(_ directory: CacheDirectory, runningIDs: Set<String>, running: [InstalledApp]) -> Bool {
        switch directory.kind {
        case .appContainer:
            return runningIDs.contains(directory.identifier)
        case .groupContainer:
            if runningIDs.contains(directory.identifier) {
                return true
            }
            return running.contains { app in
                guard let membership = try? membershipReader.membership(of: app) else {
                    return true
                }
                return membership.shares(groupIdentifier: directory.identifier)
            }
        }
    }

    private func ownerName(of directory: CacheDirectory, among apps: [InstalledApp]) -> String? {
        var candidates = [directory.identifier]
        if directory.kind == .groupContainer {
            var stripped = directory.identifier
            if stripped.hasPrefix("group.") {
                stripped.removeFirst("group.".count)
            } else if AppGroupMembership.teamPrefix(of: stripped) != nil,
                      let dot = stripped.firstIndex(of: ".") {
                stripped = String(stripped[stripped.index(after: dot)...])
            }
            candidates.append(stripped)
        }
        for candidate in candidates {
            if let app = apps.first(where: { $0.bundleIdentifier.value == candidate }) {
                return app.name
            }
        }
        return nil
    }
}

private enum ContainerCachesScanFailure: LocalizedError {
    case accessDenied(path: String)
    case incompleteSize(path: String, errors: [String])

    var errorDescription: String? {
        switch self {
        case let .accessDenied(path):
            "Not scanned: macOS denied access to \(path). Grant Terso Full Disk Access or allow it to access "
                + "data from other apps, then scan again."
        case let .incompleteSize(path, errors):
            "Unable to calculate the complete size of \(path): \(errors.joined(separator: "; "))"
        }
    }
}
