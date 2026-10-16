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

/// Schema v2 validation of bundle-ID app patterns and provenance metadata (docs/design.md §11.2).
extension RuleValidator {
    /// The only `~/Library` subfolders app patterns may point into (docs/design.md §11.4).
    static let leftoverRoots = [
        "~/Library/Application Support",
        "~/Library/Caches",
        "~/Library/Preferences",
        "~/Library/Containers",
        "~/Library/Group Containers",
        "~/Library/Saved Application State",
        "~/Library/Logs",
        "~/Library/HTTPStorages",
        "~/Library/WebKit"
    ]

    static let bundleIDPlaceholder = "{bundleID}"

    /// Rejects v2-only fields in a schema v1 database so v1 rules keep their v0.1 meaning.
    static func rejectSchemaV2Fields(in rule: CleanupRule) throws {
        if rule.appPatterns != nil {
            throw RuleValidationError.schemaV2FieldInV1Database(ruleID: rule.id, field: "appPatterns")
        }
        if rule.provenance != nil {
            throw RuleValidationError.schemaV2FieldInV1Database(ruleID: rule.id, field: "provenance")
        }
    }

    static func validateSchemaV2Fields(of rule: CleanupRule) throws {
        if let appPatterns = rule.appPatterns {
            guard !appPatterns.isEmpty else {
                throw RuleValidationError.invalidAppPattern(
                    ruleID: rule.id,
                    field: "appPatterns",
                    value: "[]",
                    reason: "must not be empty when present"
                )
            }
            guard rule.provenance != nil else {
                throw RuleValidationError.missingProvenance(ruleID: rule.id)
            }
            for (index, appPattern) in appPatterns.enumerated() {
                try validate(appPattern: appPattern, field: "appPatterns[\(index)]", rule: rule)
            }
        }
        if let provenance = rule.provenance {
            try validate(provenance: provenance, ruleID: rule.id)
        }
    }

    private static func validate(appPattern: AppPattern, field: String, rule: CleanupRule) throws {
        func reject(_ subfield: String, _ value: String, _ reason: String) -> RuleValidationError {
            .invalidAppPattern(ruleID: rule.id, field: "\(field).\(subfield)", value: value, reason: reason)
        }

        if let reason = identifierValidationError(appPattern.bundleID, minimumComponents: 2) {
            throw reject("bundleID", appPattern.bundleID, reason)
        }
        guard !appPattern.paths.isEmpty else {
            throw reject("paths", "[]", "must not be empty")
        }
        let allowlistRoots = rule.allowlistRoots.map {
            normalizeAllowlistRoot($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        for (index, path) in appPattern.paths.enumerated() {
            if let reason = appPathValidationError(
                path,
                bundleID: appPattern.bundleID,
                allowlistRoots: allowlistRoots
            ) {
                throw reject("paths[\(index)]", path, reason)
            }
        }

        switch (appPattern.shared, appPattern.groupIdentifier) {
        case (true, nil):
            throw reject("groupIdentifier", "", "is required when 'shared' is true")
        case let (true, groupIdentifier?):
            if let reason = identifierValidationError(groupIdentifier, minimumComponents: 1) {
                throw reject("groupIdentifier", groupIdentifier, reason)
            }
        case let (false, groupIdentifier?):
            throw reject("groupIdentifier", groupIdentifier, "is only allowed when 'shared' is true")
        case (false, nil):
            break
        }
    }

    /// Validates a reverse-DNS style identifier: ASCII letters, digits, `-` and `.` only, so no globs.
    private static func identifierValidationError(_ identifier: String, minimumComponents: Int) -> String? {
        guard !identifier.isEmpty else {
            return "must not be empty"
        }
        if let invalid = identifier.unicodeScalars.first(where: { !isIdentifierScalar($0) }) {
            return "contains '\(invalid)'; only ASCII letters, digits, '-' and '.' are allowed"
        }
        let components = identifier.split(separator: ".", omittingEmptySubsequences: false)
        if components.contains(where: \.isEmpty) {
            return "contains an empty component"
        }
        if components.count < minimumComponents {
            return "must be reverse-DNS with at least \(minimumComponents) components"
        }
        return nil
    }

    private static func isIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", "-", ".":
            true
        default:
            false
        }
    }

    private static func appPathValidationError(
        _ path: String,
        bundleID: String,
        allowlistRoots: [String]
    ) -> String? {
        guard path.hasPrefix("~/Library/") else {
            return "must start with '~/Library/'"
        }
        let expandedPath = path.replacingOccurrences(of: bundleIDPlaceholder, with: bundleID)
        if expandedPath.contains("{") || expandedPath.contains("}") {
            return "only the '\(bundleIDPlaceholder)' placeholder is allowed"
        }
        if expandedPath.contains(where: { "*?[]\\".contains($0) }) {
            return "glob characters are not allowed"
        }
        if expandedPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return "control characters are not allowed"
        }
        let components = expandedPath.split(separator: "/", omittingEmptySubsequences: true)
        if components.contains("..") {
            return "must not contain '..'"
        }
        // Literal components only: bundle IDs such as `com.example.App` legitimately end in `.App`.
        let literalComponents = path.split(separator: "/").filter { !$0.contains(bundleIDPlaceholder) }
        if literalComponents.contains(where: { $0.lowercased().hasSuffix(".app") }) {
            return "must not target an application bundle"
        }

        let normalizedPath = normalizeAllowlistRoot(expandedPath)
        guard leftoverRoots.contains(where: { normalizedPath.hasPrefix($0 + "/") }) else {
            return "must lie inside one of the leftover roots (docs/design.md §11.4)"
        }
        guard allowlistRoots.contains(where: { normalizedPath == $0 || normalizedPath.hasPrefix($0 + "/") }) else {
            return "must lie under one of the rule's allowlistRoots"
        }
        return nil
    }

    private static func validate(provenance: Provenance, ruleID: String) throws {
        let requiredText = [
            ("source", provenance.source),
            ("author", provenance.author),
            ("rationale", provenance.rationale)
        ]
        for (field, value) in requiredText where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RuleValidationError.invalidProvenance(ruleID: ruleID, field: field, reason: "must not be empty")
        }
        if provenance.author.contains(where: \.isWhitespace) {
            throw RuleValidationError.invalidProvenance(
                ruleID: ruleID,
                field: "author",
                reason: "must be a GitHub handle without whitespace"
            )
        }
        guard isISO8601Date(provenance.date) else {
            throw RuleValidationError.invalidProvenance(
                ruleID: ruleID,
                field: "date",
                reason: "'\(provenance.date)' is not a valid ISO 8601 date (YYYY-MM-DD)"
            )
        }
    }

    private static func isISO8601Date(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.map(\.count) == [4, 2, 2],
              parts.allSatisfy({ part in part.unicodeScalars.allSatisfy { ("0"..."9").contains($0) } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        return DateComponents(calendar: calendar, year: year, month: month, day: day).isValidDate
    }
}
