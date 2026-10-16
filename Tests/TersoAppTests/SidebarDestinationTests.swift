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

    @Test func sectionsPartitionAllDestinationsInDisplayOrder() {
        let grouped = SidebarSection.allCases.flatMap(\.destinations)
        #expect(grouped == SidebarDestination.allCases)
    }
}
