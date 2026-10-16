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

import Foundation

/// Describes a malformed JSON database or a semantic rule validation failure.
public enum RuleValidationError: Error, CustomStringConvertible, Equatable, Sendable {
    case malformedJSON(String)
    case unsupportedSchemaVersion(Int)
    case emptyAllowlistRoots(ruleID: String)
    case emptyAllowlistRoot(ruleID: String)
    case genericAllowlistRoot(ruleID: String, root: String)
    case duplicateRuleID(String)
    case invalidGlobPattern(ruleID: String, field: String, pattern: String, reason: String)
    case schemaV2FieldInV1Database(ruleID: String, field: String)
    case invalidAppPattern(ruleID: String, field: String, value: String, reason: String)
    case missingProvenance(ruleID: String)
    case invalidProvenance(ruleID: String, field: String, reason: String)

    public var description: String {
        switch self {
        case let .malformedJSON(reason):
            "Invalid rule database JSON: \(reason)"
        case let .unsupportedSchemaVersion(version):
            "Unsupported rule database schemaVersion \(version); expected 1 or 2"
        case let .emptyAllowlistRoots(ruleID):
            "Rule '\(ruleID)' must define at least one allowlist root"
        case let .emptyAllowlistRoot(ruleID):
            "Rule '\(ruleID)' contains an empty allowlist root"
        case let .genericAllowlistRoot(ruleID, root):
            "Rule '\(ruleID)' uses a generic or protected allowlist root '\(root)'"
        case let .duplicateRuleID(id):
            "Duplicate rule id '\(id)'"
        case let .invalidGlobPattern(ruleID, field, pattern, reason):
            "Rule '\(ruleID)' has an invalid glob in '\(field)': '\(pattern)' (\(reason))"
        case let .schemaV2FieldInV1Database(ruleID, field):
            "Rule '\(ruleID)' uses schema v2 field '\(field)' in a schemaVersion 1 database"
        case let .invalidAppPattern(ruleID, field, value, reason):
            "Rule '\(ruleID)' has an invalid '\(field)' value '\(value)': \(reason)"
        case let .missingProvenance(ruleID):
            "Rule '\(ruleID)' defines 'appPatterns' and must define 'provenance'"
        case let .invalidProvenance(ruleID, field, reason):
            "Rule '\(ruleID)' has an invalid 'provenance.\(field)': \(reason)"
        }
    }
}

/// Validates the semantic constraints of schema v1 and v2 rule databases.
public enum RuleValidator {
    /// Decodes JSON and reports malformed input or semantic failures as descriptive errors.
    public static func decode(_ data: Data) throws -> RuleDatabase {
        do {
            return try JSONDecoder().decode(RuleDatabase.self, from: data)
        } catch let error as RuleValidationError {
            throw error
        } catch let error as DecodingError {
            throw RuleValidationError.malformedJSON(decodingDescription(for: error))
        }
    }

    /// Validates a database independently of its decoding path.
    public static func validate(_ database: RuleDatabase) throws {
        guard database.schemaVersion == 1 || database.schemaVersion == 2 else {
            throw RuleValidationError.unsupportedSchemaVersion(database.schemaVersion)
        }

        var ruleIDs = Set<String>()
        for rule in database.rules {
            guard ruleIDs.insert(rule.id).inserted else {
                throw RuleValidationError.duplicateRuleID(rule.id)
            }
            try validate(allowlistRoots: rule.allowlistRoots, ruleID: rule.id)
            try validate(patterns: rule.patterns, field: "patterns", ruleID: rule.id)
            try validate(patterns: rule.exclusions, field: "exclusions", ruleID: rule.id)
            if database.schemaVersion == 1 {
                try rejectSchemaV2Fields(in: rule)
            } else {
                try validateSchemaV2Fields(of: rule)
            }
        }
    }

    private static func validate(allowlistRoots: [String], ruleID: String) throws {
        guard !allowlistRoots.isEmpty else {
            throw RuleValidationError.emptyAllowlistRoots(ruleID: ruleID)
        }

        for root in allowlistRoots {
            let trimmedRoot = root.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRoot.isEmpty else {
                throw RuleValidationError.emptyAllowlistRoot(ruleID: ruleID)
            }

            let normalizedRoot = normalizeAllowlistRoot(trimmedRoot)
            if normalizedRoot == "/" || normalizedRoot == "~" || isSystemRoot(normalizedRoot) {
                throw RuleValidationError.genericAllowlistRoot(ruleID: ruleID, root: root)
            }
        }
    }

    private static func validate(patterns: [String], field: String, ruleID: String) throws {
        for pattern in patterns {
            if let reason = globValidationError(in: pattern) {
                throw RuleValidationError.invalidGlobPattern(
                    ruleID: ruleID,
                    field: field,
                    pattern: pattern,
                    reason: reason
                )
            }
        }
    }

    static func normalizeAllowlistRoot(_ path: String) -> String {
        let isHomeRoot = path == "~" || path.hasPrefix("~/")
        guard isHomeRoot || path.hasPrefix("/") else {
            return path
        }

        let pathWithoutPrefix = isHomeRoot ? String(path.dropFirst()) : path
        var components: [Substring] = []
        for component in pathWithoutPrefix.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                }
            default:
                components.append(component)
            }
        }

        let normalizedPath = components.joined(separator: "/")
        if isHomeRoot {
            return normalizedPath.isEmpty ? "~" : "~/" + normalizedPath
        }
        return normalizedPath.isEmpty ? "/" : "/" + normalizedPath
    }

    private static func isSystemRoot(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return path.hasPrefix("/") &&
            components.first?.caseInsensitiveCompare("System") == .orderedSame
    }

    private static func globValidationError(in pattern: String) -> String? {
        var inCharacterClass = false
        var characterClassHasMember = false
        var isEscaped = false

        for character in pattern {
            if let reason = consumeGlobCharacter(
                character,
                inCharacterClass: &inCharacterClass,
                characterClassHasMember: &characterClassHasMember,
                isEscaped: &isEscaped
            ) {
                return reason
            }
        }

        if isEscaped {
            return "trailing escape"
        }
        if inCharacterClass {
            return "unclosed character class"
        }
        return nil
    }

    private static func consumeGlobCharacter(
        _ character: Character,
        inCharacterClass: inout Bool,
        characterClassHasMember: inout Bool,
        isEscaped: inout Bool
    ) -> String? {
        if isEscaped {
            characterClassHasMember = characterClassHasMember || inCharacterClass
            isEscaped = false
            return nil
        }
        if character == "\\" {
            isEscaped = true
            return nil
        }
        if !inCharacterClass {
            if character == "[" {
                inCharacterClass = true
                characterClassHasMember = false
            }
            return nil
        }
        if character == "]" {
            guard characterClassHasMember else {
                return "empty character class"
            }
            inCharacterClass = false
            return nil
        }
        if character == "[" {
            return "nested character class"
        }
        if character != "!" && character != "^" || characterClassHasMember {
            characterClassHasMember = true
        }
        return nil
    }

    private static func decodingDescription(for error: DecodingError) -> String {
        switch error {
        case let .dataCorrupted(context):
            context.debugDescription
        case let .keyNotFound(key, context):
            "Missing required key '\(key.stringValue)': \(context.debugDescription)"
        case let .typeMismatch(type, context):
            "Expected \(type) at \(codingPath(context.codingPath)): \(context.debugDescription)"
        case let .valueNotFound(type, context):
            "Missing \(type) at \(codingPath(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            error.localizedDescription
        }
    }

    private static func codingPath(_ codingPath: [any CodingKey]) -> String {
        codingPath.map(\.stringValue).joined(separator: ".")
    }
}
