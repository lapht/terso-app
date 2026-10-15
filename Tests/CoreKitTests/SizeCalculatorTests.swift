// SPDX-License-Identifier: GPL-3.0-or-later
//
// Terso — The Auditable Mac Cleaner
// Copyright (C) 2026 Terso Contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License
// as published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
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

struct SizeCalculatorTests {
    @Test func calculatesAllocatedSizeOfSingleFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("known-size.txt")
        try Data("known file contents".utf8).write(to: file)

        let expected = try allocatedSize(of: file)
        let result = try SizeCalculator().calculate(at: file)

        #expect(result.bytes == expected)
        #expect(result.errors.isEmpty)
    }

    @Test func calculatesNestedDirectorySizeWithoutFollowingSymlinks() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested/deeper", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let first = root.appendingPathComponent("first.txt")
        let second = nested.appendingPathComponent("second.txt")
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString).txt")
        let link = nested.appendingPathComponent("linked.txt")
        try Data("first".utf8).write(to: first)
        try Data("second file".utf8).write(to: second)
        try Data("outside file".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let expected = try allocatedSize(of: first) + allocatedSize(of: second)
        let result = try SizeCalculator().calculate(at: root)

        #expect(result.bytes == expected)
        #expect(result.errors.isEmpty)
    }

    @Test func countsHardLinkedFileOnlyOnce() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original.txt")
        let hardLink = root.appendingPathComponent("hard-link.txt")
        try Data("shared contents".utf8).write(to: original)
        try FileManager.default.linkItem(at: original, to: hardLink)

        let expected = try allocatedSize(of: original)
        let result = try SizeCalculator().calculate(at: root)

        #expect(result.bytes == expected)
        #expect(result.errors.isEmpty)
    }

    @Test func usesAllocatedSizeForSparseFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sparseFile = root.appendingPathComponent("sparse.bin")
        #expect(FileManager.default.createFile(atPath: sparseFile.path, contents: nil))
        let handle = try FileHandle(forWritingTo: sparseFile)
        try handle.seek(toOffset: 1_048_575)
        try handle.write(contentsOf: Data([0x1]))
        try handle.close()

        let expected = try allocatedSize(of: sparseFile)
        let logicalSize = try sparseFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let result = try SizeCalculator().calculate(at: sparseFile)

        #expect(result.bytes == expected)
        #expect(result.bytes <= logicalSize)
    }

    @Test func continuesAfterEncounteringAnUnreadableDirectory() throws {
        try #require(geteuid() != 0)
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let visibleFile = root.appendingPathComponent("visible.txt")
        let restrictedDirectory = root.appendingPathComponent("restricted", isDirectory: true)
        try Data("visible".utf8).write(to: visibleFile)
        try FileManager.default.createDirectory(at: restrictedDirectory, withIntermediateDirectories: false)
        try Data("hidden".utf8).write(to: restrictedDirectory.appendingPathComponent("hidden.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: restrictedDirectory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: restrictedDirectory.path)
        }

        let expected = try allocatedSize(of: visibleFile)
        let result = try SizeCalculator().calculate(at: root)

        #expect(result.bytes == expected)
        #expect(!result.errors.isEmpty)
    }

    @Test func formatsByteCountsUsingFoundation() {
        #expect(!SizeCalculator.formattedByteCount(1_024).isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-size-calculator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func allocatedSize(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey])
        return Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
    }
}
