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

struct FullDiskAccessProbeTests {
    private let home = URL(fileURLWithPath: "/tmp/fake-home", isDirectory: true)

    private func status(_ outcomes: [String: FullDiskAccessProbeOutcome]) -> TCCStatus {
        let checker = SystemTCCAccessChecker(
            homeDirectory: home,
            probeRunner: { probe, _ in outcomes[probe.name] ?? .inconclusive },
            decisionLogger: { _ in }
        )
        return checker.fullDiskAccessStatus()
    }

    @Test func readableAuthoritativeProbeMeansGranted() {
        #expect(status(["TCC.db": .readable, "Safari": .readable]) == .granted)
    }

    @Test func refusedProbeMeansDenied() {
        #expect(status(["TCC.db": .denied, "Safari": .denied]) == .denied)
    }

    @Test func deniedProbeOverridesReadableOne() {
        #expect(status(["TCC.db": .readable, "Mail": .denied]) == .denied)
    }

    @Test func readableNonAuthoritativeProbeAloneIsUnknown() {
        #expect(status(["Safari": .readable]) == .unknown)
    }

    @Test func missingProbesAreUnknown() {
        #expect(status([:]) == .unknown)
    }

    @Test func decisionIsLogged() {
        let box = LogBox()
        let checker = SystemTCCAccessChecker(
            homeDirectory: home,
            probeRunner: { _, _ in .denied },
            decisionLogger: { box.append($0) }
        )
        _ = checker.fullDiskAccessStatus()
        #expect(box.messages.count == 1)
        #expect(box.messages[0].contains("denied"))
    }

    @Test func realProbeReportsMissingFileAsInconclusive() {
        let probe = FullDiskAccessProbe(name: "x", relativePath: "does/not/exist", isAuthoritative: true)
        #expect(SystemTCCAccessChecker.runProbe(probe, homeDirectory: home) == .inconclusive)
    }

    @Test func realProbeReadsAccessibleFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("x".utf8).write(to: directory.appendingPathComponent("file"))
        let probe = FullDiskAccessProbe(name: "x", relativePath: "file", isAuthoritative: true)
        #expect(SystemTCCAccessChecker.runProbe(probe, homeDirectory: directory) == .readable)
    }

    @Test func protectedModulesRequireFDA() {
        #expect(LargeFilesModule().requiresFDA)
        #expect(TrashBinsModule().requiresFDA)
    }

    @Test func unknownStatusBlocksLargeFilesModule() async throws {
        let manager = TCCManager(accessChecker: FixedChecker(status: .unknown))
        let result = try await manager.scan(
            module: LargeFilesModule(),
            context: ScanContext(homeDirectory: home)
        )
        guard case let .requiresPermission(message) = result else {
            Issue.record("Large Files must not scan without proven FDA.")
            return
        }
        #expect(message.contains("requires Full Disk Access"))
    }
}

private struct FixedChecker: TCCAccessChecking {
    let status: TCCStatus
    func fullDiskAccessStatus() -> TCCStatus {
        status
    }
}

private final class LogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var messages: [String] { lock.withLock { stored } }
    func append(_ message: String) {
        lock.withLock { stored.append(message) }
    }
}
