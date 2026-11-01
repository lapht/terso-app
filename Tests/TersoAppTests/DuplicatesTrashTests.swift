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

private final class DuplicatesTrashFixture {
    let rootURL: URL
    let homeURL: URL
    let outsideURL: URL
    let auditLogger: AuditLogger
    private var names: [String] = []

    init() throws {
        rootURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("terso-dup-trash-\(UUID().uuidString)", isDirectory: true)
        homeURL = rootURL.appendingPathComponent("Users/testuser", isDirectory: true)
        outsideURL = rootURL.appendingPathComponent("outside", isDirectory: true)
        for folder in ["Documents", "Pictures", "Downloads"] {
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
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        for name in names {
            try? FileManager.default.removeItem(at: trash.appendingPathComponent(name))
        }
    }

    func folder(_ relativePath: String) -> URL {
        homeURL.appendingPathComponent(relativePath, isDirectory: true)
    }

    /// Writes `content` as a uniquely named file so a trashed copy can be purged from the real Trash.
    @discardableResult
    func write(_ relativeFolder: String, content: Data) throws -> URL {
        let directory = folder(relativeFolder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).bin")
        try content.write(to: url)
        names.append(url.lastPathComponent)
        return url
    }

    @MainActor
    func scanned(roots: [URL]) async throws -> DuplicatesViewModel {
        let viewModel = DuplicatesViewModel(
            homeDirectory: homeURL,
            pipeline: DeletionPipeline(homeDirectory: homeURL, auditLogger: auditLogger)
        )
        viewModel.addRoots(roots)
        viewModel.startScan()
        for _ in 0..<300 where viewModel.phase != .finished {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(viewModel.phase == .finished)
        return viewModel
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    @MainActor
    func copy(_ url: URL, in viewModel: DuplicatesViewModel) -> (group: DuplicateGroupRow, copy: DuplicateCopy)? {
        for group in viewModel.summary.groups {
            let target = url.standardizedFileURL.path
            if let found = group.copies.first(where: { $0.url.standardizedFileURL.path == target }) {
                return (group, found)
            }
        }
        return nil
    }

    @MainActor
    func select(_ urls: [URL], in viewModel: DuplicatesViewModel) throws {
        for url in urls {
            let found = try #require(copy(url, in: viewModel), "\(url.lastPathComponent) is not in a group")
            viewModel.setSelected(true, copy: found.copy, in: found.group)
        }
    }
}

private let payload = Data(repeating: 7, count: 4_096)

struct DuplicatesTrashTests {
    @MainActor
    @Test func nothingIsSelectedAndEveryGroupKeepsAtLeastOneCopy() async throws {
        let fixture = try DuplicatesTrashFixture()
        let urls = try (0..<3).map { _ in try fixture.write("Pictures/a", content: payload) }
        let viewModel = try await fixture.scanned(roots: [fixture.folder("Pictures")])
        #expect(viewModel.selectedIDs.isEmpty && viewModel.selectedCount == 0 && viewModel.selectedBytes == 0)

        let group = try #require(viewModel.summary.groups.first)
        #expect(group.copyCount == 3)
        try fixture.select(Array(urls.prefix(2)), in: viewModel)
        #expect(viewModel.selectedCount == 2)

        let last = try #require(group.copies.first { !viewModel.isSelected($0) })
        #expect(!viewModel.canSelect(last, in: group))
        viewModel.setSelected(true, copy: last, in: group)
        #expect(viewModel.selectedCount == 2 && !viewModel.isSelected(last))

        viewModel.deselectAll()
        #expect(viewModel.selectedCount == 0)
    }

    @MainActor
    @Test func dryRunChangesNothingAndTheMoveForwardsExactlyTheSelectedCopies() async throws {
        let fixture = try DuplicatesTrashFixture()
        let urls = try (0..<3).map { _ in try fixture.write("Pictures/a", content: payload) }
        let other = Data(repeating: 9, count: 4_096)
        let otherURLs = try (0..<2).map { _ in try fixture.write("Pictures/b", content: other) }
        let viewModel = try await fixture.scanned(roots: [fixture.folder("Pictures")])
        let chosen = [urls[0], urls[2], otherURLs[1]]
        try fixture.select(chosen, in: viewModel)
        #expect(viewModel.selectedBytes == 3 * 4_096)

        viewModel.performDryRun()

        #expect(viewModel.report == .dryRun(itemCount: 3, bytes: 3 * 4_096))
        #expect((urls + otherURLs).allSatisfy(fixture.exists))
        let dry = try fixture.auditLogger.readRecords()
        #expect(Set(dry.map(\.originalPath)) == Set(chosen.map { $0.standardizedFileURL.path }))
        #expect(dry.allSatisfy { $0.action == .dryRun && $0.protectedAreaException == nil })

        viewModel.moveSelectedToTrash()

        #expect(viewModel.report == .trashed(itemCount: 3, bytes: 3 * 4_096))
        #expect(chosen.allSatisfy { !fixture.exists($0) })
        #expect(fixture.exists(urls[1]) && fixture.exists(otherURLs[0]))
        let trashed = try fixture.auditLogger.readRecords().filter { $0.action == .trash }
        // /tmp and /private/tmp spell the same folder (and only while the file exists), so compare names.
        #expect(Set(trashed.map { URL(fileURLWithPath: $0.originalPath).lastPathComponent })
            == Set(chosen.map(\.lastPathComponent)))
        #expect(trashed.count == chosen.count)
        #expect(viewModel.rejections.isEmpty && viewModel.selectedIDs.isEmpty)
        // The pair that lost a copy is no longer a duplicate group; the triple lost two of three.
        #expect(viewModel.summary.groups.isEmpty)
    }

    @MainActor
    @Test func movingFromAPickedProtectedFolderNamesItAndLogsTheException() async throws {
        let fixture = try DuplicatesTrashFixture()
        let urls = try (0..<2).map { _ in try fixture.write("Documents/Taxes", content: payload) }
        let viewModel = try await fixture.scanned(roots: [fixture.folder("Documents/Taxes")])
        try fixture.select([urls[1]], in: viewModel)

        #expect(viewModel.protectedFolderNames == ["~/Documents/Taxes"])
        viewModel.moveSelectedToTrash()

        #expect(viewModel.report == .trashed(itemCount: 1, bytes: 4_096))
        #expect(!fixture.exists(urls[1]) && fixture.exists(urls[0]))
        let record = try #require(try fixture.auditLogger.readRecords().first)
        #expect(record.action == .trash && record.protectedAreaException == true)
        #expect(record.moduleId == "files.duplicates")
    }

    @MainActor
    @Test func foldersOutsideProtectedAreasAreNotNamedInTheRecap() async throws {
        let fixture = try DuplicatesTrashFixture()
        let urls = try (0..<2).map { _ in try fixture.write("Pictures/a", content: payload) }
        let viewModel = try await fixture.scanned(roots: [fixture.folder("Pictures")])
        try fixture.select([urls[0]], in: viewModel)

        #expect(viewModel.protectedFolderNames.isEmpty)
    }

    @MainActor
    @Test func pickingTheHomeFolderCannotMoveFilesOutOfAProtectedArea() async throws {
        let fixture = try DuplicatesTrashFixture()
        let urls = try (0..<2).map { _ in try fixture.write("Documents/Taxes", content: payload) }
        let viewModel = try await fixture.scanned(roots: [fixture.homeURL])
        try fixture.select([urls[1]], in: viewModel)

        viewModel.moveSelectedToTrash()

        #expect(urls.allSatisfy(fixture.exists))
        #expect(viewModel.report == .trashed(itemCount: 0, bytes: 0))
        #expect(viewModel.rejections.count >= 2) // the unusable folder and the refused copy
        #expect(viewModel.rejections.contains { $0.message.contains("cannot be used") })
        #expect(try fixture.auditLogger.readRecords().allSatisfy { $0.result == .failure })
    }

    @MainActor
    @Test func aCopyReplacedByASymlinkAfterTheScanIsNeverFollowed() async throws {
        let fixture = try DuplicatesTrashFixture()
        let urls = try (0..<2).map { _ in try fixture.write("Documents/Taxes", content: payload) }
        let secret = fixture.outsideURL.appendingPathComponent("secret.bin")
        try Data("secret".utf8).write(to: secret)
        let viewModel = try await fixture.scanned(roots: [fixture.folder("Documents/Taxes")])
        try fixture.select([urls[1]], in: viewModel)

        try FileManager.default.removeItem(at: urls[1])
        try FileManager.default.createSymbolicLink(at: urls[1], withDestinationURL: secret)
        viewModel.moveSelectedToTrash()

        #expect(fixture.exists(secret) && fixture.exists(urls[0]))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: urls[1].path)) != nil)
        #expect(viewModel.report == .trashed(itemCount: 0, bytes: 0))
        #expect(viewModel.rejections.map(\.path) == [urls[1].standardizedFileURL.path])
    }

    @MainActor
    @Test func aCopyEditedAfterTheScanIsSkippedAndTheRejectionIsVisible() async throws {
        let fixture = try DuplicatesTrashFixture()
        let urls = try (0..<2).map { _ in try fixture.write("Pictures/a", content: payload) }
        let viewModel = try await fixture.scanned(roots: [fixture.folder("Pictures")])
        try fixture.select([urls[1]], in: viewModel)

        try Data("edited since the scan".utf8).write(to: urls[1])
        viewModel.moveSelectedToTrash()

        #expect(urls.allSatisfy(fixture.exists))
        #expect(viewModel.report == .trashed(itemCount: 0, bytes: 0))
        #expect(viewModel.rejections.count == 1)
    }

    @MainActor
    @Test func aNewScanClearsTheSelectionAndTheOutcome() async throws {
        let fixture = try DuplicatesTrashFixture()
        let urls = try (0..<2).map { _ in try fixture.write("Pictures/a", content: payload) }
        let viewModel = try await fixture.scanned(roots: [fixture.folder("Pictures")])
        try fixture.select([urls[0]], in: viewModel)
        viewModel.performDryRun()
        #expect(viewModel.report != nil)

        viewModel.chooseFoldersAgain()

        #expect(viewModel.selectedIDs.isEmpty && viewModel.report == nil && viewModel.rejections.isEmpty)
    }
}
