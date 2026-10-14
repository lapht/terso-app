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

/// The outcome of a clean (deletion) operation.
///
/// Aggregates successfully trashed items, freed bytes, errors, and
/// execution time. Conforms to `Codable` so it can be persisted
/// for audit logging (Safety Invariant §8 — no silent failures).
public struct CleanResult: Sendable, Hashable, Codable {
    /// Items that were successfully moved to Trash (or permanently deleted).
    public let itemsTrashed: [CleanItem]

    /// Total bytes freed by this operation.
    public let bytesFreed: Int64

    /// Errors encountered during the operation.
    public let errors: [CleanError]

    /// Wall-clock duration of the clean operation, in seconds.
    public let executionDuration: TimeInterval

    public init(
        itemsTrashed: [CleanItem] = [],
        bytesFreed: Int64 = 0,
        errors: [CleanError] = [],
        executionDuration: TimeInterval = 0
    ) {
        self.itemsTrashed = itemsTrashed
        self.bytesFreed = bytesFreed
        self.errors = errors
        self.executionDuration = executionDuration
    }
}
