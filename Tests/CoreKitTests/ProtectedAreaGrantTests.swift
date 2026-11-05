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

/// Fixtures for the protected-area exception (design.md §11.7, #40): a fake home with
/// Documents/Downloads/Pictures and a folder outside the home for symlink attacks.
private final class GrantFixture {
    let rootURL: URL
    let homeURL: URL
    let outsideURL: URL
    let auditURL: URL
    let pipeline: DeletionPipeline
    private(set) var trashedNames: [String] = []

    init() throws {
        rootURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("terso-grant-tests-\(UUID().uuidString)", isDirectory: true)
        homeURL = rootURL.appendingPathComponent("Users/testuser", isDirectory: true)
        outsideURL = rootURL.appendingPathComponent("outside", isDirectory: true)
        auditURL = rootURL.appendingPathComponent("audit.log")
        for folder in ["Documents", "Downloads", "Pictures", "Desktop"] {
            try FileManager.default.createDirectory(
                at: homeURL.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        pipeline = DeletionPipeline(homeDirectory: homeURL, auditLogger: AuditLogger(fileURL: auditURL))
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        for name in trashedNames {
            try? FileManager.default.removeItem(at: trash.appendingPathComponent(name))
        }
    }

    var documentsURL: URL { homeURL.appendingPathComponent("Documents", isDirectory: true) }

    func grant(_ relativeFolder: String) throws -> ProtectedAreaGrant {
        try ProtectedAreaGrant(
            folder: homeURL.appendingPathComponent(relativeFolder, isDirectory: true),
            homeDirectory: homeURL
        )
    }

    /// A unique-named file so a trashed copy can be purged from the real Trash afterwards.
    @discardableResult
    func file(_ folder: String, content: String = "dup!") throws -> URL {
        let directory = homeURL.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).dat")
        try content.write(to: url, atomically: true, encoding: .utf8)
        trashedNames.append(url.lastPathComponent)
        return url
    }

    func item(_ url: URL, module: String = ProtectedAreaGrant.duplicatesModuleID) -> CleanItem {
        CleanItem(
            url: url,
            resolvedURL: url.resolvingSymlinksInPath().standardizedFileURL,
            sizeBytes: 4,
            moduleId: module,
            ruleId: module
        )
    }

    @discardableResult
    func run(
        _ item: CleanItem,
        roots: [URL],
        grants: [ProtectedAreaGrant],
        dryRun: Bool = false
    ) throws -> DeletionResult {
        try pipeline.execute(
            items: [item],
            allowedRootsByModule: [item.moduleId: roots],
            dryRun: dryRun,
            protectedAreaGrants: grants
        )
    }

    func records() throws -> [AuditRecord] {
        try AuditLogger(fileURL: auditURL).readRecords()
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

struct ProtectedAreaGrantTests {
    // MARK: - Picking a folder

    @Test func acceptsAProtectedRootAndAFolderBelowIt() throws {
        let fixture = try GrantFixture()
        _ = try fixture.file("Documents/sub")

        #expect(try fixture.grant("Documents").folder.lastPathComponent == "Documents")
        #expect(try fixture.grant("Documents/sub").folder.lastPathComponent == "sub")
    }

    @Test func rejectsTheHomeDirectoryItsParentsAndSystemPaths() throws {
        let fixture = try GrantFixture()
        for folder in [fixture.homeURL, fixture.homeURL.deletingLastPathComponent(), URL(fileURLWithPath: "/"),
                       URL(fileURLWithPath: "/System/Library"), URL(fileURLWithPath: "/Applications")] {
            #expect(throws: SafetyError.self, "\(folder.path)") {
                _ = try ProtectedAreaGrant(folder: folder, homeDirectory: fixture.homeURL)
            }
        }
    }

    @Test func rejectsMissingFoldersFilesTraversalAndSymlinks() throws {
        let fixture = try GrantFixture()
        let file = try fixture.file("Documents")
        let link = fixture.homeURL.appendingPathComponent("Documents/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.outsideURL)
        let traversal = URL(fileURLWithPath: fixture.documentsURL.path + "/../Downloads")

        for folder in [fixture.documentsURL.appendingPathComponent("nope"), file, link, traversal] {
            #expect(throws: SafetyError.self, "\(folder.path)") {
                _ = try ProtectedAreaGrant(folder: folder, homeDirectory: fixture.homeURL)
            }
        }
    }

    // MARK: - PathValidator

    @Test func aGrantLiftsTheDenialOnlyBelowThePickedFolder() throws {
        let fixture = try GrantFixture()
        _ = try fixture.file("Documents/sub")
        let grant = try fixture.grant("Documents/sub")
        let validator = PathValidator(homeDirectory: fixture.homeURL)
        let roots = [fixture.homeURL]
        let inside = fixture.documentsURL.appendingPathComponent("sub/a/b.dat")

        try validator.validate(path: inside, allowedRoots: roots, protectedAreaGrants: [grant])

        let denied = [
            inside, // no grant
            fixture.documentsURL.appendingPathComponent("other/b.dat"), // sibling of the picked folder
            fixture.documentsURL.appendingPathComponent("sub"), // the picked folder itself
            fixture.documentsURL, // the protected root
            fixture.homeURL.appendingPathComponent("Downloads/b.dat") // another protected area
        ]
        for url in denied {
            let grants = url == inside ? [] : [grant]
            #expect(throws: SafetyError.self, "\(url.path)") {
                try validator.validate(path: url, allowedRoots: roots, protectedAreaGrants: grants)
            }
        }
    }

    @Test func aGrantNeverLiftsSystemPathsOrBundles() throws {
        let fixture = try GrantFixture()
        let grant = try fixture.grant("Documents")
        let validator = PathValidator(homeDirectory: fixture.homeURL)

        for path in ["/System/Library/x", "/private/var/db/x", fixture.documentsURL.path + "/Thing.app"] {
            #expect(throws: SafetyError.self, "\(path)") {
                try validator.validate(
                    path: URL(fileURLWithPath: path),
                    allowedRoots: [URL(fileURLWithPath: "/"), fixture.homeURL],
                    protectedAreaGrants: [grant]
                )
            }
        }
    }

    // MARK: - Pipeline

    @Test func movesAFileOutOfDocumentsThroughTheGrantAndLogsTheException() throws {
        let fixture = try GrantFixture()
        let grant = try fixture.grant("Documents")
        let url = try fixture.file("Documents/photos")
        let item = fixture.item(url)

        let dry = try fixture.run(item, roots: [grant.folder], grants: [grant], dryRun: true)
        #expect(dry.isDryRun && dry.items.count == 1 && fixture.exists(url))

        let result = try fixture.run(item, roots: [grant.folder], grants: [grant])
        #expect(result.items.count == 1)
        #expect(!fixture.exists(url))
        let records = try fixture.records()
        #expect(records.map(\.action) == [.trash, .dryRun]) // newest first
        #expect(records.allSatisfy { $0.protectedAreaException == true && $0.moduleId == "files.duplicates" })
    }

    @Test func aFileOutsideProtectedAreasNeedsNoExceptionAndIsNotMarked() throws {
        let fixture = try GrantFixture()
        let grant = try fixture.grant("Pictures")
        let url = try fixture.file("Pictures/album")

        _ = try fixture.run(fixture.item(url), roots: [grant.folder], grants: [grant])

        #expect(!fixture.exists(url))
        #expect(try fixture.records().allSatisfy { $0.protectedAreaException == nil })
    }

    @Test func withoutAGrantTheProtectedAreaStaysDenied() throws {
        let fixture = try GrantFixture()
        let url = try fixture.file("Documents/photos")

        #expect(throws: SafetyError.self) {
            try fixture.run(fixture.item(url), roots: [fixture.documentsURL], grants: [])
        }
        #expect(fixture.exists(url))
        #expect(try fixture.records().map(\.result) == [.failure])
    }

    @Test func otherModulesCannotUseAGrant() throws {
        let fixture = try GrantFixture()
        let grant = try fixture.grant("Documents")
        let url = try fixture.file("Documents/photos")

        #expect(throws: SafetyError.self) {
            try fixture.run(fixture.item(url, module: "files.large"), roots: [grant.folder], grants: [grant])
        }
        #expect(fixture.exists(url))
    }

    @Test func aFileOutsideThePickedFolderIsRefusedEvenInAnotherProtectedArea() throws {
        let fixture = try GrantFixture()
        let grant = try fixture.grant("Documents")
        let url = try fixture.file("Downloads/photos")

        #expect(throws: SafetyError.self) {
            try fixture.run(fixture.item(url), roots: [grant.folder, fixture.homeURL], grants: [grant])
        }
        #expect(fixture.exists(url))
    }

    @Test func theGrantFolderIsNeverAnAllowlistRootByItself() throws {
        let fixture = try GrantFixture()
        let grant = try fixture.grant("Documents")
        let url = try fixture.file("Documents/photos")

        // The module allowlist (invariant 1) is separate from the grant and still required.
        #expect(throws: SafetyError.self) {
            let pictures = fixture.homeURL.appendingPathComponent("Pictures")
            try fixture.run(fixture.item(url), roots: [pictures], grants: [grant])
        }
        #expect(fixture.exists(url))
    }

    @Test func directoriesAndPackagesNeverLeaveAProtectedFolder() throws {
        let fixture = try GrantFixture()
        let grant = try fixture.grant("Documents")
        let directory = fixture.documentsURL.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let inApp = try fixture.file("Documents/Thing.app/Contents")
        let inLibrary = try fixture.file("Documents/Pics.photoslibrary/originals")
        let inPages = try fixture.file("Documents/Report.pages")

        for url in [directory, inApp, inLibrary, inPages] {
            #expect(throws: SafetyError.self, "\(url.path)") {
                try fixture.run(fixture.item(url), roots: [grant.folder], grants: [grant])
            }
            #expect(fixture.exists(url))
        }
    }

    @Test func aSymlinkToAnOutsideFileIsNeverFollowedOrMoved() throws {
        let fixture = try GrantFixture()
        let grant = try fixture.grant("Documents")
        let secret = fixture.outsideURL.appendingPathComponent("secret.dat")
        try "secret".write(to: secret, atomically: true, encoding: .utf8)
        let link = fixture.documentsURL.appendingPathComponent("\(UUID().uuidString)-link.dat")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)

        #expect(throws: SafetyError.self) {
            try fixture.run(fixture.item(link), roots: [grant.folder], grants: [grant])
        }
        #expect(fixture.exists(secret) && fixture.exists(link))
    }

    @Test func aSymlinkToAFileInsideTheFolderIsStillNotMoved() throws {
        let fixture = try GrantFixture()
        let grant = try fixture.grant("Documents")
        let real = try fixture.file("Documents/real")
        let link = fixture.documentsURL.appendingPathComponent("\(UUID().uuidString)-link.dat")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(throws: SafetyError.self) {
            try fixture.run(fixture.item(link), roots: [grant.folder], grants: [grant])
        }
        #expect(fixture.exists(real) && fixture.exists(link))
    }

    @Test func aParentSwappedForASymlinkAfterThePreviewIsRefused() throws {
        let fixture = try GrantFixture()
        let grant = try fixture.grant("Documents")
        let url = try fixture.file("Documents/album")
        let item = fixture.item(url)
        let parent = url.deletingLastPathComponent()
        let hidden = fixture.outsideURL.appendingPathComponent(url.lastPathComponent)

        _ = try fixture.run(item, roots: [grant.folder], grants: [grant], dryRun: true)
        try FileManager.default.moveItem(at: url, to: hidden)
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: fixture.outsideURL)

        #expect(throws: SafetyError.self) {
            try fixture.run(item, roots: [grant.folder], grants: [grant])
        }
        #expect(fixture.exists(hidden))
    }
}
