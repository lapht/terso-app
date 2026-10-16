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

struct CoreKitIntegrationTests {
    @Test func cleanItemsDefaultToRecoverableTrashAction() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Caches/sample")
        let item = CleanItem(
            url: url,
            resolvedURL: url,
            sizeBytes: 1,
            moduleId: "caches.user",
            ruleId: "cache.sample"
        )

        #expect(item.recommendedAction == .trash)
    }
}
