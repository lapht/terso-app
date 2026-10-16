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

@testable import CoreKit
import Foundation
import Testing

struct LeftoversDetectorTests {
    private static let groupContainer = "Library/Group Containers/ABCDE12345.com.example.suite"

    /// Leftovers of the removed apps (Editor, Writer) when Viewer is installed.
    private static let removedAppLeftovers = [
        "Library/Application Support/Example Editor",
        "Library/Caches/com.example.Editor",
        "Library/Containers/com.example.suite.Writer",
        groupContainer,
        "Library/Preferences/com.example.Editor.plist"
    ]

    // MARK: - Orphan detection

    @Test func removedAppReportsExactlyItsLeftovers() throws {
        let fixture = try LeftoverFixture()
        defer { fixture.remove() }

        let result = try fixture.scan(installed: ["com.example.Viewer"])

        #expect(result.status == .completed)
        #expect(result.candidates.map(fixture.relativePath) == Self.removedAppLeftovers)
        #expect(result.exclusions.isEmpty)
        #expect(result.notScannedRoots.isEmpty)
        #expect(result.issues.isEmpty)
        #expect(!result.isPartial)

        let editorFiles = result.candidates.filter { $0.bundleID == "com.example.Editor" }
        #expect(editorFiles.count == 3)
        #expect(editorFiles.allSatisfy { $0.ruleID == "leftovers.example.editor" && !$0.isShared })
        #expect(result.candidates.allSatisfy { $0.sizeBytes > 0 && $0.isSizeComplete })
        #expect(result.totalBytes == result.candidates.reduce(0) { $0 + $1.sizeBytes })

        let preferences = try #require(result.candidates.last)
        #expect(preferences.associationReason
            == "Rule leftovers.example.editor matches com.example.Editor, which is not installed")
        let group = try #require(result.candidates.first { fixture.relativePath($0) == Self.groupContainer })
        #expect(group.isShared && group.groupIdentifier == "ABCDE12345.com.example.suite")
        #expect(group.bundleID == "com.example.suite.Writer")
    }

    @Test func installedAppFilesAreNeverReported() throws {
        let fixture = try LeftoverFixture()
        defer { fixture.remove() }

        let result = try fixture.scan(installed: [
            "com.example.Editor",
            "com.example.Viewer",
            "com.example.suite.Writer"
        ])

        // The group container is excluded with a reason, never silently dropped.
        #expect(result.candidates.isEmpty)
        #expect(result.exclusions.map(fixture.relativePath) == [Self.groupContainer])
    }

    @Test func folderSharedWithAnInstalledAppIsNotReported() throws {
        let fixture = try LeftoverFixture()
        defer { fixture.remove() }

        let result = try fixture.scan(installed: ["com.example.Viewer"])

        // Example Common is claimed by the removed Editor and the installed Viewer.
        #expect(!result.candidates.map(fixture.relativePath).contains("Library/Application Support/Example Common"))
        let withoutViewer = try fixture.scan(installed: [])
        #expect(withoutViewer.candidates.map(fixture.relativePath)
            .contains("Library/Application Support/Example Common"))
    }

    @Test func missingPathsAreNotCandidates() throws {
        let fixture = try LeftoverFixture(tree: ["Library/Preferences/com.example.Editor.plist"])
        defer { fixture.remove() }

        let result = try fixture.scan(installed: [])

        #expect(result.candidates.map(fixture.relativePath) == ["Library/Preferences/com.example.Editor.plist"])
        #expect(result.issues.isEmpty && result.notScannedRoots.isEmpty)
    }

    @Test func incompleteDiscoveryReportsNoLeftovers() throws {
        let fixture = try LeftoverFixture()
        defer { fixture.remove() }
        let issue = AppDiscoveryIssue(
            kind: .unreadableLocation,
            url: URL(fileURLWithPath: "/Applications/Locked"),
            message: "Permission denied"
        )

        let result = try fixture.scan(installed: [], issues: [issue])

        #expect(result.status == .discoveryIncomplete([issue]))
        #expect(result.candidates.isEmpty && result.exclusions.isEmpty)
        #expect(result.isPartial)
    }

    @Test func scanIsDeterministic() throws {
        let fixture = try LeftoverFixture()
        defer { fixture.remove() }

        let first = try fixture.scan(installed: ["com.example.Viewer"])
        let second = try fixture.scan(installed: ["com.example.Viewer"])

        #expect(first == second)
    }

    @Test func invalidRuleFailsTheWholeScan() throws {
        let fixture = try LeftoverFixture()
        defer { fixture.remove() }
        let rule = CleanupRule(
            id: "leftovers.hostile",
            module: "leftovers",
            category: "Leftovers",
            name: "Hostile",
            description: "Points outside the leftover roots.",
            allowlistRoots: ["~/Library"],
            paths: [],
            patterns: [],
            exclusions: [],
            minAgeSeconds: nil,
            isTrashSafe: true,
            appPatterns: [
                AppPattern(bundleID: "com.example.Hostile", paths: ["~/Library/Keychains/login.keychain-db"])
            ],
            provenance: Provenance(source: "test", author: "tester", date: "2026-10-16", rationale: "Hostile input.")
        )

        #expect(throws: RuleValidationError.self) {
            try fixture.detector().scan(rules: [rule], discovery: fixture.discovery(installed: []), tccStatus: .granted)
        }
    }

    // MARK: - Shared group containers

    @Test func groupContainerSharedThroughRuleDatabaseIsExcludedWithReason() throws {
        let fixture = try LeftoverFixture()
        defer { fixture.remove() }

        let result = try fixture.scan(installed: ["com.example.Viewer", "com.example.suite.Reader"])

        #expect(!result.candidates.map(fixture.relativePath).contains(Self.groupContainer))
        #expect(result.candidates.map(fixture.relativePath).contains("Library/Containers/com.example.suite.Writer"))
        let exclusion = try #require(result.exclusions.first)
        #expect(result.exclusions.count == 1)
        #expect(fixture.relativePath(exclusion.url) == Self.groupContainer)
        #expect(exclusion.bundleID == "com.example.suite.Writer")
        #expect(exclusion.reason == .sharedWithInstalledApps(
            groupIdentifier: "ABCDE12345.com.example.suite",
            apps: ["com.example.suite.Reader (com.example.suite.Reader)"]
        ))
        #expect(exclusion.message.contains("still used by"))
    }

    @Test func groupContainerDeclaredInAnInstalledAppEntitlementIsExcluded() throws {
        let fixture = try LeftoverFixture()
        defer { fixture.remove() }
        let reader = FakeMembershipReader(memberships: [
            "com.vendor.Other": AppGroupMembership(
                teamIdentifier: "ZZZZZ99999",
                applicationGroups: ["ABCDE12345.com.example.suite"]
            )
        ])

        let result = try fixture.scan(installed: ["com.vendor.Other"], reader: reader)

        #expect(result.exclusions.map(\.reason) == [.sharedWithInstalledApps(
            groupIdentifier: "ABCDE12345.com.example.suite",
            apps: ["com.vendor.Other (com.vendor.Other)"]
        )])
    }

    @Test func groupContainerOfAnInstalledAppFromTheSameTeamIsExcluded() throws {
        let fixture = try LeftoverFixture()
        defer { fixture.remove() }
        let reader = FakeMembershipReader(memberships: [
            "com.example.suite.Mailer": AppGroupMembership(teamIdentifier: "ABCDE12345", applicationGroups: [])
        ])

        let result = try fixture.scan(installed: ["com.example.suite.Mailer"], reader: reader)

        #expect(result.exclusions.map(fixture.relativePath) == [Self.groupContainer])
    }

    @Test func unreadableSignatureKeepsGroupContainerExcluded() throws {
        let fixture = try LeftoverFixture()
        defer { fixture.remove() }
        let reader = FakeMembershipReader(unreadable: ["com.vendor.Broken"])

        let result = try fixture.scan(installed: ["com.vendor.Broken"], reader: reader)

        #expect(result.exclusions.map(\.reason) == [.sharingUnverified(
            groupIdentifier: "ABCDE12345.com.example.suite",
            apps: ["com.vendor.Broken (com.vendor.Broken)"]
        )])
        #expect(!result.candidates.map(fixture.relativePath).contains(Self.groupContainer))
    }

    @Test func teamPrefixIsOnlyTheLeadingTeamIdentifier() {
        #expect(AppGroupMembership.teamPrefix(of: "ABCDE12345.com.example.suite") == "ABCDE12345")
        #expect(AppGroupMembership.teamPrefix(of: "group.com.example.suite") == nil)
        #expect(AppGroupMembership.teamPrefix(of: "abcde12345.com.example") == nil)
        #expect(AppGroupMembership.teamPrefix(of: "ABCDE1234.com.example") == nil)

        let unsigned = AppGroupMembership(teamIdentifier: nil, applicationGroups: [])
        #expect(!unsigned.shares(groupIdentifier: "ABCDE12345.com.example.suite"))
    }

    @Test func codeSignatureReaderReadsASystemAppWithoutThrowing() throws {
        let app = InstalledApp(
            name: "TextEdit",
            bundleIdentifier: .known("com.apple.TextEdit"),
            url: URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        )
        _ = try CodeSignatureGroupMembershipReader().membership(of: app)
    }

    // MARK: - Hostile input

    @Test func symlinkEscapingTheRootIsRejectedAndNotFollowed() throws {
        let fixture = try LeftoverFixture(tree: ["Documents/Secrets/passwords.txt"])
        defer { fixture.remove() }
        try fixture.createDirectory("Library/Caches")
        try FileManager.default.createSymbolicLink(
            at: fixture.url("Library/Caches/com.example.Editor"),
            withDestinationURL: fixture.url("Documents/Secrets")
        )

        let result = try fixture.scan(installed: [])

        #expect(result.candidates.isEmpty)
        let issue = try #require(result.issues.first)
        #expect(result.issues.count == 1)
        #expect(fixture.relativePath(issue.url) == "Library/Caches/com.example.Editor")
        #expect(issue.ruleID == "leftovers.example.editor")
        guard case .rejected(.symlinkEscape) = issue.kind else {
            Issue.record("Expected a symlink escape, got \(issue.kind)")
            return
        }
        #expect(result.isPartial)
    }

    @Test func symlinkedRootIsReportedAsNotScanned() throws {
        let fixture = try LeftoverFixture(tree: ["Elsewhere/com.example.Editor.plist"])
        defer { fixture.remove() }
        try fixture.createDirectory("Library")
        try FileManager.default.createSymbolicLink(
            at: fixture.url("Library/Preferences"),
            withDestinationURL: fixture.url("Elsewhere")
        )

        let result = try fixture.scan(installed: [])

        #expect(result.candidates.isEmpty)
        #expect(result.notScannedRoots == [
            LeftoverNotScannedRoot(root: fixture.url("Library/Preferences"), reason: .symbolicLink)
        ])
    }

    // MARK: - Permissions

    @Test func permissionDeniedRootIsReportedAsNotScanned() throws {
        let fixture = try LeftoverFixture()
        defer { fixture.remove() }
        let caches = fixture.url("Library/Caches")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: caches.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: caches.path) }

        let result = try fixture.scan(installed: ["com.example.Viewer"])

        let notScanned = try #require(result.notScannedRoots.first)
        #expect(result.notScannedRoots.count == 1)
        #expect(notScanned.root == caches.standardizedFileURL)
        guard case .accessDenied = notScanned.reason else {
            Issue.record("Expected access denied, got \(notScanned.reason)")
            return
        }
        #expect(notScanned.needsFullDiskAccess)
        #expect(result.candidates.map(fixture.relativePath)
            == Self.removedAppLeftovers.filter { !$0.hasPrefix("Library/Caches/") })
        #expect(result.isPartial)
    }

    @Test func containersWithoutFullDiskAccessAreNotTouched() throws {
        let fixture = try LeftoverFixture()
        defer { fixture.remove() }

        for status in [TCCStatus.denied, .unknown] {
            let result = try fixture.scan(installed: ["com.example.Viewer"], tccStatus: status)

            #expect(result.notScannedRoots == [
                LeftoverNotScannedRoot(root: fixture.url("Library/Containers"), reason: .appDataProtection),
                LeftoverNotScannedRoot(root: fixture.url("Library/Group Containers"), reason: .appDataProtection)
            ])
            #expect(result.candidates.map(fixture.relativePath) == [
                "Library/Application Support/Example Editor",
                "Library/Caches/com.example.Editor",
                "Library/Preferences/com.example.Editor.plist"
            ])
            #expect(result.isPartial)
        }
    }

    // MARK: - Seeded Rule DB

    @Test func seededDatabaseFindsChromeLeftoversOnly() throws {
        let fixture = try LeftoverFixture(tree: [
            "Library/Application Support/Google/Chrome/Default/History",
            "Library/Application Support/Google/GoogleUpdater/state",
            "Library/Preferences/com.google.Chrome.plist",
            "Library/Caches/com.spotify.client/Data/blob"
        ])
        defer { fixture.remove() }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let databaseURL = repositoryRoot.appendingPathComponent("Rules/v2026.2.json")
        let database = try RuleValidator.decode(Data(contentsOf: databaseURL))

        let result = try fixture.detector().scan(
            rules: database.rules,
            discovery: fixture.discovery(installed: ["com.spotify.client"]),
            tccStatus: .granted
        )

        #expect(result.candidates.map(fixture.relativePath) == [
            "Library/Application Support/Google/Chrome",
            "Library/Preferences/com.google.Chrome.plist"
        ])
        #expect(result.candidates.allSatisfy { $0.ruleID == "leftovers.google.chrome" })
    }
}

private enum LeftoversDetectorTestsTree {
    /// Every app pattern path of the fixture database, plus near-miss decoys.
    static let standard = [
        "Library/Application Support/Example Editor/state.db",
        "Library/Application Support/Example Common/shared.db",
        "Library/Caches/com.example.Editor/cache.db",
        "Library/Caches/com.example.Editor2/cache.db",
        "Library/Caches/com.example.Viewer/cache.db",
        "Library/Preferences/com.example.Editor.plist",
        "Library/Preferences/com.example.Editor.plist.lockfile",
        "Library/Preferences/com.example.Viewer.plist",
        "Library/Containers/com.example.suite.Writer/Data/doc.txt",
        "Library/Group Containers/ABCDE12345.com.example.suite/settings.plist"
    ]
}

/// Answers membership lookups by bundle ID; unknown apps are unsigned.
private struct FakeMembershipReader: AppGroupMembershipReading {
    var memberships: [String: AppGroupMembership] = [:]
    var unreadable: Set<String> = []

    func membership(of app: InstalledApp) throws -> AppGroupMembership {
        let bundleID = app.bundleIdentifier.value ?? ""
        if unreadable.contains(bundleID) {
            throw CodeSignatureReadError(path: app.url.path, status: -1)
        }
        return memberships[bundleID] ?? AppGroupMembership(teamIdentifier: nil, applicationGroups: [])
    }
}

/// Temporary home directory with a known `~/Library` tree, removed by `remove()`.
private struct LeftoverFixture {
    let root: URL
    let rules: [CleanupRule]

    init(tree: [String]? = nil) throws {
        root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".terso-leftovers-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = try #require(Bundle.module.url(forResource: "rules-v2-leftovers", withExtension: "json"))
        rules = try RuleValidator.decode(Data(contentsOf: databaseURL)).rules
        for path in tree ?? LeftoversDetectorTestsTree.standard {
            try createFile(path)
        }
    }

    func url(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath).standardizedFileURL
    }

    func createDirectory(_ relativePath: String) throws {
        try FileManager.default.createDirectory(at: url(relativePath), withIntermediateDirectories: true)
    }

    func createFile(_ relativePath: String) throws {
        let file = url(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: file)
    }

    func detector(reader: any AppGroupMembershipReading = FakeMembershipReader()) -> LeftoversDetector {
        LeftoversDetector(homeDirectory: root, membershipReader: reader)
    }

    func discovery(installed bundleIDs: [String], issues: [AppDiscoveryIssue] = []) -> InstalledAppDiscoveryResult {
        InstalledAppDiscoveryResult(
            roots: [URL(fileURLWithPath: "/Applications")],
            apps: bundleIDs.map { bundleID in
                InstalledApp(
                    name: bundleID,
                    bundleIdentifier: .known(bundleID),
                    url: URL(fileURLWithPath: "/Applications/\(bundleID).app")
                )
            },
            issues: issues
        )
    }

    func scan(
        installed bundleIDs: [String],
        issues: [AppDiscoveryIssue] = [],
        tccStatus: TCCStatus = .granted,
        reader: any AppGroupMembershipReading = FakeMembershipReader()
    ) throws -> LeftoverScanResult {
        try detector(reader: reader).scan(
            rules: rules,
            discovery: discovery(installed: bundleIDs, issues: issues),
            tccStatus: tccStatus
        )
    }

    func relativePath(_ url: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    func relativePath(_ candidate: LeftoverCandidate) -> String {
        relativePath(candidate.url)
    }

    func relativePath(_ exclusion: LeftoverExclusion) -> String {
        relativePath(exclusion.url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
