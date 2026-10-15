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

/// A scanner that discovers cleanup candidates without deleting them.
///
/// Deletion is exclusively handled by the CoreKit Safety pipeline.
public protocol CleanModule: Sendable {
    /// Stable module identifier (for example, `caches.user`).
    var id: String { get }

    /// User-facing module name.
    var title: String { get }

    /// Whether this module needs Full Disk Access to scan completely.
    var requiresFDA: Bool { get }

    /// Finds cleanup candidates. This method must not perform side effects.
    func scan(context: ScanContext) async throws -> [CleanItem]
}
