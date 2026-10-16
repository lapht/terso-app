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

struct ToolScanViewModelTests {
    @MainActor
    @Test func creatingTheViewModelDoesNotScan() async throws {
        let counter = ToolScanCounter()
        let viewModel = Self.viewModel(StubScanner(counter: counter))

        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.phase == .idle)
        #expect(await counter.started == 0)
    }

    @MainActor
    @Test func scanRunsOnlyWhenStartedAndFinishes() async throws {
        let counter = ToolScanCounter()
        let viewModel = Self.viewModel(StubScanner(counter: counter))

        viewModel.startScan()
        #expect(viewModel.phase == .scanning)
        try await waitForPhase(.finished, on: viewModel)

        #expect(await counter.started == 1)
        #expect(!viewModel.isPartial)
    }

    @MainActor
    @Test func withoutADetectorTheScanIsUnavailableAndNeverStarts() {
        let viewModel = ToolScanViewModel(tool: .leftovers)

        viewModel.startScan()

        #expect(!viewModel.isScanAvailable)
        #expect(viewModel.phase == .idle)
    }

    @MainActor
    @Test func cancelStopsTheRunningScan() async throws {
        let viewModel = Self.viewModel(StubScanner(counter: ToolScanCounter(), delay: .seconds(30)))

        viewModel.startScan()
        viewModel.cancelScan()
        try await waitForPhase(.cancelled, on: viewModel)

        #expect(viewModel.items.isEmpty)
    }

    @MainActor
    @Test func scannerErrorMovesToFailed() async throws {
        let viewModel = Self.viewModel(StubScanner(counter: ToolScanCounter(), error: StubError.boom))

        viewModel.startScan()
        try await waitForPhase(.failed(StubError.boom.localizedDescription), on: viewModel)
    }

    @MainActor
    @Test func uncoveredAreasMakeTheResultPartialAndKeepThePermissionFlag() async throws {
        let areas = [
            NotScannedArea(name: "~/Library/Containers", needsFullDiskAccess: true),
            NotScannedArea(name: "~/Library/WebKit", needsFullDiskAccess: false)
        ]
        let viewModel = Self.viewModel(StubScanner(counter: ToolScanCounter(), notScanned: areas))

        viewModel.startScan()
        try await waitForPhase(.finished, on: viewModel)

        #expect(viewModel.isPartial)
        #expect(viewModel.notScanned == areas)
    }

    @MainActor
    @Test func scannerReceivesTheCurrentFullDiskAccessStatus() async throws {
        let counter = ToolScanCounter()
        let viewModel = ToolScanViewModel(
            tool: .leftovers,
            scanner: StubScanner(counter: counter),
            tccManager: TCCManager(accessChecker: StubAccessChecker(status: .denied))
        )

        viewModel.startScan()
        try await waitForPhase(.finished, on: viewModel)

        #expect(await counter.lastStatus == .denied)
    }

    @MainActor
    @Test func eachToolKeepsItsOwnSessionViewModel() {
        let store = ScanSessionStore(tccManager: TCCManager(accessChecker: StubAccessChecker(status: .granted)))

        #expect(store.leftovers.tool == .leftovers)
        #expect(store.duplicates === store.duplicates)
        #expect(store.duplicates.phase == .idle)
    }

    @MainActor
    private func waitForPhase(_ expected: ScanPhase, on viewModel: ToolScanViewModel) async throws {
        for _ in 0..<100 where viewModel.phase != expected {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(viewModel.phase == expected)
    }

    @MainActor
    private static func viewModel(_ scanner: StubScanner) -> ToolScanViewModel {
        ToolScanViewModel(
            tool: .leftovers,
            scanner: scanner,
            tccManager: TCCManager(accessChecker: StubAccessChecker(status: .granted))
        )
    }
}

private enum StubError: Error {
    case boom
}

private actor ToolScanCounter {
    private(set) var started = 0
    private(set) var lastStatus: TCCStatus?

    func record(_ status: TCCStatus) {
        started += 1
        lastStatus = status
    }
}

private struct StubScanner: ToolScanning {
    let counter: ToolScanCounter
    var delay: Duration = .zero
    var error: StubError?
    var notScanned: [NotScannedArea] = []

    func scan(context: ScanContext) async throws -> ToolScanOutcome {
        await counter.record(context.tccStatus)
        try await Task.sleep(for: delay)
        if let error {
            throw error
        }
        return ToolScanOutcome(items: [], notScanned: notScanned)
    }
}

private struct StubAccessChecker: TCCAccessChecking {
    let status: TCCStatus

    func fullDiskAccessStatus() -> TCCStatus {
        status
    }
}
