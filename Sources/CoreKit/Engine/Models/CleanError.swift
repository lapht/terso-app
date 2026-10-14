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

/// Structured error type for failures during a clean operation.
///
/// Conforms to `Codable` so that ``CleanResult`` can be serialised
/// for logging (Safety Invariant §8 — no silent failures).
public enum CleanError: Error, Sendable, Hashable, Codable {
    /// The process lacks permission to delete the item at `path`.
    case permissionDenied(path: String)

    /// The item resides on a protected path (Safety Invariant §3).
    case protectedPath(path: String)

    /// A symlink resolved outside the allowlist root (Safety Invariant §2).
    case symlinkEscape(originalPath: String, resolvedPath: String)

    /// The item was not found at the expected path (e.g. already deleted).
    case itemNotFound(path: String)

    /// An underlying OS/filesystem error occurred.
    case underlyingError(path: String, description: String)
}
