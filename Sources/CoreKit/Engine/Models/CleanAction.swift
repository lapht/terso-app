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

/// The recommended deletion action for a scanned item.
///
/// Aligns with Safety Invariant §4 (Trash-first): the default action is
/// always `.trash`; permanent deletion requires explicit user opt-in.
public enum CleanAction: String, Sendable, Hashable, Codable, CaseIterable {
    /// Move to Trash (recoverable). This is the default safe path.
    case trash

    /// Permanently delete. Requires explicit per-item opt-in; off by default.
    case permanentDelete

    /// Skip this item — no action will be taken.
    case skip
}
