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

extension CleanupRule {
    /// Glob exclusions from `versionExclusions` that apply given the installed app versions.
    ///
    /// `installedVersions` maps a bundle ID to its `CFBundleShortVersionString`, or to `nil`
    /// when the version is unknown. Fail-safe: when the app is not in the map, its version is
    /// `nil` or it cannot be parsed, the exclusion **applies** (it can only protect more
    /// paths, never fewer). Otherwise it applies when the version lies in the inclusive range.
    /// Order follows the rule's declaration order.
    public func activeVersionExclusionPaths(installedVersions: [String: String?]) -> [String] {
        (versionExclusions ?? []).flatMap { exclusion -> [String] in
            guard
                let raw = installedVersions[exclusion.bundleID] ?? nil,
                let installed = AppVersion(raw)
            else {
                return exclusion.paths
            }
            if let minimum = exclusion.minVersion.flatMap(AppVersion.init), installed < minimum {
                return []
            }
            if let maximum = exclusion.maxVersion.flatMap(AppVersion.init), installed > maximum {
                return []
            }
            return exclusion.paths
        }
    }
}

extension RuleEvaluator {
    /// Like `evaluate(rule:candidates:now:)`, additionally dropping candidates that match a
    /// version exclusion active for `installedVersions` (see `activeVersionExclusionPaths`).
    public func evaluate(
        rule: CleanupRule,
        candidates: [URL],
        installedVersions: [String: String?],
        now: Date = Date()
    ) throws -> [URL] {
        try RuleValidator.validateSchemaV2Fields(of: rule)
        let extra = rule.activeVersionExclusionPaths(installedVersions: installedVersions)
        let tightened = CleanupRule(
            id: rule.id,
            module: rule.module,
            category: rule.category,
            name: rule.name,
            description: rule.description,
            allowlistRoots: rule.allowlistRoots,
            paths: rule.paths,
            patterns: rule.patterns,
            exclusions: rule.exclusions + extra,
            minAgeSeconds: rule.minAgeSeconds,
            isTrashSafe: rule.isTrashSafe,
            appPatterns: rule.appPatterns,
            provenance: rule.provenance,
            versionExclusions: rule.versionExclusions
        )
        return try evaluate(rule: tightened, candidates: candidates, now: now)
    }
}
