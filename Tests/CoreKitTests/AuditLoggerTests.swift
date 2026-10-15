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

private final class AuditLoggerFixture {
    let rootURL: URL

    var logURL: URL {
        rootURL.appendingPathComponent("Library/Logs/Terso/audit.log")
    }

    var reportURL: URL {
        rootURL.appendingPathComponent("audit-report.txt")
    }

    init() throws {
        rootURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("terso-audit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makeItem() -> CleanItem {
        let itemURL = rootURL.appendingPathComponent("Caches/example.cache")
        return CleanItem(
            url: itemURL,
            resolvedURL: itemURL,
            sizeBytes: 123,
            moduleId: "caches.user",
            ruleId: "caches.user.example"
        )
    }
}

struct AuditLoggerTests {
    @Test func writesStructuredJsonLinesWithoutFileContents() throws {
        let fixture = try AuditLoggerFixture()
        let item = fixture.makeItem()
        try FileManager.default.createDirectory(
            at: item.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "private payload".write(to: item.url, atomically: true, encoding: .utf8)
        let logger = AuditLogger(fileURL: fixture.logURL)
        let timestamp = Date(timeIntervalSince1970: 1_735_689_600)

        try logger.record(
            action: .trash,
            item: item,
            result: .failure,
            errorCode: "permissionDenied",
            timestamp: timestamp
        )

        let contents = try String(contentsOf: fixture.logURL, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        #expect(lines.count == 1)
        let record = try JSONDecoder().decode(AuditRecord.self, from: Data(lines[0].utf8))
        #expect(record.timestamp == "2025-01-01T00:00:00.000Z")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(formatter.date(from: record.timestamp) == timestamp)
        #expect(record.action == .trash)
        #expect(record.moduleId == "caches.user")
        #expect(record.ruleId == "caches.user.example")
        #expect(record.originalPath == item.url.standardizedFileURL.path)
        #expect(record.resolvedPath == item.resolvedURL.standardizedFileURL.path)
        #expect(record.sizeBytes == 123)
        #expect(record.result == .failure)
        #expect(record.errorCode == "permissionDenied")
        #expect(!contents.contains("private payload"))
    }

    @Test func refusesFailureRecordsWithoutAnErrorCode() throws {
        let fixture = try AuditLoggerFixture()
        let logger = AuditLogger(fileURL: fixture.logURL)

        #expect(throws: AuditLoggerError.self) {
            try logger.record(action: .trash, item: fixture.makeItem(), result: .failure)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.logURL.path))
    }

    @Test func surfacesLogDirectoryWriteFailures() throws {
        let fixture = try AuditLoggerFixture()
        let blockingFileURL = fixture.rootURL.appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: blockingFileURL)
        let logger = AuditLogger(fileURL: blockingFileURL.appendingPathComponent("audit.log"))

        #expect(throws: AuditLoggerError.self) {
            try logger.record(action: .dryRun, item: fixture.makeItem(), result: .success)
        }
    }

    @Test func exportsReadableReportWithoutModifyingJsonLinesLog() throws {
        let fixture = try AuditLoggerFixture()
        let item = fixture.makeItem()
        let logger = AuditLogger(fileURL: fixture.logURL)
        try logger.record(action: .dryRun, item: item, result: .success)
        try logger.record(
            action: .trash,
            item: item,
            result: .failure,
            errorCode: "permissionDenied"
        )

        try logger.exportReport(to: fixture.reportURL)

        let report = try String(contentsOf: fixture.reportURL, encoding: .utf8)
        #expect(report.contains("Terso Audit Report"))
        #expect(report.contains("dryRun — success"))
        #expect(report.contains("trash — failure"))
        #expect(report.contains("Module: caches.user"))
        #expect(report.contains("Rule: caches.user.example"))
        #expect(report.contains("Original path: \(item.url.standardizedFileURL.path)"))
        #expect(report.contains("Resolved path: \(item.resolvedURL.standardizedFileURL.path)"))
        #expect(report.contains("Size: 123 bytes"))
        #expect(report.contains("Error code: permissionDenied"))
        #expect(try String(contentsOf: fixture.logURL, encoding: .utf8).contains("\"action\":\"dryRun\""))
    }

    @Test func exportToLogItselfIsRejected() throws {
        let fixture = try AuditLoggerFixture()
        let logger = AuditLogger(fileURL: fixture.logURL)

        #expect(throws: AuditLoggerError.self) {
            try logger.exportReport(to: fixture.logURL)
        }
    }

    @Test func defaultLogURLUsesTheUserLogsDirectory() {
        let expectedURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Terso/audit.log")
        #expect(AuditLogger.defaultLogURL == expectedURL)
    }
}
