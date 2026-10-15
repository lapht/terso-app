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

struct TrashBinsModuleTests {
    private struct Fixture {
        let root: URL
        let home: URL
        let homeTrash: URL
        let externalVolume: URL
        let externalTrash: URL
        let outside: URL
    }

    @Test func scansHomeAndMountedVolumeTrashWithExactItemsAndSizes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let homeFile = fixture.homeTrash.appendingPathComponent("home-file.txt")
        let homeDirectory = fixture.homeTrash.appendingPathComponent("home-folder", isDirectory: true)
        let nestedFile = homeDirectory.appendingPathComponent("nested.txt")
        let externalFile = fixture.externalTrash.appendingPathComponent("external-file.txt")
        try createFile(at: homeFile, contents: "home trash")
        try createFile(at: nestedFile, contents: "nested trash data")
        try createFile(at: externalFile, contents: "external trash")

        let context = ScanContext(
            homeDirectory: fixture.home,
            mountedVolumes: [VolumeInfo(
                mountPath: fixture.externalVolume,
                filesystemType: "apfs",
                isReadOnly: false,
                uuid: nil
            )]
        )
        let result = try await TrashBinsModule(userID: "501").scan(context: context)
        let expectedURLs = [homeFile, homeDirectory, externalFile].sorted { $0.path < $1.path }
        let expectedSizes = try expectedURLs.map { url in
            try SizeCalculator().calculate(at: url).bytes
        }

        #expect(result.map(\.url.lastPathComponent) == expectedURLs.map(\.lastPathComponent))
        #expect(result.map(\.sizeBytes) == expectedSizes)
        #expect(result.reduce(Int64.zero) { $0 + $1.sizeBytes } == expectedSizes.reduce(0, +))
        #expect(result.allSatisfy { $0.moduleId == "trash.user" && $0.ruleId == "trash.user" })
        #expect(result.allSatisfy {
            $0.resolvedURL.standardizedFileURL.path == $0.url.standardizedFileURL.path && !$0.isProtected
        })
    }

    @Test func ignoresOtherUsersTrashAndSymlinksEscapingTrashRoots() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let otherUserFile = fixture.externalVolume
            .appendingPathComponent(".Trashes/502/other-user.txt")
        let outsideFile = fixture.outside.appendingPathComponent("outside.txt")
        let linkedHomeFile = fixture.homeTrash.appendingPathComponent("linked-file")
        let linkedHomeDirectory = fixture.homeTrash.appendingPathComponent("linked-directory", isDirectory: true)
        try createFile(at: otherUserFile, contents: "not this user's trash")
        try createFile(at: outsideFile, contents: "outside")
        try FileManager.default.createSymbolicLink(at: linkedHomeFile, withDestinationURL: outsideFile)
        try FileManager.default.createSymbolicLink(at: linkedHomeDirectory, withDestinationURL: fixture.outside)

        let context = ScanContext(
            homeDirectory: fixture.home,
            mountedVolumes: [VolumeInfo(
                mountPath: fixture.externalVolume,
                filesystemType: "apfs",
                isReadOnly: false,
                uuid: nil
            )]
        )
        let result = try await TrashBinsModule(userID: "501").scan(context: context)

        #expect(result.isEmpty)
    }

    @Test func ignoresMissingTrashDirectoriesAndMountsOutsideVolumes() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let notAVolume = fixture.root.appendingPathComponent("NotVolumes/External", isDirectory: true)
        let ignoredTrash = notAVolume.appendingPathComponent(".Trashes/501", isDirectory: true)
        let ignoredFile = ignoredTrash.appendingPathComponent("ignored.txt")
        try createFile(at: ignoredFile, contents: "not a volume")

        let context = ScanContext(
            homeDirectory: fixture.root.appendingPathComponent("missing-home", isDirectory: true),
            mountedVolumes: [VolumeInfo(
                mountPath: notAVolume,
                filesystemType: "apfs",
                isReadOnly: false,
                uuid: nil
            )]
        )
        let result = try await TrashBinsModule(userID: "501").scan(context: context)

        #expect(result.isEmpty)
    }

    @Test func ignoresSymlinkedTrashRoot() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let redirectedTrash = fixture.outside.appendingPathComponent("redirected-trash", isDirectory: true)
        let redirectedFile = redirectedTrash.appendingPathComponent("redirected.txt")
        try createFile(at: redirectedFile, contents: "outside")
        try FileManager.default.removeItem(at: fixture.homeTrash)
        try FileManager.default.createSymbolicLink(at: fixture.homeTrash, withDestinationURL: redirectedTrash)

        let result = try await TrashBinsModule(userID: "501").scan(
            context: ScanContext(homeDirectory: fixture.home)
        )

        #expect(result.isEmpty)
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-trash-bins-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("Users/test-user", isDirectory: true)
        let homeTrash = home.appendingPathComponent(".Trash", isDirectory: true)
        let externalVolume = root.appendingPathComponent("Volumes/External", isDirectory: true)
        let externalTrash = externalVolume.appendingPathComponent(".Trashes/501", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: homeTrash, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalTrash, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        return Fixture(
            root: root,
            home: home,
            homeTrash: homeTrash,
            externalVolume: externalVolume,
            externalTrash: externalTrash,
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
}
