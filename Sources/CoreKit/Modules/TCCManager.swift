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
import os

/// Supplies the current Full Disk Access state.
public protocol TCCAccessChecking: Sendable {
    func fullDiskAccessStatus() -> TCCStatus
}

/// Result of trying to read one FDA-protected location.
public enum FullDiskAccessProbeOutcome: Sendable, Equatable {
    /// The location could be opened for reading.
    case readable
    /// macOS refused access (`EACCES`/`EPERM`).
    case denied
    /// The location is missing or failed for an unrelated reason.
    case inconclusive
}

/// A location that is readable only when Full Disk Access is granted.
public struct FullDiskAccessProbe: Sendable, Equatable {
    public let name: String
    /// Path relative to the user's home directory.
    public let relativePath: String
    /// Whether a successful read proves that FDA is granted.
    ///
    /// Some directories are only protected on certain macOS versions, so reading
    /// them proves nothing; only authoritative probes can yield `.granted`.
    public let isAuthoritative: Bool

    public init(name: String, relativePath: String, isAuthoritative: Bool) {
        self.name = name
        self.relativePath = relativePath
        self.isAuthoritative = isAuthoritative
    }

    public static let defaults: [FullDiskAccessProbe] = [
        FullDiskAccessProbe(
            name: "TCC.db",
            relativePath: "Library/Application Support/com.apple.TCC/TCC.db",
            isAuthoritative: true
        ),
        FullDiskAccessProbe(name: "Safari", relativePath: "Library/Safari", isAuthoritative: false),
        FullDiskAccessProbe(name: "Mail", relativePath: "Library/Mail", isAuthoritative: false),
        FullDiskAccessProbe(name: "Messages", relativePath: "Library/Messages", isAuthoritative: false)
    ]
}

/// Checks access by opening FDA-protected items read-only, never modifying them.
///
/// None of the default probes belongs to a category that triggers a per-folder
/// macOS prompt (Desktop, Documents, Downloads, removable or network volumes).
public struct SystemTCCAccessChecker: TCCAccessChecking {
    public typealias ProbeRunner = @Sendable (FullDiskAccessProbe, URL) -> FullDiskAccessProbeOutcome
    public typealias DecisionLogger = @Sendable (String) -> Void

    private let homeDirectory: URL
    private let probes: [FullDiskAccessProbe]
    private let probeRunner: ProbeRunner
    private let decisionLogger: DecisionLogger

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        probes: [FullDiskAccessProbe] = FullDiskAccessProbe.defaults,
        probeRunner: @escaping ProbeRunner = SystemTCCAccessChecker.runProbe,
        decisionLogger: @escaping DecisionLogger = SystemTCCAccessChecker.defaultDecisionLogger
    ) {
        self.homeDirectory = homeDirectory
        self.probes = probes
        self.probeRunner = probeRunner
        self.decisionLogger = decisionLogger
    }

    public func fullDiskAccessStatus() -> TCCStatus {
        let outcomes = probes.map { ($0, probeRunner($0, homeDirectory)) }
        let (status, reason) = Self.decide(outcomes)
        decisionLogger("FDA status \(status.rawValue): \(reason)")
        return status
    }

    /// Combines probe outcomes; `.granted` is returned only when it is demonstrable.
    public static func decide(
        _ outcomes: [(probe: FullDiskAccessProbe, outcome: FullDiskAccessProbeOutcome)]
    ) -> (status: TCCStatus, reason: String) {
        if let denied = outcomes.first(where: { $0.outcome == .denied }) {
            return (.denied, "probe \(denied.probe.name) was refused by macOS")
        }
        if let proof = outcomes.first(where: { $0.outcome == .readable && $0.probe.isAuthoritative }) {
            return (.granted, "authoritative probe \(proof.probe.name) was readable")
        }
        let summary = outcomes.map { "\($0.probe.name)=\($0.outcome)" }.joined(separator: ", ")
        return (.unknown, "no probe could prove the state (\(summary))")
    }

    public static func runProbe(_ probe: FullDiskAccessProbe, homeDirectory: URL) -> FullDiskAccessProbeOutcome {
        let path = homeDirectory.appendingPathComponent(probe.relativePath).path
        let descriptor = open(path, O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0 else {
            return errno == EACCES || errno == EPERM ? .denied : .inconclusive
        }
        close(descriptor)
        return .readable
    }

    public static func defaultDecisionLogger(_ message: String) {
        #if DEBUG
        Logger(subsystem: "io.github.lapht.Terso", category: "tcc").debug("\(message, privacy: .public)")
        #endif
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
                message: "This module requires Full Disk Access. Enable Terso in "
                    + "System Settings > Privacy & Security > Full Disk Access to scan it."
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
