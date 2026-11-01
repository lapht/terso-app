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

private final class HostileFixture {
    let rootURL: URL
    let homeURL: URL
    let cachesURL: URL
    let outsideDirectoryURL: URL
    let pipeline: DeletionPipeline

    init() throws {
        rootURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("terso-hostile-tests-\(UUID().uuidString)", isDirectory: true)
        homeURL = rootURL.appendingPathComponent("Users/testuser", isDirectory: true)
        cachesURL = homeURL.appendingPathComponent("Library/Caches", isDirectory: true)
        outsideDirectoryURL = homeURL.appendingPathComponent("Documents/private", isDirectory: true)
        try FileManager.default.createDirectory(at: cachesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDirectoryURL, withIntermediateDirectories: true)
        pipeline = DeletionPipeline(
            homeDirectory: homeURL,
            auditLogger: AuditLogger(fileURL: rootURL.appendingPathComponent("audit.log"))
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    var outsideFileURL: URL {
        outsideDirectoryURL.appendingPathComponent("file.dat")
    }

    func item(at url: URL) -> CleanItem {
        CleanItem(
            url: url,
            resolvedURL: url.resolvingSymlinksInPath(),
            sizeBytes: 6,
            moduleId: "caches.user",
            ruleId: "caches.user.fixture"
        )
    }

    func run(_ items: [CleanItem], dryRun: Bool, snapshots: [UUID: ItemSnapshot] = [:]) throws -> DeletionResult {
        try pipeline.execute(
            items: items,
            allowedRootsByModule: ["caches.user": [cachesURL]],
            dryRun: dryRun,
            snapshots: snapshots
        )
    }
}

struct DeletionPipelineHostileFilesystemTests {
    @Test func itemBelowSymlinkedParentPointingOutsideTheAllowlistIsRejected() throws {
        let fixture = try HostileFixture()
        try "secret".write(to: fixture.outsideFileURL, atomically: false, encoding: .utf8)
        let linkedParent = fixture.cachesURL.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: fixture.outsideDirectoryURL)
        let item = fixture.item(at: linkedParent.appendingPathComponent("file.dat"))

        #expect(throws: SafetyError.self) {
            try fixture.run([item], dryRun: true)
        }
        #expect(throws: SafetyError.self) {
            try fixture.run([item], dryRun: false)
        }
        #expect(try String(contentsOf: fixture.outsideFileURL, encoding: .utf8) == "secret")
    }

    @Test func parentSwappedForSymlinkAfterPreviewIsRejectedAndNothingIsMoved() throws {
        let fixture = try HostileFixture()
        try "secret".write(to: fixture.outsideFileURL, atomically: false, encoding: .utf8)
        let parent = fixture.cachesURL.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let itemURL = parent.appendingPathComponent("file.dat")
        try "secret".write(to: itemURL, atomically: false, encoding: .utf8)
        let item = fixture.item(at: itemURL)
        let preview = try fixture.run([item], dryRun: true)
        let snapshots = Dictionary(uniqueKeysWithValues: preview.items.compactMap { entry in
            entry.snapshot.map { (entry.item.id, $0) }
        })
        #expect(snapshots.count == 1)

        try FileManager.default.removeItem(at: parent)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: fixture.outsideDirectoryURL)

        #expect(throws: SafetyError.self) {
            try fixture.run([item], dryRun: false, snapshots: snapshots)
        }
        #expect(try String(contentsOf: fixture.outsideFileURL, encoding: .utf8) == "secret")
    }

    @Test func parentSwappedForSymlinkAfterScanIsRejectedEvenWithoutSnapshots() throws {
        let fixture = try HostileFixture()
        try "secret".write(to: fixture.outsideFileURL, atomically: false, encoding: .utf8)
        let parent = fixture.cachesURL.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let itemURL = parent.appendingPathComponent("file.dat")
        try "secret".write(to: itemURL, atomically: false, encoding: .utf8)
        let item = fixture.item(at: itemURL)

        try FileManager.default.removeItem(at: parent)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: fixture.outsideDirectoryURL)

        // Dry-run only: if validation wrongly accepts the item, nothing has been moved yet.
        #expect(throws: SafetyError.self) {
            try fixture.run([item], dryRun: true)
        }
    }

    @Test func itemSwappedForSymlinkToOutsideAfterPreviewIsRejected() throws {
        let fixture = try HostileFixture()
        try "secret".write(to: fixture.outsideFileURL, atomically: false, encoding: .utf8)
        let itemURL = fixture.cachesURL.appendingPathComponent("cache.dat")
        try "secret".write(to: itemURL, atomically: false, encoding: .utf8)
        let item = fixture.item(at: itemURL)
        _ = try fixture.run([item], dryRun: true)

        try FileManager.default.removeItem(at: itemURL)
        try FileManager.default.createSymbolicLink(at: itemURL, withDestinationURL: fixture.outsideFileURL)

        #expect(throws: SafetyError.self) {
            try fixture.run([item], dryRun: false)
        }
        #expect(try String(contentsOf: fixture.outsideFileURL, encoding: .utf8) == "secret")
    }
}
