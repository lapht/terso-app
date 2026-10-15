// SPDX-License-Identifier: GPL-3.0-or-later
//
// Terso — The Auditable Mac Cleaner
// Copyright (C) 2026 Terso Contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License
// as published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

@testable import CoreKit
import Foundation
import Testing

struct SmartScanAggregatorTests {
    @Test func scansModulesConcurrentlyAndAlwaysUsesDryRun() async throws {
        let recorder = SmartScanRecorder()
        let quickItem = Self.item(moduleID: "quick", size: 20)
        let slowItem = Self.item(moduleID: "slow", size: 30)
        let aggregator = SmartScanAggregator(tccManager: Self.tccManager(status: .granted))
        let (progressStream, progressContinuation) = AsyncStream<SmartScanProgress>.makeStream()
        let modules: [any CleanModule] = [
            MockCleanModule(
                id: "quick",
                behavior: .delayed(.milliseconds(20), [quickItem]),
                recorder: recorder
            ),
            MockCleanModule(
                id: "slow",
                behavior: .delayed(.milliseconds(250), [slowItem]),
                recorder: recorder
            )
        ]

        let result = try await aggregator.scan(
            modules: modules,
            context: Self.context(isDryRun: false),
            onProgress: { progressContinuation.yield($0) }
        )
        progressContinuation.finish()
        var progress: [SmartScanProgress] = []
        for await update in progressStream {
            progress.append(update)
        }

        #expect(await recorder.maximumConcurrentScans == 2)
        #expect(await recorder.dryRunValues == [true, true])
        #expect(result.items == [quickItem, slowItem])
        #expect(result.bytesFound == 50)
        #expect(result.completedModules == 2)
        #expect(result.totalModules == 2)
        #expect(result.errors.isEmpty)
        #expect(result.permissionRequirements.isEmpty)
        #expect(progress.filter { $0.moduleStatus == .scanning }.count == 2)
        #expect(progress.filter { $0.moduleStatus == .completed }.map(\.moduleID) == ["quick", "slow"])
        #expect(progress.last?.fractionCompleted == 1)
        #expect(progress.last?.itemsFound == 2)
        #expect(progress.last?.bytesFound == 50)
    }

    @Test func continuesAfterModuleFailureAndReportsPermissionRequirements() async throws {
        let recorder = SmartScanRecorder()
        let expectedItem = Self.item(moduleID: "success", size: 42)
        let aggregator = SmartScanAggregator(tccManager: Self.tccManager(status: .denied))
        let modules: [any CleanModule] = [
            MockCleanModule(id: "failure", behavior: .failure, recorder: recorder),
            MockCleanModule(id: "permission", requiresFDA: true, behavior: .immediate([]), recorder: recorder),
            MockCleanModule(id: "success", behavior: .immediate([expectedItem]), recorder: recorder)
        ]

        let result = try await aggregator.scan(modules: modules, context: Self.context())

        #expect(result.items == [expectedItem])
        #expect(result.bytesFound == 42)
        #expect(result.errors.map(\.moduleID) == ["failure"])
        #expect(result.errors.first?.message == "Expected mock failure.")
        #expect(result.permissionRequirements.map(\.moduleID) == ["permission"])
        #expect(result.completedModules == 3)
        #expect(await recorder.startedModuleIDs == ["failure", "success"])
    }

    @Test func cancellationStopsCooperativeModuleAndThrowsCancellationError() async throws {
        let recorder = SmartScanRecorder()
        let aggregator = SmartScanAggregator(tccManager: Self.tccManager(status: .granted))
        let module = MockCleanModule(id: "slow", behavior: .waitForCancellation, recorder: recorder)
        let task = Task {
            try await aggregator.scan(
                modules: [module],
                context: Self.context()
            )
        }

        await recorder.waitForStart(of: "slow")
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("A cancelled scan must not return a partial success.")
        } catch is CancellationError {
            #expect(await recorder.cancellationCount == 1)
        }
    }

    private static func context(isDryRun: Bool = true) -> ScanContext {
        ScanContext(
            homeDirectory: URL(fileURLWithPath: "/Users/test"),
            isDryRun: isDryRun,
            tccStatus: .granted
        )
    }

    private static func item(moduleID: String, size: Int64) -> CleanItem {
        let url = URL(fileURLWithPath: "/Users/test/\(moduleID).tmp")
        return CleanItem(
            url: url,
            resolvedURL: url,
            sizeBytes: size,
            moduleId: moduleID,
            ruleId: moduleID
        )
    }

    private static func tccManager(status: TCCStatus) -> TCCManager {
        TCCManager(accessChecker: MockTCCAccessChecker(status: status))
    }
}

private enum MockBehavior: Sendable {
    case immediate([CleanItem])
    case delayed(Duration, [CleanItem])
    case failure
    case waitForCancellation
}

private struct MockCleanModule: CleanModule {
    let id: String
    let title: String
    let requiresFDA: Bool
    let behavior: MockBehavior
    let recorder: SmartScanRecorder

    init(
        id: String,
        title: String? = nil,
        requiresFDA: Bool = false,
        behavior: MockBehavior,
        recorder: SmartScanRecorder
    ) {
        self.id = id
        self.title = title ?? id
        self.requiresFDA = requiresFDA
        self.behavior = behavior
        self.recorder = recorder
    }

    func scan(context: ScanContext) async throws -> [CleanItem] {
        await recorder.started(moduleID: id, isDryRun: context.isDryRun)
        do {
            let items: [CleanItem]
            switch behavior {
            case let .immediate(results):
                items = results
            case let .delayed(duration, results):
                try await Task.sleep(for: duration)
                items = results
            case .failure:
                throw MockScanError.expectedFailure
            case .waitForCancellation:
                try await Task.sleep(for: .seconds(60))
                items = []
            }
            await recorder.finished()
            return items
        } catch is CancellationError {
            await recorder.cancelled()
            await recorder.finished()
            throw CancellationError()
        } catch {
            await recorder.finished()
            throw error
        }
    }
}

private enum MockScanError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected mock failure."
    }
}

private struct MockTCCAccessChecker: TCCAccessChecking {
    let status: TCCStatus

    func fullDiskAccessStatus() -> TCCStatus {
        status
    }
}

private actor SmartScanRecorder {
    private(set) var maximumConcurrentScans = 0
    private(set) var dryRunValues: [Bool] = []
    private(set) var startedModuleIDs: Set<String> = []
    private(set) var cancellationCount = 0
    private var activeScans = 0
    private var startWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func started(moduleID: String, isDryRun: Bool) {
        startedModuleIDs.insert(moduleID)
        dryRunValues.append(isDryRun)
        activeScans += 1
        maximumConcurrentScans = max(maximumConcurrentScans, activeScans)
        startWaiters.removeValue(forKey: moduleID)?.forEach { $0.resume() }
    }

    func finished() {
        activeScans -= 1
    }

    func cancelled() {
        cancellationCount += 1
    }

    func waitForStart(of moduleID: String) async {
        guard !startedModuleIDs.contains(moduleID) else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters[moduleID, default: []].append(continuation)
        }
    }
}
