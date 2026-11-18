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

struct VersionExclusionTests {
    // MARK: - Version semantics

    @Test func parsesDottedNumericVersions() {
        #expect(AppVersion("1")?.components == [1])
        #expect(AppVersion("14.1.5.2")?.components == [14, 1, 5, 2])
        for bad in ["", "1.", ".1", "1..2", "1.2.3.4.5", "1.0-beta", "v1", "-1", "+1", "1.a", "1 .2", "1234567890"] {
            #expect(AppVersion(bad) == nil, "\(bad) must not parse")
        }
    }

    @Test func comparesComponentWiseWithImplicitZeros() throws {
        #expect(try #require(AppVersion("1.2")) == #require(AppVersion("1.2.0.0")))
        #expect(try #require(AppVersion("1.9")) < #require(AppVersion("1.10")))
        #expect(try #require(AppVersion("2")) > #require(AppVersion("1.99.99")))
        #expect(try #require(AppVersion("1.0.1")) > #require(AppVersion("1")))
    }

    // MARK: - Loading and validation

    @Test func decodesFixture() throws {
        let database = try RuleValidator.decode(fixtureData("rules-v2-version-exclusions"))
        #expect(database.rules[0].versionExclusions == [
            VersionExclusion(
                bundleID: "com.example.Editor",
                minVersion: "2.0",
                maxVersion: "2.9.9",
                paths: ["com.example.Editor/Data/**"]
            )
        ])
    }

    @Test func rejectsVersionExclusionsInV1Database() throws {
        let json = try fixtureString("rules-v2-version-exclusions").replacingOccurrences(
            of: "\"schemaVersion\": 2",
            with: "\"schemaVersion\": 1"
        )
        #expect(throws: RuleValidationError.schemaV2FieldInV1Database(
            ruleID: "caches.example.editor",
            field: "provenance"
        )) {
            try RuleValidator.decode(Data(json.utf8))
        }
    }

    @Test func rejectsVersionExclusionsWithoutProvenance() {
        let rule = makeRule(provenance: nil, exclusions: [exclusion()])
        #expect(throws: RuleValidationError.missingProvenance(ruleID: "r")) {
            try RuleDatabase(version: "1", schemaVersion: 2, rules: [rule])
        }
    }

    @Test(arguments: [
        ("versionExclusions", [VersionExclusion]()),
        ("bad bundle", [exclusion(bundleID: "nodots")]),
        ("no bounds", [exclusion(minVersion: nil, maxVersion: nil)]),
        ("bad min", [exclusion(minVersion: "2.x")]),
        ("bad max", [exclusion(maxVersion: "2.0-beta")]),
        ("min > max", [exclusion(minVersion: "3", maxVersion: "2.9")]),
        ("empty paths", [exclusion(paths: [])]),
        ("blank path", [exclusion(paths: ["  "])]),
        ("bad glob", [exclusion(paths: ["a[b"])]),
        ("escaping path", [exclusion(paths: ["../Documents/**"])])
    ])
    func rejectsInvalidVersionExclusions(label: String, exclusions: [VersionExclusion]) {
        let rule = makeRule(provenance: provenance, exclusions: exclusions)
        #expect(throws: RuleValidationError.self, "\(label)") {
            try RuleDatabase(version: "1", schemaVersion: 2, rules: [rule])
        }
    }

    @Test func rejectsUnknownFieldInVersionExclusion() throws {
        let json = try fixtureString("rules-v2-version-exclusions").replacingOccurrences(
            of: "\"minVersion\": \"2.0\",",
            with: "\"minVersion\": \"2.0\", \"appVersionRegex\": \".*\","
        )
        #expect(throws: RuleValidationError.self) {
            try RuleValidator.decode(Data(json.utf8))
        }
    }

    // MARK: - Evaluation

    @Test func exclusionAppliesOnlyInsideInclusiveRange() throws {
        let rule = try versionRule()
        let paths = ["com.example.Editor/Data/**"]
        let cases: [(String?, [String])] = [
            ("1.9.9", []),
            ("2.0", paths),
            ("2.5.1", paths),
            ("2.9.9", paths),
            ("2.10", []),
            ("3.0", [])
        ]
        for (version, expected) in cases {
            let active = rule.activeVersionExclusionPaths(installedVersions: ["com.example.Editor": version])
            #expect(active == expected, "version \(version ?? "nil")")
        }
    }

    @Test func unknownOrUnparseableVersionFailsSafeToExcluding() throws {
        let rule = try versionRule()
        let paths = ["com.example.Editor/Data/**"]
        #expect(rule.activeVersionExclusionPaths(installedVersions: [:]) == paths)
        #expect(rule.activeVersionExclusionPaths(installedVersions: ["com.example.Editor": nil]) == paths)
        #expect(rule.activeVersionExclusionPaths(installedVersions: ["com.example.Editor": "3.0-beta"]) == paths)
        #expect(rule.activeVersionExclusionPaths(installedVersions: ["com.other.App": "9.0"]) == paths)
    }

    @Test func evaluateDropsExcludedCandidatesOnlyForAffectedVersions() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".terso-app-version-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let caches = home.appendingPathComponent("Library/Caches/com.example.Editor")
        let data = caches.appendingPathComponent("Data")
        let tmp = caches.appendingPathComponent("tmp")
        for url in [data, tmp] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let dataFile = data.appendingPathComponent("doc.db")
        let tmpFile = tmp.appendingPathComponent("a.tmp")
        for file in [dataFile, tmpFile] {
            try Data("x".utf8).write(to: file)
        }
        let rule = try versionRule()
        let evaluator = RuleEvaluator(homeDirectory: home)
        let candidates = [dataFile, tmpFile]

        let affected = try evaluator.evaluate(
            rule: rule,
            candidates: candidates,
            installedVersions: ["com.example.Editor": "2.5"]
        )
        #expect(affected == [tmpFile.standardizedFileURL])

        let unaffected = try evaluator.evaluate(
            rule: rule,
            candidates: candidates,
            installedVersions: ["com.example.Editor": "3.1"]
        )
        #expect(unaffected == candidates.map(\.standardizedFileURL))

        let outside = home.appendingPathComponent("Documents/x")
        #expect(throws: (any Error).self) {
            try evaluator.evaluate(rule: rule, candidates: [outside], installedVersions: [:])
        }
    }

    // MARK: - Helpers

    private var provenance: Provenance {
        Provenance(source: "fixture", author: "tester", date: "2026-11-18", rationale: "fixture")
    }

    private static func exclusion(
        bundleID: String = "com.example.Editor",
        minVersion: String? = "1.0",
        maxVersion: String? = "2.0",
        paths: [String] = ["a/**"]
    ) -> VersionExclusion {
        VersionExclusion(bundleID: bundleID, minVersion: minVersion, maxVersion: maxVersion, paths: paths)
    }

    private func exclusion() -> VersionExclusion { Self.exclusion() }

    private func makeRule(provenance: Provenance?, exclusions: [VersionExclusion]) -> CleanupRule {
        CleanupRule(
            id: "r", module: "m", category: "c", name: "n", description: "d",
            allowlistRoots: ["~/Library/Caches"], paths: [], patterns: ["**"], exclusions: [],
            minAgeSeconds: nil, isTrashSafe: true, provenance: provenance, versionExclusions: exclusions
        )
    }

    private func versionRule() throws -> CleanupRule {
        try #require(RuleValidator.decode(fixtureData("rules-v2-version-exclusions")).rules.first)
    }

    private func fixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(name))
    }

    private func fixtureString(_ name: String) throws -> String {
        try String(contentsOf: fixtureURL(name), encoding: .utf8)
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
    }
}
