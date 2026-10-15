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

struct AuditLogViewModelTests {
    @MainActor
    @Test func loadsRecentRecordsAndExportsReadableReport() throws {
        let fixture = try AuditLogFixture()
        let logger = AuditLogger(fileURL: fixture.logURL)
        let item = fixture.makeItem()
        try logger.record(
            action: .trash,
            item: item,
            result: .success,
            timestamp: Date(timeIntervalSince1970: 1_735_689_600)
        )
        let viewModel = AuditLogViewModel(logger: logger)

        viewModel.refresh()

        #expect(viewModel.records.count == 1)
        #expect(viewModel.records[0].ruleId == "test.rule")
        #expect(viewModel.records[0].originalPath == item.url.path)
        #expect(viewModel.records[0].result == .success)

        let exportURL = fixture.rootURL.appendingPathComponent("export.txt")
        try viewModel.export(to: exportURL)

        let exportedReport = try String(contentsOf: exportURL, encoding: .utf8)
        #expect(exportedReport.contains("Terso Audit Report"))
        #expect(exportedReport.contains("test.rule"))
        #expect(exportedReport.contains(item.url.path))
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func exposesCorruptLogReadErrors() throws {
        let fixture = try AuditLogFixture()
        try Data("invalid log".utf8).write(to: fixture.logURL)
        let viewModel = AuditLogViewModel(logger: AuditLogger(fileURL: fixture.logURL))

        viewModel.refresh()

        #expect(viewModel.records.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }
}

private final class AuditLogFixture {
    let rootURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("terso-audit-ui-tests-\(UUID().uuidString)", isDirectory: true)

    var logURL: URL {
        rootURL.appendingPathComponent("audit.log")
    }

    init() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makeItem() -> CleanItem {
        let url = URL(fileURLWithPath: "/Users/test/Library/Caches/sample")
        return CleanItem(
            url: url,
            resolvedURL: url,
            sizeBytes: 123,
            moduleId: "test.module",
            ruleId: "test.rule"
        )
    }
}
