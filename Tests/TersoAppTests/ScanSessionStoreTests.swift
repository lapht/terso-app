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
import Testing

@testable import TersoApp

struct ScanSessionStoreTests {
    @MainActor
    @Test func returnsTheSameViewModelForEveryVisitToAModulePage() throws {
        let store = Self.store()

        let first = try #require(store.moduleScan(for: .userCaches))
        let second = try #require(store.moduleScan(for: .userCaches))

        #expect(first === second)
    }

    @MainActor
    @Test func keepsSeparateViewModelsPerModulePage() throws {
        let store = Self.store()

        let caches = try #require(store.moduleScan(for: .userCaches))
        let logs = try #require(store.moduleScan(for: .userLogs))

        #expect(caches !== logs)
        #expect(caches !== store.smartScan)
    }

    @MainActor
    @Test func hasNoModuleViewModelForPagesThatAreNotModules() {
        let store = Self.store()

        #expect(store.moduleScan(for: .smartScan) == nil)
        #expect(store.moduleScan(for: .leftovers) == nil)
        #expect(store.moduleScan(for: .duplicates) == nil)
        #expect(store.moduleScan(for: .largeFiles) == nil)
        #expect(store.moduleScan(for: .auditLogs) == nil)
    }

    @MainActor
    private static func store() -> ScanSessionStore {
        ScanSessionStore(tccManager: TCCManager(accessChecker: GrantedAccessChecker()))
    }
}

private struct GrantedAccessChecker: TCCAccessChecking {
    func fullDiskAccessStatus() -> TCCStatus {
        .granted
    }
}
