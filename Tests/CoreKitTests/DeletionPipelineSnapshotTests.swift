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

private final class SnapshotFixture {
    let rootURL: URL
    let homeURL: URL
    let cachesURL: URL
    let auditLogURL: URL
    let pipeline: DeletionPipeline

    init() throws {
        rootURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("terso-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        homeURL = rootURL.appendingPathComponent("Users/testuser", isDirectory: true)
        cachesURL = homeURL.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: cachesURL, withIntermediateDirectories: true)
        auditLogURL = rootURL.appendingPathComponent("audit.log")
        pipeline = DeletionPipeline(homeDirectory: homeURL, auditLogger: AuditLogger(fileURL: auditLogURL))
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    var allowedRootsByModule: [String: [URL]] {
        ["caches.user": [cachesURL]]
    }

    func makeItem(named name: String, content: String) throws -> CleanItem {
        let url = cachesURL.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return CleanItem(
            url: url,
            resolvedURL: url.resolvingSymlinksInPath(),
            sizeBytes: Int64(content.utf8.count),
            moduleId: "caches.user",
            ruleId: "caches.user.fixture"
        )
    }

    /// Runs the dry-run and returns the snapshots keyed the way `execute` expects them.
    func preview(_ items: [CleanItem]) throws -> [UUID: ItemSnapshot] {
        let result = try pipeline.execute(items: items, allowedRootsByModule: allowedRootsByModule, dryRun: true)
        var snapshots: [UUID: ItemSnapshot] = [:]
        for entry in result.items {
            guard let snapshot = entry.snapshot else {
                Issue.record("Dry-run did not capture a snapshot for \(entry.item.url.lastPathComponent)")
                continue
            }
            snapshots[entry.item.id] = snapshot
        }
        return snapshots
    }

    func auditCodes() throws -> [String?] {
        try String(contentsOf: auditLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try JSONDecoder().decode(AuditRecord.self, from: Data($0.utf8)).errorCode }
    }
}

struct DeletionPipelineSnapshotTests {
    @Test func dryRunCapturesIdentitySizeAndModificationDate() throws {
        let fixture = try SnapshotFixture()
        let item = try fixture.makeItem(named: "a.dat", content: "12345")

        let snapshot = try #require(try fixture.preview([item])[item.id])

        #expect(snapshot.sizeBytes == 5)
        #expect(!snapshot.isDirectory)
        #expect(snapshot == ItemSnapshot.capture(item.url))
    }

    @Test func itemModifiedAfterPreviewIsSkippedAndNeverMoved() throws {
        let fixture = try SnapshotFixture()
        let item = try fixture.makeItem(named: "a.dat", content: "before")
        let snapshots = try fixture.preview([item])

        try "changed after preview".write(to: item.url, atomically: false, encoding: .utf8)
        let result = try fixture.pipeline.execute(
            items: [item],
            allowedRootsByModule: fixture.allowedRootsByModule,
            dryRun: false,
            snapshots: snapshots
        )

        #expect(result.items.isEmpty)
        #expect(result.skipped.map(\.item) == [item])
        #expect(FileManager.default.fileExists(atPath: item.url.path))
        #expect(try String(contentsOf: item.url, encoding: .utf8) == "changed after preview")
        #expect(try fixture.auditCodes().last == "changedSincePreview")
    }

    @Test func itemReplacedAfterPreviewIsSkippedEvenWithSameSizeAndDate() throws {
        let fixture = try SnapshotFixture()
        let item = try fixture.makeItem(named: "a.dat", content: "original")
        let snapshots = try fixture.preview([item])
        let originalDate = try #require(
            try FileManager.default.attributesOfItem(atPath: item.url.path)[.modificationDate] as? Date
        )

        let replacement = fixture.cachesURL.appendingPathComponent("replacement.tmp")
        try "REPLACED".write(to: replacement, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: replacement.path)
        _ = try FileManager.default.replaceItemAt(item.url, withItemAt: replacement)

        let result = try fixture.pipeline.execute(
            items: [item],
            allowedRootsByModule: fixture.allowedRootsByModule,
            dryRun: false,
            snapshots: snapshots
        )

        #expect(result.items.isEmpty)
        #expect(result.skipped.count == 1)
        #expect(try String(contentsOf: item.url, encoding: .utf8) == "REPLACED")
    }

    @Test func itemWithOnlyModificationDateChangedIsSkipped() throws {
        let fixture = try SnapshotFixture()
        let item = try fixture.makeItem(named: "a.dat", content: "same size")
        let snapshots = try fixture.preview([item])

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_000)],
            ofItemAtPath: item.url.path
        )
        let result = try fixture.pipeline.execute(
            items: [item],
            allowedRootsByModule: fixture.allowedRootsByModule,
            dryRun: false,
            snapshots: snapshots
        )

        #expect(result.skipped.first?.reason == "modification date changed")
        #expect(FileManager.default.fileExists(atPath: item.url.path))
    }

    @Test func itemRemovedAfterPreviewIsSkippedAndReported() throws {
        let fixture = try SnapshotFixture()
        let item = try fixture.makeItem(named: "a.dat", content: "gone soon")
        let snapshots = try fixture.preview([item])

        try FileManager.default.removeItem(at: item.url)
        let result = try fixture.pipeline.execute(
            items: [item],
            allowedRootsByModule: fixture.allowedRootsByModule,
            dryRun: false,
            snapshots: snapshots
        )

        #expect(result.items.isEmpty)
        #expect(result.skipped.map(\.reason) == ["item no longer exists"])
        #expect(try fixture.auditCodes().last == "itemNotFound")
    }

    @Test func changedItemDoesNotBlockUnchangedItemsInTheSameBatch() throws {
        let fixture = try SnapshotFixture()
        let stable = try fixture.makeItem(named: "stable.dat", content: "stable")
        let moving = try fixture.makeItem(named: "moving.dat", content: "moving")
        let snapshots = try fixture.preview([stable, moving])
        var trashedURL: URL?
        defer {
            if let trashedURL {
                try? FileManager.default.moveItem(at: trashedURL, to: stable.url)
            }
        }

        try "grown by another process".write(to: moving.url, atomically: false, encoding: .utf8)
        let result = try fixture.pipeline.execute(
            items: [stable, moving],
            allowedRootsByModule: fixture.allowedRootsByModule,
            dryRun: false,
            snapshots: snapshots
        )

        trashedURL = result.items.first?.resultingItemURL
        #expect(result.items.map(\.item) == [stable])
        #expect(result.skipped.map(\.item) == [moving])
        #expect(!FileManager.default.fileExists(atPath: stable.url.path))
        #expect(FileManager.default.fileExists(atPath: moving.url.path))
    }

    @Test func itemsWithoutSnapshotKeepExistingBehavior() throws {
        let fixture = try SnapshotFixture()
        let item = try fixture.makeItem(named: "a.dat", content: "legacy")
        var trashedURL: URL?
        defer {
            if let trashedURL {
                try? FileManager.default.moveItem(at: trashedURL, to: item.url)
            }
        }

        let result = try fixture.pipeline.execute(
            items: [item],
            allowedRootsByModule: fixture.allowedRootsByModule,
            dryRun: false
        )

        trashedURL = result.items.first?.resultingItemURL
        #expect(result.items.map(\.item) == [item])
        #expect(result.skipped.isEmpty)
    }
}
