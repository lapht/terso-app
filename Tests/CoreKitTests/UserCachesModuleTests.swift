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

struct UserCachesModuleTests {
    private struct Fixture {
        let home: URL
        let caches: URL
        let outside: URL
    }

    @Test func excludesRunningApplicationsAndReportsClosedCacheSizes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }

        let runningCache = fixture.caches.appendingPathComponent("com.example.Open", isDirectory: true)
        let closedCache = fixture.caches.appendingPathComponent("com.example.Closed", isDirectory: true)
        let openFile = runningCache.appendingPathComponent("cache.data")
        let closedFile = closedCache.appendingPathComponent("cache.data")
        try createFile(at: openFile, contents: "running cache contents")
        try createFile(at: closedFile, contents: "closed cache contents")

        let module = UserCachesModule {
            ["com.example.Open"]
        }
        let result = try await module.scan(context: ScanContext(homeDirectory: fixture.home))
        let expectedSize = try allocatedSize(of: closedFile)

        #expect(result.map { $0.url.resolvingSymlinksInPath() } == [closedCache.resolvingSymlinksInPath()])
        #expect(result.first?.resolvedURL == closedCache.resolvingSymlinksInPath())
        #expect(result.first?.sizeBytes == expectedSize)
        #expect(result.first?.moduleId == "caches.user")
        #expect(result.first?.ruleId == "caches.user")
        #expect(result.first?.isProtected == false)
    }

    @Test func ignoresSymlinkedCacheDirectoriesOutsideTheAllowlist() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        defer { try? FileManager.default.removeItem(at: fixture.outside) }

        let outsideCache = fixture.outside.appendingPathComponent("com.example.Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideCache, withIntermediateDirectories: true)
        try createFile(at: outsideCache.appendingPathComponent("cache.data"), contents: "outside")
        let linkedCache = fixture.caches.appendingPathComponent("com.example.Linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedCache, withDestinationURL: outsideCache)

        let module = UserCachesModule { [] }
        let result = try await module.scan(context: ScanContext(homeDirectory: fixture.home))

        #expect(result.isEmpty)
    }

    private func makeFixture() throws -> Fixture {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-user-caches-\(UUID().uuidString)", isDirectory: true)
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-user-caches-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        return Fixture(home: home, caches: caches, outside: outside)
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    private func allocatedSize(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey])
        return Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
    }
}
