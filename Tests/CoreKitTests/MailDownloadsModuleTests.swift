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

struct MailDownloadsModuleTests {
    private struct Fixture {
        let root: URL
        let home: URL
        let downloads: URL
        let mailbox: URL
    }

    private func context(_ fixture: Fixture, tcc: TCCStatus = .granted) -> ScanContext {
        ScanContext(homeDirectory: fixture.home, tccStatus: tcc)
    }

    @Test func returnsOnlyMailDownloadsAndNeverMailboxes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let first = fixture.downloads.appendingPathComponent("AAAA-1111", isDirectory: true)
        let second = fixture.downloads.appendingPathComponent("BBBB-2222", isDirectory: true)
        try createFile(at: first.appendingPathComponent("invoice.pdf"), contents: "invoice")
        try createFile(at: second.appendingPathComponent("photo.jpg"), contents: "photo bytes")
        try createFile(at: fixture.mailbox.appendingPathComponent("Messages/1.emlx"), contents: "message")
        try createFile(
            at: fixture.home.appendingPathComponent("Library/Mail/V10/MailData/Envelope Index"),
            contents: "database"
        )

        let result = try await MailDownloadsModule(isMailRunning: { false }).scan(context: context(fixture))

        #expect(result.map(\.url.lastPathComponent) == ["AAAA-1111", "BBBB-2222"])
        #expect(result.map(\.sizeBytes) == [
            try SizeCalculator().calculate(at: first).bytes,
            try SizeCalculator().calculate(at: second).bytes
        ])
        #expect(result.allSatisfy { $0.moduleId == "mail.downloads" && $0.ruleId == "mail.downloads" })
        #expect(result.allSatisfy { $0.url.path.hasPrefix(fixture.downloads.path + "/") })
    }

    @Test func skipsAndReportsMailDownloadsWhileMailIsRunning() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let folder = fixture.downloads.appendingPathComponent("AAAA-1111", isDirectory: true)
        try createFile(at: folder.appendingPathComponent("invoice.pdf"), contents: "invoice")

        let report = try await MailDownloadsModule(isMailRunning: { true })
            .scanReport(context: context(fixture))

        #expect(report.items.isEmpty)
        #expect(report.skippedCaches == [SkippedCache(
            moduleID: "mail.downloads",
            bundleIdentifier: "com.apple.mail",
            estimatedBytes: try SizeCalculator().calculate(at: folder).bytes
        )])
    }

    @Test func reportsNotScannedWithoutFullDiskAccess() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try createFile(at: fixture.downloads.appendingPathComponent("AAAA/a.pdf"), contents: "a")

        let module = MailDownloadsModule(isMailRunning: { false })
        #expect(module.requiresFDA)
        for status in [TCCStatus.denied, .unknown] {
            await #expect(throws: (any Error).self) {
                try await module.scan(context: context(fixture, tcc: status))
            }
        }
    }

    @Test func missingMailDownloadsFolderYieldsNothing() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.removeItem(at: fixture.downloads)

        let result = try await MailDownloadsModule(isMailRunning: { false }).scan(context: context(fixture))

        #expect(result.isEmpty)
    }

    @Test func ignoresSymlinkChildrenPointingOutsideMailDownloads() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let secret = fixture.root.appendingPathComponent("outside", isDirectory: true)
        try createFile(at: secret.appendingPathComponent("secret.txt"), contents: "secret")
        try FileManager.default.createSymbolicLink(
            at: fixture.downloads.appendingPathComponent("link"),
            withDestinationURL: secret
        )
        try createFile(at: fixture.downloads.appendingPathComponent("real/a.pdf"), contents: "a")

        let result = try await MailDownloadsModule(isMailRunning: { false }).scan(context: context(fixture))

        #expect(result.map(\.url.lastPathComponent) == ["real"])
    }

    @Test func refusesWhenMailDownloadsItselfIsASymlink() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let elsewhere = fixture.root.appendingPathComponent("elsewhere", isDirectory: true)
        try createFile(at: elsewhere.appendingPathComponent("dir/file.txt"), contents: "data")
        try FileManager.default.removeItem(at: fixture.downloads)
        try FileManager.default.createSymbolicLink(at: fixture.downloads, withDestinationURL: elsewhere)

        let result = try await MailDownloadsModule(isMailRunning: { false }).scan(context: context(fixture))

        #expect(result.isEmpty)
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-mail-downloads-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("Users/test-user", isDirectory: true)
        let downloads = home.appendingPathComponent(MailDownloadsModule.relativeRoot, isDirectory: true)
        let mailbox = home.appendingPathComponent("Library/Mail/V10/Mailbox", isDirectory: true)
        for directory in [downloads, mailbox] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return Fixture(root: root, home: home, downloads: downloads, mailbox: mailbox)
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }
}
