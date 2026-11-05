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

/// A folder the user explicitly picked, which lets the duplicates flow move regular files
/// out of Desktop, Documents or Downloads (design.md §11.7, the exception to invariant 3).
///
/// A grant is an in-memory value for one operation. It is never stored, never shared with
/// other modules and never defined by a rule: the caller creates it from the user's pick,
/// passes it to ``DeletionPipeline/execute(items:allowedRootsByModule:dryRun:snapshots:protectedAreaGrants:)``
/// and drops it. The pipeline honors it only for items of ``duplicatesModuleID``.
///
/// What a grant never allows: the protected roots themselves, directories, packages and
/// bundles, symlinks, or anything outside the picked folder. Items still need the module's
/// allowlist root and still go through the symlink checks.
public struct ProtectedAreaGrant: Sendable, Hashable {
    /// The only module whose items may use a grant.
    public static let duplicatesModuleID = "files.duplicates"

    /// The picked folder, standardized.
    public let folder: URL

    /// Accepts a picked folder.
    ///
    /// - Throws: ``SafetyError`` when the folder is not an existing real directory, is the home
    ///   directory or one of its parents, is a system path, or contains `..` components.
    ///   Picking a protected root such as `~/Documents` is allowed: it is the main use case.
    public init(folder: URL, homeDirectory: URL) throws {
        try PathValidator(homeDirectory: homeDirectory).validateGrantFolder(folder)
        self.folder = folder.standardizedFileURL
    }
}
