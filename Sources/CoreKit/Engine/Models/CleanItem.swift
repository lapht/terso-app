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

/// A single file-system item discovered by a cleanup module's scan.
///
/// `CleanItem` is the primary data-transfer object between the
/// scanning engine and the safety pipeline. It carries both the
/// original and symlink-resolved URLs so that the safety layer can
/// enforce Invariant §2 (symlink discipline) without re-resolving.
public struct CleanItem: Sendable, Identifiable, Hashable, Codable {
    /// Stable, unique identifier for this item.
    public let id: UUID

    /// The original URL of the item as discovered by the scanner.
    public let url: URL

    /// The fully resolved URL after following any symlinks.
    /// Used by the safety layer to enforce Invariant §2.
    public let resolvedURL: URL

    /// Size of the item in bytes (regular file) or estimated total
    /// size (directory, computed recursively by the scanner).
    public let sizeBytes: Int64

    /// Identifier of the ``CleanModule`` that found this item.
    public let moduleId: String

    /// Identifier of the rule in the rule DB that matched this item.
    public let ruleId: String

    /// Whether the item falls under a protected path (Invariant §3).
    /// When `true`, the safety pipeline must refuse deletion.
    public let isProtected: Bool

    /// The recommended action for this item.
    /// Defaults to `.trash` per Invariant §4 (trash-first).
    public let recommendedAction: CleanAction

    public init(
        id: UUID = UUID(),
        url: URL,
        resolvedURL: URL,
        sizeBytes: Int64,
        moduleId: String,
        ruleId: String,
        isProtected: Bool = false,
        recommendedAction: CleanAction = .trash
    ) {
        self.id = id
        self.url = url
        self.resolvedURL = resolvedURL
        self.sizeBytes = sizeBytes
        self.moduleId = moduleId
        self.ruleId = ruleId
        self.isProtected = isProtected
        self.recommendedAction = recommendedAction
    }
}
