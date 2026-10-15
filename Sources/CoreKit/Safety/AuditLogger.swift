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

    fileprivate init(
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

/// Errors raised while writing or exporting the audit log.
public enum AuditLoggerError: Error, Sendable, Hashable {
    case invalidResult
    case invalidLog(path: String)
    case exportDestinationIsLog(path: String)
    case ioFailure(path: String, errorCode: Int)
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

    /// Exports the current JSON Lines log as a readable plain-text report.
    ///
    /// If no events have been recorded yet, the report contains its header only.
    public func exportReport(to url: URL) throws {
        let destinationURL = url.standardizedFileURL
        guard destinationURL != logURL else {
            throw AuditLoggerError.exportDestinationIsLog(path: destinationURL.path)
        }

        lock.lock()
        defer { lock.unlock() }
        do {
            let logData: Data
            do {
                logData = try Data(contentsOf: logURL)
            } catch {
                if (error as NSError).code == NSFileReadNoSuchFileError {
                    logData = Data()
                } else {
                    throw Self.ioFailure(for: error, path: logURL.path)
                }
            }
            let report = try makeReport(from: logData)
            try Data(report.utf8).write(to: destinationURL, options: .atomic)
        } catch let error as AuditLoggerError {
            throw error
        } catch {
            throw Self.ioFailure(for: error, path: destinationURL.path)
        }
    }

    private func makeReport(from data: Data) throws -> String {
        var report = "Terso Audit Report\n===================\n"
        guard !data.isEmpty else {
            return report
        }

        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
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
              Original path: \(record.originalPath)
              Resolved path: \(record.resolvedPath)
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
