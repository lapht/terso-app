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

struct LargeFilesModuleTests {
    private struct Fixture {
        let root: URL
        let home: URL
        let outside: URL
    }

    @Test func discoversOnlyFilesLargerThanConfiguredThresholdAsReadOnly() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let smallFile = fixture.home.appendingPathComponent("small.dat")
        let boundaryFile = fixture.home.appendingPathComponent("boundary.dat")
        let largeFile = fixture.home.appendingPathComponent("large.dat")
        try createFile(at: smallFile, byteCount: 64)
        try createFile(at: boundaryFile, byteCount: 4_096)
        try createFile(at: largeFile, byteCount: 256 * 1_024)
        let threshold = try SizeCalculator().calculate(at: boundaryFile).bytes
        let expectedLargeSize = try SizeCalculator().calculate(at: largeFile).bytes
        #expect(try SizeCalculator().calculate(at: smallFile).bytes <= threshold)
        #expect(expectedLargeSize > threshold)

        let result = try await LargeFilesModule(minimumSizeBytes: threshold).scan(
            context: ScanContext(homeDirectory: fixture.home)
        )

        #expect(result.map(\.url) == [largeFile])
        #expect(result.map(\.resolvedURL) == [largeFile])
        #expect(result.map(\.sizeBytes) == [expectedLargeSize])
        #expect(result.map(\.moduleId) == ["files.large"])
        #expect(result.map(\.ruleId) == ["files.large"])
        #expect(result.allSatisfy { !$0.isDeletable })
        #expect(result.allSatisfy { $0.recommendedAction == .revealInFinder })
    }

    @Test func defaultThresholdIsOneHundredMiB() {
        #expect(LargeFilesModule.defaultMinimumSizeBytes == 100 * 1_024 * 1_024)
    }

    @Test func ignoresSymlinksToFilesOutsideTheHomeDirectory() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let outsideFile = fixture.outside.appendingPathComponent("large.dat")
        try createFile(at: outsideFile, byteCount: 256 * 1_024)
        try FileManager.default.createSymbolicLink(
            at: fixture.home.appendingPathComponent("linked.dat"),
            withDestinationURL: outsideFile
        )

        let result = try await LargeFilesModule(minimumSizeBytes: 0).scan(
            context: ScanContext(homeDirectory: fixture.home)
        )

        #expect(result.isEmpty)
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-large-files-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("Users/test-user", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        return Fixture(root: root, home: home, outside: outside)
    }

    private func createFile(at url: URL, byteCount: Int) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x01, count: byteCount).write(to: url)
    }
}
