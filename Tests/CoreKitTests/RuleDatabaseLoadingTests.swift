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

struct RuleDatabaseLoadingTests {
    @Test func rejectsVersionConditionalExclusionsAsUnknownField() throws {
        let error = try validationError(for: fixtureData("rules-v2-unknown-field"))
        #expect(error == .unknownField(ruleID: "leftovers.example.editor", field: "appPatterns[0].excludedVersions"))
        #expect(
            error.description == "Rule 'leftovers.example.editor' has unknown field 'appPatterns[0].excludedVersions'"
        )
    }

    @Test func rejectsUnsupportedSchemaVersionFixture() throws {
        let error = try validationError(for: fixtureData("rules-unsupported-schema"))
        #expect(error == .unsupportedSchemaVersion(3))
        #expect(error.description.contains("expected 1 or 2"))
    }

    @Test(arguments: [1, 2])
    func rejectsUnknownTopLevelField(schemaVersion: Int) throws {
        var database = makeDatabase(schemaVersion: schemaVersion)
        database["generatedBy"] = "tool"
        let error = try validationError(for: data(database))
        #expect(error == .unknownField(ruleID: nil, field: "generatedBy"))
        #expect(error.description == "Rule database has unknown top-level field 'generatedBy'")
    }

    @Test(arguments: [1, 2])
    func rejectsUnknownRuleField(schemaVersion: Int) throws {
        var rule = makeV1Rule()
        rule["isTrashsafe"] = true
        let error = try validationError(for: data(makeDatabase(schemaVersion: schemaVersion, rules: [rule])))
        #expect(error == .unknownField(ruleID: "fixture.rule", field: "isTrashsafe"))
    }

    @Test func reportsUnknownFieldInLaterAppPattern() throws {
        var rule = makeV2Rule()
        rule["appPatterns"] = [
            ["bundleID": "com.example.App", "paths": ["~/Library/Caches/{bundleID}"]],
            ["bundleID": "com.example.Other", "paths": ["~/Library/Caches/{bundleID}"], "minVersion": "2.0"]
        ]
        let error = try validationError(for: data(makeDatabase(rules: [rule])))
        #expect(error == .unknownField(ruleID: "fixture.rule", field: "appPatterns[1].minVersion"))
    }

    @Test func reportsUnknownProvenanceField() throws {
        var rule = makeV2Rule()
        rule["provenance"] = [
            "source": "https://example.com",
            "author": "terso-maintainer",
            "date": "2026-10-16",
            "rationale": "Fixture rationale.",
            "reviewer": "someone"
        ]
        let error = try validationError(for: data(makeDatabase(rules: [rule])))
        #expect(error == .unknownField(ruleID: "fixture.rule", field: "provenance.reviewer"))
    }

    @Test func reportsUnknownFieldOnTheRuleThatDeclaresIt() throws {
        var second = makeV1Rule(id: "fixture.second")
        second["note"] = "unexpected"
        let error = try validationError(for: data(makeDatabase(rules: [makeV1Rule(), second])))
        #expect(error == .unknownField(ruleID: "fixture.second", field: "note"))
    }

    @Test func reportsFirstUnknownFieldInSortedOrder() throws {
        var rule = makeV1Rule()
        rule["zeta"] = 1
        rule["alpha"] = 1
        let error = try validationError(for: data(makeDatabase(rules: [rule])))
        #expect(error == .unknownField(ruleID: "fixture.rule", field: "alpha"))
    }

    @Test func v1RuleCopiedIntoV2DatabaseDecodesIdentically() throws {
        let schemaV1 = try RuleValidator.decode(data(makeDatabase(schemaVersion: 1)))
        let schemaV2 = try RuleValidator.decode(data(makeDatabase(schemaVersion: 2)))
        #expect(schemaV1.rules == schemaV2.rules)
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
            return error
        }
        Issue.record("Expected the rule database to be rejected")
        throw CancellationError()
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func makeDatabase(schemaVersion: Int = 2, rules: [[String: Any]]? = nil) -> [String: Any] {
        ["version": "test", "schemaVersion": schemaVersion, "rules": rules ?? [makeV1Rule()]]
    }

    private func makeV1Rule(id: String = "fixture.rule") -> [String: Any] {
        [
            "id": id,
            "module": "fixture",
            "category": "Test",
            "name": "Fixture rule",
            "description": "Rule used by loading tests.",
            "allowlistRoots": ["~/Library/Caches"],
            "paths": [],
            "patterns": ["*.tmp"],
            "exclusions": [],
            "minAgeSeconds": 60,
            "isTrashSafe": true
        ]
    }

    private func makeV2Rule() -> [String: Any] {
        var rule = makeV1Rule()
        rule["appPatterns"] = [["bundleID": "com.example.App", "paths": ["~/Library/Caches/{bundleID}"]]]
        rule["provenance"] = [
            "source": "https://example.com",
            "author": "terso-maintainer",
            "date": "2026-10-16",
            "rationale": "Fixture rationale."
        ]
        return rule
    }
}
