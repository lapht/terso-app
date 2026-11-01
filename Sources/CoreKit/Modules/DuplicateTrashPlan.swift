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

/// One copy in a duplicate group, as the scan found it.
public struct DuplicateTrashCopy: Sendable, Hashable {
    public let url: URL

    /// Modification date read right after the scan; `nil` when it could not be read.
    public let modificationDate: Date?

    public init(url: URL, modificationDate: Date?) {
        self.url = url
        self.modificationDate = modificationDate
    }
}

/// A duplicate group as the selection sees it: every copy the scan found, not only the selected ones.
public struct DuplicateTrashGroup: Sendable, Hashable, Identifiable {
    public let id: String
    public let fileSizeBytes: Int64
    public let copies: [DuplicateTrashCopy]

    public init(id: String, fileSizeBytes: Int64, copies: [DuplicateTrashCopy]) {
        self.id = id
        self.fileSizeBytes = fileSizeBytes
        self.copies = copies
    }
}

/// A selected copy that was left out of the plan, with the reason to show to the user.
public struct DuplicateTrashSkip: Sendable, Hashable {
    public let path: String
    public let reason: String
}

/// Why a selection cannot become a plan at all.
public enum DuplicateTrashPlanError: Error, LocalizedError, Sendable, Hashable {
    /// Every copy of the group was selected, or the copy that would stay is gone or changed.
    case noCopyKept(groupID: String)

    /// A selected path does not belong to any group.
    case unknownCopy(path: String)

    public var errorDescription: String? {
        switch self {
        case .noCopyKept:
            return "Each group must keep at least one copy that is still there and unchanged."
        case let .unknownCopy(path):
            return "\(path) is not part of the scanned duplicate groups."
        }
    }
}

/// Turns a user's selection of duplicate copies into the exact items for the Safety pipeline.
///
/// The plan only reads (`lstat`); it never touches the filesystem. Rules:
/// - at least one copy of every affected group stays, and it must still exist with the scanned size;
/// - a selected copy that is gone, is no longer a regular file, or whose size or modification date
///   differs from the scan is skipped and reported, never moved: it may no longer be a duplicate;
/// - the returned items are exactly the valid selected copies, nothing else, with `.trash` as the action.
public enum DuplicateTrashPlan {
    public struct Plan: Sendable, Hashable {
        public let items: [CleanItem]
        public let skipped: [DuplicateTrashSkip]
    }

    public static let moduleID = ProtectedAreaGrant.duplicatesModuleID

    /// - Parameters:
    ///   - groups: All groups of the last scan.
    ///   - selectedPaths: Standardized paths of the copies the user selected. Empty means an empty plan.
    /// - Throws: ``DuplicateTrashPlanError`` when a group would lose every copy or a path is unknown.
    @discardableResult
    public static func make(groups: [DuplicateTrashGroup], selectedPaths: Set<String>) throws -> Plan {
        let known = Set(groups.flatMap { $0.copies.map { $0.url.standardizedFileURL.path } })
        if let unknown = selectedPaths.subtracting(known).sorted().first {
            throw DuplicateTrashPlanError.unknownCopy(path: unknown)
        }

        var items: [CleanItem] = []
        var skipped: [DuplicateTrashSkip] = []
        for group in groups {
            let selected = group.copies.filter { selectedPaths.contains($0.url.standardizedFileURL.path) }
            guard !selected.isEmpty else {
                continue
            }
            let kept = group.copies.filter { !selectedPaths.contains($0.url.standardizedFileURL.path) }
            guard kept.contains(where: { isIntact($0, size: group.fileSizeBytes) == nil }) else {
                throw DuplicateTrashPlanError.noCopyKept(groupID: group.id)
            }
            for copy in selected {
                let path = copy.url.standardizedFileURL.path
                if let problem = isIntact(copy, size: group.fileSizeBytes) {
                    skipped.append(DuplicateTrashSkip(path: path, reason: problem))
                    continue
                }
                items.append(CleanItem(
                    url: copy.url,
                    resolvedURL: copy.url.resolvingSymlinksInPath().standardizedFileURL,
                    sizeBytes: group.fileSizeBytes,
                    moduleId: moduleID,
                    ruleId: moduleID,
                    isPreselected: false,
                    note: "Selected duplicate copy"
                ))
            }
        }
        return Plan(items: items, skipped: skipped)
    }

    /// `nil` when the copy is still a regular file with the scanned size and date, else the reason.
    private static func isIntact(_ copy: DuplicateTrashCopy, size: Int64) -> String? {
        var info = stat()
        guard lstat(copy.url.path, &info) == 0 else {
            return "no longer exists"
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            return "is no longer a regular file"
        }
        guard Int64(info.st_size) == size else {
            return "changed since the scan (size)"
        }
        guard let scanned = copy.modificationDate else {
            return "modification date was unavailable at scan time"
        }
        let current = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
            + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        guard abs(current.timeIntervalSince(scanned)) < 0.001 else {
            return "changed since the scan (modification date)"
        }
        return nil
    }
}
