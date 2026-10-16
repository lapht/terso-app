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

/// The operation recorded for a cleanup item.
public enum AuditAction: String, Codable, Sendable {
    case trash
    case dryRun
}

/// Whether the requested cleanup operation completed.
public enum AuditResult: String, Codable, Sendable {
    case success
    case failure
}

/// A single structured audit-log event.
public struct AuditRecord: Codable, Sendable, Equatable {
    public let timestamp: String
    public let action: AuditAction
    public let moduleId: String
    public let ruleId: String
    public let originalPath: String
    public let resolvedPath: String
    public let sizeBytes: Int64
    public let result: AuditResult
    public let errorCode: String?

    init(
        timestamp: Date,
        action: AuditAction,
        item: CleanItem,
        result: AuditResult,
        errorCode: String?
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        self.timestamp = formatter.string(from: timestamp)
        self.action = action
        self.moduleId = item.moduleId
        self.ruleId = item.ruleId
        self.originalPath = item.url.standardizedFileURL.path
        self.resolvedPath = item.resolvedURL.standardizedFileURL.path
        self.sizeBytes = item.sizeBytes
        self.result = result
        self.errorCode = errorCode
    }
}

/// Privacy options applied to exported reports only; the local log is never altered.
///
/// Exports always replace the home directory with `~`. When ``redactFileNames`` is on,
/// every path component below the matching allowlist root is replaced with `<redacted>`.
/// A path under no known root is redacted below the home directory (fail-closed).
public struct AuditExportOptions: Sendable, Equatable {
    public static let redactedComponent = "<redacted>"

    public var redactFileNames: Bool
    public var homeDirectory: URL
    public var allowlistRoots: [URL]

    public init(
        redactFileNames: Bool = false,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        allowlistRoots: [URL]? = nil
    ) {
        self.redactFileNames = redactFileNames
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.allowlistRoots = (allowlistRoots ?? Self.defaultAllowlistRoots(home: homeDirectory))
            .map(\.standardizedFileURL)
    }

    /// The `~/Library` and Trash roots that cleanup modules are allowed to touch.
    public static func defaultAllowlistRoots(home: URL) -> [URL] {
        ["Library/Caches", "Library/Logs", "Library/Developer", "Library/Application Support",
         "Library/Preferences", "Library/Containers", "Library/Group Containers",
         "Library/Saved Application State", "Library/HTTPStorages", "Library/WebKit", ".Trash"]
            .map { home.appendingPathComponent($0) }
    }

    /// Returns the export-safe form of `path`.
    func sanitize(_ path: String) -> String {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        let homeComponents = homeDirectory.pathComponents
        let underHome = components.starts(with: homeComponents)

        var keep = components.count
        if redactFileNames {
            let matched = allowlistRoots.map(\.pathComponents)
                .filter { components.starts(with: $0) }
                .map(\.count).max()
            keep = matched ?? (underHome ? homeComponents.count : 1)
        }

        var output = Array(components.prefix(keep))
        output += Array(repeating: Self.redactedComponent, count: components.count - keep)
        if underHome {
            output.replaceSubrange(0..<homeComponents.count, with: ["~"])
            return output.joined(separator: "/")
        }
        return "/" + output.dropFirst().joined(separator: "/")
    }
}

/// Errors raised while writing or exporting the audit log.
public enum AuditLoggerError: Error, LocalizedError, Sendable, Hashable {
    case invalidResult
    case invalidLog(path: String)
    case invalidRecordLimit
    case exportDestinationIsLog(path: String)
    case ioFailure(path: String, errorCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResult:
            "The audit result and error code do not match."
        case let .invalidLog(path):
            "The audit log at \(path) is invalid or unreadable."
        case .invalidRecordLimit:
            "The audit record limit must be greater than zero."
        case let .exportDestinationIsLog(path):
            "Cannot export the audit report over the source log at \(path)."
        case let .ioFailure(path, errorCode):
            "Unable to access audit data at \(path) (error \(errorCode))."
        }
    }
}

/// Appends cleanup events to a local JSON Lines log and exports readable reports.
///
/// The log contains paths and filesystem metadata only; file contents are never read.
public final class AuditLogger: @unchecked Sendable {
    /// Default audit-log location for the current user.
    public static var defaultLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Terso/audit.log")
    }

    private let logURL: URL
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Creates a logger. The file is created lazily when the first record is written.
    ///
    /// - Parameter fileURL: Destination for JSON Lines records. Defaults to
    ///   `~/Library/Logs/Terso/audit.log`.
    public init(fileURL: URL = AuditLogger.defaultLogURL) {
        self.logURL = fileURL.standardizedFileURL
        self.encoder.outputFormatting = [.sortedKeys]
    }

    /// Records one item operation. Failures must include a stable error code.
    public func record(
        action: AuditAction,
        item: CleanItem,
        result: AuditResult,
        errorCode: String? = nil,
        timestamp: Date = Date()
    ) throws {
        guard (result == .failure) == (errorCode != nil) else {
            throw AuditLoggerError.invalidResult
        }

        let record = AuditRecord(
            timestamp: timestamp,
            action: action,
            item: item,
            result: result,
            errorCode: errorCode
        )

        lock.lock()
        defer { lock.unlock() }
        do {
            var data = try encoder.encode(record)
            data.append(0x0A)
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: logURL.path) {
                guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
                    throw AuditLoggerError.ioFailure(path: logURL.path, errorCode: -1)
                }
            }

            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch let error as AuditLoggerError {
            throw error
        } catch {
            throw Self.ioFailure(for: error, path: logURL.path)
        }
    }

    /// Reads the most recent audit events, newest first.
    ///
    /// - Parameter limit: Maximum number of events to return. Must be greater than zero.
    /// - Returns: The newest events in reverse chronological log order.
    /// - Throws: `AuditLoggerError` if the limit is invalid or the log cannot be read.
    public func readRecords(limit: Int = 500) throws -> [AuditRecord] {
        guard limit > 0 else {
            throw AuditLoggerError.invalidRecordLimit
        }

        lock.lock()
        defer { lock.unlock() }
        let logData = try readLogData()
        guard !logData.isEmpty else {
            return []
        }
        guard let contents = String(data: logData, encoding: .utf8) else {
            throw AuditLoggerError.invalidLog(path: logURL.path)
        }

        let records = try contents.split(whereSeparator: \.isNewline).map { line in
            do {
                return try decoder.decode(AuditRecord.self, from: Data(line.utf8))
            } catch {
                throw AuditLoggerError.invalidLog(path: logURL.path)
            }
        }
        return Array(records.suffix(limit).reversed())
    }

    /// Exports the current JSON Lines log as a readable plain-text report.
    ///
    /// If no events have been recorded yet, the report contains its header only.
    ///
    /// - Parameter options: Path-privacy options. By default the home directory is
    ///   replaced with `~`; the local log keeps full paths (invariant 8).
    public func exportReport(to url: URL, options: AuditExportOptions = AuditExportOptions()) throws {
        let destinationURL = url.standardizedFileURL
        guard destinationURL != logURL else {
            throw AuditLoggerError.exportDestinationIsLog(path: destinationURL.path)
        }

        lock.lock()
        defer { lock.unlock() }
        do {
            let logData = try readLogData()
            let report = try makeReport(from: logData, options: options)
            try Data(report.utf8).write(to: destinationURL, options: .atomic)
        } catch let error as AuditLoggerError {
            throw error
        } catch {
            throw Self.ioFailure(for: error, path: destinationURL.path)
        }
    }

    private func readLogData() throws -> Data {
        do {
            return try Data(contentsOf: logURL)
        } catch {
            if (error as NSError).code == NSFileReadNoSuchFileError {
                return Data()
            }
            throw Self.ioFailure(for: error, path: logURL.path)
        }
    }

    private func makeReport(from data: Data, options: AuditExportOptions) throws -> String {
        var report = "Terso Audit Report\n===================\n"
        guard !data.isEmpty else {
            return report
        }

        guard let contents = String(data: data, encoding: .utf8) else {
            throw AuditLoggerError.invalidLog(path: logURL.path)
        }
        let lines = contents.split(whereSeparator: \.isNewline)
        for line in lines {
            let record: AuditRecord
            do {
                record = try decoder.decode(AuditRecord.self, from: Data(line.utf8))
            } catch {
                throw AuditLoggerError.invalidLog(path: logURL.path)
            }
            report += """

            [\(record.timestamp)] \(record.action.rawValue) — \(record.result.rawValue)
              Module: \(record.moduleId)
              Rule: \(record.ruleId)
              Original path: \(options.sanitize(record.originalPath))
              Resolved path: \(options.sanitize(record.resolvedPath))
              Size: \(record.sizeBytes) bytes
            """
            if let errorCode = record.errorCode {
                report += "\n  Error code: \(errorCode)"
            }
            report += "\n"
        }
        return report
    }

    private static func ioFailure(for error: Error, path: String) -> AuditLoggerError {
        AuditLoggerError.ioFailure(path: path, errorCode: (error as NSError).code)
    }
}
