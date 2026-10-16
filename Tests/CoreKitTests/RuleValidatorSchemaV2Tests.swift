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

struct RuleValidatorSchemaV2Tests {
    // MARK: - Fixtures

    @Test func decodesSchemaV2Fixture() throws {
        let database = try RuleValidator.decode(fixtureData("rules-v2-valid"))

        #expect(database.schemaVersion == 2)
        #expect(database.rules.map(\.id) == [
            "caches.user.basic",
            "leftovers.example.editor",
            "leftovers.example.suite"
        ])

        let v1Rule = database.rules[0]
        #expect(v1Rule.appPatterns == nil)
        #expect(v1Rule.provenance == nil)
        #expect(v1Rule.minAgeSeconds == 86_400)

        let editor = database.rules[1]
        #expect(editor.appPatterns == [
            AppPattern(
                bundleID: "com.example.Editor",
                paths: [
                    "~/Library/Application Support/Example Editor",
                    "~/Library/Caches/{bundleID}",
                    "~/Library/Preferences/{bundleID}.plist"
                ]
            )
        ])
        #expect(editor.provenance == Provenance(
            source: "https://example.com/editor/uninstall",
            author: "terso-maintainer",
            date: "2026-10-16",
            rationale: "Vendor documentation lists these locations as created by the app."
        ))

        let suitePattern = try #require(database.rules[2].appPatterns?.first)
        #expect(suitePattern.shared)
        #expect(suitePattern.groupIdentifier == "ABCDE12345.com.example.suite")
    }

    @Test func schemaV1FixturesStayLoadableWithUnchangedMeaning() throws {
        let fixture = try RuleValidator.decode(fixtureData("rules-v1-valid"))
        #expect(fixture.schemaVersion == 1)
        #expect(fixture.rules.allSatisfy { $0.appPatterns == nil && $0.provenance == nil })

        let shippedURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Rules/v2026.1.json")
        let shipped = try RuleValidator.decode(Data(contentsOf: shippedURL))
        #expect(shipped.schemaVersion == 1)
        #expect(!shipped.rules.isEmpty)
        #expect(shipped.rules.allSatisfy { $0.appPatterns == nil && $0.provenance == nil })
    }

    @Test func encodingAV1RuleOmitsSchemaV2Fields() throws {
        let database = try RuleValidator.decode(fixtureData("rules-v1-valid"))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(database)) as? [String: Any]
        let rule = try #require((encoded?["rules"] as? [[String: Any]])?.first)
        #expect(rule["appPatterns"] == nil)
        #expect(rule["provenance"] == nil)
    }

    @Test func schemaV2DatabaseRoundTripsThroughJSON() throws {
        let database = try RuleValidator.decode(fixtureData("rules-v2-valid"))
        let decoded = try RuleValidator.decode(JSONEncoder().encode(database))
        #expect(decoded == database)
    }

    @Test func rejectsMissingProvenanceFixture() throws {
        let error = try validationError(for: fixtureData("rules-v2-missing-provenance"))
        #expect(error == .missingProvenance(ruleID: "leftovers.example.editor"))
        #expect(error.description.contains("provenance"))
    }

    @Test func rejectsEscapingPathFixture() throws {
        let error = try validationError(for: fixtureData("rules-v2-escaping-path"))
        #expect(error == .invalidAppPattern(
            ruleID: "leftovers.hostile",
            field: "appPatterns[0].paths[0]",
            value: "~/Library/Caches/{bundleID}/../../../Documents",
            reason: "must not contain '..'"
        ))
        #expect(error.description.contains("leftovers.hostile"))
        #expect(error.description.contains("appPatterns[0].paths[0]"))
    }

    @Test func rejectsSchemaV2FieldsInV1DatabaseFixture() throws {
        let error = try validationError(for: fixtureData("rules-v1-with-v2-fields"))
        #expect(error == .schemaV2FieldInV1Database(ruleID: "leftovers.example.editor", field: "appPatterns"))
    }

    @Test func rejectsProvenanceInV1Database() throws {
        var rule = makeRule()
        rule["appPatterns"] = nil
        let error = try validationError(for: makeDatabaseData(rule: rule, schemaVersion: 1))
        #expect(error == .schemaV2FieldInV1Database(ruleID: "fixture.rule", field: "provenance"))
    }

    // MARK: - Bundle ID

    @Test(arguments: [
        ("", "must not be empty"),
        ("com", "must be reverse-DNS with at least 2 components"),
        ("com..example", "contains an empty component"),
        (".com.example", "contains an empty component"),
        ("com.example.", "contains an empty component"),
        ("com.example.*", "contains '*'; only ASCII letters, digits, '-' and '.' are allowed"),
        ("com.example.App?", "contains '?'; only ASCII letters, digits, '-' and '.' are allowed"),
        ("com.example.[A]", "contains '['; only ASCII letters, digits, '-' and '.' are allowed"),
        ("com.example/App", "contains '/'; only ASCII letters, digits, '-' and '.' are allowed"),
        ("com.example. App", "contains ' '; only ASCII letters, digits, '-' and '.' are allowed"),
        ("com.exämple.App", "contains 'ä'; only ASCII letters, digits, '-' and '.' are allowed")
    ])
    func rejectsInvalidBundleIDs(bundleID: String, reason: String) throws {
        let data = try makeDatabaseData(rule: makeRule(bundleID: bundleID, paths: ["~/Library/Caches/com.example"]))
        let error = try validationError(for: data)
        #expect(error == .invalidAppPattern(
            ruleID: "fixture.rule",
            field: "appPatterns[0].bundleID",
            value: bundleID,
            reason: reason
        ))
    }

    @Test(arguments: ["com.example.App", "com.example-corp.App2", "org.mozilla.firefox", "A1.b2"])
    func acceptsValidBundleIDs(bundleID: String) throws {
        let data = try makeDatabaseData(rule: makeRule(bundleID: bundleID))
        _ = try RuleValidator.decode(data)
    }

    // MARK: - Paths and hostile patterns

    @Test(arguments: [
        ("/Library/Caches/{bundleID}", "must start with '~/Library/'"),
        ("~/Documents/{bundleID}", "must start with '~/Library/'"),
        ("~/Desktop", "must start with '~/Library/'"),
        ("/System/Library/{bundleID}", "must start with '~/Library/'"),
        ("/private/var/db/{bundleID}", "must start with '~/Library/'"),
        ("Library/Caches/{bundleID}", "must start with '~/Library/'"),
        ("~/Library/Caches/{bundleID}/../../../Desktop", "must not contain '..'"),
        ("~/Library/Caches/..", "must not contain '..'"),
        ("~/Library/Caches/{bundleId}", "only the '{bundleID}' placeholder is allowed"),
        ("~/Library/Caches/{home}", "only the '{bundleID}' placeholder is allowed"),
        ("~/Library/Caches/*", "glob characters are not allowed"),
        ("~/Library/Caches/**/{bundleID}", "glob characters are not allowed"),
        ("~/Library/Caches/{bundleID}?", "glob characters are not allowed"),
        ("~/Library/Caches/[a-z]", "glob characters are not allowed"),
        ("~/Library/Caches/\u{0}x", "control characters are not allowed"),
        ("~/Library/Caches/Helper.app", "must not target an application bundle"),
        ("~/Library/Caches/Helper.APP/Contents", "must not target an application bundle"),
        ("~/Library/Caches", "must lie inside one of the leftover roots (docs/design.md §11.4)"),
        ("~/Library/Caches/", "must lie inside one of the leftover roots (docs/design.md §11.4)"),
        ("~/Library/./Caches", "must lie inside one of the leftover roots (docs/design.md §11.4)"),
        ("~/Library/Keychains/{bundleID}", "must lie inside one of the leftover roots (docs/design.md §11.4)"),
        ("~/Library/LaunchAgents/{bundleID}.plist", "must lie inside one of the leftover roots (docs/design.md §11.4)"),
        ("~/Library/caches/{bundleID}", "must lie inside one of the leftover roots (docs/design.md §11.4)"),
        ("~/Library/CachesEvil/{bundleID}", "must lie inside one of the leftover roots (docs/design.md §11.4)"),
        ("~/Library/Logs/{bundleID}", "must lie under one of the rule's allowlistRoots")
    ])
    func rejectsHostileOrInvalidPaths(path: String, reason: String) throws {
        let data = try makeDatabaseData(rule: makeRule(paths: [path]))
        let error = try validationError(for: data)
        #expect(error == .invalidAppPattern(
            ruleID: "fixture.rule",
            field: "appPatterns[0].paths[0]",
            value: path,
            reason: reason
        ))
    }

    @Test func patternsCannotWidenANarrowAllowlistRoot() throws {
        let rule = makeRule(
            allowlistRoots: ["~/Library/Caches/com.example.App"],
            paths: ["~/Library/Caches/com.example.Other"]
        )
        let error = try validationError(for: makeDatabaseData(rule: rule))
        #expect(error == .invalidAppPattern(
            ruleID: "fixture.rule",
            field: "appPatterns[0].paths[0]",
            value: "~/Library/Caches/com.example.Other",
            reason: "must lie under one of the rule's allowlistRoots"
        ))
    }

    @Test func protectedAllowlistRootDoesNotAuthorizeAppPatterns() throws {
        let rule = makeRule(allowlistRoots: ["~/Documents"], paths: ["~/Documents/{bundleID}"])
        let error = try validationError(for: makeDatabaseData(rule: rule))
        guard case let .invalidAppPattern(_, field, _, reason) = error else {
            Issue.record("Expected invalidAppPattern, got \(error)")
            return
        }
        #expect(field == "appPatterns[0].paths[0]")
        #expect(reason == "must start with '~/Library/'")
    }

    @Test func acceptsPathEqualToANarrowAllowlistRoot() throws {
        let rule = makeRule(
            allowlistRoots: ["~/Library/Caches/com.example.App"],
            paths: ["~/Library/Caches/{bundleID}"]
        )
        _ = try RuleValidator.decode(makeDatabaseData(rule: rule))
    }

    @Test func reportsIndexOfFailingPatternAndPath() throws {
        var rule = makeRule()
        rule["appPatterns"] = [
            ["bundleID": "com.example.App", "paths": ["~/Library/Caches/{bundleID}"]],
            ["bundleID": "com.example.Other", "paths": ["~/Library/Caches/{bundleID}", "~/Library/Caches/*"]]
        ]
        let error = try validationError(for: makeDatabaseData(rule: rule))
        guard case let .invalidAppPattern(_, field, _, _) = error else {
            Issue.record("Expected invalidAppPattern, got \(error)")
            return
        }
        #expect(field == "appPatterns[1].paths[1]")
    }

    @Test func rejectsEmptyAppPatternsAndEmptyPaths() throws {
        var rule = makeRule()
        rule["appPatterns"] = []
        #expect(try validationError(for: makeDatabaseData(rule: rule)) == .invalidAppPattern(
            ruleID: "fixture.rule",
            field: "appPatterns",
            value: "[]",
            reason: "must not be empty when present"
        ))

        let emptyPaths = makeRule(paths: [])
        #expect(try validationError(for: makeDatabaseData(rule: emptyPaths)) == .invalidAppPattern(
            ruleID: "fixture.rule",
            field: "appPatterns[0].paths",
            value: "[]",
            reason: "must not be empty"
        ))
    }

    @Test func rejectsMissingBundleIDAsMalformedJSON() throws {
        var rule = makeRule()
        rule["appPatterns"] = [["paths": ["~/Library/Caches/x"]]]
        let error = try validationError(for: makeDatabaseData(rule: rule))
        guard case let .malformedJSON(reason) = error else {
            Issue.record("Expected malformedJSON, got \(error)")
            return
        }
        #expect(reason.contains("bundleID"))
    }
}

extension RuleValidatorSchemaV2Tests {
    // MARK: - Shared locations

    @Test func sharedPatternRequiresGroupIdentifier() throws {
        let rule = makeRule(paths: ["~/Library/Group Containers/group.com.example"], shared: true)
        #expect(try validationError(for: makeDatabaseData(rule: rule)) == .invalidAppPattern(
            ruleID: "fixture.rule",
            field: "appPatterns[0].groupIdentifier",
            value: "",
            reason: "is required when 'shared' is true"
        ))
    }

    @Test func groupIdentifierRequiresSharedPattern() throws {
        let rule = makeRule(groupIdentifier: "group.com.example")
        #expect(try validationError(for: makeDatabaseData(rule: rule)) == .invalidAppPattern(
            ruleID: "fixture.rule",
            field: "appPatterns[0].groupIdentifier",
            value: "group.com.example",
            reason: "is only allowed when 'shared' is true"
        ))
    }

    @Test(arguments: ["", "group.*", "group..example", "team id"])
    func rejectsInvalidGroupIdentifiers(groupIdentifier: String) throws {
        let rule = makeRule(shared: true, groupIdentifier: groupIdentifier)
        let error = try validationError(for: makeDatabaseData(rule: rule))
        guard case let .invalidAppPattern(_, field, value, _) = error else {
            Issue.record("Expected invalidAppPattern, got \(error)")
            return
        }
        #expect(field == "appPatterns[0].groupIdentifier")
        #expect(value == groupIdentifier)
    }

    @Test(arguments: ["UBF8T346G9", "group.com.example.suite", "UBF8T346G9.Office"])
    func acceptsValidGroupIdentifiers(groupIdentifier: String) throws {
        let rule = makeRule(shared: true, groupIdentifier: groupIdentifier)
        _ = try RuleValidator.decode(makeDatabaseData(rule: rule))
    }

    // MARK: - Provenance

    @Test(arguments: ["source", "author", "rationale"])
    func rejectsEmptyProvenanceText(field: String) throws {
        let data = try makeDatabaseData(rule: makeRule(provenance: [field: "  "]))
        #expect(try validationError(for: data) == .invalidProvenance(
            ruleID: "fixture.rule",
            field: field,
            reason: "must not be empty"
        ))
    }

    @Test func rejectsAuthorWithWhitespace() throws {
        let data = try makeDatabaseData(rule: makeRule(provenance: ["author": "Jane Doe"]))
        #expect(try validationError(for: data) == .invalidProvenance(
            ruleID: "fixture.rule",
            field: "author",
            reason: "must be a GitHub handle without whitespace"
        ))
    }

    @Test(arguments: [
        "", "2026-1-01", "2026/01/01", "26-01-01", "2026-13-01", "2026-02-30", "2026-01-01T00:00:00Z", "２０２６-01-01"
    ])
    func rejectsInvalidProvenanceDates(date: String) throws {
        let data = try makeDatabaseData(rule: makeRule(provenance: ["date": date]))
        let error = try validationError(for: data)
        guard case let .invalidProvenance(ruleID, field, _) = error else {
            Issue.record("Expected invalidProvenance, got \(error)")
            return
        }
        #expect(ruleID == "fixture.rule")
        #expect(field == "date")
    }

    @Test(arguments: ["2024-02-29", "2026-12-31"])
    func acceptsValidProvenanceDates(date: String) throws {
        _ = try RuleValidator.decode(makeDatabaseData(rule: makeRule(provenance: ["date": date])))
    }

    @Test func rejectsMissingProvenanceFieldAsMalformedJSON() throws {
        var rule = makeRule()
        rule["provenance"] = ["source": "x", "author": "y", "date": "2026-01-01"]
        let error = try validationError(for: makeDatabaseData(rule: rule))
        guard case let .malformedJSON(reason) = error else {
            Issue.record("Expected malformedJSON, got \(error)")
            return
        }
        #expect(reason.contains("rationale"))
    }

    @Test func validatesProvenanceOnRulesWithoutAppPatterns() throws {
        var rule = makeRule(provenance: ["date": "yesterday"])
        rule["appPatterns"] = nil
        let error = try validationError(for: makeDatabaseData(rule: rule))
        guard case .invalidProvenance(_, "date", _) = error else {
            Issue.record("Expected invalidProvenance for date, got \(error)")
            return
        }
    }

    @Test func provenanceIsOptionalWithoutAppPatterns() throws {
        var rule = makeRule()
        rule["appPatterns"] = nil
        rule["provenance"] = nil
        let database = try RuleValidator.decode(makeDatabaseData(rule: rule))
        #expect(database.rules[0].provenance == nil)
    }

    // MARK: - Helpers

    private func fixtureData(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func validationError(for data: Data) throws -> RuleValidationError {
        do {
            _ = try RuleValidator.decode(data)
        } catch let error as RuleValidationError {
            #expect(!error.description.isEmpty)
            return error
        }
        Issue.record("Expected the rule database to be rejected")
        throw CancellationError()
    }

    private func makeRule(
        allowlistRoots: [String] = ["~/Library/Caches", "~/Library/Group Containers"],
        bundleID: String = "com.example.App",
        paths: [String] = ["~/Library/Caches/{bundleID}"],
        shared: Bool? = nil,
        groupIdentifier: String? = nil,
        provenance overrides: [String: String] = [:]
    ) -> [String: Any] {
        var appPattern: [String: Any] = ["bundleID": bundleID, "paths": paths]
        appPattern["shared"] = shared
        appPattern["groupIdentifier"] = groupIdentifier
        let provenance = [
            "source": "https://example.com/app",
            "author": "terso-maintainer",
            "date": "2026-10-16",
            "rationale": "Fixture rationale."
        ].merging(overrides) { _, override in override }
        return [
            "id": "fixture.rule",
            "module": "leftovers",
            "category": "Leftovers",
            "name": "Fixture rule",
            "description": "Rule used by schema v2 validator tests.",
            "allowlistRoots": allowlistRoots,
            "paths": [],
            "patterns": [],
            "exclusions": [],
            "isTrashSafe": true,
            "appPatterns": [appPattern],
            "provenance": provenance
        ]
    }

    private func makeDatabaseData(rule: [String: Any], schemaVersion: Int = 2) throws -> Data {
        let database: [String: Any] = [
            "version": "test",
            "schemaVersion": schemaVersion,
            "rules": [rule]
        ]
        return try JSONSerialization.data(withJSONObject: database)
    }
}
