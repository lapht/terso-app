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
import Testing

@testable import TersoApp

struct MenuBarScanCoordinatorTests {
    @MainActor
    @Test func firstLaunchStartsASingleReadOnlyScan() async throws {
        let counter = ScanCounter()
        let coordinator = Self.coordinator(module: CountingModule(counter: counter))

        #expect(coordinator.statusText == nil)
        #expect(coordinator.launchSmartScan() == .started)
        #expect(coordinator.isScanning)
        #expect(coordinator.statusText == "Smart Scan in progress…")

        try await waitUntilFinished(coordinator)

        #expect(await counter.count == 1)
        #expect(coordinator.statusText?.hasPrefix("Smart Scan found 0 items") == true)
        // Scanning never produces a cleanup result.
        #expect(coordinator.scanSessions.smartScan.cleanupResult == nil)
    }

    @MainActor
    @Test func repeatedLaunchesDuringAScanDoNotStartConcurrentScans() async throws {
        let counter = ScanCounter()
        let coordinator = Self.coordinator(
            module: CountingModule(counter: counter, delay: .milliseconds(200))
        )

        #expect(coordinator.launchSmartScan() == .started)
        #expect(coordinator.launchSmartScan() == .alreadyRunning)
        #expect(coordinator.launchSmartScan() == .alreadyRunning)
        // Every request still asks the window to come forward.
        #expect(coordinator.focusRequestCount == 3)

        try await waitUntilFinished(coordinator)

        #expect(await counter.count == 1)
    }

    @MainActor
    @Test func reportsFullDiskAccessRequirementInTheStatus() async throws {
        let module = CountingModule(counter: ScanCounter(), requiresFDA: true)
        let coordinator = Self.coordinator(module: module, tcc: .denied)

        coordinator.launchSmartScan()
        try await waitUntilFinished(coordinator)

        #expect(coordinator.statusText == "Smart Scan finished: Full Disk Access needed for some modules")
    }

    @MainActor
    private func waitUntilFinished(_ coordinator: MenuBarScanCoordinator) async throws {
        for _ in 0..<200 where coordinator.isScanning || coordinator.scanSessions.smartScan.state == .idle {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(coordinator.scanSessions.smartScan.state == .finished)
    }

    @MainActor
    private static func coordinator(
        module: any CleanModule,
        tcc: TCCStatus = .granted
    ) -> MenuBarScanCoordinator {
        let tccManager = TCCManager(accessChecker: FixedTCCAccessChecker(status: tcc))
        let smartScan = SmartScanViewModel(
            tccManager: tccManager,
            modules: [module],
            context: ScanContext(homeDirectory: URL(fileURLWithPath: "/Users/test"), tccStatus: tcc)
        )
        return MenuBarScanCoordinator(
            scanSessions: ScanSessionStore(tccManager: tccManager, smartScan: smartScan)
        )
    }
}

private struct FixedTCCAccessChecker: TCCAccessChecking {
    let status: TCCStatus

    func fullDiskAccessStatus() -> TCCStatus {
        status
    }
}

private actor ScanCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

private struct CountingModule: CleanModule {
    let id = "test.module"
    let title = "Test Module"
    let counter: ScanCounter
    var delay: Duration = .zero
    var requiresFDA = false

    func scan(context: ScanContext) async throws -> [CleanItem] {
        await counter.increment()
        try await Task.sleep(for: delay)
        return []
    }
}
