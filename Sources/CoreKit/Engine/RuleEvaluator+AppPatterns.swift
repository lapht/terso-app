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

/// A filesystem item associated with an app bundle ID by a schema v2 app pattern.
public struct AppPatternMatch: Equatable, Sendable {
    /// Rule that declared the app pattern.
    public let ruleID: String

    /// Bundle ID the item belongs to.
    public let bundleID: String

    /// Standardized location of the matched item.
    public let url: URL

    /// Whether the location may be shared by several apps.
    public let shared: Bool

    /// Group identifier used to detect other installed apps sharing the location.
    public let groupIdentifier: String?
}

extension RuleEvaluator {
    /// Returns the candidates that are exactly one of the rule's app pattern paths.
    ///
    /// The rule's v2 fields are validated again, so a hand-built `CleanupRule` cannot
    /// bypass the loader. Every candidate passes the same allowlist and symlink checks
    /// as `evaluate(rule:candidates:now:)`; unsafe candidates are thrown, never skipped.
    /// Paths are compared exactly after `{bundleID}` substitution. Results follow
    /// candidate order, then app pattern and path order, so they are deterministic.
    public func evaluateAppPatterns(rule: CleanupRule, candidates: [URL]) throws -> [AppPatternMatch] {
        try RuleValidator.validateSchemaV2Fields(of: rule)
        guard let appPatterns = rule.appPatterns else {
            return []
        }

        let allowedRoots = try rule.allowlistRoots.map { try expandAllowlistRoot($0, ruleID: rule.id) }
        let resolvedPaths = appPatterns.flatMap { appPattern in
            appPattern.paths.map { path in
                (appPattern, expandAppPath(path, bundleID: appPattern.bundleID))
            }
        }
        var matches: [AppPatternMatch] = []

        for candidate in candidates {
            try pathValidator.validate(path: candidate, allowedRoots: allowedRoots)
            _ = try symlinkValidator.resolveAndValidate(path: candidate, allowedRoots: allowedRoots)
            try pathValidator.validate(
                path: candidate.resolvingSymlinksInPath().standardizedFileURL,
                allowedRoots: allowedRoots
            )

            let candidateURL = candidate.standardizedFileURL
            for (appPattern, url) in resolvedPaths where url.path == candidateURL.path {
                matches.append(AppPatternMatch(
                    ruleID: rule.id,
                    bundleID: appPattern.bundleID,
                    url: candidateURL,
                    shared: appPattern.shared,
                    groupIdentifier: appPattern.groupIdentifier
                ))
            }
        }

        return matches
    }

    func expandAppPath(_ path: String, bundleID: String) -> URL {
        let expandedPath = path.replacingOccurrences(of: RuleValidator.bundleIDPlaceholder, with: bundleID)
        return homeDirectory.appendingPathComponent(String(expandedPath.dropFirst(2))).standardizedFileURL
    }
}
