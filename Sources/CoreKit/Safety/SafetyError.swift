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

/// Errors thrown by the Terso safety pipeline.
///
/// Each case maps to one or more of the 8 safety invariants
/// defined in `docs/design.md §5`. The pipeline must never suppress
/// these errors — they must surface to the caller for logging and UI
/// (Safety Invariant §8 — no silent failures).
public enum SafetyError: Error, Sendable, Hashable {
    // MARK: Invariant §1 — Allowlist-only roots

    /// The path is not under any allowlisted root for the calling module.
    ///
    /// - Parameters:
    ///   - path: The standardized absolute path that was rejected.
    ///   - allowedRoots: The set of roots that would have been accepted.
    case pathNotAllowlisted(path: String, allowedRoots: [String])

    // MARK: Invariant §3 — Protected paths

    /// The path matches a hard-denied protected location.
    ///
    /// - Parameters:
    ///   - path: The standardized absolute path that was rejected.
    ///   - reason: A human-readable description of why the path is protected.
    case protectedPath(path: String, reason: String)

    // MARK: Path integrity

    /// The path could not be standardized to an absolute path, or contains
    /// illegal components such as path-traversal sequences (`..`, `./`).
    ///
    /// - Parameter path: The raw path string that failed normalization.
    case invalidPath(path: String)
}

// MARK: - CustomStringConvertible

extension SafetyError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .pathNotAllowlisted(path, roots):
            return "Path '\(path)' is not under any allowlisted root: \(roots.joined(separator: ", "))"
        case let .protectedPath(path, reason):
            return "Path '\(path)' is hard-denied: \(reason)"
        case let .invalidPath(path):
            return "Path '\(path)' is invalid or cannot be normalized"
        }
    }
}
