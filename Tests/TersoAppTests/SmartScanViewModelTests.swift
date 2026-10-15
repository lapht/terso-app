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

struct SmartScanViewModelTests {
    @MainActor
    @Test func transitionsFromIdleThroughScanningToFinished() async throws {
        let item = Self.item(moduleID: "test.module", size: 1_024)
        let recorder = ScanStartRecorder()
        let module = MockSmartScanModule(items: [item], recorder: recorder)
        let viewModel = Self.viewModel(module: module)

        #expect(viewModel.state == .idle)
        viewModel.startScan()
        await recorder.waitForStart()
        #expect(viewModel.state == .scanning)

        try await waitForState(.finished, on: viewModel)

        #expect(viewModel.result?.items == [item])
        #expect(viewModel.reclaimableBytes == 1_024)
        #expect(viewModel.activeModuleTitles.isEmpty)
        #expect(
            viewModel.moduleSummaries == [
                SmartScanModuleSummary(
                    id: "test.module",
                    title: "Test Module",
                    itemsFound: 1,
                    bytesFound: 1_024,
                    status: .completed
                )
            ])
    }

    @MainActor
    @Test func transitionsToCancelledWhenTheRunningScanIsCancelled() async throws {
        let recorder = ScanStartRecorder()
        let module = MockSmartScanModule(
            delay: .seconds(30),
            items: [],
            recorder: recorder
        )
        let viewModel = Self.viewModel(module: module)

        viewModel.startScan()
        await recorder.waitForStart()
        #expect(viewModel.state == .scanning)

        viewModel.cancelScan()
        try await waitForState(.cancelled, on: viewModel)
        #expect(viewModel.result == nil)
    }

    @MainActor
    private func waitForState(
        _ expected: SmartScanViewState,
        on viewModel: SmartScanViewModel
    ) async throws {
        for _ in 0..<100 where viewModel.state != expected {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(viewModel.state == expected)
    }

    @MainActor
    private static func viewModel(module: any CleanModule) -> SmartScanViewModel {
        let tccManager = TCCManager(accessChecker: GrantedTCCAccessChecker())
        return SmartScanViewModel(
            tccManager: tccManager,
            modules: [module],
            context: ScanContext(
                homeDirectory: URL(fileURLWithPath: "/Users/test"),
                tccStatus: .granted
            )
        )
    }

    private static func item(moduleID: String, size: Int64) -> CleanItem {
        let url = URL(fileURLWithPath: "/Users/test/candidate")
        return CleanItem(
            url: url,
            resolvedURL: url,
            sizeBytes: size,
            moduleId: moduleID,
            ruleId: moduleID
        )
    }
}

private struct GrantedTCCAccessChecker: TCCAccessChecking {
    func fullDiskAccessStatus() -> TCCStatus {
        .granted
    }
}

private struct MockSmartScanModule: CleanModule {
    let id = "test.module"
    let title = "Test Module"
    let requiresFDA = false

    var delay: Duration = .zero
    let items: [CleanItem]
    let recorder: ScanStartRecorder

    func scan(context: ScanContext) async throws -> [CleanItem] {
        await recorder.markStarted()
        try await Task.sleep(for: delay)
        return items
    }
}

private actor ScanStartRecorder {
    private var hasStarted = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        hasStarted = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }

    func waitForStart() async {
        guard !hasStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
