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
import Darwin
import Foundation
import Testing

private let payload = String(repeating: "x", count: 8192)
private let payloadBytes = Int64(payload.utf8.count)

private final class SharedSpaceFixture {
    let rootURL: URL
    let homeURL: URL
    let cachesURL: URL
    let pipeline: DeletionPipeline

    init() throws {
        rootURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("terso-shared-space-tests-\(UUID().uuidString)", isDirectory: true)
        homeURL = rootURL.appendingPathComponent("Users/testuser", isDirectory: true)
        cachesURL = homeURL.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: cachesURL, withIntermediateDirectories: true)
        pipeline = DeletionPipeline(
            homeDirectory: homeURL,
            auditLogger: AuditLogger(fileURL: rootURL.appendingPathComponent("audit.log"))
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makeFile(named name: String, content: String = payload) throws -> URL {
        let url = cachesURL.appendingPathComponent(name)
        try content.write(to: url, atomically: false, encoding: .utf8)
        return url
    }

    func hardLink(_ url: URL, named name: String) throws -> URL {
        let linkURL = cachesURL.appendingPathComponent(name)
        try #require(link(url.path, linkURL.path) == 0)
        return linkURL
    }

    func clone(_ url: URL, named name: String) throws -> URL {
        let cloneURL = cachesURL.appendingPathComponent(name)
        try #require(clonefile(url.path, cloneURL.path, 0) == 0, "APFS clonefile is required")
        try #require(DuplicateFileReader.cloneIdentifier(of: cloneURL) != nil, "clone must be reported by APFS")
        return cloneURL
    }

    func item(_ url: URL, sizeBytes: Int64 = payloadBytes) -> CleanItem {
        CleanItem(
            url: url,
            resolvedURL: url.resolvingSymlinksInPath(),
            sizeBytes: sizeBytes,
            moduleId: "caches.user",
            ruleId: "caches.user.fixture"
        )
    }

    func dryRun(_ items: [CleanItem]) throws -> DeletionResult {
        try pipeline.execute(items: items, allowedRootsByModule: ["caches.user": [cachesURL]], dryRun: true)
    }
}

struct DeletionPipelineSharedSpaceTests {
    @Test func independentFilesAreSummed() throws {
        let fixture = try SharedSpaceFixture()
        let first = fixture.item(try fixture.makeFile(named: "a.dat", content: payload))
        let secondURL = try fixture.makeFile(named: "b.dat", content: payload + "y")
        let second = fixture.item(secondURL, sizeBytes: payloadBytes + 1)

        let result = try fixture.dryRun([first, second])

        #expect(result.estimatedBytes == payloadBytes * 2 + 1)
        #expect(result.sharedBytes == 0)
    }

    @Test func hardLinksAllSelectedAreCountedOnce() throws {
        let fixture = try SharedSpaceFixture()
        let original = try fixture.makeFile(named: "a.dat")
        let linked = try fixture.hardLink(original, named: "a-link.dat")

        let result = try fixture.dryRun([fixture.item(original), fixture.item(linked)])

        #expect(result.estimatedBytes == payloadBytes)
        #expect(result.sharedBytes == 0)
    }

    @Test func hardLinkWithRemainingLinkOutsideBatchFreesNothing() throws {
        let fixture = try SharedSpaceFixture()
        let original = try fixture.makeFile(named: "a.dat")
        _ = try fixture.hardLink(original, named: "a-link.dat")

        let result = try fixture.dryRun([fixture.item(original)])

        #expect(result.estimatedBytes == 0)
        #expect(result.sharedBytes == payloadBytes)
    }

    @Test func clonesAreReportedAsSharedAndCountedOnce() throws {
        let fixture = try SharedSpaceFixture()
        let original = try fixture.makeFile(named: "a.dat")
        let cloned = try fixture.clone(original, named: "a-clone.dat")

        let result = try fixture.dryRun([fixture.item(original), fixture.item(cloned)])

        #expect(result.estimatedBytes == 0)
        #expect(result.sharedBytes == payloadBytes)
    }

    @Test func singleCloneIsNotPromisedAsFreed() throws {
        let fixture = try SharedSpaceFixture()
        let original = try fixture.makeFile(named: "a.dat")
        let cloned = try fixture.clone(original, named: "a-clone.dat")

        let result = try fixture.dryRun([fixture.item(cloned)])

        #expect(result.estimatedBytes == 0)
        #expect(result.sharedBytes == payloadBytes)
    }

    @Test func plainFilesAreCountedAlongsideSharedOnes() throws {
        let fixture = try SharedSpaceFixture()
        let original = try fixture.makeFile(named: "a.dat")
        let cloned = try fixture.clone(original, named: "a-clone.dat")
        let plain = try fixture.makeFile(named: "plain.dat", content: "plain contents")

        let result = try fixture.dryRun([
            fixture.item(cloned),
            fixture.item(plain, sizeBytes: Int64("plain contents".utf8.count))
        ])

        #expect(result.estimatedBytes == Int64("plain contents".utf8.count))
        #expect(result.sharedBytes == payloadBytes)
    }

    @Test func directoriesUseTheScannedSize() throws {
        let fixture = try SharedSpaceFixture()
        let directory = fixture.cachesURL.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let result = try fixture.dryRun([fixture.item(directory, sizeBytes: 123_456)])

        #expect(result.estimatedBytes == 123_456)
        #expect(result.sharedBytes == 0)
    }
}
