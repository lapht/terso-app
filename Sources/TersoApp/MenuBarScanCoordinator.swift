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

/// What the menu bar's Smart Scan action did with a request.
enum MenuBarScanLaunchOutcome: Equatable {
    case started
    case alreadyRunning
}

/// Menu bar entry point for Smart Scan. It only starts the read-only scan on the shared view
/// model; it never reaches the cleanup pipeline, so nothing is moved to Trash from the menu.
@MainActor
final class MenuBarScanCoordinator: ObservableObject {
    let scanSessions: ScanSessionStore
    /// Bumped on every request so the main window can bring Smart Scan to the front.
    @Published private(set) var focusRequestCount = 0

    private var scanChanges: AnyCancellable?
    private var smartScan: SmartScanViewModel { scanSessions.smartScan }

    init(scanSessions: ScanSessionStore = ScanSessionStore()) {
        self.scanSessions = scanSessions
        // Keeps the menu's status line live while the scan progresses.
        scanChanges = scanSessions.smartScan.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var isScanning: Bool {
        smartScan.state == .scanning
    }

    /// Starts Smart Scan unless one is already running, and always asks the UI to show it.
    @discardableResult
    func launchSmartScan() -> MenuBarScanLaunchOutcome {
        focusRequestCount += 1
        guard smartScan.state != .scanning else {
            return .alreadyRunning
        }
        smartScan.startScan()
        return .started
    }

    /// One-line status for the menu; details stay in the main window.
    var statusText: String? {
        switch smartScan.state {
        case .idle:
            return nil
        case .scanning:
            return "Smart Scan in progress…"
        case .cancelled:
            return "Smart Scan cancelled"
        case .failed(let message):
            return "Smart Scan failed: \(message)"
        case .finished:
            guard let result = smartScan.result else {
                return "Smart Scan finished"
            }
            if !result.permissionRequirements.isEmpty {
                return "Smart Scan finished: Full Disk Access needed for some modules"
            }
            if !result.errors.isEmpty {
                return "Smart Scan finished with errors"
            }
            return "Smart Scan found \(result.items.count) items, "
                + "\(SizeCalculator.formattedByteCount(smartScan.reclaimableBytes)) reclaimable"
        }
    }
}
