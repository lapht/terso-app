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

struct ElectronCachesModuleTests {
    private struct Fixture {
        let home: URL
        let support: URL
        let outside: URL
    }

    /// Folders that hold user data and must never be matched.
    private static let userData = [
        "Local Storage/leveldb/000003.log",
        "IndexedDB/https_app.example_0.indexeddb.leveldb/data",
        "Cookies",
        "Preferences",
        "User/settings.json",
        "Default/Login Data"
    ]

    private func module(running: Set<String> = []) -> ElectronCachesModule {
        ElectronCachesModule(runningBundleIdentifiers: { running })
    }

    private func makeAppFixture(_ fixture: Fixture) throws {
        for app in ElectronCachesModule.apps {
            let appFolder = fixture.support.appendingPathComponent(app.supportFolder, isDirectory: true)
            for cache in app.cacheFolders {
                try createFile(at: appFolder.appendingPathComponent("\(cache)/blob.bin"), contents: "cache")
            }
            for data in Self.userData {
                try createFile(at: appFolder.appendingPathComponent(data), contents: "user data")
            }
        }
    }

    @Test func matchesOnlyCacheFoldersNextToUserData() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        try makeAppFixture(fixture)

        let items = try await module().scan(context: ScanContext(homeDirectory: fixture.home))

        let expected = ElectronCachesModule.apps.flatMap { app in
            app.cacheFolders.map {
                fixture.support.appendingPathComponent("\(app.supportFolder)/\($0)").path
            }
        }
        #expect(Set(items.map(\.url.path)) == Set(expected))
        #expect(items.count == expected.count)
        #expect(items.allSatisfy { $0.moduleId == "caches.electron" && $0.recommendedAction == .trash })
        #expect(items.allSatisfy { $0.sizeBytes > 0 && !$0.isProtected })
        for item in items {
            for data in Self.userData {
                #expect(!item.url.path.contains(data.components(separatedBy: "/")[0]))
            }
        }
    }

    @Test func eachAppFixtureProducesItsOwnRuleAndOwner() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        try makeAppFixture(fixture)

        let items = try await module().scan(context: ScanContext(homeDirectory: fixture.home))

        for app in ElectronCachesModule.apps {
            let appItems = items.filter { $0.ruleId == app.ruleID }
            #expect(appItems.count == app.cacheFolders.count, "\(app.name)")
            #expect(appItems.allSatisfy { $0.ownerName == app.name })
        }
        #expect(Set(ElectronCachesModule.apps.map(\.name)) == [
            "Slack", "Discord", "Microsoft Teams", "Spotify", "Visual Studio Code"
        ])
    }

    @Test func ignoresAppsThatAreNotInstalledAndEmptyHome() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        let report = try await module().scanReport(context: ScanContext(homeDirectory: fixture.home))
        #expect(report.items.isEmpty && report.skippedCaches.isEmpty)
    }

    @Test func skipsAndReportsCachesOfRunningApps() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        try makeAppFixture(fixture)

        let report = try await module(running: ["com.tinyspeck.slackmacgap"])
            .scanReport(context: ScanContext(homeDirectory: fixture.home))

        #expect(report.items.allSatisfy { $0.ruleId != "caches.electron.slack" })
        #expect(report.items.contains { $0.ruleId == "caches.electron.discord" })
        let skipped = try #require(report.skippedCaches.first)
        #expect(report.skippedCaches.count == 1)
        #expect(skipped.moduleID == "caches.electron")
        #expect(skipped.bundleIdentifier == "com.tinyspeck.slackmacgap")
        #expect(skipped.displayName == "Slack")
        #expect(skipped.estimatedBytes > 0)
        // Skipping is read-only: the running app's cache is untouched.
        let slackFile = fixture.support.appendingPathComponent("Slack/Cache/blob.bin")
        #expect(FileManager.default.fileExists(atPath: slackFile.path))
    }

    @Test func eitherTeamsBundleIdentifierMarksTeamsAsRunning() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        try makeAppFixture(fixture)

        let report = try await module(running: ["com.microsoft.teams2"])
            .scanReport(context: ScanContext(homeDirectory: fixture.home))

        #expect(report.items.allSatisfy { $0.ruleId != "caches.electron.teams" })
        #expect(report.skippedCaches.map(\.displayName) == ["Microsoft Teams"])
    }

    @Test func rejectsSymlinkedCacheAndAppFolders() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let fileManager = FileManager.default

        // Slack/Cache is a symlink to a tree outside Application Support.
        try createFile(at: fixture.outside.appendingPathComponent("victim/keep.txt"), contents: "keep")
        try createFile(at: fixture.support.appendingPathComponent("Slack/Local Storage/a"), contents: "a")
        try fileManager.createSymbolicLink(
            at: fixture.support.appendingPathComponent("Slack/Cache"),
            withDestinationURL: fixture.outside.appendingPathComponent("victim")
        )
        // discord is a symlink to an outside tree that has a real Cache folder.
        try createFile(at: fixture.outside.appendingPathComponent("discord-real/Cache/x"), contents: "x")
        try fileManager.createSymbolicLink(
            at: fixture.support.appendingPathComponent("discord"),
            withDestinationURL: fixture.outside.appendingPathComponent("discord-real")
        )
        // Code/Service Worker is a symlink, so Service Worker/CacheStorage resolves elsewhere.
        try createFile(at: fixture.outside.appendingPathComponent("sw/CacheStorage/y"), contents: "y")
        try fileManager.createDirectory(
            at: fixture.support.appendingPathComponent("Code"),
            withIntermediateDirectories: true
        )
        try fileManager.createSymbolicLink(
            at: fixture.support.appendingPathComponent("Code/Service Worker"),
            withDestinationURL: fixture.outside.appendingPathComponent("sw")
        )

        let items = try await module().scan(context: ScanContext(homeDirectory: fixture.home))

        #expect(items.isEmpty)
        #expect(ElectronCachesModule.allowedRoots(homeDirectory: fixture.home).isEmpty)
        #expect(fileManager.fileExists(atPath: fixture.outside.appendingPathComponent("victim/keep.txt").path))
    }

    @Test func rejectsSymlinkedApplicationSupport() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        try createFile(at: fixture.outside.appendingPathComponent("Support/Slack/Cache/a"), contents: "a")
        try FileManager.default.removeItem(at: fixture.support)
        try FileManager.default.createSymbolicLink(
            at: fixture.support,
            withDestinationURL: fixture.outside.appendingPathComponent("Support")
        )

        let items = try await module().scan(context: ScanContext(homeDirectory: fixture.home))
        #expect(items.isEmpty)
    }

    @Test func allowedRootsAreExactlyTheCacheFoldersAndSafetyRefusesUserData() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        try makeAppFixture(fixture)

        let roots = ElectronCachesModule.allowedRoots(homeDirectory: fixture.home)
        let items = try await module().scan(context: ScanContext(homeDirectory: fixture.home))
        #expect(Set(roots.map(\.path)) == Set(items.map(\.url.path)))

        let validator = PathValidator(homeDirectory: fixture.home)
        for item in items {
            try validator.validate(path: item.url, allowedRoots: roots)
        }
        for app in ElectronCachesModule.apps {
            let appFolder = fixture.support.appendingPathComponent(app.supportFolder, isDirectory: true)
            #expect(throws: SafetyError.self) {
                try validator.validate(path: appFolder, allowedRoots: roots)
            }
            for data in Self.userData {
                #expect(throws: SafetyError.self) {
                    try validator.validate(path: appFolder.appendingPathComponent(data), allowedRoots: roots)
                }
            }
        }
    }

    @Test func neverListsUserDataFolderNames() {
        let forbidden = ["Local Storage", "IndexedDB", "Cookies", "Preferences", "User", "Default", "Session Storage"]
        for app in ElectronCachesModule.apps {
            for folder in app.cacheFolders {
                #expect(!folder.contains(".."))
                #expect(!forbidden.contains { folder.hasPrefix($0) }, "\(app.name): \(folder)")
            }
        }
    }

    // MARK: - Rule database

    @Test func rulesInDatabaseMatchModuleTable() throws {
        let data = try Data(contentsOf: Self.repositoryRoot.appendingPathComponent("Rules/v2026.4.json"))
        let database = try RuleValidator.decode(data)
        let rules = database.rules.filter { $0.module == ElectronCachesModule.moduleID }

        #expect(Set(rules.map(\.id)) == Set(ElectronCachesModule.apps.map(\.ruleID)))
        for app in ElectronCachesModule.apps {
            let rule = try #require(rules.first { $0.id == app.ruleID }, "\(app.ruleID) missing")
            let expectedRoots = app.cacheFolders.map { "~/Library/Application Support/\(app.supportFolder)/\($0)" }
            #expect(rule.allowlistRoots == expectedRoots, "\(app.ruleID) roots differ from the module")
            #expect(rule.isTrashSafe)
            let provenance = try #require(rule.provenance, "\(app.ruleID) has no provenance")
            #expect(!provenance.source.isEmpty && !provenance.rationale.isEmpty)
        }
    }

    @Test(arguments: [
        ("allowlistRoots", "\"~/Library/Application Support/Slack/../Safari\"", "[\"**/*\"]"),
        ("allowlistRoots", "\"~/Library/Application Support/Slack/Cache/../../../Documents\"", "[\"**/*\"]"),
        ("patterns", "\"~/Library/Application Support/Slack/Cache\"", "[\"../../Local Storage/**\"]"),
        ("patterns", "\"~/Library/Application Support/Slack/Cache\"", "[\"**/../../Cookies\"]")
    ])
    func validatorRejectsPatternsThatEscapeTheAppFolder(field: String, root: String, patterns: String) throws {
        let json = """
        {"version":"2026.9","schemaVersion":2,"rules":[{
          "id":"caches.electron.hostile","module":"caches.electron","category":"Caches",
          "name":"Hostile","description":"Escapes its folder.",
          "allowlistRoots":[\(root)],"paths":[],"patterns":\(patterns),"exclusions":[],
          "isTrashSafe":true,
          "provenance":{"source":"https://example.com","author":"x","date":"2026-11-01","rationale":"test"}
        }]}
        """
        let error = #expect(throws: RuleValidationError.self) {
            try RuleValidator.decode(Data(json.utf8))
        }
        guard case let .pathEscapesRoot(ruleID, reportedField, _)? = error else {
            Issue.record("Expected pathEscapesRoot, got \(String(describing: error))")
            return
        }
        #expect(ruleID == "caches.electron.hostile")
        #expect(reportedField == field)
    }

    // MARK: - Helpers

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func makeFixture() throws -> Fixture {
        // Under /tmp, not /var/folders: the pipeline hard-denies /var.
        let base = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let home = base.appendingPathComponent("terso-electron-\(UUID().uuidString)", isDirectory: true)
        let outside = base.appendingPathComponent("terso-electron-outside-\(UUID().uuidString)", isDirectory: true)
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        return Fixture(home: home, support: support, outside: outside)
    }

    private func cleanUp(_ fixture: Fixture) {
        try? FileManager.default.removeItem(at: fixture.home)
        try? FileManager.default.removeItem(at: fixture.outside)
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }
}
