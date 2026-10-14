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

/// Non-fatal warnings and rejections surfaced during safety validation.
///
/// In particular, when scanning or validating items, symlinks pointing to targets
/// outside allowlisted roots or toward protected system paths are excluded and
/// reported as warnings rather than failing the entire batch (Invariant §2 & §8).
public enum SafetyWarning: Sendable, Hashable, Codable {
    /// A symlink was discarded because its resolved target escapes the module's allowlist root
    /// or targets a protected path (Invariant §2 — Symlink discipline).
    case externalSymlinkTarget(originalPath: String, resolvedPath: String)

    /// A symlink was discarded because its target does not exist (broken symlink).
    case brokenSymlink(path: String, destination: String)

    /// A symlink was discarded because it forms a circular reference loop.
    case circularSymlink(path: String)
}

// MARK: - CustomStringConvertible

extension SafetyWarning: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .externalSymlinkTarget(originalPath, resolvedPath):
            return "Symlink '\(originalPath)' targets external or protected location '\(resolvedPath)'"
        case let .brokenSymlink(path, destination):
            return "Symlink '\(path)' is broken (destination '\(destination)' does not exist)"
        case let .circularSymlink(path):
            return "Symlink '\(path)' contains a circular reference loop"
        }
    }
}
