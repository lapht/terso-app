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

/// Read-only discovery of installed apps and their bundle IDs (design §11.3).
///
/// Scans each root and its subfolders for `.app` bundles and reads only their
/// `Info.plist`. It never writes, moves or trashes anything, and never offers
/// an app for removal (design §11.1). Anything it cannot read is reported as an
/// ``AppDiscoveryIssue`` and marks the result incomplete.
public struct InstalledAppDiscovery: Sendable {
    /// Info.plist locations relative to the bundle, in lookup order:
    /// macOS bundles, iOS apps installed on Apple silicon, flat bundles.
    private static let infoPlistPaths = ["Contents/Info.plist", "WrappedBundle/Info.plist", "Info.plist"]

    public let roots: [URL]

    public init(roots: [URL]) {
        self.roots = roots.map(\.standardizedFileURL)
    }

    /// `/Applications` and `~/Applications` for the given home directory.
    public static func standard(homeDirectory: URL) -> InstalledAppDiscovery {
        InstalledAppDiscovery(roots: [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ])
    }

    public func discover() -> InstalledAppDiscoveryResult {
        var apps: [InstalledApp] = []
        var issues: [AppDiscoveryIssue] = []
        for root in roots {
            scan(root: root, apps: &apps, issues: &issues)
        }
        return InstalledAppDiscoveryResult(
            roots: roots,
            apps: apps.sorted { $0.url.path < $1.url.path },
            issues: issues.sorted { ($0.url.path, $0.message) < ($1.url.path, $1.message) }
        )
    }

    private func scan(root: URL, apps: inout [InstalledApp], issues: inout [AppDiscoveryIssue]) {
        let rootValues: URLResourceValues
        do {
            rootValues = try root.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // A missing root (commonly ~/Applications) holds no apps.
            return
        } catch {
            issues.append(AppDiscoveryIssue(
                kind: .unreadableLocation,
                url: root,
                message: error.localizedDescription
            ))
            return
        }
        guard rootValues.isDirectory == true else {
            issues.append(AppDiscoveryIssue(kind: .unreadableLocation, url: root, message: "Not a directory"))
            return
        }

        var enumerationIssues: [AppDiscoveryIssue] = []
        let enumerator = FileManager.default.enumerator(
            // The enumerator does not descend into a symlinked root, so start from its target.
            at: root.resolvingSymlinksInPath(),
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { failedURL, error in
                enumerationIssues.append(AppDiscoveryIssue(
                    kind: .unreadableLocation,
                    url: failedURL,
                    message: error.localizedDescription
                ))
                return true
            }
        )
        guard let enumerator else {
            issues.append(AppDiscoveryIssue(kind: .unreadableLocation, url: root, message: "Cannot enumerate"))
            return
        }

        while let enumeratedURL = enumerator.nextObject() as? URL {
            guard enumeratedURL.pathExtension.lowercased() == "app" else {
                continue
            }
            // Bundles inside a bundle (helpers, embedded apps) are not separate installs.
            enumerator.skipDescendants()
            // Report the path under the root as configured, not its canonical form.
            let url = enumeratedURL.pathComponents.suffix(enumerator.level).reduce(root) {
                $0.appendingPathComponent($1)
            }
            switch readApp(at: url) {
            case let .app(app):
                apps.append(app)
            case let .issue(issue):
                issues.append(issue)
            case .notABundle:
                continue
            }
        }
        issues.append(contentsOf: enumerationIssues)
    }

    private enum BundleReadResult {
        case app(InstalledApp)
        case issue(AppDiscoveryIssue)
        case notABundle
    }

    private func readApp(at url: URL) -> BundleReadResult {
        // A symlinked .app counts as installed: following it only reads metadata.
        let bundle = url.resolvingSymlinksInPath()
        let isDirectory = (try? bundle.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
        guard isDirectory == true else {
            return .notABundle
        }

        func issue(_ message: String) -> BundleReadResult {
            .issue(AppDiscoveryIssue(kind: .unreadableMetadata, url: url, message: message))
        }

        let infoPlistURL = Self.infoPlistPaths
            .map { bundle.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        guard let infoPlistURL else {
            return issue("Info.plist not found")
        }

        let plist: Any
        do {
            let data = try Data(contentsOf: infoPlistURL)
            plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            return issue("Cannot read \(infoPlistURL.lastPathComponent): \(error.localizedDescription)")
        }
        guard let info = plist as? [String: Any] else {
            return issue("Info.plist is not a dictionary")
        }

        let bundleIdentifier: AppBundleIdentifier
        switch info["CFBundleIdentifier"] {
        case nil:
            bundleIdentifier = .missing
        case let identifier as String:
            let isBlank = identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            bundleIdentifier = isBlank ? .missing : .known(identifier)
        default:
            return issue("CFBundleIdentifier is not a string")
        }

        return .app(InstalledApp(
            name: Self.name(from: info, bundleURL: url),
            bundleIdentifier: bundleIdentifier,
            url: url
        ))
    }

    private static func name(from info: [String: Any], bundleURL: URL) -> String {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = info[key] as? String,
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
        }
        return bundleURL.deletingPathExtension().lastPathComponent
    }
}
