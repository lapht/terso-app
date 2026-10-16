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

/// The bundle identifier read from an app's `Info.plist`.
public enum AppBundleIdentifier: Sendable, Hashable, Codable {
    /// `CFBundleIdentifier` is present and non-empty.
    case known(String)

    /// `Info.plist` has no usable `CFBundleIdentifier` (absent or blank).
    /// Such an app is reported but never matched to anything (design §11.3).
    case missing

    /// The identifier when known, otherwise `nil`.
    public var value: String? {
        if case let .known(identifier) = self {
            return identifier
        }
        return nil
    }
}

/// An `.app` bundle found by ``InstalledAppDiscovery``.
public struct InstalledApp: Sendable, Hashable, Codable {
    /// Display name (`CFBundleDisplayName`, `CFBundleName`, or the bundle file name).
    public let name: String

    /// The bundle identifier, or ``AppBundleIdentifier/missing``.
    public let bundleIdentifier: AppBundleIdentifier

    /// Location of the `.app` bundle as found in the scanned root (not symlink-resolved).
    public let url: URL

    public init(name: String, bundleIdentifier: AppBundleIdentifier, url: URL) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.url = url
    }
}

/// A location or bundle that discovery could not read completely.
public struct AppDiscoveryIssue: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        /// A scanned root or one of its subfolders could not be listed.
        case unreadableLocation

        /// An app's metadata (`Info.plist`) is absent, unreadable or malformed.
        case unreadableMetadata
    }

    public let kind: Kind
    public let url: URL
    public let message: String

    public init(kind: Kind, url: URL, message: String) {
        self.kind = kind
        self.url = url
        self.message = message
    }
}

/// Whether an app with a given bundle ID is installed, as far as discovery can tell.
public enum AppInstallationStatus: Sendable, Hashable {
    /// At least one discovered app has this bundle ID.
    case installed

    /// Discovery is complete and no app has this bundle ID.
    case notInstalled

    /// Discovery is incomplete: absence cannot be concluded (design §11.3).
    case undetermined
}

/// The single app owning a bundle ID, when that can be decided without guessing.
public enum InstalledAppLookup: Sendable, Hashable {
    /// Exactly one discovered app has this bundle ID.
    case unique(InstalledApp)

    /// Several discovered apps share this bundle ID; none is chosen automatically.
    case ambiguous([InstalledApp])

    /// Discovery is complete and no app has this bundle ID.
    case notFound

    /// Discovery is incomplete and no app with this bundle ID was seen.
    case undetermined
}

/// Result of a read-only installed-app discovery (design §11.3).
public struct InstalledAppDiscoveryResult: Sendable, Hashable {
    /// Roots that were scanned, in scan order.
    public let roots: [URL]

    /// Every `.app` bundle found, sorted by path.
    public let apps: [InstalledApp]

    /// Every location or bundle that could not be read, sorted by path.
    public let issues: [AppDiscoveryIssue]

    public init(roots: [URL], apps: [InstalledApp], issues: [AppDiscoveryIssue]) {
        self.roots = roots
        self.apps = apps
        self.issues = issues
    }

    /// `false` when any location or metadata could not be read.
    /// An incomplete discovery must never be read as "app not installed".
    public var isComplete: Bool {
        issues.isEmpty
    }

    /// Apps without a usable bundle ID.
    public var appsWithoutBundleIdentifier: [InstalledApp] {
        apps.filter { $0.bundleIdentifier == .missing }
    }

    /// Bundle IDs carried by more than one discovered app, mapped to those apps.
    public var ambiguousBundleIdentifiers: [String: [InstalledApp]] {
        appsByBundleIdentifier.filter { $0.value.count > 1 }
    }

    public func installationStatus(ofBundleIdentifier bundleIdentifier: String) -> AppInstallationStatus {
        if appsByBundleIdentifier[bundleIdentifier] != nil {
            return .installed
        }
        return isComplete ? .notInstalled : .undetermined
    }

    public func app(withBundleIdentifier bundleIdentifier: String) -> InstalledAppLookup {
        guard let matches = appsByBundleIdentifier[bundleIdentifier] else {
            return isComplete ? .notFound : .undetermined
        }
        guard matches.count == 1, let match = matches.first else {
            return .ambiguous(matches)
        }
        return .unique(match)
    }

    private var appsByBundleIdentifier: [String: [InstalledApp]] {
        var grouped: [String: [InstalledApp]] = [:]
        for app in apps {
            if let identifier = app.bundleIdentifier.value {
                grouped[identifier, default: []].append(app)
            }
        }
        return grouped
    }
}
