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

/// Versioned collection of cleanup rules loaded from a JSON rule database.
public struct RuleDatabase: Codable, Equatable, Sendable {
    /// Version identifier for this database release, for example `2026.1`.
    public let version: String

    /// Version of the JSON schema used by this database.
    public let schemaVersion: Int

    /// Rules available to cleanup modules.
    public let rules: [CleanupRule]

    public init(version: String, schemaVersion: Int, rules: [CleanupRule]) throws {
        self.version = version
        self.schemaVersion = schemaVersion
        self.rules = rules
        try RuleValidator.validate(self)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        rules = try container.decode([CleanupRule].self, forKey: .rules)
        try RuleValidator.validate(self)
    }
}

/// Declarative cleanup rule consumed by a cleanup module and the rule engine.
public struct CleanupRule: Codable, Equatable, Sendable {
    /// Stable identifier unique within a rule database.
    public let id: String

    /// Identifier of the module that evaluates this rule.
    public let module: String

    /// User-facing grouping for the rule.
    public let category: String

    /// User-facing rule name.
    public let name: String

    /// User-facing explanation of what the rule matches.
    public let description: String

    /// Narrow filesystem roots that the rule may inspect.
    public let allowlistRoots: [String]

    /// Explicit paths interpreted by the consuming module.
    public let paths: [String]

    /// Glob patterns used to select matching paths.
    public let patterns: [String]

    /// Glob patterns excluded even when they match `patterns`.
    public let exclusions: [String]

    /// Minimum age of an item in seconds, or `nil` when no age threshold applies.
    public let minAgeSeconds: Int64?

    /// Whether matching items may be recommended for trashing.
    public let isTrashSafe: Bool

    public init(
        id: String,
        module: String,
        category: String,
        name: String,
        description: String,
        allowlistRoots: [String],
        paths: [String],
        patterns: [String],
        exclusions: [String],
        minAgeSeconds: Int64?,
        isTrashSafe: Bool
    ) {
        self.id = id
        self.module = module
        self.category = category
        self.name = name
        self.description = description
        self.allowlistRoots = allowlistRoots
        self.paths = paths
        self.patterns = patterns
        self.exclusions = exclusions
        self.minAgeSeconds = minAgeSeconds
        self.isTrashSafe = isTrashSafe
    }
}
