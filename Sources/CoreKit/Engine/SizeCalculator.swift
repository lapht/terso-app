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

import Foundation

/// The result of measuring a file or directory tree.
public struct SizeCalculationResult: Sendable, Hashable {
    /// Total allocated bytes for successfully inspected regular files.
    public let bytes: Int64

    /// Items that could not be inspected. Other items are still included in `bytes`.
    public let errors: [SizeCalculationError]

    public init(bytes: Int64, errors: [SizeCalculationError] = []) {
        self.bytes = bytes
        self.errors = errors
    }
}

/// An item that could not be inspected while calculating a size.
public struct SizeCalculationError: Sendable, Hashable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// Calculates allocated disk usage without following symbolic links or counting hard links twice.
public struct SizeCalculator {
    private struct FileIdentity: Hashable {
        let device: UInt64
        let inode: UInt64
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Calculates the allocated size of a regular file or all regular files below a directory.
    ///
    /// A failure to inspect the root is thrown. Failures for descendants are returned in
    /// `SizeCalculationResult.errors` and do not prevent other descendants from being counted.
    public func calculate(at url: URL) throws -> SizeCalculationResult {
        var errors: [SizeCalculationError] = []
        var seenFiles: Set<FileIdentity> = []
        let bytes = try calculateRoot(at: url, seenFiles: &seenFiles, errors: &errors)
        return SizeCalculationResult(bytes: bytes, errors: errors)
    }

    /// Formats a byte count using Foundation's native file-size formatting.
    public static func formattedByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func calculateRoot(
        at url: URL,
        seenFiles: inout Set<FileIdentity>,
        errors: inout [SizeCalculationError]
    ) throws -> Int64 {
        let values = try url.resourceValues(forKeys: Self.resourceKeySet)
        if values.isSymbolicLink == true {
            return 0
        }
        if values.isRegularFile == true {
            return try allocatedSize(at: url, values: values, seenFiles: &seenFiles)
        }
        guard values.isDirectory == true else {
            return 0
        }

        var enumerationErrors: [SizeCalculationError] = []
        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Self.resourceKeys,
            options: [],
            errorHandler: { failedURL, error in
                enumerationErrors.append(
                    SizeCalculationError(path: failedURL.path, message: error.localizedDescription)
                )
                return true
            }
        )
        guard let enumerator else {
            throw SizeCalculatorFailure.cannotEnumerate(url.path)
        }

        var total: Int64 = 0
        while let childURL = enumerator.nextObject() as? URL {
            do {
                let childValues = try childURL.resourceValues(forKeys: Self.resourceKeySet)
                guard childValues.isSymbolicLink != true,
                      childValues.isRegularFile == true else {
                    continue
                }
                let size = try allocatedSize(at: childURL, values: childValues, seenFiles: &seenFiles)
                let (sum, overflow) = total.addingReportingOverflow(size)
                guard !overflow else {
                    throw SizeCalculatorFailure.sizeOverflow(url.path)
                }
                total = sum
            } catch let failure as SizeCalculatorFailure {
                if case .sizeOverflow = failure {
                    throw failure
                }
                errors.append(SizeCalculationError(path: childURL.path, message: failure.localizedDescription))
            } catch {
                errors.append(SizeCalculationError(path: childURL.path, message: error.localizedDescription))
            }
        }
        errors.append(contentsOf: enumerationErrors)
        return total
    }

    private func allocatedSize(
        at url: URL,
        values: URLResourceValues,
        seenFiles: inout Set<FileIdentity>
    ) throws -> Int64 {
        if let identity = try fileIdentity(at: url) {
            guard seenFiles.insert(identity).inserted else {
                return 0
            }
        }
        guard let size = values.fileAllocatedSize ?? values.fileSize else {
            throw SizeCalculatorFailure.sizeUnavailable(url.path)
        }
        return Int64(size)
    }

    private func fileIdentity(at url: URL) throws -> FileIdentity? {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            return nil
        }
        return FileIdentity(device: device.uint64Value, inode: inode.uint64Value)
    }

    private static let resourceKeys: [URLResourceKey] = [
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey
    ]

    private static let resourceKeySet = Set(resourceKeys)
}

private enum SizeCalculatorFailure: Error, LocalizedError {
    case cannotEnumerate(String)
    case sizeUnavailable(String)
    case sizeOverflow(String)

    var errorDescription: String? {
        switch self {
        case let .cannotEnumerate(path):
            "Unable to enumerate directory at \(path)."
        case let .sizeUnavailable(path):
            "Unable to determine file size at \(path)."
        case let .sizeOverflow(path):
            "The total size exceeds the supported range at \(path)."
        }
    }
}
