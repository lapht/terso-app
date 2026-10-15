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

struct ModuleSelectionViewModelTests {
    @MainActor
    @Test func startsWithRecommendedItemsSelectedAndTogglesIndividualItems() {
        let recommended = Self.item(name: "recommended", size: 10)
        let notRecommended = Self.item(name: "not-recommended", size: 20, action: .permanentDelete)
        let skipped = Self.item(name: "skipped", size: 30, action: .skip)
        let viewModel = ModuleSelectionViewModel(items: [recommended, notRecommended, skipped])

        #expect(viewModel.isSelected(recommended))
        #expect(!viewModel.isSelected(notRecommended))
        #expect(!viewModel.isSelected(skipped))
        #expect(viewModel.selectedBytes == 10)

        viewModel.toggleSelection(for: recommended)
        viewModel.toggleSelection(for: notRecommended)

        #expect(!viewModel.isSelected(recommended))
        #expect(viewModel.isSelected(notRecommended))
        #expect(!viewModel.isSelected(skipped))
        #expect(viewModel.selectedBytes == 20)
    }

    @MainActor
    @Test func selectAllAndDeselectAllRecalculateSelectedBytes() {
        let first = Self.item(name: "first", size: 10)
        let second = Self.item(name: "second", size: 25, action: .permanentDelete)
        let readOnly = Self.item(name: "read-only", size: 100, isDeletable: false, action: .revealInFinder)
        let viewModel = ModuleSelectionViewModel(items: [first, second, readOnly])

        viewModel.selectAll()
        #expect(viewModel.selectedItems.count == 2)
        #expect(viewModel.selectedBytes == 35)

        viewModel.deselectAll()
        #expect(viewModel.selectedItems.isEmpty)
        #expect(viewModel.selectedBytes == 0)
    }

    @MainActor
    @Test func protectedItemsCannotBeSelectedAndReadOnlyModulesNeverSelectItems() {
        let protected = Self.item(name: "protected", size: 10, isProtected: true)
        let readOnly = Self.item(name: "read-only", size: 20, isDeletable: false, action: .revealInFinder)
        let selectableViewModel = ModuleSelectionViewModel(items: [protected])
        let readOnlyViewModel = ModuleSelectionViewModel(items: [readOnly], allowsSelection: false)

        selectableViewModel.selectAll()
        readOnlyViewModel.selectAll()

        #expect(selectableViewModel.selectedItems.isEmpty)
        #expect(readOnlyViewModel.selectedItems.isEmpty)
        readOnlyViewModel.toggleSelection(for: readOnly)
        #expect(readOnlyViewModel.selectedItems.isEmpty)
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
