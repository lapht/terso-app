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

private final class LeftoversReviewFixture {
    let rootURL: URL
    let homeURL: URL
    let auditLogger: AuditLogger

    init() throws {
        rootURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("terso-leftovers-vm-\(UUID().uuidString)", isDirectory: true)
        homeURL = rootURL.appendingPathComponent("Users/testuser", isDirectory: true)
        for folder in ["Library/Caches", "Library/Application Support", "Documents"] {
            try FileManager.default.createDirectory(
                at: homeURL.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        auditLogger = AuditLogger(fileURL: rootURL.appendingPathComponent("audit.log"))
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    @MainActor
    func makeViewModel() -> LeftoversViewModel {
        LeftoversViewModel(
            homeDirectory: homeURL,
            pipeline: DeletionPipeline(homeDirectory: homeURL, auditLogger: auditLogger)
        )
    }

    func item(_ relativePath: String, content: String = "leftover") throws -> CleanItem {
        let url = homeURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return LeftoverCandidate(
            url: url,
            ruleID: "leftovers.example.gone",
            bundleID: "com.example.Gone",
            sizeBytes: Int64(content.utf8.count)
        ).cleanItem
    }

    func exists(_ item: CleanItem) -> Bool {
        FileManager.default.fileExists(atPath: item.url.path)
    }
}

struct LeftoversViewModelTests {
    @MainActor
    @Test func nothingIsSelectedByDefaultAndTotalsFollowTheSelection() throws {
        let fixture = try LeftoversReviewFixture()
        let first = try fixture.item("Library/Caches/com.example.Gone/a.dat", content: "aaaa")
        let second = try fixture.item("Library/Caches/com.example.Gone/b.dat", content: "bb")
        let viewModel = fixture.makeViewModel()

        viewModel.load(items: [first, second], reasons: [first.id: "Rule x matches y"])

        #expect(viewModel.selectedItems.isEmpty)
        #expect(viewModel.selectedBytes == 0)
        viewModel.setSelected(true, for: second)
        #expect(viewModel.selectedItems == [second])
        #expect(viewModel.selectedBytes == 2)
        viewModel.setSelected(true, for: first)
        #expect(viewModel.selectedItems.count == 2 && viewModel.selectedBytes == 6)
        viewModel.deselectAll()
        #expect(viewModel.selectedItems.isEmpty)
    }

    @MainActor
    @Test func dryRunReportsBytesOfTheSelectionOnlyAndChangesNothing() throws {
        let fixture = try LeftoversReviewFixture()
        let selected = try fixture.item("Library/Caches/com.example.Gone/a.dat", content: "aaaa")
        let other = try fixture.item("Library/Caches/com.example.Gone/b.dat", content: "bb")
        let viewModel = fixture.makeViewModel()
        viewModel.load(items: [selected, other])
        viewModel.setSelected(true, for: selected)

        viewModel.performDryRun()

        #expect(viewModel.report == .dryRun(itemCount: 1, bytes: 4))
        #expect(viewModel.items.count == 2)
        #expect(fixture.exists(selected) && fixture.exists(other))
        let records = try fixture.auditLogger.readRecords()
        #expect(records.map(\.action) == [.dryRun])
        #expect(records.first?.originalPath == selected.url.standardizedFileURL.path)
    }

    @MainActor
    @Test func moveToTrashSendsExactlyTheSelectedItemsToThePipeline() throws {
        let fixture = try LeftoversReviewFixture()
        let selected = try fixture.item("Library/Caches/com.example.Gone/a.dat", content: "aaaa")
        let kept = try fixture.item("Library/Caches/com.example.Gone/b.dat", content: "bb")
        let viewModel = fixture.makeViewModel()
        viewModel.load(items: [selected, kept])
        viewModel.setSelected(true, for: selected)

        viewModel.moveSelectedToTrash()
        defer {
            for record in (try? fixture.auditLogger.readRecords()) ?? [] where record.action == .trash {
                // Trashed fixture files are removed from the real Trash.
                let name = URL(fileURLWithPath: record.originalPath).lastPathComponent
                try? FileManager.default.removeItem(
                    at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash/\(name)")
                )
            }
        }

        #expect(viewModel.report == .trashed(itemCount: 1, bytes: 4))
        #expect(viewModel.items == [kept])
        #expect(!fixture.exists(selected) && fixture.exists(kept))
        #expect(viewModel.rejections.isEmpty)
        #expect(try fixture.auditLogger.readRecords().map(\.action) == [.trash])
    }

    @MainActor
    @Test func refusalsAreVisibleLoggedAndDoNotBlockTheOtherItems() throws {
        let fixture = try LeftoversReviewFixture()
        let secret = fixture.homeURL.appendingPathComponent("Documents/secret.txt")
        try "keep me".write(to: secret, atomically: true, encoding: .utf8)
        let link = fixture.homeURL.appendingPathComponent("Library/Caches/com.example.Evil")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret.deletingLastPathComponent())
        let attack = LeftoverCandidate(url: link, ruleID: "leftovers.evil", bundleID: "com.example.Evil", sizeBytes: 7)
            .cleanItem
        let protected = try fixture.item("Documents/report.txt")
        let good = try fixture.item("Library/Caches/com.example.Gone/a.dat", content: "aaaa")
        let viewModel = fixture.makeViewModel()
        viewModel.load(items: [attack, protected, good])
        [attack, protected, good].forEach { viewModel.setSelected(true, for: $0) }

        viewModel.moveSelectedToTrash()
        defer {
            try? FileManager.default.removeItem(
                at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash/a.dat")
            )
        }

        #expect(viewModel.rejections.map(\.path)
            == [link.standardizedFileURL.path, protected.url.standardizedFileURL.path])
        #expect(viewModel.rejections.allSatisfy { !$0.message.isEmpty })
        #expect(viewModel.report == .trashed(itemCount: 1, bytes: 4))
        #expect(Set(viewModel.items.map(\.id)) == [attack.id, protected.id])
        #expect(FileManager.default.fileExists(atPath: secret.path) && fixture.exists(protected))
        let records = try fixture.auditLogger.readRecords()
        #expect(records.filter { $0.result == .failure }.compactMap(\.errorCode).sorted()
            == ["protectedPath", "symlinkEscape"])
    }
}
