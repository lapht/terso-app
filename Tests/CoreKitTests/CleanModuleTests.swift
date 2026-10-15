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

@testable import CoreKit
import Foundation
import Testing

struct CleanModuleTests {
    @Test func grantedFDAAllowsRequiredModuleScan() async throws {
        let recorder = ScanRecorder()
        let module = TestCleanModule(requiresFDA: true, recorder: recorder)
        let manager = TCCManager(accessChecker: StubTCCAccessChecker(status: .granted))

        let result = try await manager.scan(module: module, context: Self.context(status: .denied))

        #expect(result == .completed([]))
        #expect(await recorder.scanCount == 1)
        #expect(await recorder.observedStatus == .granted)
    }

    @Test func deniedFDAPreventsRequiredModuleFromStarting() async throws {
        let recorder = ScanRecorder()
        let module = TestCleanModule(requiresFDA: true, recorder: recorder)
        let manager = TCCManager(accessChecker: StubTCCAccessChecker(status: .denied))

        let result = try await manager.scan(module: module, context: Self.context(status: .granted))

        guard case let .requiresPermission(message) = result else {
            Issue.record("Expected the module to require permission.")
            return
        }

        #expect(message.contains("Full Disk Access"))
        #expect(await recorder.scanCount == 0)
    }

    @Test func unknownFDAAlsoPreventsRequiredModuleFromStarting() async throws {
        let recorder = ScanRecorder()
        let module = TestCleanModule(requiresFDA: true, recorder: recorder)
        let manager = TCCManager(accessChecker: StubTCCAccessChecker(status: .unknown))

        let result = try await manager.scan(module: module, context: Self.context(status: .unknown))

        guard case .requiresPermission = result else {
            Issue.record("Unknown permission must not allow a partial scan.")
            return
        }

        #expect(await recorder.scanCount == 0)
    }

    @Test func deniedFDADoesNotDisableModuleThatDoesNotRequireIt() async throws {
        let recorder = ScanRecorder()
        let module = TestCleanModule(requiresFDA: false, recorder: recorder)
        let manager = TCCManager(accessChecker: StubTCCAccessChecker(status: .denied))

        let result = try await manager.scan(module: module, context: Self.context(status: .granted))

        #expect(result == .completed([]))
        #expect(await recorder.scanCount == 1)
        #expect(await recorder.observedStatus == .denied)
    }

    private static func context(status: TCCStatus) -> ScanContext {
        ScanContext(
            homeDirectory: URL(fileURLWithPath: "/Users/test"),
            tccStatus: status
        )
    }
}

private struct StubTCCAccessChecker: TCCAccessChecking {
    let status: TCCStatus

    func fullDiskAccessStatus() -> TCCStatus {
        status
    }
}

private struct TestCleanModule: CleanModule {
    let id = "test.module"
    let title = "Test Module"
    let requiresFDA: Bool
    let recorder: ScanRecorder

    func scan(context: ScanContext) async throws -> [CleanItem] {
        await recorder.record(status: context.tccStatus)
        return []
    }
}

private actor ScanRecorder {
    private(set) var scanCount = 0
    private(set) var observedStatus: TCCStatus?

    func record(status: TCCStatus) {
        scanCount += 1
        observedStatus = status
    }
}
