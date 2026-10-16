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

    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, schemaVersion, rules
    }

    public init(from decoder: Decoder) throws {
        do {
            try decoder.rejectUnknownKeys(CodingKeys.self)
        } catch let error as UnknownFieldError {
            throw RuleValidationError.unknownField(ruleID: nil, field: error.field(relativeTo: decoder.codingPath))
        }
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

    /// Schema v2 paths associated with installed or removed apps, keyed by bundle ID.
    public let appPatterns: [AppPattern]?

    /// Schema v2 metadata describing where the rule comes from and why it is correct.
    public let provenance: Provenance?

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
        isTrashSafe: Bool,
        appPatterns: [AppPattern]? = nil,
        provenance: Provenance? = nil
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
        self.appPatterns = appPatterns
        self.provenance = provenance
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, module, category, name, description, allowlistRoots, paths, patterns, exclusions
        case minAgeSeconds, isTrashSafe, appPatterns, provenance
    }

    /// Decodes a rule and reports unknown keys, including nested ones, with this rule's id.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        do {
            try decoder.rejectUnknownKeys(CodingKeys.self)
            self.init(
                id: id,
                module: try container.decode(String.self, forKey: .module),
                category: try container.decode(String.self, forKey: .category),
                name: try container.decode(String.self, forKey: .name),
                description: try container.decode(String.self, forKey: .description),
                allowlistRoots: try container.decode([String].self, forKey: .allowlistRoots),
                paths: try container.decode([String].self, forKey: .paths),
                patterns: try container.decode([String].self, forKey: .patterns),
                exclusions: try container.decode([String].self, forKey: .exclusions),
                minAgeSeconds: try container.decodeIfPresent(Int64.self, forKey: .minAgeSeconds),
                isTrashSafe: try container.decode(Bool.self, forKey: .isTrashSafe),
                appPatterns: try container.decodeIfPresent([AppPattern].self, forKey: .appPatterns),
                provenance: try container.decodeIfPresent(Provenance.self, forKey: .provenance)
            )
        } catch let error as UnknownFieldError {
            throw RuleValidationError.unknownField(ruleID: id, field: error.field(relativeTo: decoder.codingPath))
        }
    }
}

/// Schema v2 set of `~/Library` paths that belong to a single app bundle ID.
public struct AppPattern: Codable, Equatable, Sendable {
    /// Reverse-DNS bundle ID matched exactly and case-sensitively.
    public let bundleID: String

    /// `~/Library/...` paths; `{bundleID}` is the only placeholder allowed.
    public let paths: [String]

    /// Whether the location is used by several apps, such as a group container.
    public let shared: Bool

    /// Team or group identifier used to detect other installed apps sharing a `shared` location.
    public let groupIdentifier: String?

    public init(bundleID: String, paths: [String], shared: Bool = false, groupIdentifier: String? = nil) {
        self.bundleID = bundleID
        self.paths = paths
        self.shared = shared
        self.groupIdentifier = groupIdentifier
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case bundleID, paths, shared, groupIdentifier
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        paths = try container.decode([String].self, forKey: .paths)
        shared = try container.decodeIfPresent(Bool.self, forKey: .shared) ?? false
        groupIdentifier = try container.decodeIfPresent(String.self, forKey: .groupIdentifier)
    }
}

/// Schema v2 audit metadata explaining the origin of a rule.
public struct Provenance: Codable, Equatable, Sendable {
    /// URL or reference, such as vendor documentation, an observed install or an issue.
    public let source: String

    /// GitHub handle of the person who proposed the rule.
    public let author: String

    /// ISO 8601 date (`YYYY-MM-DD`) of the last review.
    public let date: String

    /// Why the paths belong to the app and are safe to propose.
    public let rationale: String

    public init(source: String, author: String, date: String, rationale: String) {
        self.source = source
        self.author = author
        self.date = date
        self.rationale = rationale
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case source, author, date, rationale
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        author = try container.decode(String.self, forKey: .author)
        date = try container.decode(String.self, forKey: .date)
        rationale = try container.decode(String.self, forKey: .rationale)
    }
}
