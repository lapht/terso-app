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

struct XcodeJunkModuleTests {
    private struct Fixture {
        let root: URL
        let home: URL
        let derivedData: URL
        let archives: URL
        let simulatorCaches: URL
        let outside: URL
    }

    @Test func groupsTargetsAndReportsExactSizesForAllXcodeLocations() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let firstProject = fixture.derivedData.appendingPathComponent("FirstProject-abc", isDirectory: true)
        let secondProject = fixture.derivedData.appendingPathComponent("SecondProject-def", isDirectory: true)
        let oldArchive = fixture.archives
            .appendingPathComponent("2025-01-01/FirstProject.xcarchive", isDirectory: true)
        let recentArchive = fixture.archives
            .appendingPathComponent("2025-02-01/RecentProject.xcarchive", isDirectory: true)
        let simulatorCache = fixture.simulatorCaches.appendingPathComponent("dyld", isDirectory: true)
        let sharedCache = fixture.simulatorCaches.appendingPathComponent("runtime.cache")

        try createFile(
            at: firstProject.appendingPathComponent("Build/Products/App.app/executable"),
            contents: "first project build output"
        )
        try createFile(at: secondProject.appendingPathComponent("index.noindex/records"), contents: "index data")
        try createFile(at: oldArchive.appendingPathComponent("Products/App.app/archive"), contents: "old archive")
        try createFile(
            at: recentArchive.appendingPathComponent("Products/App.app/archive"),
            contents: "recent archive"
        )
        try createFile(at: simulatorCache.appendingPathComponent("dyld_shared_cache"), contents: "dyld cache")
        try createFile(at: sharedCache, contents: "simulator cache")
        try setDates(
            Date(timeIntervalSince1970: now.timeIntervalSince1970 - XcodeJunkModule.minimumArchiveAgeSeconds - 1),
            at: oldArchive
        )
        try setDates(now.addingTimeInterval(-60), at: recentArchive)

        let result = try await XcodeJunkModule(
            isXcodeRunning: { false },
            now: { now }
        ).scan(context: ScanContext(homeDirectory: fixture.home))
        let expectedURLs = [
            firstProject,
            secondProject,
            oldArchive,
            simulatorCache,
            sharedCache
        ].sorted { $0.path < $1.path }
        let expectedSizes = try expectedURLs.map { try SizeCalculator().calculate(at: $0).bytes }

        #expect(result.map { $0.url.pathComponents.suffix(4).joined(separator: "/") } == expectedURLs.map {
            $0.pathComponents.suffix(4).joined(separator: "/")
        })
        #expect(result.map(\.sizeBytes) == expectedSizes)
        #expect(result.map(\.moduleId) == Array(repeating: "xcode.junk", count: expectedURLs.count))
        #expect(result.map(\.ruleId) == expectedURLs.map { url in
            if url.path.hasPrefix(fixture.derivedData.path + "/") {
                return "xcode.derived-data"
            }
            if url.path.hasPrefix(fixture.archives.path + "/") {
                return "xcode.old-archives"
            }
            return "xcode.simulator-caches"
        })
    }

    @Test func excludesDerivedDataWhileXcodeIsRunningButScansOtherCaches() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let project = fixture.derivedData.appendingPathComponent("RunningProject-build", isDirectory: true)
        let simulatorCache = fixture.simulatorCaches.appendingPathComponent("dyld", isDirectory: true)
        try createFile(at: project.appendingPathComponent("build.data"), contents: "active build")
        try createFile(at: simulatorCache.appendingPathComponent("cache.data"), contents: "simulator cache")

        let result = try await XcodeJunkModule(
            isXcodeRunning: { true },
            now: Date.init
        ).scan(context: ScanContext(homeDirectory: fixture.home))

        #expect(result.map { $0.url.pathComponents.suffix(4).joined(separator: "/") } == [
            simulatorCache.pathComponents.suffix(4).joined(separator: "/")
        ])
    }

    @Test func ignoresSymlinksEscapingEachAllowlistedRoot() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let outsideProject = fixture.outside.appendingPathComponent("OutsideProject", isDirectory: true)
        let outsideArchive = fixture.outside
            .appendingPathComponent("Outside.xcarchive", isDirectory: true)
        let outsideCache = fixture.outside.appendingPathComponent("OutsideCache", isDirectory: true)
        try createFile(at: outsideProject.appendingPathComponent("build.data"), contents: "outside")
        try createFile(at: outsideArchive.appendingPathComponent("archive.data"), contents: "outside")
        try createFile(at: outsideCache.appendingPathComponent("cache.data"), contents: "outside")
        try FileManager.default.createDirectory(
            at: fixture.archives.appendingPathComponent("2025-01-01", isDirectory: true),
            withIntermediateDirectories: true
        )

        try FileManager.default.createSymbolicLink(
            at: fixture.derivedData.appendingPathComponent("linked-project", isDirectory: true),
            withDestinationURL: outsideProject
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.archives.appendingPathComponent("2025-01-01/Linked.xcarchive", isDirectory: true),
            withDestinationURL: outsideArchive
        )
        try FileManager.default.removeItem(at: fixture.simulatorCaches)
        try FileManager.default.createSymbolicLink(
            at: fixture.simulatorCaches,
            withDestinationURL: outsideCache
        )

        let result = try await XcodeJunkModule(
            isXcodeRunning: { false },
            now: Date.init
        ).scan(context: ScanContext(homeDirectory: fixture.home))

        #expect(result.isEmpty)
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-xcode-junk-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("Users/test-user", isDirectory: true)
        let developer = home.appendingPathComponent("Library/Developer", isDirectory: true)
        let derivedData = developer.appendingPathComponent("Xcode/DerivedData", isDirectory: true)
        let archives = developer.appendingPathComponent("Xcode/Archives", isDirectory: true)
        let simulatorCaches = developer.appendingPathComponent("CoreSimulator/Caches", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        for directory in [derivedData, archives, simulatorCaches, outside] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return Fixture(
            root: root,
            home: home,
            derivedData: derivedData,
            archives: archives,
            simulatorCaches: simulatorCaches,
            outside: outside
        )
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    private func setDates(_ date: Date, at url: URL) throws {
        try FileManager.default.setAttributes(
            [.creationDate: date, .modificationDate: date],
            ofItemAtPath: url.path
        )
    }
}
