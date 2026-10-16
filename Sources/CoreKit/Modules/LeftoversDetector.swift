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

/// Read-only detection of files left behind by apps that are no longer installed (design §11.4).
///
/// Only the exact paths declared by Rule DB v2 app patterns are inspected, and only
/// under the `~/Library` roots of design §11.4. A path is reported only when every
/// bundle ID claiming it is absent from a complete installed-app discovery. The
/// detector never writes, moves or trashes anything; acting on the results is #37.
public struct LeftoversDetector: Sendable {
    /// Roots where macOS protects other apps' data unless Full Disk Access is granted.
    static let appDataProtectedRoots: Set<String> = ["~/Library/Containers", "~/Library/Group Containers"]

    public let id = "leftovers"
    public let title = "Leftovers"

    private let homeDirectory: URL
    private let evaluator: RuleEvaluator
    private let membershipReader: any AppGroupMembershipReading

    public init(
        homeDirectory: URL,
        membershipReader: any AppGroupMembershipReading = CodeSignatureGroupMembershipReader()
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        evaluator = RuleEvaluator(homeDirectory: homeDirectory)
        self.membershipReader = membershipReader
    }

    /// Scans the app pattern paths of `rules` for leftovers of removed apps.
    ///
    /// - Throws: a `RuleValidationError` when a rule's v2 fields are invalid (there is
    ///   no partial fallback), or `CancellationError` when the surrounding task is cancelled.
    ///   Unsafe or unreadable locations are reported in ``LeftoverScanResult/issues``.
    public func scan(
        rules: [CleanupRule],
        discovery: InstalledAppDiscoveryResult,
        tccStatus: TCCStatus
    ) throws -> LeftoverScanResult {
        let appRules = rules.filter { $0.appPatterns != nil }
        for rule in appRules {
            try RuleValidator.validateSchemaV2Fields(of: rule)
        }
        guard discovery.isComplete else {
            return LeftoverScanResult(status: .discoveryIncomplete(discovery.issues))
        }

        var notScannedRoots: [LeftoverNotScannedRoot] = []
        var scannedRoots: [URL] = []
        for root in RuleValidator.leftoverRoots {
            let url = expandRoot(root)
            if let reason = notScannedReason(root: root, url: url, tccStatus: tccStatus) {
                notScannedRoots.append(LeftoverNotScannedRoot(root: url, reason: reason))
            } else {
                scannedRoots.append(url)
            }
        }

        var state = ScanState()
        var sharing = SharingResolver(rules: appRules, discovery: discovery, reader: membershipReader)
        for (url, claims) in claimsByPath(appRules) {
            try Task.checkCancellation()
            // Paths under a root that was not scanned are covered by that root's report.
            guard scannedRoots.contains(where: { url.path.hasPrefix($0.path + "/") }) else {
                continue
            }
            func isRemoved(_ claim: Claim) -> Bool {
                discovery.installationStatus(ofBundleIdentifier: claim.pattern.bundleID) == .notInstalled
            }
            let removedClaims = claims.filter(isRemoved)
            // Data an installed app owns outright is not a leftover. A shared location
            // claimed by an installed app is excluded with a visible reason in `inspect`.
            let isOwnedByInstalledApp = claims.contains { !$0.pattern.shared && !isRemoved($0) }
            guard !removedClaims.isEmpty, !isOwnedByInstalledApp else {
                continue
            }
            let sharedGroups = Set(claims.compactMap { $0.pattern.shared ? $0.pattern.groupIdentifier : nil })
            try inspect(url, claims: removedClaims, sharedGroups: sharedGroups, sharing: &sharing, state: &state)
        }

        return LeftoverScanResult(
            status: .completed,
            candidates: state.candidates,
            exclusions: state.exclusions,
            notScannedRoots: notScannedRoots,
            issues: state.issues
        )
    }

    // MARK: - Roots

    private func expandRoot(_ root: String) -> URL {
        homeDirectory.appendingPathComponent(String(root.dropFirst(2)), isDirectory: true).standardizedFileURL
    }

    private func notScannedReason(root: String, url: URL, tccStatus: TCCStatus) -> LeftoverNotScannedRoot.Reason? {
        // Without Full Disk Access these roots are not touched at all, so no macOS prompt
        // appears and no partial listing is mistaken for a complete one.
        if Self.appDataProtectedRoots.contains(root), tccStatus != .granted {
            return .appDataProtection
        }

        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            let code = errno
            // A missing root holds no leftovers.
            return code == ENOENT ? nil : Self.reason(forErrno: code)
        }
        if info.st_mode & S_IFMT == S_IFLNK {
            return .symbolicLink
        }
        guard info.st_mode & S_IFMT == S_IFDIR else {
            return .unreadable("Not a directory")
        }
        let expectedPath = homeDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(String(root.dropFirst(2)))
            .standardizedFileURL.path
        guard url.resolvingSymlinksInPath().standardizedFileURL.path == expectedPath else {
            // A parent such as ~/Library is a symlink: the root lives elsewhere.
            return .symbolicLink
        }

        guard let directory = opendir(url.path) else {
            return Self.reason(forErrno: errno)
        }
        closedir(directory)
        return nil
    }

    private static func reason(forErrno code: Int32) -> LeftoverNotScannedRoot.Reason {
        let message = String(cString: strerror(code))
        return code == EACCES || code == EPERM ? .accessDenied(message) : .unreadable(message)
    }

    // MARK: - Candidates

    private struct Claim {
        let rule: CleanupRule
        let pattern: AppPattern
    }

    /// Every app pattern path after `{bundleID}` substitution, sorted by path, with the
    /// patterns claiming it in rule order.
    private func claimsByPath(_ rules: [CleanupRule]) -> [(URL, [Claim])] {
        var claims: [String: (URL, [Claim])] = [:]
        for rule in rules {
            for pattern in rule.appPatterns ?? [] {
                for path in pattern.paths {
                    let url = evaluator.expandAppPath(path, bundleID: pattern.bundleID)
                    claims[url.path, default: (url, [])].1.append(Claim(rule: rule, pattern: pattern))
                }
            }
        }
        return claims.sorted { $0.key < $1.key }.map(\.value)
    }

    private func inspect(
        _ url: URL,
        claims: [Claim],
        sharedGroups: Set<String>,
        sharing: inout SharingResolver,
        state: inout ScanState
    ) throws {
        guard let primary = claims.first else {
            return
        }
        func report(_ kind: LeftoverScanIssue.Kind, ruleID: String = primary.rule.id) {
            state.issues.append(LeftoverScanIssue(url: url, ruleID: ruleID, kind: kind))
        }

        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            let code = errno
            if code != ENOENT, code != ENOTDIR {
                report(.unreadable(String(cString: strerror(code))))
            }
            return
        }

        // Same allowlist, protected-path and symlink checks as every other rule evaluation.
        for claim in claims {
            do {
                _ = try evaluator.evaluateAppPatterns(rule: claim.rule, candidates: [url])
            } catch let error as SafetyError {
                report(.rejected(error), ruleID: claim.rule.id)
                return
            }
        }

        for groupIdentifier in sharedGroups.sorted() {
            if let reason = sharing.exclusionReason(for: groupIdentifier) {
                state.exclusions.append(LeftoverExclusion(
                    url: url,
                    ruleID: primary.rule.id,
                    bundleID: primary.pattern.bundleID,
                    reason: reason
                ))
                return
            }
        }

        let size: SizeCalculationResult
        do {
            size = try SizeCalculator().calculate(at: url)
        } catch {
            report(.unreadable(error.localizedDescription))
            return
        }
        state.candidates.append(LeftoverCandidate(
            url: url,
            ruleID: primary.rule.id,
            bundleID: primary.pattern.bundleID,
            sizeBytes: size.bytes,
            sizeErrors: size.errors,
            isShared: primary.pattern.shared,
            groupIdentifier: primary.pattern.groupIdentifier
        ))
    }
}

private struct ScanState {
    var candidates: [LeftoverCandidate] = []
    var exclusions: [LeftoverExclusion] = []
    var issues: [LeftoverScanIssue] = []
}

/// Decides whether an installed app may still use a shared group, reading signatures once.
private struct SharingResolver {
    private enum Membership {
        case read(AppGroupMembership)
        case unreadable
    }

    private let rules: [CleanupRule]
    private let discovery: InstalledAppDiscoveryResult
    private let reader: any AppGroupMembershipReading
    private var memberships: [(InstalledApp, Membership)]?

    init(rules: [CleanupRule], discovery: InstalledAppDiscoveryResult, reader: any AppGroupMembershipReading) {
        self.rules = rules
        self.discovery = discovery
        self.reader = reader
    }

    mutating func exclusionReason(for groupIdentifier: String) -> LeftoverExclusion.Reason? {
        // Installed apps whose Rule DB patterns declare the same group.
        var sharers = Set(rules
            .flatMap { $0.appPatterns ?? [] }
            .filter { $0.groupIdentifier == groupIdentifier }
            .flatMap { pattern in
                discovery.apps.filter { $0.bundleIdentifier.value == pattern.bundleID }
            }
            .map(Self.label))
        var unverified: Set<String> = []

        for (app, membership) in loadMemberships() {
            switch membership {
            case let .read(membership) where membership.shares(groupIdentifier: groupIdentifier):
                sharers.insert(Self.label(app))
            case .read:
                continue
            case .unreadable:
                unverified.insert(Self.label(app))
            }
        }

        if !sharers.isEmpty {
            return .sharedWithInstalledApps(groupIdentifier: groupIdentifier, apps: sharers.sorted())
        }
        if !unverified.isEmpty {
            return .sharingUnverified(groupIdentifier: groupIdentifier, apps: unverified.sorted())
        }
        return nil
    }

    private mutating func loadMemberships() -> [(InstalledApp, Membership)] {
        if let memberships {
            return memberships
        }
        let loaded = discovery.apps.map { app in
            (app, (try? reader.membership(of: app)).map(Membership.read) ?? .unreadable)
        }
        memberships = loaded
        return loaded
    }

    private static func label(_ app: InstalledApp) -> String {
        guard let bundleID = app.bundleIdentifier.value else {
            return app.name
        }
        return "\(app.name) (\(bundleID))"
    }
}
