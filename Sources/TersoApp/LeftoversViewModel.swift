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

import Combine
import CoreKit
import Foundation

/// Review state for found leftovers: nothing is selected until the user chooses it, and only
/// the selected items ever reach the Safety pipeline (design.md §11.4, invariants 4–6, 8).
@MainActor
final class LeftoversViewModel: ObservableObject {
    /// An item the pipeline refused or failed to process, kept visible next to the list.
    struct Rejection: Identifiable, Equatable {
        let id = UUID()
        let path: String
        let message: String
    }

    /// What the last dry-run or cleanup did, with the byte count of the invariant 5 recap.
    enum Report: Equatable {
        case dryRun(itemCount: Int, bytes: Int64)
        case trashed(itemCount: Int, bytes: Int64)
    }

    @Published private(set) var items: [CleanItem] = []
    @Published private(set) var reasons: [UUID: String] = [:]
    @Published private(set) var selectedIDs: Set<UUID> = []
    @Published private(set) var rejections: [Rejection] = []
    @Published private(set) var report: Report?

    let homeDirectory: URL
    private let pipeline: DeletionPipeline

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        pipeline: DeletionPipeline? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.pipeline = pipeline ?? DeletionPipeline(homeDirectory: homeDirectory)
    }

    var selectedItems: [CleanItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        Self.totalBytes(of: selectedItems)
    }

    /// Replaces the list with a new scan result. Nothing is preselected.
    func load(items: [CleanItem], reasons: [UUID: String] = [:]) {
        self.items = items
        self.reasons = reasons
        selectedIDs = []
        rejections = []
        report = nil
    }

    func isSelected(_ item: CleanItem) -> Bool {
        selectedIDs.contains(item.id)
    }

    func setSelected(_ isSelected: Bool, for item: CleanItem) {
        guard items.contains(item) else {
            return
        }
        if isSelected {
            selectedIDs.insert(item.id)
        } else {
            selectedIDs.remove(item.id)
        }
    }

    func deselectAll() {
        selectedIDs = []
    }

    /// Validates the selection without changing the filesystem and reports the byte count.
    func performDryRun() {
        run(dryRun: true)
    }

    /// Moves the selected items to the Trash through the Safety pipeline (the caller has confirmed).
    func moveSelectedToTrash() {
        run(dryRun: false)
    }

    // MARK: - Execution

    /// Items go to the pipeline one at a time so a refusal never hides the others: each one is
    /// validated, trashed or refused on its own, and every refusal is audit-logged by the pipeline.
    private func run(dryRun: Bool) {
        let selection = selectedItems
        guard !selection.isEmpty else {
            return
        }
        let allowedRoots = [LeftoversDetector.moduleID: LeftoversDetector.allowedRoots(homeDirectory: homeDirectory)]
        var processed: [CleanItem] = []
        var newRejections: [Rejection] = []

        for item in selection {
            do {
                let result = try pipeline.execute(items: [item], allowedRootsByModule: allowedRoots, dryRun: dryRun)
                processed.append(contentsOf: result.items.map(\.item))
            } catch {
                newRejections.append(Rejection(
                    path: item.url.standardizedFileURL.path,
                    message: Self.message(for: error)
                ))
            }
        }

        rejections = newRejections
        let bytes = Self.totalBytes(of: processed)
        if dryRun {
            report = .dryRun(itemCount: processed.count, bytes: bytes)
            return
        }
        report = .trashed(itemCount: processed.count, bytes: bytes)
        let processedIDs = Set(processed.map(\.id))
        items.removeAll { processedIDs.contains($0.id) }
        selectedIDs = []
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

    private static func totalBytes(of items: [CleanItem]) -> Int64 {
        items.reduce(into: Int64.zero) { total, item in
            let (sum, overflow) = total.addingReportingOverflow(item.sizeBytes)
            total = overflow ? .max : sum
        }
    }
}
