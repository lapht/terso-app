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

public extension LeftoversDetector {
    /// Module ID carried by leftover `CleanItem`s; the key of their allowlist roots.
    static let moduleID = "leftovers"

    /// The `~/Library` roots of design §11.4, expanded for `homeDirectory`.
    ///
    /// These are the only roots the deletion pipeline accepts for leftover items.
    static func allowedRoots(homeDirectory: URL) -> [URL] {
        let home = homeDirectory.standardizedFileURL
        return RuleValidator.leftoverRoots.map {
            home.appendingPathComponent(String($0.dropFirst(2)), isDirectory: true).standardizedFileURL
        }
    }
}

public extension LeftoverCandidate {
    /// The item handed to the deletion pipeline once the user selects this leftover.
    ///
    /// Trash-first (`.trash`). Protection and symlink checks are not decided here:
    /// the pipeline revalidates every item against the allowlist before moving it.
    var cleanItem: CleanItem {
        CleanItem(
            url: url,
            resolvedURL: url.resolvingSymlinksInPath().standardizedFileURL,
            sizeBytes: sizeBytes,
            moduleId: LeftoversDetector.moduleID,
            ruleId: ruleID,
            recommendedAction: .trash
        )
    }
}
