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

/// How many bytes moving a set of items to Trash is expected to free.
///
/// Items that share storage with something else are never counted as freed:
///
/// - A hard link frees space only when every link to its inode is in the batch;
///   the inode is counted once however many of its links are selected.
/// - An APFS clone shares blocks with its siblings, and whether those siblings
///   stay on disk cannot be known cheaply, so cloned files are reported as shared.
///
/// Directories use the scanner's recursive size and are always counted as reclaimable.
public struct SpaceEstimate: Sendable, Hashable {
    /// Bytes expected to be freed, with shared storage counted at most once and only when safe.
    public let reclaimableBytes: Int64

    /// Bytes of items that share storage and may not be freed; each shared block is counted once.
    public let sharedBytes: Int64

    private struct Identity: Hashable {
        let device: Int64
        let inode: UInt64
    }

    private struct Entry {
        let sizeBytes: Int64
        let identity: Identity?
        let linkCount: Int
        let cloneID: UInt64?
    }

    /// Estimates the space freed by moving `items` to Trash.
    ///
    /// - Throws: ``DeletionPipelineError/sizeOverflow`` when a total does not fit in an `Int64`.
    static func make(for items: [CleanItem]) throws -> SpaceEstimate {
        let entries = items.map(entry(for:))
        var linksInBatch: [Identity: Int] = [:]
        for identity in entries.compactMap(\.identity) {
            linksInBatch[identity, default: 0] += 1
        }

        var reclaimable: Int64 = 0
        var shared: Int64 = 0
        var seenInodes: Set<Identity> = []
        var seenClones: Set<UInt64> = []

        for entry in entries {
            guard let identity = entry.identity else {
                reclaimable = try add(reclaimable, entry.sizeBytes)
                continue
            }
            guard seenInodes.insert(identity).inserted else {
                continue
            }
            if entry.linkCount > linksInBatch[identity, default: 0] {
                shared = try add(shared, entry.sizeBytes)
            } else if let cloneID = entry.cloneID {
                if seenClones.insert(cloneID).inserted {
                    shared = try add(shared, entry.sizeBytes)
                }
            } else {
                reclaimable = try add(reclaimable, entry.sizeBytes)
            }
        }
        return SpaceEstimate(reclaimableBytes: reclaimable, sharedBytes: shared)
    }

    /// Reads link and clone information for regular files only; anything else is a plain entry.
    private static func entry(for item: CleanItem) -> Entry {
        var info = stat()
        guard lstat(item.url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            return Entry(sizeBytes: item.sizeBytes, identity: nil, linkCount: 1, cloneID: nil)
        }
        return Entry(
            sizeBytes: item.sizeBytes,
            identity: Identity(device: Int64(info.st_dev), inode: UInt64(info.st_ino)),
            linkCount: Int(info.st_nlink),
            cloneID: DuplicateFileReader.cloneIdentifier(of: item.url)
        )
    }

    private static func add(_ total: Int64, _ value: Int64) throws -> Int64 {
        let (sum, overflow) = total.addingReportingOverflow(value)
        guard !overflow else {
            throw DeletionPipelineError.sizeOverflow
        }
        return sum
    }
}
