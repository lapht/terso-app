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

/// A file that belongs to a group of byte-identical duplicates.
public struct DuplicateFile: Sendable, Hashable {
    /// Location of the file as discovered under a user-chosen root.
    public let url: URL

    /// Whether this file is an APFS clone of an earlier file in the same group.
    ///
    /// Clones share storage blocks, so removing one would not reclaim space;
    /// their size is never counted in ``DuplicateGroup/reclaimableBytes``.
    public let isClone: Bool

    public init(url: URL, isClone: Bool) {
        self.url = url
        self.isClone = isClone
    }
}

/// Files with identical size and identical SHA-256 content hash.
///
/// Hard links to the same inode are collapsed to a single file before
/// grouping, so a group always contains at least two distinct inodes.
public struct DuplicateGroup: Sendable, Hashable, Identifiable {
    public var id: String { contentHash }

    /// Lowercase hexadecimal SHA-256 digest of the full file contents.
    public let contentHash: String

    /// Logical size of each file in the group.
    public let fileSizeBytes: Int64

    /// Files in the group, sorted by path.
    public let files: [DuplicateFile]

    public init(contentHash: String, fileSizeBytes: Int64, files: [DuplicateFile]) {
        self.contentHash = contentHash
        self.fileSizeBytes = fileSizeBytes
        self.files = files
    }

    /// Bytes that keeping a single copy would free, excluding APFS clones.
    public var reclaimableBytes: Int64 {
        let independentCopies = files.filter { !$0.isClone }.count
        return Int64(max(independentCopies - 1, 0)) * fileSizeBytes
    }
}

/// A file or directory that could not be read during a duplicate scan.
///
/// Files with issues never take part in grouping.
public struct DuplicateScanIssue: Sendable, Hashable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// Outcome of a read-only duplicate scan.
public struct DuplicateScanResult: Sendable, Hashable {
    /// Duplicate groups sorted by reclaimable bytes, largest first.
    public let groups: [DuplicateGroup]

    /// Number of distinct regular files examined (hard links counted once).
    public let examinedFileCount: Int

    /// Cloud (iCloud/File Provider) files skipped because they are not
    /// downloaded locally. The scan never triggers downloads.
    public let skippedDatalessFileCount: Int

    /// Read and enumeration errors. Affected files are excluded from groups.
    public let issues: [DuplicateScanIssue]

    /// Whether the scan was cancelled before every candidate was compared.
    public let isCancelled: Bool

    public init(
        groups: [DuplicateGroup],
        examinedFileCount: Int,
        skippedDatalessFileCount: Int,
        issues: [DuplicateScanIssue],
        isCancelled: Bool
    ) {
        self.groups = groups
        self.examinedFileCount = examinedFileCount
        self.skippedDatalessFileCount = skippedDatalessFileCount
        self.issues = issues
        self.isCancelled = isCancelled
    }

    /// Whether the groups may be incomplete because of cancellation or errors.
    public var isPartial: Bool {
        isCancelled || !issues.isEmpty
    }

    public var totalReclaimableBytes: Int64 {
        groups.reduce(0) { $0 + $1.reclaimableBytes }
    }
}

/// Progress reported while a duplicate scan runs.
public struct DuplicateScanProgress: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        /// Walking the chosen folders; `totalFiles` is not yet known.
        case enumerating
        /// Hashing same-size candidates.
        case hashing
    }

    public let phase: Phase
    public let completedFiles: Int
    public let totalFiles: Int?

    public init(phase: Phase, completedFiles: Int, totalFiles: Int?) {
        self.phase = phase
        self.completedFiles = completedFiles
        self.totalFiles = totalFiles
    }
}
