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
import Testing

@testable import TersoApp

struct CleanResultViewTests {
    @MainActor
    @Test func formatsCleanupSummaryAndRetainsWarnings() {
        let itemURL = URL(fileURLWithPath: "/Users/test/Library/Caches/sample")
        let result = CleanResult(
            itemsTrashed: [
                CleanItem(
                    url: itemURL,
                    resolvedURL: itemURL,
                    sizeBytes: 2_048,
                    moduleId: "caches.user",
                    ruleId: "cache.sample"
                )
            ],
            bytesFreed: 2_048,
            executionDuration: 1.25
        )
        let warning = "User Logs: Full Disk Access is unavailable."
        let view = CleanResultView(
            result: result,
            warnings: [warning],
            onScanAgain: {},
            onViewAuditLog: {}
        )

        #expect(!view.formattedBytes.isEmpty)
        #expect(view.formattedDuration == "1.2 seconds")
        #expect(view.warnings == [warning])
        #expect(result.itemsTrashed.count == 1)
    }
}
