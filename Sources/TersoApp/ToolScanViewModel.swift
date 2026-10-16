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

/// The on-demand tools that live outside Smart Scan (design.md §11.1).
enum ScanTool: Equatable {
    case leftovers
    case duplicates

    var title: String {
        switch self {
        case .leftovers:
            "Leftovers"
        case .duplicates:
            "Duplicates"
        }
    }
}

/// Why part of a tool's scope was not scanned (invariant 7: never silently scan less).
struct NotScannedArea: Equatable, Sendable {
    let name: String
    let needsFullDiskAccess: Bool
}

/// What a tool scan found, and which areas it could not cover.
struct ToolScanOutcome: Sendable {
    var items: [CleanItem] = []
    var notScanned: [NotScannedArea] = []
}

/// Read-only detection behind a tool page. The real detectors arrive with #36 and #38.
protocol ToolScanning: Sendable {
    func scan(context: ScanContext) async throws -> ToolScanOutcome
}

/// Runs a tool scan only when asked; it never joins Smart Scan.
@MainActor
final class ToolScanViewModel: ObservableObject {
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var items: [CleanItem] = []
    @Published private(set) var notScanned: [NotScannedArea] = []

    let tool: ScanTool
    let homeDirectory: URL
    private let scanner: (any ToolScanning)?
    private let tccManager: TCCManager
    private var scanTask: Task<Void, Never>?

    init(
        tool: ScanTool,
        scanner: (any ToolScanning)? = nil,
        tccManager: TCCManager = TCCManager(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.tool = tool
        self.scanner = scanner
        self.tccManager = tccManager
        self.homeDirectory = homeDirectory
    }

    /// False while no detector is wired in, so the page never reports an empty result it did not compute.
    var isScanAvailable: Bool { scanner != nil }

    /// A finished scan that could not cover everything it was meant to.
    var isPartial: Bool { phase == .finished && !notScanned.isEmpty }

    func startScan() {
        guard scanTask == nil, let scanner else {
            return
        }
        items = []
        notScanned = []
        phase = .scanning

        let tccManager = self.tccManager
        let homeDirectory = self.homeDirectory
        scanTask = Task { [weak self] in
            let context = ScanContext(homeDirectory: homeDirectory, tccStatus: tccManager.status)
            var outcome = ToolScanOutcome()
            let result: ScanPhase
            do {
                outcome = try await scanner.scan(context: context)
                result = .finished
            } catch is CancellationError {
                result = .cancelled
            } catch {
                result = .failed(error.localizedDescription)
            }
            guard let self else {
                return
            }
            self.items = outcome.items
            self.notScanned = outcome.notScanned
            self.phase = result
            self.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }
}
