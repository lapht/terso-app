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

private final class LeftoversCleanupFixture {
    let rootURL: URL
    let homeURL: URL
    let libraryURL: URL
    let auditLogger: AuditLogger

    init() throws {
        rootURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("terso-leftovers-cleanup-\(UUID().uuidString)", isDirectory: true)
        homeURL = rootURL.appendingPathComponent("Users/testuser", isDirectory: true)
        libraryURL = homeURL.appendingPathComponent("Library", isDirectory: true)
        for folder in ["Library/Caches", "Library/Application Support", "Documents", "Desktop"] {
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

    var pipeline: DeletionPipeline {
        DeletionPipeline(homeDirectory: homeURL, auditLogger: auditLogger)
    }

    var allowedRootsByModule: [String: [URL]] {
        [LeftoversDetector.moduleID: LeftoversDetector.allowedRoots(homeDirectory: homeURL)]
    }

    @discardableResult
    func makeFile(_ relativePath: String, content: String = "leftover") throws -> URL {
        let url = homeURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func candidate(_ url: URL, bundleID: String = "com.example.Gone") -> LeftoverCandidate {
        LeftoverCandidate(
            url: url.standardizedFileURL,
            ruleID: "leftovers.example.gone",
            bundleID: bundleID,
            sizeBytes: Int64(((try? Data(contentsOf: url))?.count) ?? 0)
        )
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

struct LeftoversCleanupTests {
    @Test func candidateBecomesATrashFirstItemOfTheLeftoversModule() throws {
        let fixture = try LeftoversCleanupFixture()
        let url = try fixture.makeFile("Library/Caches/com.example.Gone/cache.dat", content: "12345")

        let item = fixture.candidate(url).cleanItem

        #expect(item.moduleId == "leftovers")
        #expect(item.ruleId == "leftovers.example.gone")
        #expect(item.recommendedAction == .trash)
        #expect(item.sizeBytes == 5)
        #expect(item.isDeletable && !item.isProtected)
        #expect(item.url == url.standardizedFileURL)
    }

    @Test func allowedRootsAreExactlyTheDesignLeftoverRoots() throws {
        let fixture = try LeftoversCleanupFixture()

        let roots = LeftoversDetector.allowedRoots(homeDirectory: fixture.homeURL).map(\.path)

        #expect(roots == RuleValidator.leftoverRoots.map {
            fixture.homeURL.path + "/" + String($0.dropFirst(2))
        })
        #expect(!roots.contains { $0.hasSuffix("/Documents") || $0.hasSuffix("/Desktop") })
    }

    @Test func dryRunSendsExactlyTheSelectedItemsAndChangesNothing() throws {
        let fixture = try LeftoversCleanupFixture()
        let selected = try fixture.makeFile("Library/Caches/com.example.Gone/a.dat", content: "aaaa")
        let alsoSelected = try fixture.makeFile("Library/Application Support/Gone/b.dat", content: "bb")
        let notSelected = try fixture.makeFile("Library/Caches/com.example.Other/c.dat", content: "c")
        let items = [selected, alsoSelected].map { fixture.candidate($0).cleanItem }

        let result = try fixture.pipeline.execute(
            items: items,
            allowedRootsByModule: fixture.allowedRootsByModule,
            dryRun: true
        )

        #expect(result.isDryRun)
        #expect(result.items.map(\.item.url) == items.map(\.url))
        #expect(result.estimatedBytes == 6)
        #expect([selected, alsoSelected, notSelected].allSatisfy(fixture.exists))
        let records = try fixture.auditLogger.readRecords()
        #expect(records.map(\.action) == [.dryRun, .dryRun])
        #expect(records.allSatisfy { $0.moduleId == "leftovers" && $0.result == .success })
    }

    @Test func confirmedCleanupTrashesOnlyTheSelectedItems() throws {
        let fixture = try LeftoversCleanupFixture()
        let selected = try fixture.makeFile("Library/Caches/com.example.Gone/a.dat", content: "aaaa")
        let notSelected = try fixture.makeFile("Library/Caches/com.example.Other/c.dat", content: "c")

        let result = try fixture.pipeline.execute(
            items: [fixture.candidate(selected).cleanItem],
            allowedRootsByModule: fixture.allowedRootsByModule,
            dryRun: false
        )
        defer {
            if let trashed = result.items.first?.resultingItemURL {
                try? FileManager.default.removeItem(at: trashed)
            }
        }

        #expect(!result.isDryRun)
        #expect(!fixture.exists(selected))
        #expect(fixture.exists(notSelected))
        let trashed = try #require(result.items.first?.resultingItemURL)
        #expect(trashed.path.contains(".Trash"))
        #expect(try fixture.auditLogger.readRecords().map(\.action) == [.trash])
    }

    @Test func symlinkPointingOutsideTheRootIsRejectedAndLeftUntouched() throws {
        let fixture = try LeftoversCleanupFixture()
        let secret = try fixture.makeFile("Documents/secret.txt", content: "keep me")
        let link = fixture.homeURL.appendingPathComponent("Library/Caches/com.example.Gone")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret.deletingLastPathComponent())
        let item = fixture.candidate(link).cleanItem

        #expect(throws: SafetyError.self) {
            try fixture.pipeline.execute(
                items: [item],
                allowedRootsByModule: fixture.allowedRootsByModule,
                dryRun: false
            )
        }

        #expect(fixture.exists(secret))
        #expect(fixture.exists(link))
        let record = try #require(fixture.auditLogger.readRecords().last)
        #expect(record.result == .failure)
        #expect(record.errorCode == "symlinkEscape")
    }

    @Test func protectedUserFoldersAreRefusedEvenWhenSubmitted() throws {
        let fixture = try LeftoversCleanupFixture()
        let document = try fixture.makeFile("Documents/report.txt")
        let desktop = try fixture.makeFile("Desktop/notes.txt")

        for url in [document, desktop] {
            #expect(throws: SafetyError.self) {
                try fixture.pipeline.execute(
                    items: [fixture.candidate(url).cleanItem],
                    allowedRootsByModule: fixture.allowedRootsByModule,
                    dryRun: false
                )
            }
            #expect(fixture.exists(url))
        }
        let records = try fixture.auditLogger.readRecords()
        #expect(records.count == 2 && records.allSatisfy { $0.result == .failure && $0.errorCode != nil })
    }

    @Test func installedApplicationBundlesAreRefused() throws {
        let fixture = try LeftoversCleanupFixture()
        let bundle = fixture.homeURL.appendingPathComponent("Applications/Active.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let url = bundle.appendingPathComponent("Info.plist")
        try "plist".write(to: url, atomically: true, encoding: .utf8)

        #expect(throws: SafetyError.self) {
            try fixture.pipeline.execute(
                items: [fixture.candidate(url).cleanItem],
                allowedRootsByModule: fixture.allowedRootsByModule,
                dryRun: false
            )
        }
        #expect(fixture.exists(url))
    }

    @Test func itemsOfAnotherModuleCannotUseTheLeftoverRoots() throws {
        let fixture = try LeftoversCleanupFixture()
        let url = try fixture.makeFile("Library/Caches/com.example.Gone/a.dat")
        let candidate = fixture.candidate(url)
        let foreign = CleanItem(
            url: candidate.url,
            resolvedURL: candidate.url,
            sizeBytes: 1,
            moduleId: "caches.user",
            ruleId: "x"
        )

        #expect(throws: SafetyError.self) {
            try fixture.pipeline.execute(
                items: [foreign],
                allowedRootsByModule: fixture.allowedRootsByModule,
                dryRun: false
            )
        }
        #expect(fixture.exists(url))
    }
}
