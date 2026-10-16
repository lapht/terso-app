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

/// A file or folder left behind by an app that is no longer installed (design §11.4).
///
/// Candidates carry no selection state: nothing is preselected, and choosing what
/// to move to Trash is a separate, explicit step (#37).
public struct LeftoverCandidate: Sendable, Hashable, Identifiable {
    public var id: String { url.path }

    /// Standardized location of the leftover, exactly as declared by the app pattern.
    public let url: URL

    /// Rule that associates the location with the bundle ID.
    public let ruleID: String

    /// Bundle ID of the removed app the location belongs to.
    public let bundleID: String

    /// Allocated size of the item; a lower bound when ``sizeErrors`` is not empty.
    public let sizeBytes: Int64

    /// Descendants whose size could not be read; they are not counted in ``sizeBytes``.
    public let sizeErrors: [SizeCalculationError]

    /// Whether the app pattern marks the location as shared by several apps.
    public let isShared: Bool

    /// Group identifier of a shared location, if any.
    public let groupIdentifier: String?

    public init(
        url: URL,
        ruleID: String,
        bundleID: String,
        sizeBytes: Int64,
        sizeErrors: [SizeCalculationError] = [],
        isShared: Bool = false,
        groupIdentifier: String? = nil
    ) {
        self.url = url
        self.ruleID = ruleID
        self.bundleID = bundleID
        self.sizeBytes = sizeBytes
        self.sizeErrors = sizeErrors
        self.isShared = isShared
        self.groupIdentifier = groupIdentifier
    }

    /// Whether ``sizeBytes`` covers every descendant.
    public var isSizeComplete: Bool {
        sizeErrors.isEmpty
    }

    /// Why the item is reported: the rule and the bundle ID of the removed app.
    public var associationReason: String {
        "Rule \(ruleID) matches \(bundleID), which is not installed"
    }
}

/// A location that matches a removed app but is withheld because another app may use it.
public struct LeftoverExclusion: Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        /// Installed apps share the group identifier; listed as "name (bundle ID)" or name.
        case sharedWithInstalledApps(groupIdentifier: String, apps: [String])

        /// The code signature of some installed apps could not be read, so sharing
        /// cannot be ruled out (fail-closed).
        case sharingUnverified(groupIdentifier: String, apps: [String])
    }

    public let url: URL
    public let ruleID: String
    public let bundleID: String
    public let reason: Reason

    public init(url: URL, ruleID: String, bundleID: String, reason: Reason) {
        self.url = url
        self.ruleID = ruleID
        self.bundleID = bundleID
        self.reason = reason
    }

    /// User-facing explanation of why the location is not reported.
    public var message: String {
        switch reason {
        case let .sharedWithInstalledApps(groupIdentifier, apps):
            "Shared group \(groupIdentifier) is still used by \(apps.joined(separator: ", "))"
        case let .sharingUnverified(groupIdentifier, apps):
            "Cannot verify that shared group \(groupIdentifier) is unused: "
                + "unable to read the signature of \(apps.joined(separator: ", "))"
        }
    }
}

/// A leftover root that was not scanned, shown to the user instead of silently skipped (invariant 7).
public struct LeftoverNotScannedRoot: Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        /// `~/Library/Containers` or `~/Library/Group Containers` without Full Disk Access:
        /// macOS protects other apps' data there, so the root is not touched.
        case appDataProtection

        /// macOS refused to list the root (`EACCES`/`EPERM`).
        case accessDenied(String)

        /// The root is a symbolic link or resolves elsewhere; it is never followed.
        case symbolicLink

        /// The root exists but could not be read for another reason.
        case unreadable(String)
    }

    public let root: URL
    public let reason: Reason

    public init(root: URL, reason: Reason) {
        self.root = root
        self.reason = reason
    }

    /// Whether granting Full Disk Access may let a later scan cover this root.
    public var needsFullDiskAccess: Bool {
        switch reason {
        case .appDataProtection, .accessDenied:
            true
        case .symbolicLink, .unreadable:
            false
        }
    }
}

/// A matching location that could not be reported, kept visible instead of dropped (invariant 8).
public struct LeftoverScanIssue: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// The Safety validators refused the location (symlink escape, protected path, ...).
        case rejected(SafetyError)

        /// The location's metadata or size could not be read.
        case unreadable(String)
    }

    public let url: URL
    public let ruleID: String
    public let kind: Kind

    public init(url: URL, ruleID: String, kind: Kind) {
        self.url = url
        self.ruleID = ruleID
        self.kind = kind
    }

    public var message: String {
        switch kind {
        case let .rejected(error):
            error.description
        case let .unreadable(message):
            message
        }
    }
}

/// Result of a read-only leftovers scan (design §11.4).
public struct LeftoverScanResult: Sendable, Hashable {
    public enum Status: Sendable, Hashable {
        /// Installed-app discovery was complete, so absent bundle IDs mean removed apps.
        case completed

        /// Discovery was incomplete: no item is reported as a leftover (design §11.3).
        case discoveryIncomplete([AppDiscoveryIssue])
    }

    public let status: Status

    /// Leftovers sorted by path. Empty when discovery was incomplete.
    public let candidates: [LeftoverCandidate]

    /// Shared locations withheld with a visible reason, sorted by path.
    public let exclusions: [LeftoverExclusion]

    /// Roots that were not scanned, in design §11.4 order.
    public let notScannedRoots: [LeftoverNotScannedRoot]

    /// Matching locations that were refused or unreadable, sorted by path.
    public let issues: [LeftoverScanIssue]

    public init(
        status: Status,
        candidates: [LeftoverCandidate] = [],
        exclusions: [LeftoverExclusion] = [],
        notScannedRoots: [LeftoverNotScannedRoot] = [],
        issues: [LeftoverScanIssue] = []
    ) {
        self.status = status
        self.candidates = candidates
        self.exclusions = exclusions
        self.notScannedRoots = notScannedRoots
        self.issues = issues
    }

    /// Whether the candidates may be incomplete: discovery, roots or items were not fully covered.
    public var isPartial: Bool {
        status != .completed
            || !notScannedRoots.isEmpty
            || !issues.isEmpty
            || candidates.contains { !$0.isSizeComplete }
    }

    /// Sum of ``LeftoverCandidate/sizeBytes`` over all candidates.
    public var totalBytes: Int64 {
        candidates.reduce(0) { $0 + $1.sizeBytes }
    }
}
