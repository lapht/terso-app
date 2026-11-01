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

private final class LargeFilesTrashFixture {
    let rootURL: URL
    let homeURL: URL
    let outsideURL: URL
    let auditLogger: AuditLogger

    init() throws {
        rootURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("terso-large-trash-\(UUID().uuidString)", isDirectory: true)
        homeURL = rootURL.appendingPathComponent("Users/testuser", isDirectory: true)
        outsideURL = rootURL.appendingPathComponent("outside", isDirectory: true)
        for folder in ["Movies", "Documents"] {
            try FileManager.default.createDirectory(
                at: homeURL.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        auditLogger = AuditLogger(fileURL: rootURL.appendingPathComponent("audit.log"))
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    @MainActor
    func makeViewModel() -> LargeFilesViewModel {
        LargeFilesViewModel(
            homeDirectory: homeURL,
            pipeline: DeletionPipeline(homeDirectory: homeURL, auditLogger: auditLogger)
        )
    }

    /// An item shaped like the ones `LargeFilesModule` returns for a regular file.
    func item(_ relativePath: String, content: String = "large") throws -> CleanItem {
        let url = homeURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return CleanItem(
            url: url,
            resolvedURL: url,
            sizeBytes: Int64(content.utf8.count),
            moduleId: LargeFilesModule.moduleID,
            ruleId: LargeFilesModule.moduleID
        )
    }

    func exists(_ item: CleanItem) -> Bool {
        FileManager.default.fileExists(atPath: item.url.path)
    }

    /// Trashed fixture files are removed from the real Trash.
    func purgeTrash(named names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(
                at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash/\(name)")
            )
        }
    }
}

struct LargeFilesTrashTests {
    @MainActor
    @Test func nothingIsPreselectedAndTheExactSelectionReachesSafety() throws {
        let fixture = try LargeFilesTrashFixture()
        let chosen = try fixture.item("Movies/\(UUID().uuidString)-a.mov", content: "aaaa")
        let other = try fixture.item("Movies/\(UUID().uuidString)-b.mov", content: "bb")
        let viewModel = fixture.makeViewModel()
        viewModel.review.load(items: [chosen, other])
        #expect(viewModel.review.selectedItems.isEmpty)

        viewModel.review.setSelected(true, for: chosen)
        viewModel.review.performDryRun()

        #expect(viewModel.review.report == .dryRun(itemCount: 1, bytes: 4))
        #expect(fixture.exists(chosen) && fixture.exists(other))
        #expect(try fixture.auditLogger.readRecords().map(\.originalPath) == [chosen.url.standardizedFileURL.path])

        viewModel.review.moveSelectedToTrash()
        defer { fixture.purgeTrash(named: [chosen.url.lastPathComponent]) }

        #expect(viewModel.review.report == .trashed(itemCount: 1, bytes: 4))
        #expect(!fixture.exists(chosen) && fixture.exists(other))
        let trashed = try fixture.auditLogger.readRecords().filter { $0.action == .trash }
        #expect(trashed.map(\.originalPath) == [chosen.url.standardizedFileURL.path])
    }

    @MainActor
    @Test func protectedPathAndSymlinkOutsideTheRootAreRefusedAndVisible() throws {
        let fixture = try LargeFilesTrashFixture()
        let protected = try fixture.item("Documents/report.pdf")
        let secret = fixture.outsideURL.appendingPathComponent("secret.dat")
        try "keep me".write(to: secret, atomically: true, encoding: .utf8)
        let link = fixture.homeURL.appendingPathComponent("Movies/link.mov")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)
        let attack = CleanItem(
            url: link,
            resolvedURL: link,
            sizeBytes: 7,
            moduleId: LargeFilesModule.moduleID,
            ruleId: LargeFilesModule.moduleID
        )
        let viewModel = fixture.makeViewModel()
        viewModel.review.load(items: [protected, attack])
        [protected, attack].forEach { viewModel.review.setSelected(true, for: $0) }

        viewModel.review.moveSelectedToTrash()

        #expect(viewModel.review.rejections.map(\.path)
            == [protected.url.standardizedFileURL.path, link.standardizedFileURL.path])
        #expect(viewModel.review.rejections.allSatisfy { !$0.message.isEmpty })
        #expect(viewModel.review.report == .trashed(itemCount: 0, bytes: 0))
        #expect(fixture.exists(protected) && FileManager.default.fileExists(atPath: secret.path))
        let codes = try fixture.auditLogger.readRecords().filter { $0.result == .failure }.compactMap(\.errorCode)
        #expect(codes.sorted() == ["protectedPath", "symlinkEscape"])
    }

    @MainActor
    @Test func aFileChangedAfterThePreviewIsSkippedAndNotMoved() throws {
        let fixture = try LargeFilesTrashFixture()
        let file = try fixture.item("Movies/\(UUID().uuidString)-c.mov", content: "before")
        let viewModel = fixture.makeViewModel()
        viewModel.review.load(items: [file])
        viewModel.review.setSelected(true, for: file)
        viewModel.review.performDryRun()

        try "after the preview, larger".write(to: file.url, atomically: true, encoding: .utf8)
        viewModel.review.moveSelectedToTrash()

        #expect(fixture.exists(file))
        #expect(viewModel.review.report == .trashed(itemCount: 0, bytes: 0))
        #expect(viewModel.review.rejections.map(\.path) == [file.url.standardizedFileURL.path])
        #expect(viewModel.review.items == [file])
    }

    @MainActor
    @Test func revealOnlyItemsCannotBeSelected() throws {
        let fixture = try LargeFilesTrashFixture()
        let url = fixture.homeURL.appendingPathComponent("Pictures/Photos.photoslibrary/original.heic")
        let inPackage = CleanItem(
            url: url,
            resolvedURL: url,
            sizeBytes: 10,
            moduleId: LargeFilesModule.moduleID,
            ruleId: LargeFilesModule.moduleID,
            isDeletable: false,
            recommendedAction: .revealInFinder
        )
        let viewModel = fixture.makeViewModel()
        viewModel.review.load(items: [inPackage])

        viewModel.review.setSelected(true, for: inPackage)

        #expect(viewModel.review.selectedItems.isEmpty)
    }
}
