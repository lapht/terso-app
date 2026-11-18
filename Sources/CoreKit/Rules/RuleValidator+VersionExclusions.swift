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

/// Schema v2 validation of version-conditional exclusions (docs/design.md §11.2).
extension RuleValidator {
    static func validateVersionExclusions(of rule: CleanupRule) throws {
        guard let exclusions = rule.versionExclusions else {
            return
        }
        guard !exclusions.isEmpty else {
            throw invalid(rule, "versionExclusions", "[]", "must not be empty when present")
        }
        guard rule.provenance != nil else {
            throw RuleValidationError.missingProvenance(ruleID: rule.id)
        }
        for (index, exclusion) in exclusions.enumerated() {
            try validate(exclusion, field: "versionExclusions[\(index)]", rule: rule)
        }
    }

    private static func invalid(
        _ rule: CleanupRule,
        _ field: String,
        _ value: String,
        _ reason: String
    ) -> RuleValidationError {
        .invalidVersionExclusion(ruleID: rule.id, field: field, value: value, reason: reason)
    }

    private static func validate(_ exclusion: VersionExclusion, field: String, rule: CleanupRule) throws {
        if let reason = identifierValidationError(exclusion.bundleID, minimumComponents: 2) {
            throw invalid(rule, "\(field).bundleID", exclusion.bundleID, reason)
        }
        guard exclusion.minVersion != nil || exclusion.maxVersion != nil else {
            throw invalid(rule, field, "", "must define 'minVersion', 'maxVersion' or both")
        }
        var bounds: [AppVersion] = []
        for (name, value) in [("minVersion", exclusion.minVersion), ("maxVersion", exclusion.maxVersion)] {
            guard let value else {
                continue
            }
            guard let version = AppVersion(value) else {
                throw invalid(rule, "\(field).\(name)", value, "must be 1-4 dot-separated numbers, e.g. '3.2.1'")
            }
            bounds.append(version)
        }
        if bounds.count == 2, bounds[0] > bounds[1] {
            throw invalid(rule, field, "", "'minVersion' must not be greater than 'maxVersion'")
        }
        guard !exclusion.paths.isEmpty else {
            throw invalid(rule, "\(field).paths", "[]", "must not be empty")
        }
        for (index, path) in exclusion.paths.enumerated() {
            if path.trimmingCharacters(in: .whitespaces).isEmpty {
                throw invalid(rule, "\(field).paths[\(index)]", path, "must not be empty")
            }
            if let reason = globValidationError(in: path) {
                throw invalid(rule, "\(field).paths[\(index)]", path, reason)
            }
        }
    }
}
