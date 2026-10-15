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

struct UserLogsModuleTests {
    private struct Fixture {
        let home: URL
        let logs: URL
        let outside: URL
    }

    @Test func returnsOnlyOldRotatedLogsAndReportsTheirExactSizes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let oldLogURLs = [
            fixture.logs.appendingPathComponent("app.log.1"),
            fixture.logs.appendingPathComponent("app.log.2026"),
            fixture.logs.appendingPathComponent("app.log.gz"),
            fixture.logs.appendingPathComponent("app.crash"),
            fixture.logs.appendingPathComponent("nested/app.diag")
        ]
        for url in oldLogURLs {
            try createFile(at: url, contents: url.lastPathComponent)
            try setModificationDate(now.addingTimeInterval(-120), at: url)
        }

        let recentLog = fixture.logs.appendingPathComponent("recent.log.gz")
        try createFile(at: recentLog, contents: "recent log")
        try setModificationDate(now.addingTimeInterval(-30), at: recentLog)

        let activeLog = fixture.logs.appendingPathComponent("active.log")
        let unrotatedLog = fixture.logs.appendingPathComponent("app.log.latest")
        try createFile(at: activeLog, contents: "active log")
        try createFile(at: unrotatedLog, contents: "unrotated log")
        try setModificationDate(now.addingTimeInterval(-120), at: activeLog)
        try setModificationDate(now.addingTimeInterval(-120), at: unrotatedLog)

        let module = UserLogsModule(
            minAgeSeconds: 60,
            now: { now },
            writableOpenPaths: { _ in [] }
        )
        let result = try await module.scan(context: ScanContext(homeDirectory: fixture.home))
        let expectedURLs = oldLogURLs.sorted { $0.path < $1.path }
        let expectedSizes = try expectedURLs.map(allocatedSize(of:))

        #expect(result.map(\.url.path) == expectedURLs.map(\.path))
        #expect(result.map(\.sizeBytes) == expectedSizes)
        #expect(result.allSatisfy { $0.moduleId == "logs.user" && $0.ruleId == "logs.user" })
    }

    @Test func excludesLogsCurrentlyOpenForWriting() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let openLog = fixture.logs.appendingPathComponent("open.log.1")
        let closedLog = fixture.logs.appendingPathComponent("closed.log.1")
        try createFile(at: openLog, contents: "open")
        try createFile(at: closedLog, contents: "closed")
        try setModificationDate(now.addingTimeInterval(-120), at: openLog)
        try setModificationDate(now.addingTimeInterval(-120), at: closedLog)

        let module = UserLogsModule(
            minAgeSeconds: 60,
            now: { now },
            writableOpenPaths: { _ in [openLog.path] }
        )
        let result = try await module.scan(context: ScanContext(homeDirectory: fixture.home))

        #expect(result.map(\.url.path) == [closedLog.path])
    }

    @Test func ignoresSymlinksThatEscapeTheLogsRoot() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        defer { try? FileManager.default.removeItem(at: fixture.outside) }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let outsideLog = fixture.outside.appendingPathComponent("outside.log.1")
        try createFile(at: outsideLog, contents: "outside")
        try setModificationDate(now.addingTimeInterval(-120), at: outsideLog)
        let linkedLog = fixture.logs.appendingPathComponent("linked.log.1")
        try FileManager.default.createSymbolicLink(at: linkedLog, withDestinationURL: outsideLog)

        let linkedDirectory = fixture.logs.appendingPathComponent("linked-directory", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: fixture.outside)
        let module = UserLogsModule(
            minAgeSeconds: 60,
            now: { now },
            writableOpenPaths: { _ in [] }
        )
        let result = try await module.scan(context: ScanContext(homeDirectory: fixture.home))

        #expect(result.isEmpty)
    }

    @Test func ignoresALogsRootThatIsASymbolicLink() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        defer { try? FileManager.default.removeItem(at: fixture.outside) }

        let redirectedLogs = fixture.outside.appendingPathComponent("redirected", isDirectory: true)
        try FileManager.default.createDirectory(at: redirectedLogs, withIntermediateDirectories: true)
        let redirectedLog = redirectedLogs.appendingPathComponent("redirected.log.1")
        try createFile(at: redirectedLog, contents: "redirected")
        try FileManager.default.removeItem(at: fixture.logs)
        try FileManager.default.createSymbolicLink(at: fixture.logs, withDestinationURL: redirectedLogs)

        let module = UserLogsModule(
            minAgeSeconds: 60,
            now: { Date(timeIntervalSince1970: 2_000_000_000) },
            writableOpenPaths: { _ in [] }
        )
        let result = try await module.scan(context: ScanContext(homeDirectory: fixture.home))

        #expect(result.isEmpty)
    }

    @Test func publicInitializerUsesTheTwentyFourHourDefault() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }

        let now = Date()
        let olderLog = fixture.logs.appendingPathComponent("older.log.1")
        let recentLog = fixture.logs.appendingPathComponent("recent.log.1")
        try createFile(at: olderLog, contents: "old")
        try createFile(at: recentLog, contents: "recent")
        try setModificationDate(now.addingTimeInterval(-UserLogsModule.defaultMinAgeSeconds - 60), at: olderLog)
        try setModificationDate(now.addingTimeInterval(-UserLogsModule.defaultMinAgeSeconds + 60), at: recentLog)

        let result = try await UserLogsModule().scan(context: ScanContext(homeDirectory: fixture.home))

        #expect(result.map(\.url.path) == [olderLog.path])
    }

    private func makeFixture() throws -> Fixture {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-user-logs-\(UUID().uuidString)", isDirectory: true)
        let logs = home.appendingPathComponent("Library/Logs", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-user-logs-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        return Fixture(home: home, logs: logs, outside: outside)
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    private func setModificationDate(_ date: Date, at url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func allocatedSize(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey])
        return Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
    }
}
