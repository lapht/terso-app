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

struct GlobMatcherTests {
    @Test(arguments: [
        ("*.log", "build.log", true),
        ("*.log", "nested/build.log", false),
        ("**/*.log", "build.log", true),
        ("**/*.log", "nested/deep/build.log", true),
        ("file?.[ch]", "file1.c", true),
        ("file?.[ch]", "file12.c", false),
        ("[!a-z]*.tmp", "1.tmp", true),
        ("[!a-z]*.tmp", "abc.tmp", false),
        (#"literal\*.txt"#, "literal*.txt", true),
        ("cache/**/item?.tmp", "cache/item1.tmp", true),
        ("cache/**/item?.tmp", "cache/a/b/item2.tmp", true)
    ])
    func matchesStandardGlobPatterns(pattern: String, path: String, expected: Bool) throws {
        let matcher = try GlobMatcher(pattern: pattern)
        #expect(matcher.matches(path: path) == expected)
    }

    @Test(arguments: ["[", "[]", "a[bc", "trailing\\", "[z-a]"])
    func rejectsMalformedPatterns(pattern: String) {
        #expect(throws: GlobMatcher.PatternError.self) {
            try GlobMatcher(pattern: pattern)
        }
    }
}

struct RuleEvaluatorTests {
    private struct Fixture {
        let root: URL
        let caches: URL
        let evaluator: RuleEvaluator
    }

    @Test func appliesPositivePatternsAndNestedExclusions() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let rootFile = fixture.caches.appendingPathComponent("root.log")
        let nestedLog = fixture.caches.appendingPathComponent("nested/deep/keep.log")
        let excludedDirectoryLog = fixture.caches.appendingPathComponent("nested/deep/private.log")
        let excludedFile = fixture.caches.appendingPathComponent("nested/deep/keep.tmp")
        try createFile(at: rootFile)
        try createFile(at: nestedLog)
        try createFile(at: excludedDirectoryLog)
        try createFile(at: excludedFile)

        let rule = makeRule(
            patterns: ["**/*.log", "**/*.tmp"],
            exclusions: ["nested/**/private.log", "**/keep.tmp"]
        )
        let results = try fixture.evaluator.evaluate(
            rule: rule,
            candidates: [rootFile, nestedLog, excludedDirectoryLog, excludedFile]
        )

        #expect(Set(results.map(\.path)) == Set([rootFile.path, nestedLog.path]))
    }

    @Test func minimumAgeUsesNewestCreationOrModificationDate() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let oldFile = fixture.caches.appendingPathComponent("old.log")
        let recentlyModified = fixture.caches.appendingPathComponent("recent.log")
        try createFile(at: oldFile)
        try createFile(at: recentlyModified)

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let oldDate = now.addingTimeInterval(-400)
        let recentDate = now.addingTimeInterval(-30)
        try FileManager.default.setAttributes(
            [.creationDate: oldDate, .modificationDate: oldDate],
            ofItemAtPath: oldFile.path
        )
        try FileManager.default.setAttributes(
            [.creationDate: oldDate, .modificationDate: recentDate],
            ofItemAtPath: recentlyModified.path
        )

        let results = try fixture.evaluator.evaluate(
            rule: makeRule(patterns: ["*.log"], minAgeSeconds: 120),
            candidates: [oldFile, recentlyModified],
            now: now
        )

        #expect(results.map(\.path) == [oldFile.path])
    }

    @Test func rejectsCandidateOutsideAllowlist() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let outsideFile = fixture.root.appendingPathComponent("outside.log")
        try createFile(at: outsideFile)

        #expect(throws: SafetyError.self) {
            try fixture.evaluator.evaluate(
                rule: makeRule(patterns: ["*.log"]),
                candidates: [outsideFile]
            )
        }
    }

    @Test func rejectsSymlinkEscapingAllowlist() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let outsideFile = fixture.root.appendingPathComponent("outside.log")
        let symlink = fixture.caches.appendingPathComponent("linked.log")
        try createFile(at: outsideFile)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outsideFile)

        #expect(throws: SafetyError.self) {
            try fixture.evaluator.evaluate(
                rule: makeRule(patterns: ["*.log"]),
                candidates: [symlink]
            )
        }
    }

    private func makeFixture() throws -> Fixture {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".terso-rule-evaluator-\(UUID().uuidString)", isDirectory: true)
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        return Fixture(root: home, caches: caches, evaluator: RuleEvaluator(homeDirectory: home))
    }

    private func makeRule(
        patterns: [String],
        exclusions: [String] = [],
        minAgeSeconds: Int64? = nil
    ) -> CleanupRule {
        CleanupRule(
            id: "fixture.rule",
            module: "fixture",
            category: "Test",
            name: "Fixture rule",
            description: "Rule used by evaluator tests.",
            allowlistRoots: ["~/Library/Caches"],
            paths: [],
            patterns: patterns,
            exclusions: exclusions,
            minAgeSeconds: minAgeSeconds,
            isTrashSafe: true
        )
    }

    private func createFile(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(to: url)
    }
}
