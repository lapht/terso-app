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

struct PackageCachesModuleTests {
    private struct Fixture {
        let root: URL
        let home: URL
        let outside: URL
    }

    @Test func discoversOnlyAllowlistedPackageCachesAndPreservesConfiguration() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let expectedCaches = [
            fixture.home.appendingPathComponent("Library/Caches/Homebrew", isDirectory: true),
            fixture.home.appendingPathComponent(".npm/_cacache", isDirectory: true),
            fixture.home.appendingPathComponent("Library/Caches/Yarn", isDirectory: true),
            fixture.home.appendingPathComponent(".cache/yarn", isDirectory: true),
            fixture.home.appendingPathComponent("Library/Caches/pnpm", isDirectory: true)
        ]
        for (index, cache) in expectedCaches.enumerated() {
            try createFile(at: cache.appendingPathComponent("content.data"), contents: "cache \(index)")
        }

        let configurationFiles = [
            fixture.home.appendingPathComponent(".npmrc"),
            fixture.home.appendingPathComponent("package-lock.json"),
            fixture.home.appendingPathComponent("yarn.lock"),
            fixture.home.appendingPathComponent("pnpm-workspace.yaml"),
            fixture.home.appendingPathComponent("Library/Homebrew/Formula/local.rb"),
            fixture.home.appendingPathComponent("Library/Caches/OtherPackageManager/cache.data")
        ]
        for file in configurationFiles {
            try createFile(at: file, contents: "configuration and local formula data")
        }
        let originalConfigurations = try configurationFiles.map { try Data(contentsOf: $0) }

        let result = try await PackageCachesModule().scan(
            context: ScanContext(homeDirectory: fixture.home)
        )

        let sortedCaches = expectedCaches.sorted { $0.path < $1.path }
        let expectedSizes = try sortedCaches.map { try SizeCalculator().calculate(at: $0).bytes }
        #expect(result.map(\.url.path) == sortedCaches.map(\.path))
        #expect(result.map(\.resolvedURL.path) == sortedCaches.map(\.path))
        #expect(result.map(\.sizeBytes) == expectedSizes)
        #expect(result.map(\.moduleId) == Array(repeating: "caches.packages", count: sortedCaches.count))
        #expect(result.map(\.ruleId) == sortedCaches.map { cache in
            if cache.path.hasSuffix("/Homebrew") {
                return "packages.homebrew"
            }
            if cache.path.hasSuffix("/_cacache") {
                return "packages.npm"
            }
            if cache.path.hasSuffix("/Yarn") || cache.path.hasSuffix("/yarn") {
                return "packages.yarn"
            }
            return "packages.pnpm"
        })
        #expect(try configurationFiles.map { try Data(contentsOf: $0) } == originalConfigurations)
    }

    @Test func ignoresCacheSymlinksThatEscapeTheirAllowlistedLocations() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let homebrewParent = fixture.home.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: homebrewParent, withIntermediateDirectories: true)
        let outsideHomebrew = fixture.outside.appendingPathComponent("Homebrew", isDirectory: true)
        try createFile(at: outsideHomebrew.appendingPathComponent("cache.data"), contents: "outside")
        try FileManager.default.createSymbolicLink(
            at: homebrewParent.appendingPathComponent("Homebrew", isDirectory: true),
            withDestinationURL: outsideHomebrew
        )

        let outsideYarnRoot = fixture.outside.appendingPathComponent("linked-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideYarnRoot, withIntermediateDirectories: true)
        try createFile(at: outsideYarnRoot.appendingPathComponent("cache.data"), contents: "outside")
        try FileManager.default.createSymbolicLink(
            at: fixture.home.appendingPathComponent(".cache", isDirectory: true),
            withDestinationURL: fixture.outside
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.outside.appendingPathComponent("yarn", isDirectory: true),
            withDestinationURL: outsideYarnRoot
        )

        let result = try await PackageCachesModule().scan(
            context: ScanContext(homeDirectory: fixture.home)
        )

        #expect(result.isEmpty)
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-package-caches-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("Users/test-user", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        return Fixture(root: root, home: home, outside: outside)
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }
}
