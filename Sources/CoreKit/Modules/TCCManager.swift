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

import Darwin
import Foundation

/// Supplies the current Full Disk Access state.
public protocol TCCAccessChecking: Sendable {
    func fullDiskAccessStatus() -> TCCStatus
}

/// Checks access by listing a TCC-protected directory without changing it.
public struct SystemTCCAccessChecker: TCCAccessChecking {
    public init() {}

    public func fullDiskAccessStatus() -> TCCStatus {
        let protectedDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari", isDirectory: true)

        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: protectedDirectory.path)
            return .granted
        } catch {
            let fileError = error as NSError
            if Self.isPermissionDenied(fileError) {
                return .denied
            }

            return .unknown
        }
    }

    private static func isPermissionDenied(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain,
           error.code == CocoaError.Code.fileReadNoPermission.rawValue {
            return true
        }

        if error.domain == NSPOSIXErrorDomain,
           error.code == EACCES || error.code == EPERM {
            return true
        }

        guard let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return false
        }
        return underlyingError.domain == NSPOSIXErrorDomain
            && (underlyingError.code == EACCES || underlyingError.code == EPERM)
    }
}

/// Outcome of requesting a scan through ``TCCManager``.
public enum CleanModuleScanResult: Sendable, Equatable {
    case completed([CleanItem])
    case requiresPermission(message: String)
}

/// Checks FDA and prevents FDA-dependent modules from silently scanning partially.
public struct TCCManager: Sendable {
    private let accessChecker: any TCCAccessChecking

    public init(accessChecker: any TCCAccessChecking = SystemTCCAccessChecker()) {
        self.accessChecker = accessChecker
    }

    /// The latest Full Disk Access state.
    public var status: TCCStatus {
        accessChecker.fullDiskAccessStatus()
    }

    /// Scans only when the module can produce a complete result.
    public func scan(
        module: any CleanModule,
        context: ScanContext
    ) async throws -> CleanModuleScanResult {
        let currentStatus = status
        guard !module.requiresFDA || currentStatus == .granted else {
            return .requiresPermission(
                message: "Enable Terso in System Settings > Privacy & Security > Full Disk Access "
                    + "to scan this module."
            )
        }

        let authorizedContext = ScanContext(
            homeDirectory: context.homeDirectory,
            mountedVolumes: context.mountedVolumes,
            isDryRun: context.isDryRun,
            exclusions: context.exclusions,
            tccStatus: currentStatus
        )
        return .completed(try await module.scan(context: authorizedContext))
    }
}
