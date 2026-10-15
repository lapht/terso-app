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

private final class DeletionFixture {
    let rootURL: URL
    let homeURL: URL
    let cachesURL: URL
    let outsideURL: URL
    let auditLogURL: URL
    let auditLogger: AuditLogger

    init() throws {
        rootURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("terso-deletion-tests-\(UUID().uuidString)", isDirectory: true)
        homeURL = rootURL.appendingPathComponent("Users/testuser", isDirectory: true)
        cachesURL = homeURL.appendingPathComponent("Library/Caches", isDirectory: true)
        outsideURL = homeURL.appendingPathComponent("Library/Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: cachesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        auditLogURL = rootURL.appendingPathComponent("audit.log")
        auditLogger = AuditLogger(fileURL: auditLogURL)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makeItem(
        at url: URL,
        content: String,
        action: CleanAction = .trash,
        isDeletable: Bool = true
    ) throws -> CleanItem {
        try content.write(to: url, atomically: true, encoding: .utf8)
        return CleanItem(
            url: url,
            resolvedURL: url.resolvingSymlinksInPath(),
            sizeBytes: Int64(content.utf8.count),
            moduleId: "caches.user",
            ruleId: "caches.user.fixture",
            isDeletable: isDeletable,
            recommendedAction: action
        )
    }

    var allowedRootsByModule: [String: [URL]] {
        ["caches.user": [cachesURL]]
    }
}

struct DeletionPipelineTests {
    @Test func dryRunReportsItemsAndBytesWithoutChangingFilesystem() throws {
        let fixture = try DeletionFixture()
        let itemURL = fixture.cachesURL.appendingPathComponent("cache.dat")
        let item = try fixture.makeItem(at: itemURL, content: "cached contents")
        let originalContents = try String(contentsOf: itemURL, encoding: .utf8)
        let pipeline = DeletionPipeline(homeDirectory: fixture.homeURL, auditLogger: fixture.auditLogger)

        let result = try pipeline.execute(
            items: [item],
            allowedRootsByModule: fixture.allowedRootsByModule,
            dryRun: true
        )

        #expect(result.isDryRun)
        #expect(result.items.map(\.item) == [item])
        #expect(result.items.first?.resultingItemURL == nil)
        #expect(result.estimatedBytes == Int64(originalContents.utf8.count))
        #expect(FileManager.default.fileExists(atPath: itemURL.path))
        #expect(try String(contentsOf: itemURL, encoding: .utf8) == originalContents)
        let records = try String(contentsOf: fixture.auditLogURL, encoding: .utf8)
            .split(separator: "\n")
        #expect(records.count == 1)
        let record = try JSONDecoder().decode(AuditRecord.self, from: Data(records[0].utf8))
        #expect(record.action == .dryRun)
        #expect(record.result == .success)
    }

    @Test func executionMovesItemToTrashAndReturnsResultingURL() throws {
        let fixture = try DeletionFixture()
        let itemURL = fixture.cachesURL.appendingPathComponent("cache.dat")
        let item = try fixture.makeItem(at: itemURL, content: "trash me")
        let pipeline = DeletionPipeline(homeDirectory: fixture.homeURL, auditLogger: fixture.auditLogger)
        var resultingItemURL: URL?

        defer {
            if let resultingItemURL, FileManager.default.fileExists(atPath: resultingItemURL.path) {
                do {
                    try FileManager.default.moveItem(at: resultingItemURL, to: itemURL)
                } catch {
                    Issue.record("Could not restore the test item from Trash: \(error)")
                }
            }
        }

        let result = try pipeline.execute(
            items: [item],
            allowedRootsByModule: fixture.allowedRootsByModule,
            dryRun: false
        )

        let returnedItemURL = try #require(result.items.first?.resultingItemURL)
        resultingItemURL = returnedItemURL
        #expect(!result.isDryRun)
        #expect(result.estimatedBytes == Int64("trash me".utf8.count))
        #expect(!FileManager.default.fileExists(atPath: itemURL.path))
        #expect(FileManager.default.fileExists(atPath: returnedItemURL.path))
        let records = try String(contentsOf: fixture.auditLogURL, encoding: .utf8)
            .split(separator: "\n")
        let record = try JSONDecoder().decode(AuditRecord.self, from: Data(try #require(records.first).utf8))
        #expect(record.action == .trash)
        #expect(record.result == .success)
    }

    @Test func unauthorizedItemIsRejectedBeforeAnyItemIsMoved() throws {
        let fixture = try DeletionFixture()
        let authorizedURL = fixture.cachesURL.appendingPathComponent("allowed.dat")
        let unauthorizedURL = fixture.outsideURL.appendingPathComponent("not-allowed.dat")
        let authorizedItem = try fixture.makeItem(at: authorizedURL, content: "safe")
        let unauthorizedItem = try fixture.makeItem(at: unauthorizedURL, content: "blocked")
        let pipeline = DeletionPipeline(homeDirectory: fixture.homeURL, auditLogger: fixture.auditLogger)

        #expect(throws: SafetyError.self) {
            try pipeline.execute(
                items: [authorizedItem, unauthorizedItem],
                allowedRootsByModule: fixture.allowedRootsByModule,
                dryRun: false
            )
        }
        #expect(FileManager.default.fileExists(atPath: authorizedURL.path))
        #expect(FileManager.default.fileExists(atPath: unauthorizedURL.path))
        let records = try String(contentsOf: fixture.auditLogURL, encoding: .utf8)
            .split(separator: "\n")
        let record = try JSONDecoder().decode(AuditRecord.self, from: Data(try #require(records.first).utf8))
        #expect(record.action == .trash)
        #expect(record.result == .failure)
        #expect(record.errorCode == "pathNotAllowlisted")
    }

    @Test func symlinkEscapeIsRejectedWithoutMovingTheLink() throws {
        let fixture = try DeletionFixture()
        let targetURL = fixture.outsideURL.appendingPathComponent("target.dat")
        try "outside".write(to: targetURL, atomically: true, encoding: .utf8)
        let linkURL = fixture.cachesURL.appendingPathComponent("outside-link")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)
        let item = CleanItem(
            url: linkURL,
            resolvedURL: targetURL,
            sizeBytes: 7,
            moduleId: "caches.user",
            ruleId: "caches.user.fixture"
        )
        let pipeline = DeletionPipeline(homeDirectory: fixture.homeURL, auditLogger: fixture.auditLogger)

        #expect(throws: SafetyError.self) {
            try pipeline.execute(
                items: [item],
                allowedRootsByModule: fixture.allowedRootsByModule,
                dryRun: false
            )
        }
        #expect(FileManager.default.fileExists(atPath: linkURL.path))
        #expect(try String(contentsOf: targetURL, encoding: .utf8) == "outside")
    }

    @Test func permanentDeletionIsNotSupported() throws {
        let fixture = try DeletionFixture()
        let itemURL = fixture.cachesURL.appendingPathComponent("keep.dat")
        let item = try fixture.makeItem(at: itemURL, content: "keep", action: .permanentDelete)
        let pipeline = DeletionPipeline(homeDirectory: fixture.homeURL, auditLogger: fixture.auditLogger)

        #expect(throws: DeletionPipelineError.self) {
            try pipeline.execute(
                items: [item],
                allowedRootsByModule: fixture.allowedRootsByModule,
                dryRun: false
            )
        }
        #expect(FileManager.default.fileExists(atPath: itemURL.path))
    }

    @Test func nonDeletableItemIsRejectedBeforeDryRunOrDeletion() throws {
        let fixture = try DeletionFixture()
        let itemURL = fixture.cachesURL.appendingPathComponent("large-file.dat")
        let item = try fixture.makeItem(
            at: itemURL,
            content: "read only",
            action: .revealInFinder,
            isDeletable: false
        )
        let pipeline = DeletionPipeline(homeDirectory: fixture.homeURL, auditLogger: fixture.auditLogger)

        do {
            _ = try pipeline.execute(
                items: [item],
                allowedRootsByModule: fixture.allowedRootsByModule,
                dryRun: true
            )
            Issue.record("The pipeline must reject non-deletable items.")
        } catch let error as DeletionPipelineError {
            #expect(error == .nonDeletableItem(path: itemURL.path))
        }

        #expect(FileManager.default.fileExists(atPath: itemURL.path))
        let records = try String(contentsOf: fixture.auditLogURL, encoding: .utf8)
            .split(separator: "\n")
        let record = try JSONDecoder().decode(AuditRecord.self, from: Data(try #require(records.first).utf8))
        #expect(record.action == .dryRun)
        #expect(record.result == .failure)
        #expect(record.errorCode == "nonDeletableItem")
    }
}
