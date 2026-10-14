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

/// Metadata for a mounted volume, used by ``ScanContext``.
public struct VolumeInfo: Sendable, Hashable, Codable, Identifiable {
    /// Stable identifier — the volume UUID when available, otherwise the mount path.
    public var id: String { uuid ?? mountPath.path }

    /// The mount point of the volume (e.g. `/Volumes/External`).
    public let mountPath: URL

    /// The filesystem type (e.g. `"apfs"`, `"hfs"`).
    public let filesystemType: String

    /// Whether the volume is mounted read-only.
    public let isReadOnly: Bool

    /// The volume UUID, if available.
    public let uuid: String?

    public init(
        mountPath: URL,
        filesystemType: String,
        isReadOnly: Bool,
        uuid: String?
    ) {
        self.mountPath = mountPath
        self.filesystemType = filesystemType
        self.isReadOnly = isReadOnly
        self.uuid = uuid
    }
}
