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

    public var id: String { "\(moduleID):\(bundleIdentifier)" }

    public init(moduleID: String, bundleIdentifier: String, estimatedBytes: Int64) {
        self.moduleID = moduleID
        self.bundleIdentifier = bundleIdentifier
        self.estimatedBytes = estimatedBytes
    }
}

/// The items a module found plus what it deliberately left out.
public struct ModuleScanReport: Sendable, Equatable {
    public let items: [CleanItem]
    public let skippedCaches: [SkippedCache]

    public init(items: [CleanItem], skippedCaches: [SkippedCache] = []) {
        self.items = items
        self.skippedCaches = skippedCaches
    }
}

/// A module that can report what it skipped, in addition to its cleanup candidates.
public protocol SkippedCacheReporting: CleanModule {
    /// Same read-only scan as ``CleanModule/scan(context:)``, plus the skipped caches.
    func scanReport(context: ScanContext) async throws -> ModuleScanReport
}
