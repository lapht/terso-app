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

import CryptoKit
import Darwin
import Foundation

/// `lstat` metadata needed to compare files without following symlinks.
struct DuplicateFileStatus: Sendable, Hashable {
    /// `SF_DATALESS`: the file's contents live in iCloud/File Provider only.
    static let datalessFlag: UInt32 = 0x4000_0000

    let device: Int64
    let inode: UInt64
    let sizeBytes: Int64
    let flags: UInt32
    let isRegularFile: Bool

    var isDataless: Bool { flags & Self.datalessFlag != 0 }

    init(device: Int64, inode: UInt64, sizeBytes: Int64, flags: UInt32, isRegularFile: Bool) {
        self.device = device
        self.inode = inode
        self.sizeBytes = sizeBytes
        self.flags = flags
        self.isRegularFile = isRegularFile
    }

    init(_ info: stat) {
        self.init(
            device: Int64(info.st_dev),
            inode: UInt64(info.st_ino),
            sizeBytes: Int64(info.st_size),
            flags: info.st_flags,
            isRegularFile: info.st_mode & S_IFMT == S_IFREG
        )
    }
}

struct DuplicateReadError: Error, Sendable {
    let message: String

    static func posix(_ operation: String, _ code: Int32) -> DuplicateReadError {
        DuplicateReadError(message: "\(operation) failed: \(String(cString: strerror(code)))")
    }
}

/// Read-only file access used by ``DuplicateFinder``.
///
/// Files are opened with `O_NOFOLLOW` and re-checked with `fstat`, so a path
/// swapped for a symlink or another file after enumeration is reported as an
/// error instead of being hashed.
struct DuplicateFileReader: Sendable {
    let readChunkSize: Int
    let status: @Sendable (URL) throws -> DuplicateFileStatus

    init(
        readChunkSize: Int,
        status: @escaping @Sendable (URL) throws -> DuplicateFileStatus = DuplicateFileReader.lstatus
    ) {
        self.readChunkSize = readChunkSize
        self.status = status
    }

    static func lstatus(_ url: URL) throws -> DuplicateFileStatus {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw DuplicateReadError.posix("lstat", errno)
        }
        return DuplicateFileStatus(info)
    }

    /// SHA-256 of the first `limit` bytes, or of the whole file when `limit` is nil.
    ///
    /// Throws `CancellationError` when the surrounding task is cancelled.
    func hash(of url: URL, expected: DuplicateFileStatus, limit: Int64?) throws -> String {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw DuplicateReadError.posix("open", errno)
        }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw DuplicateReadError.posix("fstat", errno)
        }
        let opened = DuplicateFileStatus(info)
        guard opened.device == expected.device, opened.inode == expected.inode,
              opened.sizeBytes == expected.sizeBytes, opened.isRegularFile, !opened.isDataless else {
            throw DuplicateReadError(message: "The file changed during the scan.")
        }

        let target = min(limit ?? expected.sizeBytes, expected.sizeBytes)
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: readChunkSize)
        var bytesRead: Int64 = 0
        while bytesRead < target {
            if Task.isCancelled {
                throw CancellationError()
            }
            let wanted = Int(min(Int64(readChunkSize), target - bytesRead))
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, wanted) }
            if count < 0 {
                if errno == EINTR { continue }
                throw DuplicateReadError.posix("read", errno)
            }
            if count == 0 {
                throw DuplicateReadError(message: "The file is shorter than expected; it changed during the scan.")
            }
            buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<count])) }
            bytesRead += Int64(count)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// APFS clone identifier, or nil when the file system does not report one.
    ///
    /// Files that are clones of each other share this identifier and have
    /// `EF_MAY_SHARE_BLOCKS` set.
    static func cloneIdentifier(of url: URL) -> UInt64? {
        let mayShareBlocks: UInt64 = 0x1
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        request.forkattr = attrgroup_t(ATTR_CMNEXT_CLONEID | ATTR_CMNEXT_EXT_FLAGS)

        var buffer = [UInt8](repeating: 0, count: 64)
        let options = UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW)
        let result = buffer.withUnsafeMutableBytes {
            getattrlist(url.path, &request, $0.baseAddress, $0.count, options)
        }
        guard result == 0 else {
            return nil
        }

        return buffer.withUnsafeBytes { raw -> UInt64? in
            let returned = raw.loadUnaligned(fromByteOffset: 4, as: attribute_set_t.self)
            let wanted = attrgroup_t(ATTR_CMNEXT_CLONEID | ATTR_CMNEXT_EXT_FLAGS)
            guard returned.forkattr & wanted == wanted else {
                return nil
            }
            let offset = 4 + MemoryLayout<attribute_set_t>.size
            let cloneID = raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
            let extendedFlags = raw.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self)
            guard cloneID != 0, extendedFlags & mayShareBlocks != 0 else {
                return nil
            }
            return cloneID
        }
    }
}
