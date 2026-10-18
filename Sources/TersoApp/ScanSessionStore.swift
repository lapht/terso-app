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

/// Keeps each scan page's view model alive for the window's lifetime, so switching sidebar
/// destinations never discards a finished scan or interrupts a running one.
@MainActor
final class ScanSessionStore: ObservableObject {
    let smartScan: SmartScanViewModel
    let largeFiles: LargeFilesViewModel
    let leftovers: ToolScanViewModel
    let leftoversReview: LeftoversViewModel
    let duplicates: DuplicatesViewModel

    private let tccManager: TCCManager
    private var moduleScans: [SidebarDestination: SmartScanViewModel] = [:]

    init(tccManager: TCCManager = TCCManager(), smartScan: SmartScanViewModel? = nil) {
        self.tccManager = tccManager
        self.smartScan = smartScan ?? SmartScanViewModel(tccManager: tccManager)
        largeFiles = LargeFilesViewModel(tccManager: tccManager)
        leftovers = ToolScanViewModel(tool: .leftovers, scanner: LeftoversToolScanner(), tccManager: tccManager)
        leftoversReview = LeftoversViewModel()
        duplicates = DuplicatesViewModel()
    }

    /// The view model for a single module's page, created on first visit and reused afterwards.
    /// Returns `nil` for destinations that are not single cleanup modules.
    func moduleScan(for destination: SidebarDestination) -> SmartScanViewModel? {
        if let existing = moduleScans[destination] {
            return existing
        }
        guard let module = destination.cleanModule else {
            return nil
        }
        let viewModel = SmartScanViewModel(tccManager: tccManager, modules: [module])
        moduleScans[destination] = viewModel
        return viewModel
    }
}
