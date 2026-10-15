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

struct CleanupConfirmationViewModelTests {
    @MainActor
    @Test func cleanupOnlyRunsAfterExplicitConfirmation() {
        let item = Self.item(name: "cache", size: 1_500_000_000)
        var confirmedBatches: [[CleanItem]] = []
        let viewModel = CleanupConfirmationViewModel { items in
            confirmedBatches.append(items)
        }

        viewModel.requestConfirmation(for: [item])

        #expect(viewModel.isPresented)
        #expect(viewModel.pendingItems == [item])
        #expect(viewModel.pendingBytes == item.sizeBytes)
        #expect(confirmedBatches.isEmpty)

        viewModel.cancel()
        #expect(!viewModel.isPresented)
        #expect(confirmedBatches.isEmpty)
        viewModel.confirm()
        #expect(confirmedBatches.isEmpty)

        viewModel.requestConfirmation(for: [item])
        #expect(confirmedBatches.isEmpty)
        viewModel.confirm()

        #expect(!viewModel.isPresented)
        #expect(confirmedBatches == [[item]])
    }

    @MainActor
    @Test func confirmationExcludesItemsThatCannotBeMovedToTrash() {
        let trashable = Self.item(name: "cache", size: 10)
        let permanent = Self.item(name: "permanent", size: 20, action: .permanentDelete)
        let protected = Self.item(name: "protected", size: 30, isProtected: true)
        let readOnly = Self.item(name: "read-only", size: 40, isDeletable: false)
        let viewModel = CleanupConfirmationViewModel { _ in
            Issue.record("Cleanup must not run when there are no trashable items.")
        }

        viewModel.requestConfirmation(for: [permanent, protected, readOnly])
        #expect(!viewModel.isPresented)
        #expect(viewModel.pendingItems.isEmpty)

        viewModel.requestConfirmation(for: [trashable, permanent, protected, readOnly])
        #expect(viewModel.isPresented)
        #expect(viewModel.pendingItems == [trashable])
        #expect(viewModel.pendingBytes == trashable.sizeBytes)
    }

    private static func item(
        name: String,
        size: Int64,
        isProtected: Bool = false,
        isDeletable: Bool = true,
        action: CleanAction = .trash
    ) -> CleanItem {
        let url = URL(fileURLWithPath: "/Users/test/Library/Caches/\(name)")
        return CleanItem(
            url: url,
            resolvedURL: url,
            sizeBytes: size,
            moduleId: "test.module",
            ruleId: "test.rule",
            isProtected: isProtected,
            isDeletable: isDeletable,
            recommendedAction: action
        )
    }
}
