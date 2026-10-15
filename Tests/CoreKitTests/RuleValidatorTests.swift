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

struct RuleValidatorTests {
    @Test func decodesSchemaV1Fixture() throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "rules-v1-valid", withExtension: "json"))
        let data = try Data(contentsOf: fixtureURL)
        let database = try RuleValidator.decode(data)

        #expect(database.version == "2026.1")
        #expect(database.schemaVersion == 1)
        #expect(database.rules.count == 1)
        #expect(database.rules[0].id == "caches.user.basic")
        #expect(database.rules[0].allowlistRoots == ["~/Library/Caches"])
        #expect(database.rules[0].patterns == ["*.tmp", "**/*.log", "[0-9]*.cache"])
        #expect(database.rules[0].minAgeSeconds == 86_400)
        #expect(database.rules[0].isTrashSafe)
    }

    @Test(arguments: ["", " ", "/", "//", "~", "~/", "/System", "/System/Library", "/System/../"])
    func rejectsEmptyOrGenericAllowlistRoots(root: String) throws {
        let data = try makeDatabaseData(roots: [root])
        do {
            _ = try RuleValidator.decode(data)
            Issue.record("Expected allowlist root '\(root)' to be rejected")
        } catch let error as RuleValidationError {
            #expect(
                error == .emptyAllowlistRoot(ruleID: "fixture.rule") ||
                    error == .genericAllowlistRoot(ruleID: "fixture.rule", root: root)
            )
            #expect(!error.description.isEmpty)
        }
    }

    @Test func rejectsRulesWithoutAllowlistRoots() throws {
        let data = try makeDatabaseData(roots: [])
        do {
            _ = try JSONDecoder().decode(RuleDatabase.self, from: data)
            Issue.record("Expected a rule with no allowlist roots to be rejected")
        } catch let error as RuleValidationError {
            #expect(error == .emptyAllowlistRoots(ruleID: "fixture.rule"))
        }
    }

    @Test func rejectsDuplicateRuleIDs() throws {
        let data = try makeDatabaseData(roots: ["~/Library/Caches"], duplicateRule: true)
        do {
            _ = try RuleValidator.decode(data)
            Issue.record("Expected duplicate rule IDs to be rejected")
        } catch let error as RuleValidationError {
            #expect(error == .duplicateRuleID("fixture.rule"))
            #expect(error.description.contains("Duplicate rule id"))
        }
    }

    @Test(arguments: ["[", "logs[0-9", "trailing\\"])
    func rejectsMalformedGlobPatterns(pattern: String) throws {
        let data = try makeDatabaseData(roots: ["~/Library/Caches"], patterns: [pattern])
        do {
            _ = try RuleValidator.decode(data)
            Issue.record("Expected malformed glob '\(pattern)' to be rejected")
        } catch let error as RuleValidationError {
            guard case let .invalidGlobPattern(ruleID, field, invalidPattern, _) = error else {
                Issue.record("Expected invalidGlobPattern, got \(error)")
                return
            }
            #expect(ruleID == "fixture.rule")
            #expect(field == "patterns")
            #expect(invalidPattern == pattern)
        }
    }

    @Test func rejectsMalformedJSONWithDescription() throws {
        do {
            _ = try RuleValidator.decode(Data("{".utf8))
            Issue.record("Expected malformed JSON to be rejected")
        } catch let error as RuleValidationError {
            guard case let .malformedJSON(reason) = error else {
                Issue.record("Expected malformedJSON, got \(error)")
                return
            }
            #expect(!reason.isEmpty)
            #expect(error.description.contains("Invalid rule database JSON"))
        }
    }

    @Test func reportsMissingRequiredJSONKey() throws {
        let data = Data(#"{"version":"test","schemaVersion":1}"#.utf8)
        do {
            _ = try RuleValidator.decode(data)
            Issue.record("Expected a missing required key to be rejected")
        } catch let error as RuleValidationError {
            guard case let .malformedJSON(reason) = error else {
                Issue.record("Expected malformedJSON, got \(error)")
                return
            }
            #expect(reason.contains("rules"))
        }
    }

    @Test func validatesExclusionGlobSyntax() throws {
        let data = try makeDatabaseData(roots: ["~/Library/Caches"], exclusions: ["["])
        do {
            _ = try RuleValidator.decode(data)
            Issue.record("Expected malformed exclusion glob to be rejected")
        } catch let error as RuleValidationError {
            guard case let .invalidGlobPattern(_, field, _, _) = error else {
                Issue.record("Expected invalidGlobPattern, got \(error)")
                return
            }
            #expect(field == "exclusions")
        }
    }

    @Test func rejectsUnsupportedSchemaVersion() throws {
        let data = try makeDatabaseData(roots: ["~/Library/Caches"], schemaVersion: 2)
        do {
            _ = try RuleValidator.decode(data)
            Issue.record("Expected unsupported schema version to be rejected")
        } catch let error as RuleValidationError {
            #expect(error == .unsupportedSchemaVersion(2))
        }
    }

    private func makeDatabaseData(
        roots: [String],
        patterns: [String] = ["*.tmp"],
        exclusions: [String] = [],
        schemaVersion: Int = 1,
        duplicateRule: Bool = false
    ) throws -> Data {
        let rule: [String: Any] = [
            "id": "fixture.rule",
            "module": "fixture",
            "category": "Test",
            "name": "Fixture rule",
            "description": "Rule used by validator tests.",
            "allowlistRoots": roots,
            "paths": [],
            "patterns": patterns,
            "exclusions": exclusions,
            "isTrashSafe": true
        ]
        var rules = [rule]
        if duplicateRule {
            rules.append(rule)
        }
        let database: [String: Any] = [
            "version": "test",
            "schemaVersion": schemaVersion,
            "rules": rules
        ]
        return try JSONSerialization.data(withJSONObject: database)
    }
}
