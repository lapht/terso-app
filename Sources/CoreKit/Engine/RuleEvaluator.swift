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

/// Errors encountered while evaluating a cleanup rule against candidate paths.
public enum RuleEvaluationError: Error, CustomStringConvertible, Equatable, Sendable {
    case invalidAllowlistRoot(ruleID: String, root: String)
    case negativeMinimumAge(ruleID: String, seconds: Int64)
    case missingFileDates(path: String)

    public var description: String {
        switch self {
        case let .invalidAllowlistRoot(ruleID, root):
            "Rule '\(ruleID)' has a non-absolute allowlist root '\(root)'"
        case let .negativeMinimumAge(ruleID, seconds):
            "Rule '\(ruleID)' has a negative minimum age of \(seconds) seconds"
        case let .missingFileDates(path):
            "Could not determine creation or modification date for '\(path)'"
        }
    }
}

/// Applies a cleanup rule to candidate paths after checking Safety allowlists.
public struct RuleEvaluator: Sendable {
    private let homeDirectory: URL
    private let pathValidator: PathValidator
    private let symlinkValidator: SymlinkValidator

    /// Creates an evaluator using the current user's home directory for `~` roots.
    public init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        pathValidator = PathValidator(homeDirectory: homeDirectory)
        symlinkValidator = SymlinkValidator(homeDirectory: homeDirectory)
    }

    /// Returns the candidates matched by `rule`, preserving their input order.
    ///
    /// Every candidate is checked against the rule's allowlist and symlink targets
    /// before pattern, exclusion, or age filtering. Unsafe paths and filesystem
    /// metadata failures are thrown rather than silently omitted.
    public func evaluate(
        rule: CleanupRule,
        candidates: [URL],
        now: Date = Date()
    ) throws -> [URL] {
        if let minimumAge = rule.minAgeSeconds, minimumAge < 0 {
            throw RuleEvaluationError.negativeMinimumAge(
                ruleID: rule.id,
                seconds: minimumAge
            )
        }

        let allowedRoots = try rule.allowlistRoots.map { try expandAllowlistRoot($0, ruleID: rule.id) }
        let positiveMatchers = try rule.patterns.map(GlobMatcher.init(pattern:))
        let exclusionMatchers = try rule.exclusions.map(GlobMatcher.init(pattern:))
        var matches: [URL] = []

        for candidate in candidates {
            try pathValidator.validate(path: candidate, allowedRoots: allowedRoots)
            let resolvedURL = try symlinkValidator.resolveAndValidate(
                path: candidate,
                allowedRoots: allowedRoots
            )
            try pathValidator.validate(
                path: candidate.resolvingSymlinksInPath().standardizedFileURL,
                allowedRoots: allowedRoots
            )

            guard let relativePath = relativePath(of: candidate, under: allowedRoots) else {
                continue
            }

            guard positiveMatchers.contains(where: { $0.matches(path: relativePath) }) else {
                continue
            }
            guard !exclusionMatchers.contains(where: { $0.matches(path: relativePath) }) else {
                continue
            }

            if let minimumAge = rule.minAgeSeconds {
                let attributes = try FileManager.default.attributesOfItem(atPath: resolvedURL.path)
                let dates = [
                    attributes[.creationDate] as? Date,
                    attributes[.modificationDate] as? Date
                ].compactMap { $0 }
                guard let latestDate = dates.max() else {
                    throw RuleEvaluationError.missingFileDates(path: resolvedURL.path)
                }
                guard now.timeIntervalSince(latestDate) >= TimeInterval(minimumAge) else {
                    continue
                }
            }

            matches.append(candidate.standardizedFileURL)
        }

        return matches
    }

    private func expandAllowlistRoot(_ root: String, ruleID: String) throws -> URL {
        if root == "~" {
            return homeDirectory
        }
        if root.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(root.dropFirst(2))).standardizedFileURL
        }
        guard root.hasPrefix("/") else {
            throw RuleEvaluationError.invalidAllowlistRoot(ruleID: ruleID, root: root)
        }
        return URL(fileURLWithPath: root).standardizedFileURL
    }

    private func relativePath(of candidate: URL, under allowedRoots: [URL]) -> String? {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let containingRoots = allowedRoots
            .map(\.standardizedFileURL)
            .filter { root in
                let rootComponents = root.pathComponents
                guard candidateComponents.count >= rootComponents.count else {
                    return false
                }
                return zip(candidateComponents, rootComponents).allSatisfy {
                    $0.caseInsensitiveCompare($1) == .orderedSame
                }
            }
            .sorted { $0.pathComponents.count > $1.pathComponents.count }

        guard let root = containingRoots.first else {
            return nil
        }
        return candidateComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
    }
}
