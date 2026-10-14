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

/// The TCC/Full Disk Access authorization state observed at scan time.
///
/// Used by ``ScanContext`` so that modules can adapt gracefully
/// (Safety Invariant §7 — never silently scan less than displayed).
public enum TCCStatus: String, Sendable, Hashable, Codable {
    /// Full Disk Access has been granted.
    case granted

    /// Full Disk Access has not been granted; FDA-dependent modules must disable.
    case denied

    /// Authorization status could not be determined.
    case unknown
}

/// Contextual information passed to every ``CleanModule/scan(context:)`` call.
///
/// `ScanContext` is immutable and `Sendable` so it can be shared
/// safely across concurrent module scans (Smart Scan runs modules
/// in parallel — see design §4).
public struct ScanContext: Sendable, Hashable, Codable {
    /// The user's home directory (e.g. `/Users/alice`).
    public let homeDirectory: URL

    /// Mounted volumes available at scan time.
    public let mountedVolumes: [VolumeInfo]

    /// Whether this scan is a dry run (Invariant §5).
    /// When `true`, modules must not perform any side effects.
    public let isDryRun: Bool

    /// Set of path prefixes or glob patterns to exclude from scanning.
    public let exclusions: Set<String>

    /// Current Full Disk Access / TCC authorization state (Invariant §7).
    public let tccStatus: TCCStatus

    public init(
        homeDirectory: URL,
        mountedVolumes: [VolumeInfo] = [],
        isDryRun: Bool = true,
        exclusions: Set<String> = [],
        tccStatus: TCCStatus = .unknown
    ) {
        self.homeDirectory = homeDirectory
        self.mountedVolumes = mountedVolumes
        self.isDryRun = isDryRun
        self.exclusions = exclusions
        self.tccStatus = tccStatus
    }
}
