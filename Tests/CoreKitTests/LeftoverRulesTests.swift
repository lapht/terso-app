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

/// Seed leftover rules shipped in `Rules/v2026.2.json` (#101).
struct LeftoverRulesTests {
    /// Every leftover rule with the exact paths it must match, in app pattern order.
    private static let expectedMatches: [String: (bundleID: String, paths: [String])] = [
        "leftovers.google.chrome": ("com.google.Chrome", [
            "Library/Application Support/Google/Chrome",
            "Library/Caches/Google/Chrome",
            "Library/Caches/com.google.Chrome",
            "Library/Preferences/com.google.Chrome.plist",
            "Library/Saved Application State/com.google.Chrome.savedState",
            "Library/HTTPStorages/com.google.Chrome",
            "Library/WebKit/com.google.Chrome"
        ]),
        "leftovers.microsoft.vscode": ("com.microsoft.VSCode", [
            "Library/Application Support/Code",
            "Library/Caches/com.microsoft.VSCode.ShipIt",
            "Library/Caches/com.microsoft.VSCode",
            "Library/Preferences/com.microsoft.VSCode.plist",
            "Library/Saved Application State/com.microsoft.VSCode.savedState",
            "Library/HTTPStorages/com.microsoft.VSCode",
            "Library/WebKit/com.microsoft.VSCode"
        ]),
        "leftovers.spotify.client": ("com.spotify.client", [
            "Library/Application Support/Spotify",
            "Library/Caches/com.spotify.client",
            "Library/Preferences/com.spotify.client.plist",
            "Library/Saved Application State/com.spotify.client.savedState",
            "Library/HTTPStorages/com.spotify.client",
            "Library/WebKit/com.spotify.client"
        ]),
        "leftovers.bitwarden.desktop": ("com.bitwarden.desktop", [
            "Library/Containers/com.bitwarden.desktop",
            "Library/Containers/com.bitwarden.desktop.loginhelper",
            "Library/Containers/com.bitwarden.desktop.safari",
            "Library/Group Containers/LTZ2PFU5D6.com.bitwarden.desktop"
        ]),
        "leftovers.c3.theunarchiver": ("cx.c3.theunarchiver", [
            "Library/Containers/cx.c3.theunarchiver"
        ])
    ]

    /// Data of other apps, shared vendor folders and near-miss names that no rule may match.
    private static let decoyPaths = [
        "Library/Application Support/Google",
        "Library/Application Support/Google/Chrome Beta",
        "Library/Application Support/Google/GoogleUpdater",
        "Library/Application Support/Code - Insiders",
        "Library/Application Support/Spotify/Users",
        "Library/Application Support/com.example.Other",
        "Library/Caches/Google",
        "Library/Caches/com.google.GoogleUpdater",
        "Library/Caches/com.google.Chrome.canary",
        "Library/Caches/com.microsoft.VSCodeInsiders",
        "Library/Caches/com.spotify.client/Data",
        "Library/Preferences/com.google.Keystone.Agent.plist",
        "Library/Preferences/com.spotify.client.plist.lockfile",
        "Library/HTTPStorages/com.spotify.client-launcher",
        "Library/HTTPStorages/com.spotify.installer",
        "Library/Containers/com.bitwarden.desktop.other",
        "Library/Containers/com.macpaw.CleanMyMac5",
        "Library/Containers/cx.c3.theunarchiver2",
        "Library/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5",
        "Library/Group Containers/LTZ2PFU5D6.com.bitwarden.other"
    ]

    // MARK: - Database

    @Test func v2026Point2DatabaseMatchesSnapshotAndKeepsV1Rules() throws {
        let databaseData = try Data(contentsOf: Self.repositoryRoot.appendingPathComponent("Rules/v2026.2.json"))
        let snapshotURL = try #require(
            Bundle.module.url(forResource: "rules-v2026.2.snapshot", withExtension: "json")
        )
        #expect(databaseData == (try Data(contentsOf: snapshotURL)))

        let database = try RuleValidator.decode(databaseData)
        #expect(database.version == "2026.2")
        #expect(database.schemaVersion == 2)

        let v1Data = try Data(contentsOf: Self.repositoryRoot.appendingPathComponent("Rules/v2026.1.json"))
        let v1Rules = try RuleValidator.decode(v1Data).rules
        #expect(Array(database.rules.prefix(v1Rules.count)) == v1Rules)
        #expect(database.rules.dropFirst(v1Rules.count).allSatisfy { $0.module == "leftovers" })
    }

    @Test func everyLeftoverRuleIsAuditableAndExpected() throws {
        let rules = try Self.leftoverRules()

        #expect(Set(rules.map(\.id)) == Set(Self.expectedMatches.keys))
        for rule in rules {
            let provenance = try #require(rule.provenance, "\(rule.id) has no provenance")
            #expect(!provenance.source.isEmpty && !provenance.rationale.isEmpty)
            #expect(rule.isTrashSafe)
            #expect(rule.paths.isEmpty && rule.patterns.isEmpty, "\(rule.id) must match only app patterns")
            #expect(rule.allowlistRoots.allSatisfy(RuleValidator.leftoverRoots.contains))
            let appPatterns = try #require(rule.appPatterns)
            #expect(appPatterns.allSatisfy { $0.bundleID == Self.expectedMatches[rule.id]?.bundleID })
        }
    }

    @Test func groupContainersAreMarkedShared() throws {
        let appPatterns = try Self.leftoverRules().flatMap { $0.appPatterns ?? [] }

        for appPattern in appPatterns {
            let inGroupContainers = appPattern.paths.contains { $0.hasPrefix("~/Library/Group Containers/") }
            #expect(appPattern.shared == inGroupContainers, "\(appPattern.bundleID): \(appPattern.paths)")
            if appPattern.shared {
                let groupIdentifier = try #require(appPattern.groupIdentifier)
                #expect(appPattern.paths == ["~/Library/Group Containers/\(groupIdentifier)"])
            }
        }
    }

    // MARK: - Fixture tree

    @Test func eachRuleMatchesOnlyItsBundleIDPaths() throws {
        let home = try LeftoverFixtureHome()
        defer { home.remove() }
        let expectedPaths = Self.expectedMatches.values.flatMap(\.paths)
        try (expectedPaths + Self.decoyPaths).forEach { try home.createDirectory($0) }

        for rule in try Self.leftoverRules() {
            let expected = try #require(Self.expectedMatches[rule.id])
            let candidates = (expectedPaths + Self.decoyPaths)
                .filter { path in rule.allowlistRoots.contains { path.hasPrefix(String($0.dropFirst(2)) + "/") } }
                .map(home.url)

            let matches = try home.evaluator.evaluateAppPatterns(rule: rule, candidates: candidates)

            #expect(Set(matches.map(home.relativePath)) == Set(expected.paths), "\(rule.id)")
            #expect(matches.count == expected.paths.count, "\(rule.id)")
            #expect(matches.allSatisfy { $0.ruleID == rule.id && $0.bundleID == expected.bundleID })
        }
    }

    @Test func bitwardenGroupContainerIsReportedAsShared() throws {
        let home = try LeftoverFixtureHome()
        defer { home.remove() }
        let rule = try #require(try Self.leftoverRules().first { $0.id == "leftovers.bitwarden.desktop" })
        let container = try home.createDirectory("Library/Group Containers/LTZ2PFU5D6.com.bitwarden.desktop")
        let ownContainer = try home.createDirectory("Library/Containers/com.bitwarden.desktop")

        let matches = try home.evaluator.evaluateAppPatterns(rule: rule, candidates: [ownContainer, container])

        #expect(matches.map(\.shared) == [false, true])
        #expect(matches.map(\.groupIdentifier) == [nil, "LTZ2PFU5D6.com.bitwarden.desktop"])
    }

    // MARK: - Negative fixtures

    @Test(arguments: ["Desktop", "Documents", "Downloads", "Library/Mail", "Applications/Spotify.app"])
    func protectedOrOutOfRootPathsAreRejectedByEveryRule(path: String) throws {
        let home = try LeftoverFixtureHome()
        defer { home.remove() }
        let candidate = try home.createDirectory(path)

        for rule in try Self.leftoverRules() {
            #expect(throws: (any Error).self, "\(rule.id) accepted \(path)") {
                try home.evaluator.evaluateAppPatterns(rule: rule, candidates: [candidate])
            }
        }
    }

    @Test func symlinkAtLeftoverPathEscapingTheRootIsRejected() throws {
        let home = try LeftoverFixtureHome()
        defer { home.remove() }
        let rule = try #require(try Self.leftoverRules().first { $0.id == "leftovers.spotify.client" })
        let documents = try home.createDirectory("Documents")
        let link = home.url("Library/Caches/com.spotify.client")
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: documents)

        #expect(throws: (any Error).self) {
            try home.evaluator.evaluateAppPatterns(rule: rule, candidates: [link])
        }
    }

    @Test func noRuleMatchesAnotherRulesPaths() throws {
        let home = try LeftoverFixtureHome()
        defer { home.remove() }
        let rules = try Self.leftoverRules()

        for rule in rules {
            for (otherID, other) in Self.expectedMatches where otherID != rule.id {
                let candidates = try other.paths
                    .filter { path in
                        rule.allowlistRoots.contains { path.hasPrefix(String($0.dropFirst(2)) + "/") }
                    }
                    .map(home.createDirectory)

                let matches = try home.evaluator.evaluateAppPatterns(rule: rule, candidates: candidates)
                #expect(matches.isEmpty, "\(rule.id) matched data of \(otherID)")
            }
        }
    }

    // MARK: - Helpers

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func leftoverRules() throws -> [CleanupRule] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("Rules/v2026.2.json"))
        return try RuleValidator.decode(data).rules.filter { $0.module == "leftovers" }
    }
}

/// Temporary home directory with a known tree, removed by `remove()`.
private struct LeftoverFixtureHome {
    let root: URL
    let evaluator: RuleEvaluator

    init() throws {
        root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".terso-leftover-rules-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        evaluator = RuleEvaluator(homeDirectory: root)
    }

    func url(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    @discardableResult
    func createDirectory(_ relativePath: String) throws -> URL {
        let directory = url(relativePath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func relativePath(_ match: AppPatternMatch) -> String {
        String(match.url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
