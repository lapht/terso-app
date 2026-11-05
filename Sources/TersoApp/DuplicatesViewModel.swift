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

import CoreKit
import Foundation

/// Read-only duplicate detection behind the Duplicates page.
protocol DuplicateScanning: Sendable {
    func scan(roots: [URL]) async throws -> DuplicateScanResult
}

extension DuplicateFinder: DuplicateScanning {
    func scan(roots: [URL]) async throws -> DuplicateScanResult {
        try await scan(roots: roots, progress: nil)
    }
}

/// One copy in a duplicate group, with the metadata the page shows for it.
/// A nil `modificationDate` means the file could not be read after the scan (moved or removed).
struct DuplicateCopy: Identifiable, Equatable, Sendable {
    let url: URL
    let sizeBytes: Int64
    let isClone: Bool
    let modificationDate: Date?

    var id: String { url.path }
}

/// A group as the page shows it, derived from `DuplicateGroup` without changing its paths or byte counts.
struct DuplicateGroupRow: Identifiable, Equatable, Sendable {
    let id: String
    let fileSizeBytes: Int64
    let reclaimableBytes: Int64
    let copies: [DuplicateCopy]

    var copyCount: Int { copies.count }
}

/// Everything a finished duplicate scan shows, including what it could not cover.
struct DuplicateScanSummary: Equatable, Sendable {
    var groups: [DuplicateGroupRow] = []
    var examinedFileCount = 0
    var skippedDatalessFileCount = 0
    var issues: [DuplicateScanIssue] = []
    var isCancelled = false

    var totalReclaimableBytes: Int64 {
        groups.reduce(0) { $0 + $1.reclaimableBytes }
    }

    var isPartial: Bool { isCancelled || !issues.isEmpty }
}

/// A copy the pipeline or the plan refused or skipped, kept visible next to the list.
struct DuplicateRejection: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let message: String
}

/// What the last dry-run or move did, with the byte count of the invariant 5 recap.
/// Bytes are what is expected to be freed: hard links and clones are never double counted.
enum DuplicateTrashReport: Equatable {
    case dryRun(itemCount: Int, bytes: Int64)
    case trashed(itemCount: Int, bytes: Int64)
}

/// Runs a duplicate scan on the chosen folders only when asked, then lets the user pick copies
/// to move to the Trash (#40). Nothing is selected by default, every group keeps at least one
/// copy, and only the selected copies reach the Safety pipeline (design.md §11.5, §11.7).
@MainActor
final class DuplicatesViewModel: ObservableObject {
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var roots: [URL] = []
    @Published private(set) var summary = DuplicateScanSummary()
    @Published private(set) var selectedIDs: Set<String> = []
    @Published private(set) var rejections: [DuplicateRejection] = []
    @Published private(set) var report: DuplicateTrashReport?

    let homeDirectory: URL
    private let scanner: any DuplicateScanning
    private let modificationDate: @Sendable (URL) -> Date?
    private let pipeline: DeletionPipeline
    private var scanTask: Task<Void, Never>?
    /// The folders the last scan covered. Only these can become protected-area grants, and only
    /// for the operation being run: nothing is kept between operations.
    private var scannedRoots: [URL] = []
    /// State captured by the last dry-run, so the confirmed move can detect files changed since.
    private var previewSnapshots: [String: ItemSnapshot] = [:]

    init(
        scanner: any DuplicateScanning = DuplicateFinder(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        modificationDate: @escaping @Sendable (URL) -> Date? = DuplicatesViewModel.fileModificationDate,
        pipeline: DeletionPipeline? = nil
    ) {
        self.scanner = scanner
        self.homeDirectory = homeDirectory
        self.modificationDate = modificationDate
        self.pipeline = pipeline ?? DeletionPipeline(homeDirectory: homeDirectory)
    }

    var canScan: Bool { !roots.isEmpty && scanTask == nil }

    func addRoots(_ urls: [URL]) {
        for url in urls.map(\.standardizedFileURL) where !roots.contains(url) {
            roots.append(url)
        }
    }

    func removeRoot(_ url: URL) {
        roots.removeAll { $0 == url }
    }

    /// Returns to the folder choice, keeping the chosen folders.
    func chooseFoldersAgain() {
        guard scanTask == nil else {
            return
        }
        resetReview()
        summary = DuplicateScanSummary()
        phase = .idle
    }

    func startScan() {
        guard canScan else {
            return
        }
        resetReview()
        summary = DuplicateScanSummary()
        phase = .scanning
        scannedRoots = roots

        let scanner = self.scanner
        let roots = self.roots
        let modificationDate = self.modificationDate
        scanTask = Task { [weak self] in
            let outcome: ScanPhase
            var found = DuplicateScanSummary()
            do {
                let result = try await scanner.scan(roots: roots)
                // Reading modification dates touches the disk: keep it off the main actor.
                found = await Task.detached {
                    Self.summary(of: result, modificationDate: modificationDate)
                }.value
                outcome = .finished
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            guard let self else {
                return
            }
            self.summary = found
            self.phase = outcome
            self.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    // MARK: - Selection

    func isSelected(_ copy: DuplicateCopy) -> Bool {
        selectedIDs.contains(copy.id)
    }

    /// A copy can be ticked only while another copy of its group stays unticked.
    func canSelect(_ copy: DuplicateCopy, in group: DuplicateGroupRow) -> Bool {
        isSelected(copy) || selectedCount(in: group) < group.copyCount - 1
    }

    func setSelected(_ isSelected: Bool, copy: DuplicateCopy, in group: DuplicateGroupRow) {
        guard group.copies.contains(copy) else {
            return
        }
        if isSelected {
            guard canSelect(copy, in: group) else {
                return
            }
            selectedIDs.insert(copy.id)
        } else {
            selectedIDs.remove(copy.id)
        }
        // A dry-run describes one selection; changing it invalidates what was previewed.
        previewSnapshots = [:]
    }

    func deselectAll() {
        selectedIDs = []
        previewSnapshots = [:]
    }

    func selectedCount(in group: DuplicateGroupRow) -> Int {
        group.copies.filter { selectedIDs.contains($0.id) }.count
    }

    var selectedCount: Int {
        summary.groups.reduce(0) { $0 + selectedCount(in: $1) }
    }

    /// Bytes of the ticked copies. What would really be freed is reported by the dry-run.
    var selectedBytes: Int64 {
        summary.groups.reduce(Int64.zero) { $0 + Int64(selectedCount(in: $1)) * $1.fileSizeBytes }
    }

    /// Picked folders inside Desktop, Documents or Downloads that hold ticked copies. The
    /// confirmation names them: moving from there uses the protected-area exception (§11.7).
    var protectedFolderNames: [String] {
        let selected = selectedPaths
        return scannedRoots.filter { root in
            Self.isInProtectedArea(root, home: homeDirectory)
                && selected.contains { Self.contains($0, in: root) }
        }
        .map { DuplicatePathFormatter.displayPath($0, homeDirectory: homeDirectory) }
    }

    // MARK: - Dry run and Trash

    /// Validates the selection without changing the filesystem and reports the byte count.
    func performDryRun() {
        run(dryRun: true)
    }

    /// Moves the selected copies to the Trash through the Safety pipeline (the caller has confirmed).
    func moveSelectedToTrash() {
        run(dryRun: false)
    }

    private var selectedPaths: Set<String> {
        Set(selectedIDs.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
    }

    private func resetReview() {
        selectedIDs = []
        rejections = []
        report = nil
        previewSnapshots = [:]
    }

    /// Items go to the pipeline one at a time so a refusal never hides the others; every refusal
    /// is audit-logged by the pipeline and shown here.
    private func run(dryRun: Bool) {
        guard !selectedIDs.isEmpty, scanTask == nil else {
            return
        }
        var newRejections: [DuplicateRejection] = []

        let plan: DuplicateTrashPlan.Plan
        do {
            plan = try DuplicateTrashPlan.make(groups: trashGroups, selectedPaths: selectedPaths)
        } catch {
            rejections = [DuplicateRejection(path: "", message: Self.message(for: error))]
            return
        }
        newRejections.append(contentsOf: plan.skipped.map { DuplicateRejection(path: $0.path, message: $0.reason) })

        // Grants only for the picked folders that hold a selected copy, built for this operation.
        let grants = makeGrants(rejections: &newRejections)
        let allowedRoots = [DuplicateTrashPlan.moduleID: grants.map(\.folder)]

        var newSnapshots: [String: ItemSnapshot] = [:]
        var processed: [CleanItem] = []
        var bytes: Int64 = 0
        for item in plan.items {
            let path = item.url.standardizedFileURL.path
            let snapshots = (dryRun ? nil : previewSnapshots[path]).map { [item.id: $0] } ?? [:]
            do {
                let result = try pipeline.execute(
                    items: [item],
                    allowedRootsByModule: allowedRoots,
                    dryRun: dryRun,
                    snapshots: snapshots,
                    protectedAreaGrants: grants
                )
                processed.append(contentsOf: result.items.map(\.item))
                bytes += result.estimatedBytes
                for entry in result.items {
                    newSnapshots[path] = entry.snapshot
                }
                newRejections.append(contentsOf: result.skipped.map {
                    DuplicateRejection(path: $0.item.url.standardizedFileURL.path, message: $0.reason)
                })
            } catch {
                newRejections.append(DuplicateRejection(path: path, message: Self.message(for: error)))
            }
        }

        rejections = newRejections
        if dryRun {
            previewSnapshots = newSnapshots
            report = .dryRun(itemCount: processed.count, bytes: bytes)
            return
        }
        report = .trashed(itemCount: processed.count, bytes: bytes)
        removeFromResults(Set(processed.map { $0.url.standardizedFileURL.path }))
        selectedIDs = []
        previewSnapshots = [:]
    }

    private var trashGroups: [DuplicateTrashGroup] {
        summary.groups.map { group in
            DuplicateTrashGroup(
                id: group.id,
                fileSizeBytes: group.fileSizeBytes,
                copies: group.copies.map { DuplicateTrashCopy(url: $0.url, modificationDate: $0.modificationDate) }
            )
        }
    }

    private func makeGrants(rejections: inout [DuplicateRejection]) -> [ProtectedAreaGrant] {
        let selected = selectedPaths
        var grants: [ProtectedAreaGrant] = []
        for root in scannedRoots where selected.contains(where: { Self.contains($0, in: root) }) {
            do {
                grants.append(try ProtectedAreaGrant(folder: root, homeDirectory: homeDirectory))
            } catch {
                rejections.append(DuplicateRejection(
                    path: root.standardizedFileURL.path,
                    message: "This folder cannot be used for moving files: " + Self.message(for: error)
                ))
            }
        }
        return grants
    }

    /// Drops moved copies, and groups left with a single copy, which are no longer duplicates.
    private func removeFromResults(_ movedPaths: Set<String>) {
        summary.groups = summary.groups.compactMap { group in
            let copies = group.copies.filter { !movedPaths.contains($0.url.standardizedFileURL.path) }
            guard copies.count >= 2 else {
                return nil
            }
            let independent = copies.filter { !$0.isClone }.count
            return DuplicateGroupRow(
                id: group.id,
                fileSizeBytes: group.fileSizeBytes,
                reclaimableBytes: Int64(max(independent - 1, 0)) * group.fileSizeBytes,
                copies: copies
            )
        }
    }

    private static func contains(_ path: String, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path.lowercased()
        let lower = path.lowercased()
        return lower == rootPath || lower.hasPrefix(rootPath + "/")
    }

    private static func isInProtectedArea(_ root: URL, home: URL) -> Bool {
        let path = root.standardizedFileURL.path.lowercased()
        return ["Desktop", "Documents", "Downloads"].contains { name in
            let area = home.appendingPathComponent(name).standardizedFileURL.path.lowercased()
            return path == area || path.hasPrefix(area + "/")
        }
    }

    private static func message(for error: Error) -> String {
        if let error = error as? SafetyError {
            return error.description
        }
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        return String(describing: error)
    }

    nonisolated static func summary(
        of result: DuplicateScanResult,
        modificationDate: (URL) -> Date?
    ) -> DuplicateScanSummary {
        let groups = result.groups.map { group in
            DuplicateGroupRow(
                id: group.id,
                fileSizeBytes: group.fileSizeBytes,
                reclaimableBytes: group.reclaimableBytes,
                copies: group.files.map {
                    DuplicateCopy(
                        url: $0.url,
                        sizeBytes: group.fileSizeBytes,
                        isClone: $0.isClone,
                        modificationDate: modificationDate($0.url)
                    )
                }
            )
        }
        return DuplicateScanSummary(
            groups: groups,
            examinedFileCount: result.examinedFileCount,
            skippedDatalessFileCount: result.skippedDatalessFileCount,
            issues: result.issues,
            isCancelled: result.isCancelled
        )
    }

    nonisolated static func fileModificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
