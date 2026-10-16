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

/// Integration tests: rule database fixtures evaluated against a fake home tree.
struct RuleEvaluatorAppPatternTests {
    // MARK: - v0.1 fixture

    @Test func v1FixtureMatchesExactlyTheExpectedCacheFiles() throws {
        let home = try FakeHome()
        defer { home.remove() }
        let rule = try #require(loadDatabase("rules-v1-valid").rules.first)

        let candidates = try [
            "Library/Caches/a.tmp",
            "Library/Caches/sub/b.log",
            "Library/Caches/7.cache",
            "Library/Caches/sub/Keep/c.log",
            "Library/Caches/notes.txt"
        ].map(home.createFile)

        let matches = try home.evaluator.evaluate(rule: rule, candidates: candidates, now: Date() + 172_800)

        #expect(matches.map(home.relativePath) == [
            "Library/Caches/a.tmp",
            "Library/Caches/sub/b.log",
            "Library/Caches/7.cache"
        ])
        #expect(try home.evaluator.evaluateAppPatterns(rule: rule, candidates: candidates).isEmpty)
    }

    // MARK: - v2 fixture

    @Test func v2FixtureMatchesExactlyTheAppPatternPaths() throws {
        let home = try FakeHome()
        defer { home.remove() }
        let database = try loadDatabase("rules-v2-valid")
        let editor = try #require(database.rules.first { $0.id == "leftovers.example.editor" })

        let candidates = try [
            home.createDirectory("Library/Application Support/Example Editor"),
            home.createFile("Library/Application Support/Example Editor/state.db"),
            home.createDirectory("Library/Caches/com.example.Editor"),
            home.createDirectory("Library/Caches/com.example.Editor2"),
            home.createFile("Library/Preferences/com.example.Editor.plist"),
            home.createFile("Library/Preferences/com.example.Editor.plist.lockfile"),
            home.createFile("Library/Preferences/com.example.Other.plist")
        ]

        let matches = try home.evaluator.evaluateAppPatterns(rule: editor, candidates: candidates)

        #expect(matches.map(home.relativePath) == [
            "Library/Application Support/Example Editor",
            "Library/Caches/com.example.Editor",
            "Library/Preferences/com.example.Editor.plist"
        ])
        #expect(matches.allSatisfy {
            $0.ruleID == "leftovers.example.editor" && $0.bundleID == "com.example.Editor" && !$0.shared
        })
    }

    @Test func v2FixtureReportsSharedGroupContainer() throws {
        let home = try FakeHome()
        defer { home.remove() }
        let suite = try #require(loadDatabase("rules-v2-valid").rules.first { $0.id == "leftovers.example.suite" })
        let container = try home.createDirectory("Library/Group Containers/ABCDE12345.com.example.suite")

        let matches = try home.evaluator.evaluateAppPatterns(rule: suite, candidates: [container])

        #expect(matches == [AppPatternMatch(
            ruleID: "leftovers.example.suite",
            bundleID: "com.example.suite.Writer",
            url: container.standardizedFileURL,
            shared: true,
            groupIdentifier: "ABCDE12345.com.example.suite"
        )])
    }

    @Test func matchingIsDeterministicAndFollowsCandidateOrder() throws {
        let home = try FakeHome()
        defer { home.remove() }
        let editor = try #require(loadDatabase("rules-v2-valid").rules.first { $0.id == "leftovers.example.editor" })
        let candidates = try [
            home.createFile("Library/Preferences/com.example.Editor.plist"),
            home.createDirectory("Library/Caches/com.example.Editor")
        ]

        let first = try home.evaluator.evaluateAppPatterns(rule: editor, candidates: candidates)
        let second = try home.evaluator.evaluateAppPatterns(rule: editor, candidates: candidates)
        let reversed = try home.evaluator.evaluateAppPatterns(rule: editor, candidates: candidates.reversed())

        #expect(first == second)
        #expect(first.map(home.relativePath) == [
            "Library/Preferences/com.example.Editor.plist",
            "Library/Caches/com.example.Editor"
        ])
        #expect(reversed == first.reversed())
    }

    @Test func bundleIDMatchIsCaseSensitive() throws {
        let home = try FakeHome()
        defer { home.remove() }
        let editor = try #require(loadDatabase("rules-v2-valid").rules.first { $0.id == "leftovers.example.editor" })
        try home.createDirectory("Library/Caches/com.example.Editor")
        let differentCase = home.url("Library/Caches/com.example.editor")

        #expect(try home.evaluator.evaluateAppPatterns(rule: editor, candidates: [differentCase]).isEmpty)
    }

    // MARK: - Hostile input

    @Test func symlinkAtAppPatternPathEscapingAllowlistIsRejected() throws {
        let home = try FakeHome()
        defer { home.remove() }
        let editor = try #require(loadDatabase("rules-v2-valid").rules.first { $0.id == "leftovers.example.editor" })
        let outside = try home.createDirectory("Documents/Secrets")
        let link = home.url("Library/Caches/com.example.Editor")
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        #expect(throws: SafetyError.self) {
            try home.evaluator.evaluateAppPatterns(rule: editor, candidates: [link])
        }
    }

    @Test func candidateOutsideAllowlistIsRejectedNotSkipped() throws {
        let home = try FakeHome()
        defer { home.remove() }
        let editor = try #require(loadDatabase("rules-v2-valid").rules.first { $0.id == "leftovers.example.editor" })
        let outside = try home.createDirectory("Library/Containers/com.example.Editor")

        #expect(throws: SafetyError.self) {
            try home.evaluator.evaluateAppPatterns(rule: editor, candidates: [outside])
        }
    }

    @Test func handBuiltHostileRuleIsRejectedByTheEngine() throws {
        let home = try FakeHome()
        defer { home.remove() }
        let hostile = CleanupRule(
            id: "leftovers.hostile",
            module: "leftovers",
            category: "Leftovers",
            name: "Hostile",
            description: "Bypasses the loader.",
            allowlistRoots: ["~/Library/Caches"],
            paths: [],
            patterns: [],
            exclusions: [],
            minAgeSeconds: nil,
            isTrashSafe: true,
            appPatterns: [AppPattern(bundleID: "com.example.Hostile", paths: ["~/Library/Caches/../../Documents"])],
            provenance: Provenance(source: "x", author: "attacker", date: "2026-10-16", rationale: "x")
        )
        let documents = try home.createDirectory("Documents")

        #expect(throws: RuleValidationError.self) {
            try home.evaluator.evaluateAppPatterns(rule: hostile, candidates: [documents])
        }
    }

    // MARK: - Helpers

    private func loadDatabase(_ name: String) throws -> RuleDatabase {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try RuleValidator.decode(Data(contentsOf: url))
    }
}

/// Temporary home directory with a known tree, removed by `remove()`.
private struct FakeHome {
    let root: URL
    let evaluator: RuleEvaluator

    init() throws {
        root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".terso-app-pattern-\(UUID().uuidString)", isDirectory: true)
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

    func createFile(_ relativePath: String) throws -> URL {
        let file = url(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(to: file)
        return file
    }

    func relativePath(_ url: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    func relativePath(_ match: AppPatternMatch) -> String {
        relativePath(match.url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
