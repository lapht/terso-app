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

struct DuplicateFinderSafetyTests {
    @Test func symlinkAttackIsNotFollowed() async throws {
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        let secret = DuplicateFixture.bytes(0x66, count: 4_096)
        let outsideFile = try fixture.file("secret.dat", secret, in: fixture.outside)
        try fixture.file("secret-copy.dat", secret, in: fixture.outside)
        try fixture.file("real.dat", secret)
        try FileManager.default.createSymbolicLink(
            at: fixture.scanRoot.appendingPathComponent("linked-dir"),
            withDestinationURL: fixture.outside
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.scanRoot.appendingPathComponent("linked-file.dat"),
            withDestinationURL: outsideFile
        )

        let result = try await DuplicateFinder().scan(roots: [fixture.scanRoot])

        #expect(result.groups.isEmpty)
        #expect(result.examinedFileCount == 1)
        #expect(result.issues.isEmpty)

        let symlinkRoot = fixture.root.appendingPathComponent("root-link")
        try FileManager.default.createSymbolicLink(at: symlinkRoot, withDestinationURL: fixture.outside)
        await #expect(throws: DuplicateScanError.self) {
            try await DuplicateFinder().scan(roots: [symlinkRoot])
        }
    }

    @Test func packageContentsAreNotTraversed() async throws {
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        let content = DuplicateFixture.bytes(0x31, count: 1_024)
        try fixture.file("keep.dat", content)
        try fixture.file("Tool.app/Contents/Resources/keep.dat", content)
        try fixture.file("Tool.app/Contents/Resources/keep-2.dat", content)
        try fixture.file("Family.photoslibrary/originals/keep.dat", content)

        let result = try await DuplicateFinder().scan(roots: [fixture.scanRoot])

        #expect(result.groups.isEmpty)
        #expect(result.examinedFileCount == 1)

        await #expect(throws: DuplicateScanError.self) {
            try await DuplicateFinder().scan(roots: [fixture.scanRoot.appendingPathComponent("Tool.app")])
        }
    }

    @Test func datalessCloudFilesAreSkippedCountedAndNeverRead() async throws {
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        let content = DuplicateFixture.bytes(0x99, count: 2_000)
        try fixture.file("local.dat", content)
        try fixture.file("cloud.dat", content)
        let reader = DuplicateFileReader(readChunkSize: 512) { url in
            let status = try DuplicateFileReader.lstatus(url)
            guard url.lastPathComponent == "cloud.dat" else {
                return status
            }
            return DuplicateFileStatus(
                device: status.device,
                inode: status.inode,
                sizeBytes: status.sizeBytes,
                flags: status.flags | DuplicateFileStatus.datalessFlag,
                isRegularFile: true
            )
        }

        let result = try await DuplicateFinder(partialHashByteCount: 64, reader: reader)
            .scan(roots: [fixture.scanRoot])

        #expect(result.groups.isEmpty)
        #expect(result.skippedDatalessFileCount == 1)
        #expect(result.examinedFileCount == 1)
        #expect(result.issues.isEmpty)
    }

    @Test func readErrorsAreExposedAndNeverTreatedAsHashes() async throws {
        guard getuid() != 0 else {
            return // Root ignores file permissions, so a read error cannot be provoked.
        }
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        let content = DuplicateFixture.bytes(0x10, count: 3_000)
        try fixture.file("a.dat", content)
        try fixture.file("b.dat", content)
        let unreadable = try fixture.file("c.dat", content)
        let lonely = try fixture.file("pair/x.dat", DuplicateFixture.bytes(0x20, count: 50))
        let lonelyTwin = try fixture.file("pair/y.dat", DuplicateFixture.bytes(0x20, count: 50))
        for url in [unreadable, lonelyTwin] {
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        }
        defer {
            for url in [unreadable, lonelyTwin] {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            }
        }

        let result = try await DuplicateFinder().scan(roots: [fixture.scanRoot])

        #expect(result.groups.count == 1)
        #expect(result.groups[0].files.map(\.url.lastPathComponent) == ["a.dat", "b.dat"])
        #expect(Set(result.issues.map(\.path)) == [unreadable.path, lonelyTwin.path])
        #expect(result.issues.allSatisfy { !$0.message.isEmpty })
        #expect(!result.groups.flatMap(\.files).map(\.url).contains(lonely))
        #expect(result.isPartial)
        #expect(!result.isCancelled)
    }

    @Test func cancellationBeforeStartReturnsLabelledPartialResult() async throws {
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        let content = DuplicateFixture.bytes(0x01, count: 100)
        try fixture.file("a", content)
        try fixture.file("b", content)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DuplicateFinder().scan(roots: [fixture.scanRoot])
        }
        let result = try await task.value

        #expect(result.isCancelled)
        #expect(result.isPartial)
        #expect(result.groups.isEmpty)
    }

    @Test func cancellationDuringHashingKeepsOnlyFullyComparedGroups() async throws {
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        let small = DuplicateFixture.bytes(0x01, count: 100)
        let large = DuplicateFixture.bytes(0x02, count: 200)
        try fixture.file("small-1", small)
        try fixture.file("small-2", small)
        try fixture.file("large-1", large)
        try fixture.file("large-2", large)

        let task = Task {
            try await DuplicateFinder().scan(roots: [fixture.scanRoot]) { progress in
                if progress.phase == .hashing {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        let result = try await task.value

        #expect(result.isCancelled)
        #expect(result.isPartial)
        #expect(result.groups.map(\.fileSizeBytes) == [100])
    }

    @Test func scanDoesNotModifyFiles() async throws {
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        let content = DuplicateFixture.bytes(0x77, count: 70_000)
        let files = [
            try fixture.file("one.dat", content),
            try fixture.file("two.dat", content),
            try fixture.file("three.dat", DuplicateFixture.bytes(0x78, count: 70_000))
        ]
        let before = try files.map(Self.snapshot)

        let result = try await DuplicateFinder().scan(roots: [fixture.scanRoot])

        #expect(result.groups.count == 1)
        #expect(try files.map(Self.snapshot) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.scanRoot.path).sorted()
            == ["one.dat", "three.dat", "two.dat"])
    }

    private static func snapshot(_ url: URL) throws -> [String] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return [
            (try Data(contentsOf: url)).base64EncodedString(),
            "\(attributes[.modificationDate] ?? "")",
            "\(attributes[.posixPermissions] ?? "")",
            "\(attributes[.size] ?? "")"
        ]
    }
}
