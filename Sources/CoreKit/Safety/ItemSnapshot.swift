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

/// The filesystem state of one item at preview time, used to detect changes before a move.
///
/// The snapshot is read with `lstat`, so symlinks are never followed and file contents
/// are never read or materialized.
public struct ItemSnapshot: Sendable, Hashable, Codable {
    /// The device containing the item.
    public let device: Int64

    /// The inode number, which together with `device` identifies the file.
    public let inode: UInt64

    /// The `st_size` of the item. Not compared for directories, whose scanned size is recursive.
    public let sizeBytes: Int64

    /// Modification time, whole seconds since the epoch.
    public let modificationSeconds: Int64

    /// Modification time, nanosecond part.
    public let modificationNanoseconds: Int64

    /// Whether the item was a directory.
    public let isDirectory: Bool

    /// Whether the item is a dataless placeholder whose contents live only in iCloud/File Provider.
    public let isDataless: Bool

    /// Reads the current state of `url` without following symlinks.
    ///
    /// - Returns: `nil` when the item does not exist or cannot be inspected.
    public static func capture(_ url: URL) -> ItemSnapshot? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            return nil
        }
        return ItemSnapshot(
            device: Int64(info.st_dev),
            inode: UInt64(info.st_ino),
            sizeBytes: Int64(info.st_size),
            modificationSeconds: Int64(info.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(info.st_mtimespec.tv_nsec),
            isDirectory: (info.st_mode & S_IFMT) == S_IFDIR,
            isDataless: info.st_flags & DuplicateFileStatus.datalessFlag != 0
        )
    }

    /// Describes what differs from `current`, or `nil` when the item is unchanged.
    func difference(from current: ItemSnapshot) -> String? {
        if device != current.device || inode != current.inode {
            return "file identity changed"
        }
        if isDirectory != current.isDirectory {
            return "item type changed"
        }
        if !isDirectory, sizeBytes != current.sizeBytes {
            return "size changed"
        }
        if modificationSeconds != current.modificationSeconds
            || modificationNanoseconds != current.modificationNanoseconds {
            return "modification date changed"
        }
        return nil
    }
}
