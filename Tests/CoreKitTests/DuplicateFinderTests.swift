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

import CommonCrypto
@testable import CoreKit
import Darwin
import Foundation
import Testing

/// A temporary folder tree with known contents for duplicate-scan tests.
struct DuplicateFixture {
    let root: URL
    let scanRoot: URL
    let outside: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-duplicates-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // `resolvingSymlinksInPath()` maps /private/var back to /var; realpath gives the canonical path.
        guard let canonical = realpath(base.path, nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        defer { free(canonical) }
        root = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
        scanRoot = root.appendingPathComponent("chosen", isDirectory: true)
        outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func file(_ relativePath: String, _ data: Data, in base: URL? = nil) throws -> URL {
        let url = (base ?? scanRoot).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
        return url
    }

    static func bytes(_ value: UInt8, count: Int) -> Data {
        Data(repeating: value, count: count)
    }
}

struct DuplicateFinderTests {
    @Test func groupsKnownTreeWithExactFilesAndSizes() async throws {
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        let photo = DuplicateFixture.bytes(0xA1, count: 10_000)
        let note = Data("same note".utf8)
        let photoA = try fixture.file("Photos/a.jpg", photo)
        let photoB = try fixture.file("Backup/a-copy.jpg", photo)
        let note1 = try fixture.file("Notes/1.txt", note)
        let note2 = try fixture.file("Notes/2.txt", note)
        let note3 = try fixture.file("Notes/old/3.txt", note)
        try fixture.file("unique.dat", DuplicateFixture.bytes(0xC3, count: 777))
        try fixture.file("same-size.jpg", DuplicateFixture.bytes(0xB2, count: 10_000))
        try fixture.file("empty-1", Data())
        try fixture.file("empty-2", Data())

        let result = try await DuplicateFinder().scan(roots: [fixture.scanRoot])

        #expect(result.groups.count == 2)
        #expect(result.groups.map(\.fileSizeBytes) == [10_000, 9])
        #expect(result.groups[0].files.map(\.url) == [photoB, photoA])
        #expect(result.groups[1].files.map(\.url) == [note1, note2, note3])
        #expect(result.groups.map(\.reclaimableBytes) == [10_000, 18])
        #expect(result.totalReclaimableBytes == 10_018)
        #expect(result.groups.allSatisfy { group in group.files.allSatisfy { !$0.isClone } })
        #expect(result.groups[1].contentHash == Self.sha256Hex(note))
        #expect(result.examinedFileCount == 9)
        #expect(result.skippedDatalessFileCount == 0)
        #expect(result.issues.isEmpty)
        #expect(!result.isPartial)
    }

    @Test func sameSizeDifferentContentIsNotGroupedEvenWithMatchingPartialHash() async throws {
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        var first = DuplicateFixture.bytes(0x11, count: 4_096)
        var second = first
        first[4_095] = 0x01
        second[4_095] = 0x02
        try fixture.file("first.bin", first)
        try fixture.file("second.bin", second)
        try fixture.file("third.bin", DuplicateFixture.bytes(0x22, count: 4_096))

        let result = try await DuplicateFinder(partialHashByteCount: 16, readChunkSize: 100)
            .scan(roots: [fixture.scanRoot])

        #expect(result.groups.isEmpty)
        #expect(result.examinedFileCount == 3)
        #expect(!result.isPartial)
    }

    @Test func fullStreamingHashGroupsLargeFilesAcrossChunks() async throws {
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        let content = Data((0..<10_000).map { UInt8($0 % 251) })
        try fixture.file("one.bin", content)
        try fixture.file("two.bin", content)

        let result = try await DuplicateFinder(partialHashByteCount: 64, readChunkSize: 333)
            .scan(roots: [fixture.scanRoot])

        #expect(result.groups.map(\.contentHash) == [Self.sha256Hex(content)])
        #expect(result.groups.map(\.files.count) == [2])
    }

    @Test func emptyFilesAreNeverReportedAsDuplicates() async throws {
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        try fixture.file("a", Data())
        try fixture.file("b", Data())
        try fixture.file("c", Data())

        let result = try await DuplicateFinder().scan(roots: [fixture.scanRoot])

        #expect(result.groups.isEmpty)
        #expect(result.examinedFileCount == 3)
    }

    @Test func hardLinksAreCollapsedAndNotReportedAsDuplicates() async throws {
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        let content = DuplicateFixture.bytes(0x5A, count: 2_048)
        let original = try fixture.file("original.dat", content)
        try FileManager.default.linkItem(at: original, to: fixture.scanRoot.appendingPathComponent("link.dat"))

        let onlyLinks = try await DuplicateFinder().scan(roots: [fixture.scanRoot])
        #expect(onlyLinks.groups.isEmpty)
        #expect(onlyLinks.examinedFileCount == 1)

        let copy = try fixture.file("z-copy.dat", content)
        let withCopy = try await DuplicateFinder().scan(roots: [fixture.scanRoot])
        #expect(withCopy.groups.count == 1)
        #expect(withCopy.groups[0].files.count == 2)
        #expect(withCopy.groups[0].files.last?.url == copy)
        #expect(withCopy.groups[0].reclaimableBytes == 2_048)
    }

    @Test func overlappingRootsDoNotDoubleCountFiles() async throws {
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        let content = DuplicateFixture.bytes(0x42, count: 512)
        try fixture.file("nested/a.dat", content)
        try fixture.file("nested/b.dat", content)

        let result = try await DuplicateFinder().scan(
            roots: [fixture.scanRoot, fixture.scanRoot.appendingPathComponent("nested")]
        )

        #expect(result.groups.map(\.files.count) == [2])
        #expect(result.examinedFileCount == 2)
    }

    @Test func apfsClonesAreMarkedAndNotCountedAsReclaimable() async throws {
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        let content = DuplicateFixture.bytes(0x7E, count: 100_000)
        let original = try fixture.file("a-original.dat", content)
        let clone = fixture.scanRoot.appendingPathComponent("b-clone.dat")
        guard clonefile(original.path, clone.path, 0) == 0 else {
            // The temporary volume is not APFS; clone semantics cannot be exercised here.
            #expect(errno == ENOTSUP)
            return
        }
        try fixture.file("c-copy.dat", content)

        let result = try await DuplicateFinder().scan(roots: [fixture.scanRoot])

        #expect(result.groups.count == 1)
        #expect(result.groups[0].files.map(\.isClone) == [false, true, false])
        #expect(result.groups[0].reclaimableBytes == 100_000)
    }

    @Test func rejectsMissingOrInvalidRoots() async throws {
        let fixture = try DuplicateFixture()
        defer { fixture.cleanUp() }

        await #expect(throws: DuplicateScanError.noRoots) {
            try await DuplicateFinder().scan(roots: [])
        }
        let file = try fixture.file("plain.txt", Data("x".utf8))
        await #expect(throws: DuplicateScanError.self) {
            try await DuplicateFinder().scan(roots: [file])
        }
        await #expect(throws: DuplicateScanError.self) {
            try await DuplicateFinder().scan(roots: [fixture.root.appendingPathComponent("missing")])
        }
    }

    static func sha256Hex(_ data: Data) -> String {
        var hasher = SHA256Hasher()
        hasher.update(data)
        return hasher.hex
    }
}

/// Independent SHA-256 helper so tests do not reuse the finder's hashing path.
private struct SHA256Hasher {
    private var context = CC_SHA256_CTX()

    init() {
        CC_SHA256_Init(&context)
    }

    mutating func update(_ data: Data) {
        data.withUnsafeBytes { _ = CC_SHA256_Update(&context, $0.baseAddress, CC_LONG(data.count)) }
    }

    var hex: String {
        var copy = context
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &copy)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
