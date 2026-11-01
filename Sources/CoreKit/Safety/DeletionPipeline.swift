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

/// The result for one item considered by the deletion pipeline.
public struct DeletionItemResult: Sendable, Hashable {
    /// The item that was validated and processed.
    public let item: CleanItem

    /// The URL returned by macOS after moving the item to Trash; `nil` in dry-run mode.
    public let resultingItemURL: URL?

    /// The item's filesystem state captured by the dry-run; `nil` in trash mode.
    public let snapshot: ItemSnapshot?
}

/// An item that passed validation but was not moved because it changed after the preview.
public struct DeletionSkippedItem: Sendable, Hashable {
    /// The item that was left untouched.
    public let item: CleanItem

    /// Why the item was skipped, for display and bug reports.
    public let reason: String
}

/// The outcome of a deletion pipeline run.
public struct DeletionResult: Sendable, Hashable {
    /// Items successfully considered or moved to Trash.
    public let items: [DeletionItemResult]

    /// Items skipped because they changed or disappeared since the dry-run snapshot.
    public let skipped: [DeletionSkippedItem]

    /// Bytes expected to be freed. Hard links and APFS clones are never double counted,
    /// and storage shared with files outside the batch is excluded (see ``sharedBytes``).
    public let estimatedBytes: Int64

    /// Bytes of items that share storage with other files and may not be freed by this operation.
    public let sharedBytes: Int64

    /// Whether this result was produced without changing the filesystem.
    public let isDryRun: Bool
}

/// Errors raised when a scanned item cannot safely be processed by this pipeline.
public enum DeletionPipelineError: Error, Sendable, Hashable {
    /// The item's path or resolved target changed since the scan.
    case staleItem(path: String)

    /// The item no longer exists at its scanned path.
    case itemNotFound(path: String)

    /// Permanent deletion is not supported by this pipeline.
    case unsupportedAction(path: String, action: CleanAction)

    /// The scanner marked the item as read-only.
    case nonDeletableItem(path: String)

    /// The scanner supplied an invalid byte count.
    case invalidSize(path: String, sizeBytes: Int64)

    /// The combined byte count does not fit in an `Int64`.
    case sizeOverflow
}

/// The only project-level component that performs file modification for clean operations.
///
/// Every non-skipped item must pass both path and symlink validation. Filesystem changes
/// are limited to moving validated items into the system Trash.
public final class DeletionPipeline {
    private struct Candidate {
        let item: CleanItem
        let roots: [URL]
        /// Grants this item may use; empty for every module except duplicates.
        let grants: [ProtectedAreaGrant]
        /// Whether the item is only acceptable thanks to a protected-area grant (audit marker).
        let usesProtectedAreaException: Bool
    }

    private let pathValidator: PathValidator
    private let symlinkValidator: SymlinkValidator
    private let auditLogger: AuditLogger
    private let inspect: @Sendable (URL) -> ItemSnapshot?

    /// Creates a pipeline configured for the current user's home directory.
    public convenience init(homeDirectory: URL, auditLogger: AuditLogger = AuditLogger()) {
        self.init(homeDirectory: homeDirectory, auditLogger: auditLogger, inspect: ItemSnapshot.capture)
    }

    /// Creates a pipeline with a custom file inspector; tests use it to simulate states,
    /// such as dataless placeholders, that cannot be created on a real filesystem.
    init(
        homeDirectory: URL,
        auditLogger: AuditLogger,
        inspect: @escaping @Sendable (URL) -> ItemSnapshot?
    ) {
        self.pathValidator = PathValidator(homeDirectory: homeDirectory)
        self.symlinkValidator = SymlinkValidator(homeDirectory: homeDirectory, pathValidator: pathValidator)
        self.auditLogger = auditLogger
        self.inspect = inspect
    }

    /// Validates and, unless `dryRun` is true, moves items to the system Trash.
    ///
    /// Allowlist roots are associated with module IDs so roots belonging to one
    /// cleanup module cannot authorize items from another.
    ///
    /// The whole batch is validated before any item is moved. Every item is then
    /// revalidated immediately before it is passed to `FileManager.trashItem`.
    ///
    /// When `snapshots` carries the state captured by the dry-run, each item is also
    /// compared against it right before the move. An item whose identity, size or
    /// modification date changed, or that disappeared, is skipped, logged and reported
    /// in ``DeletionResult/skipped``; it is never moved. Items without a snapshot are
    /// not compared.
    ///
    /// - Parameters:
    ///   - items: Items selected for cleanup.
    ///   - allowedRootsByModule: Allowlisted roots keyed by each item's module ID.
    ///   - dryRun: When true, return the validated items and estimated byte count without mutation.
    ///   - snapshots: Dry-run snapshots keyed by ``CleanItem/id``, from ``DeletionItemResult/snapshot``.
    ///   - protectedAreaGrants: Folders the user picked for this one operation (design.md §11.7).
    ///     Only items of ``ProtectedAreaGrant/duplicatesModuleID`` can use them; they allow regular
    ///     files below the folder to leave Desktop/Documents/Downloads, never the protected roots,
    ///     directories, packages or symlinks. Held for this call only.
    /// - Returns: The items processed and their estimated combined size.
    /// - Throws: A safety or filesystem error when an item cannot be safely processed.
    public func execute(
        items: [CleanItem],
        allowedRootsByModule: [String: [URL]],
        dryRun: Bool,
        snapshots: [UUID: ItemSnapshot] = [:],
        protectedAreaGrants: [ProtectedAreaGrant] = []
    ) throws -> DeletionResult {
        let (presentItems, vanished) = try separateUnavailableItems(items, dryRun: dryRun, snapshots: snapshots)
        let (candidates, estimate) = try prepareCandidates(
            items: presentItems,
            allowedRootsByModule: allowedRootsByModule,
            protectedAreaGrants: protectedAreaGrants,
            action: dryRun ? .dryRun : .trash
        )

        if dryRun {
            try recordDryRun(candidates)
            return DeletionResult(
                items: candidates.map {
                    DeletionItemResult(
                        item: $0.item,
                        resultingItemURL: nil,
                        snapshot: inspect($0.item.url)
                    )
                },
                skipped: vanished,
                estimatedBytes: estimate.reclaimableBytes,
                sharedBytes: estimate.sharedBytes,
                isDryRun: true
            )
        }

        let (moved, skipped) = try trash(candidates, snapshots: snapshots)
        return DeletionResult(
            items: moved,
            skipped: vanished + skipped,
            estimatedBytes: estimate.reclaimableBytes,
            sharedBytes: estimate.sharedBytes,
            isDryRun: false
        )
    }

    /// Splits off items that must be reported and skipped instead of processed, so one such
    /// item never aborts the whole batch.
    ///
    /// - Dataless iCloud placeholders are skipped in every mode. They are inspected with
    ///   `lstat` only, so nothing is read or downloaded; moving one would free no local
    ///   space and would propagate the deletion to the cloud copy.
    /// - Items with a dry-run snapshot that no longer exist are skipped when executing.
    private func separateUnavailableItems(
        _ items: [CleanItem],
        dryRun: Bool,
        snapshots: [UUID: ItemSnapshot]
    ) throws -> (present: [CleanItem], skipped: [DeletionSkippedItem]) {
        let action: AuditAction = dryRun ? .dryRun : .trash
        var present: [CleanItem] = []
        var skipped: [DeletionSkippedItem] = []
        for item in items {
            let current = inspect(item.url)
            if current?.isDataless == true {
                try auditLogger.record(action: action, item: item, result: .failure, errorCode: "datalessSkipped")
                skipped.append(DeletionSkippedItem(item: item, reason: "not downloaded from iCloud; left untouched"))
            } else if !dryRun, current == nil, snapshots[item.id] != nil {
                try auditLogger.record(action: action, item: item, result: .failure, errorCode: "itemNotFound")
                skipped.append(DeletionSkippedItem(item: item, reason: "item no longer exists"))
            } else {
                present.append(item)
            }
        }
        return (present, skipped)
    }

    private func prepareCandidates(
        items: [CleanItem],
        allowedRootsByModule: [String: [URL]],
        protectedAreaGrants: [ProtectedAreaGrant],
        action: AuditAction
    ) throws -> (candidates: [Candidate], estimate: SpaceEstimate) {
        var candidates: [Candidate] = []
        var estimatedBytes: Int64 = 0

        for item in items {
            do {
                guard item.isDeletable else {
                    throw DeletionPipelineError.nonDeletableItem(path: item.url.standardizedFileURL.path)
                }

                switch item.recommendedAction {
                case .skip:
                    continue
                case .permanentDelete:
                    throw DeletionPipelineError.unsupportedAction(
                        path: item.url.standardizedFileURL.path,
                        action: item.recommendedAction
                    )
                case .trash:
                    break
                case .revealInFinder:
                    throw DeletionPipelineError.unsupportedAction(
                        path: item.url.standardizedFileURL.path,
                        action: item.recommendedAction
                    )
                }

                let roots = allowedRootsByModule[item.moduleId] ?? []
                // Grants are honored for the duplicates module only; for any other module they are dropped.
                let grants = item.moduleId == ProtectedAreaGrant.duplicatesModuleID ? protectedAreaGrants : []
                let usesException = try validate(item: item, allowedRoots: roots, grants: grants)
                guard FileManager.default.fileExists(atPath: item.url.path) else {
                    throw DeletionPipelineError.itemNotFound(path: item.url.standardizedFileURL.path)
                }
                guard item.sizeBytes >= 0 else {
                    throw DeletionPipelineError.invalidSize(
                        path: item.url.standardizedFileURL.path,
                        sizeBytes: item.sizeBytes
                    )
                }

                let (newTotal, overflow) = estimatedBytes.addingReportingOverflow(item.sizeBytes)
                guard !overflow else {
                    throw DeletionPipelineError.sizeOverflow
                }
                estimatedBytes = newTotal
                candidates.append(Candidate(
                    item: item,
                    roots: roots,
                    grants: grants,
                    usesProtectedAreaException: usesException
                ))
            } catch {
                try auditLogger.record(
                    action: action,
                    item: item,
                    result: .failure,
                    errorCode: Self.errorCode(for: error)
                )
                throw error
            }
        }

        return (candidates, try SpaceEstimate.make(for: candidates.map(\.item)))
    }

    /// - Returns: `true` when the item is only acceptable because a protected-area grant covers it.
    @discardableResult
    private func validate(item: CleanItem, allowedRoots: [URL], grants: [ProtectedAreaGrant]) throws -> Bool {
        let path = item.url.standardizedFileURL.path
        guard !item.isProtected else {
            throw SafetyError.protectedPath(path: path, reason: "item marked protected by scanner")
        }

        try pathValidator.validate(path: item.url, allowedRoots: allowedRoots, protectedAreaGrants: grants)
        let resolvedURL = try symlinkValidator.resolveAndValidate(
            path: item.url,
            allowedRoots: allowedRoots,
            protectedAreaGrants: grants
        )
        guard resolvedURL.standardizedFileURL == item.resolvedURL.standardizedFileURL else {
            throw DeletionPipelineError.staleItem(path: path)
        }

        let grant = pathValidator.protectedAreaGrant(covering: item.url, in: grants)
            ?? pathValidator.protectedAreaGrant(covering: resolvedURL, in: grants)
        guard let grant else {
            return false
        }
        try requireRegularFileOutsidePackages(item.url, grant: grant)
        return true
    }

    private func recordDryRun(_ candidates: [Candidate]) throws {
        for candidate in candidates {
            try auditLogger.record(
                action: .dryRun,
                item: candidate.item,
                result: .success,
                protectedAreaException: candidate.usesProtectedAreaException
            )
        }
    }

    private func trash(
        _ candidates: [Candidate],
        snapshots: [UUID: ItemSnapshot]
    ) throws -> (moved: [DeletionItemResult], skipped: [DeletionSkippedItem]) {
        var moved: [DeletionItemResult] = []
        var skipped: [DeletionSkippedItem] = []
        for candidate in candidates {
            if let reason = try changeSincePreview(candidate, snapshot: snapshots[candidate.item.id]) {
                skipped.append(DeletionSkippedItem(item: candidate.item, reason: reason))
                continue
            }
            moved.append(try trash(candidate))
        }
        return (moved, skipped)
    }

    /// Compares the item with its dry-run snapshot and logs a failure when it no longer matches.
    ///
    /// - Returns: The reason the item must be skipped, or `nil` when it may proceed.
    private func changeSincePreview(_ candidate: Candidate, snapshot: ItemSnapshot?) throws -> String? {
        guard let snapshot else {
            return nil
        }
        let reason: String
        let errorCode: String
        if let current = inspect(candidate.item.url) {
            guard let difference = snapshot.difference(from: current) else {
                return nil
            }
            reason = difference
            errorCode = "changedSincePreview"
        } else {
            reason = "item no longer exists"
            errorCode = "itemNotFound"
        }
        try auditLogger.record(action: .trash, item: candidate.item, result: .failure, errorCode: errorCode)
        return reason
    }

    private func trash(_ candidate: Candidate) throws -> DeletionItemResult {
        let item = candidate.item
        let resultingItemURL: NSURL?
        do {
            try validate(item: item, allowedRoots: candidate.roots, grants: candidate.grants)
            guard FileManager.default.fileExists(atPath: item.url.path) else {
                throw DeletionPipelineError.itemNotFound(path: item.url.standardizedFileURL.path)
            }

            var trashedItemURL: NSURL?
            try FileManager.default.trashItem(at: item.url, resultingItemURL: &trashedItemURL)
            resultingItemURL = trashedItemURL
        } catch {
            try auditLogger.record(
                action: .trash,
                item: item,
                result: .failure,
                errorCode: Self.errorCode(for: error)
            )
            throw error
        }

        try auditLogger.record(
            action: .trash,
            item: item,
            result: .success,
            protectedAreaException: candidate.usesProtectedAreaException
        )
        return DeletionItemResult(item: item, resultingItemURL: resultingItemURL as URL?, snapshot: nil)
    }

    private static func errorCode(for error: Error) -> String {
        if let error = error as? SafetyError {
            return errorCode(for: error)
        }
        if let error = error as? DeletionPipelineError {
            return errorCode(for: error)
        }
        let nsError = error as NSError
        return "NSError.\(nsError.domain).\(nsError.code)"
    }

    private static func errorCode(for error: SafetyError) -> String {
        switch error {
        case .pathNotAllowlisted:
            return "pathNotAllowlisted"
        case .symlinkEscape:
            return "symlinkEscape"
        case .brokenSymlink:
            return "brokenSymlink"
        case .circularSymlink:
            return "circularSymlink"
        case .protectedPath:
            return "protectedPath"
        case .invalidPath:
            return "invalidPath"
        }
    }

    private static func errorCode(for error: DeletionPipelineError) -> String {
        switch error {
        case .staleItem:
            return "staleItem"
        case .itemNotFound:
            return "itemNotFound"
        case .unsupportedAction:
            return "unsupportedAction"
        case .nonDeletableItem:
            return "nonDeletableItem"
        case .invalidSize:
            return "invalidSize"
        case .sizeOverflow:
            return "sizeOverflow"
        }
    }
}

// MARK: - Protected-area exception checks (design.md §11.7)

extension DeletionPipeline {
    /// Package/bundle folder names whose contents are never moved out one by one, in addition to
    /// whatever the system reports as a package.
    private static let packageSuffixes = [
        ".app", ".framework", ".kext", ".plugin", ".appex", ".bundle", ".photoslibrary", ".musiclibrary",
        ".tvlibrary", ".fcpbundle", ".logicx", ".band", ".pages", ".numbers", ".key", ".rtfd", ".xcodeproj",
        ".xcworkspace", ".playground", ".sparsebundle", ".sparseimage"
    ]

    /// Extra rules for the protected-area exception: only a regular file (never a directory, a
    /// symlink or a special file), and none of its parent folders may be a package or bundle.
    private func requireRegularFileOutsidePackages(_ url: URL, grant: ProtectedAreaGrant) throws {
        let path = url.standardizedFileURL.path
        let type = (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType
        guard type == .typeRegular else {
            throw SafetyError.protectedPath(
                path: path,
                reason: "only regular files can leave a protected folder; directories and symlinks stay put"
            )
        }
        var folder = url.standardizedFileURL.deletingLastPathComponent()
        while folder.path != "/" {
            let name = folder.lastPathComponent.lowercased()
            let isPackage = (try? folder.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
            if isPackage || Self.packageSuffixes.contains(where: { name.hasSuffix($0) }) {
                throw SafetyError.protectedPath(
                    path: path,
                    reason: "file is inside a package or bundle (\(folder.lastPathComponent))"
                )
            }
            folder = folder.deletingLastPathComponent()
        }
    }
}
