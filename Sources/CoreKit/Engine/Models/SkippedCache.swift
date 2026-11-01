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

/// A cache directory left out of a scan because its app is running.
///
/// It is informational only: it is never a ``CleanItem``, so it can never be selected or deleted.
public struct SkippedCache: Sendable, Equatable, Identifiable {
    /// Identifier of the module that skipped the cache.
    public let moduleID: String

    /// Bundle identifier of the running app that owns the cache.
    public let bundleIdentifier: String

    /// Estimated size of the skipped cache directory (may be partial if some files were unreadable).
    public let estimatedBytes: Int64

    /// Resolved app name when the module found one; callers fall back to the identifier.
    public let displayName: String?

    public var id: String { "\(moduleID):\(bundleIdentifier)" }

    public init(moduleID: String, bundleIdentifier: String, estimatedBytes: Int64, displayName: String? = nil) {
        self.moduleID = moduleID
        self.bundleIdentifier = bundleIdentifier
        self.estimatedBytes = estimatedBytes
        self.displayName = displayName
    }
}

/// Guidance about something Terso found but deliberately does not clean itself.
///
/// It is informational only: it is never a ``CleanItem``, and Terso never runs `command`.
public struct ModuleAdvisory: Sendable, Equatable, Identifiable {
    /// Identifier of the module that produced the advisory.
    public let moduleID: String

    /// Stable identifier of the advisory within its module.
    public let advisoryID: String

    /// Short user-facing title.
    public let title: String

    /// User-facing explanation.
    public let detail: String

    /// A command the user can run themselves in Terminal.
    public let command: String

    /// Estimated size of what the command would affect, if known.
    public let estimatedBytes: Int64

    public var id: String { "\(moduleID):\(advisoryID)" }

    public init(
        moduleID: String,
        advisoryID: String,
        title: String,
        detail: String,
        command: String,
        estimatedBytes: Int64
    ) {
        self.moduleID = moduleID
        self.advisoryID = advisoryID
        self.title = title
        self.detail = detail
        self.command = command
        self.estimatedBytes = estimatedBytes
    }
}

/// The items a module found plus what it deliberately left out.
public struct ModuleScanReport: Sendable, Equatable {
    public let items: [CleanItem]
    public let skippedCaches: [SkippedCache]
    public let advisories: [ModuleAdvisory]

    public init(
        items: [CleanItem],
        skippedCaches: [SkippedCache] = [],
        advisories: [ModuleAdvisory] = []
    ) {
        self.items = items
        self.skippedCaches = skippedCaches
        self.advisories = advisories
    }
}

/// A module that can report what it skipped, in addition to its cleanup candidates.
public protocol SkippedCacheReporting: CleanModule {
    /// Same read-only scan as ``CleanModule/scan(context:)``, plus the skipped caches.
    func scanReport(context: ScanContext) async throws -> ModuleScanReport
}
