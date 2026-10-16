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

struct LargeFilesViewModelTests {
    @MainActor
    @Test func creatingTheViewModelDoesNotScan() async throws {
        let counter = ScanCounter()
        let viewModel = Self.viewModel(module: CountingModule(counter: counter))

        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.phase == .idle)
        #expect(await counter.started == 0)
    }

    @MainActor
    @Test func scanRunsOnlyWhenStartedAndFinishes() async throws {
        let counter = ScanCounter()
        let viewModel = Self.viewModel(module: CountingModule(counter: counter))

        viewModel.startScan()
        #expect(viewModel.phase == .scanning)
        try await waitForPhase(.finished, on: viewModel)

        #expect(await counter.started == 1)
    }

    @MainActor
    @Test func cancelStopsTheRunningScan() async throws {
        let counter = ScanCounter()
        let viewModel = Self.viewModel(
            module: CountingModule(counter: counter, delay: .seconds(30))
        )

        viewModel.startScan()
        try await waitForPhase(.scanning, on: viewModel)
        viewModel.cancelScan()
        try await waitForPhase(.cancelled, on: viewModel)

        #expect(viewModel.items.isEmpty)
    }

    @MainActor
    @Test func missingFullDiskAccessReportsRequiresPermission() async throws {
        let counter = ScanCounter()
        let viewModel = LargeFilesViewModel(
            module: CountingModule(counter: counter, requiresFDA: true),
            tccManager: TCCManager(accessChecker: StubAccessChecker(status: .denied))
        )

        viewModel.startScan()
        try await waitForRequiresPermission(on: viewModel)

        #expect(await counter.started == 0)
    }

    @MainActor
    private func waitForPhase(_ expected: ScanPhase, on viewModel: LargeFilesViewModel) async throws {
        for _ in 0..<100 where viewModel.phase != expected {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(viewModel.phase == expected)
    }

    @MainActor
    private func waitForRequiresPermission(on viewModel: LargeFilesViewModel) async throws {
        for _ in 0..<100 where viewModel.phase == .scanning || viewModel.phase == .idle {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .requiresPermission = viewModel.phase else {
            Issue.record("Expected requiresPermission, got \(viewModel.phase)")
            return
        }
    }

    @MainActor
    private static func viewModel(module: any CleanModule) -> LargeFilesViewModel {
        LargeFilesViewModel(
            module: module,
            tccManager: TCCManager(accessChecker: StubAccessChecker(status: .granted))
        )
    }
}

private actor ScanCounter {
    private(set) var started = 0

    func increment() {
        started += 1
    }
}

private struct CountingModule: CleanModule {
    let id = "test.large"
    let title = "Test Large Files"
    var requiresFDA = false

    let counter: ScanCounter
    var delay: Duration = .zero

    init(counter: ScanCounter, delay: Duration = .zero, requiresFDA: Bool = false) {
        self.counter = counter
        self.delay = delay
        self.requiresFDA = requiresFDA
    }

    func scan(context: ScanContext) async throws -> [CleanItem] {
        await counter.increment()
        try await Task.sleep(for: delay)
        return []
    }
}

private struct StubAccessChecker: TCCAccessChecking {
    let status: TCCStatus

    func fullDiskAccessStatus() -> TCCStatus {
        status
    }
}
