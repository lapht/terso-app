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

/// One category of old files with its totals, for display.
struct OldFilesGroup: Identifiable, Equatable {
    var id: OldFileCategory { category }
    let category: OldFileCategory
    let items: [OldFileItem]

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }
}

extension OldFilesReport {
    /// Non-empty categories in a stable order, largest file first. Nothing is ever selected.
    var groups: [OldFilesGroup] {
        OldFileCategory.allCases.compactMap { category in
            let inCategory = items.filter { $0.category == category }.sorted { $0.sizeBytes > $1.sizeBytes }
            return inCategory.isEmpty ? nil : OldFilesGroup(category: category, items: inCategory)
        }
    }
}

/// Runs the read-only old files discovery only when asked. Nothing here can select, move or
/// delete an item.
@MainActor
final class OldFilesViewModel: ObservableObject {
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var report = OldFilesReport(items: [], notScanned: [], skippedDatalessCount: 0)

    private let scanner: OldFilesScanner
    private let homeDirectory: URL
    private var scanTask: Task<Void, Never>?

    init(
        scanner: OldFilesScanner = OldFilesScanner(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.scanner = scanner
        self.homeDirectory = homeDirectory
    }

    var totalBytes: Int64 {
        report.items.reduce(0) { $0 + $1.sizeBytes }
    }

    func startScan() {
        guard scanTask == nil else {
            return
        }
        report = OldFilesReport(items: [], notScanned: [], skippedDatalessCount: 0)
        phase = .scanning

        let scanner = self.scanner
        let home = homeDirectory
        scanTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                scanner.scan(homeDirectory: home)
            }.value
            guard let self else {
                return
            }
            if Task.isCancelled {
                phase = .cancelled
            } else {
                report = result
                phase = .finished
            }
            scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }
}
