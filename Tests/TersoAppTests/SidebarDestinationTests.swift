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

import AppKit
import CoreKit
import Testing
@testable import TersoApp

struct SidebarDestinationTests {
    @Test func sidebarContainsAllModulesInDisplayOrder() {
        #expect(SidebarDestination.allCases.map(\.title) == [
            "Smart Scan",
            "User Caches",
            "User Logs",
            "Trash Bins",
            "Xcode Junk",
            "Package Caches",
            "Leftovers",
            "Duplicates",
            "Large Files",
            "Audit Log"
        ])
    }

    @Test func everyDestinationHasAStableIdentityAndSymbol() {
        for destination in SidebarDestination.allCases {
            #expect(destination.id == destination)
            #expect(!destination.symbol.isEmpty)
        }
    }

    @Test func everySymbolExistsInSFSymbols() {
        for destination in SidebarDestination.allCases {
            #expect(
                NSImage(systemSymbolName: destination.symbol, accessibilityDescription: nil) != nil,
                "Missing SF Symbol: \(destination.symbol)"
            )
        }
    }

    @MainActor @Test func everyModuleDestinationScansItsOwnModule() {
        let scanSessions = ScanSessionStore()
        let expectedModuleIDs: [SidebarDestination: String] = [
            .userCaches: "caches.user",
            .userLogs: "logs.user",
            .trashBins: "trash.user",
            .xcodeJunk: "xcode.junk",
            .packageCaches: "caches.packages"
        ]
        for destination in SidebarSection.modules.destinations {
            let module = destination.cleanModule
            #expect(module?.id == expectedModuleIDs[destination])
            #expect(module?.title == destination.title)
            #expect(ModuleScanView(destination: destination, scanSessions: scanSessions) != nil)
        }
    }

    @MainActor @Test func nonModuleDestinationsHaveNoModuleScanPage() {
        let scanSessions = ScanSessionStore()
        for destination in [SidebarDestination.smartScan, .leftovers, .duplicates, .largeFiles, .auditLogs] {
            #expect(destination.cleanModule == nil)
            #expect(ModuleScanView(destination: destination, scanSessions: scanSessions) == nil)
        }
    }

    @Test func sectionsPartitionAllDestinationsInDisplayOrder() {
        let grouped = SidebarSection.allCases.flatMap(\.destinations)
        #expect(grouped == SidebarDestination.allCases)
    }
}
