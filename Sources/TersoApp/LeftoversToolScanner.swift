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

import CoreKit
import Foundation

/// Runs the read-only leftovers detector for the Leftovers page (design.md §11.4).
///
/// Rules and installed apps are read on every scan. If either cannot be read completely the
/// scan fails with a message instead of reporting an empty list that was never computed.
struct LeftoversToolScanner: ToolScanning {
    enum ScanError: LocalizedError, Equatable {
        case rulesUnavailable(String)
        case discoveryIncomplete

        var errorDescription: String? {
            switch self {
            case let .rulesUnavailable(reason):
                String(localized: "The rule database could not be loaded: \(reason)")
            case .discoveryIncomplete:
                String(localized: "Installed apps could not be listed completely, so no leftovers are reported.")
            }
        }
    }

    /// The rule database shipped inside the app bundle.
    static let bundledRulesName = "v2026.2"

    let loadRules: @Sendable () throws -> [CleanupRule]
    let discoverApps: @Sendable (URL) -> InstalledAppDiscoveryResult

    init(
        loadRules: @escaping @Sendable () throws -> [CleanupRule] = Self.loadBundledRules,
        discoverApps: @escaping @Sendable (URL) -> InstalledAppDiscoveryResult = {
            InstalledAppDiscovery.standard(homeDirectory: $0).discover()
        }
    ) {
        self.loadRules = loadRules
        self.discoverApps = discoverApps
    }

    func scan(context: ScanContext) async throws -> ToolScanOutcome {
        let rules: [CleanupRule]
        do {
            rules = try loadRules()
        } catch {
            throw ScanError.rulesUnavailable(error.localizedDescription)
        }

        let home = context.homeDirectory
        let result = try LeftoversDetector(homeDirectory: home).scan(
            rules: rules,
            discovery: discoverApps(home),
            tccStatus: context.tccStatus
        )
        if case .discoveryIncomplete = result.status {
            throw ScanError.discoveryIncomplete
        }

        var outcome = ToolScanOutcome()
        for candidate in result.candidates {
            let item = candidate.cleanItem
            outcome.items.append(item)
            outcome.reasons[item.id] = candidate.associationReason
        }
        // Roots that were skipped and locations that were refused stay visible (invariants 7, 8).
        outcome.notScanned = result.notScannedRoots.map {
            NotScannedArea(name: Self.displayPath($0.root, home: home), needsFullDiskAccess: $0.needsFullDiskAccess)
        } + result.issues.map {
            NotScannedArea(name: "\(Self.displayPath($0.url, home: home)): \($0.message)", needsFullDiskAccess: false)
        }
        return outcome
    }

    @Sendable
    static func loadBundledRules() throws -> [CleanupRule] {
        guard let url = Bundle.main.url(forResource: bundledRulesName, withExtension: "json") else {
            throw ScanError.rulesUnavailable("\(bundledRulesName).json is missing from the app bundle")
        }
        return try RuleValidator.decode(Data(contentsOf: url)).rules
    }

    private static func displayPath(_ url: URL, home: URL) -> String {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        return path.hasPrefix(homePath + "/") ? "~" + path.dropFirst(homePath.count) : path
    }
}
