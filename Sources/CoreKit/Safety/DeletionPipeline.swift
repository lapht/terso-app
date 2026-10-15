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
}

/// The outcome of a deletion pipeline run.
public struct DeletionResult: Sendable, Hashable {
    /// Items successfully considered or moved to Trash.
    public let items: [DeletionItemResult]

    /// The sum of the scanned item sizes, used as an estimate for the operation.
    public let estimatedBytes: Int64

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
    }

    private let pathValidator: PathValidator
    private let symlinkValidator: SymlinkValidator
    private let auditLogger: AuditLogger

    /// Creates a pipeline configured for the current user's home directory.
    public init(homeDirectory: URL, auditLogger: AuditLogger = AuditLogger()) {
        self.pathValidator = PathValidator(homeDirectory: homeDirectory)
        self.symlinkValidator = SymlinkValidator(homeDirectory: homeDirectory, pathValidator: pathValidator)
        self.auditLogger = auditLogger
    }

    /// Validates and, unless `dryRun` is true, moves items to the system Trash.
    ///
    /// Allowlist roots are associated with module IDs so roots belonging to one
    /// cleanup module cannot authorize items from another.
    ///
    /// The whole batch is validated before any item is moved. Every item is then
    /// revalidated immediately before it is passed to `FileManager.trashItem`.
    ///
    /// - Parameters:
    ///   - items: Items selected for cleanup.
    ///   - allowedRootsByModule: Allowlisted roots keyed by each item's module ID.
    ///   - dryRun: When true, return the validated items and estimated byte count without mutation.
    /// - Returns: The items processed and their estimated combined size.
    /// - Throws: A safety or filesystem error when an item cannot be safely processed.
    public func execute(
        items: [CleanItem],
        allowedRootsByModule: [String: [URL]],
        dryRun: Bool
    ) throws -> DeletionResult {
        let (candidates, estimatedBytes) = try prepareCandidates(
            items: items,
            allowedRootsByModule: allowedRootsByModule,
            action: dryRun ? .dryRun : .trash
        )

        if dryRun {
            try recordDryRun(candidates)
            return DeletionResult(
                items: candidates.map { DeletionItemResult(item: $0.item, resultingItemURL: nil) },
                estimatedBytes: estimatedBytes,
                isDryRun: true
            )
        }

        return DeletionResult(
            items: try trash(candidates),
            estimatedBytes: estimatedBytes,
            isDryRun: false
        )
    }

    private func prepareCandidates(
        items: [CleanItem],
        allowedRootsByModule: [String: [URL]],
        action: AuditAction
    ) throws -> (candidates: [Candidate], estimatedBytes: Int64) {
        var candidates: [Candidate] = []
        var estimatedBytes: Int64 = 0

        for item in items {
            do {
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
                }

                let roots = allowedRootsByModule[item.moduleId] ?? []
                try validate(item: item, allowedRoots: roots)
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
                candidates.append(Candidate(item: item, roots: roots))
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

        return (candidates, estimatedBytes)
    }

    private func validate(item: CleanItem, allowedRoots: [URL]) throws {
        let path = item.url.standardizedFileURL.path
        guard !item.isProtected else {
            throw SafetyError.protectedPath(path: path, reason: "item marked protected by scanner")
        }

        try pathValidator.validate(path: item.url, allowedRoots: allowedRoots)
        let resolvedURL = try symlinkValidator.resolveAndValidate(
            path: item.url,
            allowedRoots: allowedRoots
        )
        guard resolvedURL.standardizedFileURL == item.resolvedURL.standardizedFileURL else {
            throw DeletionPipelineError.staleItem(path: path)
        }
    }

    private func recordDryRun(_ candidates: [Candidate]) throws {
        for candidate in candidates {
            try auditLogger.record(action: .dryRun, item: candidate.item, result: .success)
        }
    }

    private func trash(_ candidates: [Candidate]) throws -> [DeletionItemResult] {
        var results: [DeletionItemResult] = []
        for candidate in candidates {
            results.append(try trash(candidate))
        }
        return results
    }

    private func trash(_ candidate: Candidate) throws -> DeletionItemResult {
        let item = candidate.item
        let resultingItemURL: NSURL?
        do {
            try validate(item: item, allowedRoots: candidate.roots)
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

        try auditLogger.record(action: .trash, item: item, result: .success)
        return DeletionItemResult(item: item, resultingItemURL: resultingItemURL as URL?)
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
        case .invalidSize:
            return "invalidSize"
        case .sizeOverflow:
            return "sizeOverflow"
        }
    }
}
