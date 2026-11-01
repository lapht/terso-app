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

/// A real SF_DATALESS placeholder cannot be created without iCloud, so the file named
/// `placeholder.dat` is reported as dataless through the pipeline's injected inspector.
private final class DatalessFixture {
    let rootURL: URL
    let homeURL: URL
    let cachesURL: URL
    let auditLogURL: URL
    let pipeline: DeletionPipeline

    init() throws {
        rootURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("terso-dataless-tests-\(UUID().uuidString)", isDirectory: true)
        homeURL = rootURL.appendingPathComponent("Users/testuser", isDirectory: true)
        cachesURL = homeURL.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: cachesURL, withIntermediateDirectories: true)
        auditLogURL = rootURL.appendingPathComponent("audit.log")
        pipeline = DeletionPipeline(
            homeDirectory: homeURL,
            auditLogger: AuditLogger(fileURL: auditLogURL),
            inspect: { url in
                guard let real = ItemSnapshot.capture(url) else {
                    return nil
                }
                guard url.lastPathComponent == "placeholder.dat" else {
                    return real
                }
                return ItemSnapshot(
                    device: real.device,
                    inode: real.inode,
                    sizeBytes: real.sizeBytes,
                    modificationSeconds: real.modificationSeconds,
                    modificationNanoseconds: real.modificationNanoseconds,
                    isDirectory: real.isDirectory,
                    isDataless: true
                )
            }
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makeItem(named name: String, content: String) throws -> CleanItem {
        let url = cachesURL.appendingPathComponent(name)
        try content.write(to: url, atomically: false, encoding: .utf8)
        return CleanItem(
            url: url,
            resolvedURL: url.resolvingSymlinksInPath(),
            sizeBytes: Int64(content.utf8.count),
            moduleId: "caches.user",
            ruleId: "caches.user.fixture"
        )
    }

    func run(_ items: [CleanItem], dryRun: Bool) throws -> DeletionResult {
        try pipeline.execute(items: items, allowedRootsByModule: ["caches.user": [cachesURL]], dryRun: dryRun)
    }

    func auditCodes() throws -> [String?] {
        try String(contentsOf: auditLogURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try JSONDecoder().decode(AuditRecord.self, from: Data($0.utf8)).errorCode }
    }
}

struct DatalessSafetyTests {
    @Test func dryRunSkipsPlaceholderAndExcludesItsBytes() throws {
        let fixture = try DatalessFixture()
        let placeholder = try fixture.makeItem(named: "placeholder.dat", content: "cloud only")

        let result = try fixture.run([placeholder], dryRun: true)

        #expect(result.items.isEmpty)
        #expect(result.skipped.map(\.item) == [placeholder])
        #expect(result.estimatedBytes == 0)
        #expect(try fixture.auditCodes() == ["datalessSkipped"])
    }

    @Test func executionNeverMovesPlaceholderAndReportsIt() throws {
        let fixture = try DatalessFixture()
        let placeholder = try fixture.makeItem(named: "placeholder.dat", content: "cloud only")

        let result = try fixture.run([placeholder], dryRun: false)

        #expect(result.items.isEmpty)
        #expect(result.skipped.first?.reason == "not downloaded from iCloud; left untouched")
        #expect(FileManager.default.fileExists(atPath: placeholder.url.path))
        #expect(try fixture.auditCodes() == ["datalessSkipped"])
    }

    @Test func placeholderDoesNotBlockLocalItemsInTheSameBatch() throws {
        let fixture = try DatalessFixture()
        let placeholder = try fixture.makeItem(named: "placeholder.dat", content: "cloud only")
        let local = try fixture.makeItem(named: "local.dat", content: "local")
        var trashedURL: URL?
        defer {
            if let trashedURL {
                try? FileManager.default.moveItem(at: trashedURL, to: local.url)
            }
        }

        let result = try fixture.run([placeholder, local], dryRun: false)

        trashedURL = result.items.first?.resultingItemURL
        #expect(result.items.map(\.item) == [local])
        #expect(result.skipped.map(\.item) == [placeholder])
        #expect(result.estimatedBytes == Int64("local".utf8.count))
        #expect(FileManager.default.fileExists(atPath: placeholder.url.path))
    }

    @Test func hashingRefusesPlaceholderBeforeOpeningIt() {
        let missing = URL(fileURLWithPath: "/tmp/terso-never-created-\(UUID().uuidString)")
        let dataless = DuplicateFileStatus(
            device: 1,
            inode: 1,
            sizeBytes: 10,
            flags: DuplicateFileStatus.datalessFlag,
            isRegularFile: true
        )
        let reader = DuplicateFileReader(readChunkSize: 1024, status: { _ in dataless })

        // open() on the missing path would fail with "open failed"; this message proves it never ran.
        #expect(throws: DuplicateReadError.self) {
            try reader.hash(of: missing, expected: dataless, limit: nil)
        }
        do {
            _ = try reader.hash(of: missing, expected: dataless, limit: nil)
        } catch let error as DuplicateReadError {
            #expect(error.message.contains("not downloaded"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
