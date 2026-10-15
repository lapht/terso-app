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

import Combine
import CoreKit
import Foundation

@MainActor
final class ModuleSelectionViewModel: ObservableObject {
    @Published private(set) var selectedItemIDs: Set<UUID>

    private let items: [CleanItem]
    private let allowsSelection: Bool

    var selectedItems: [CleanItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(into: Int64.zero) { total, item in
            let (sum, overflow) = total.addingReportingOverflow(item.sizeBytes)
            total = overflow ? .max : sum
        }
    }

    init(items: [CleanItem], allowsSelection: Bool = true) {
        self.items = items
        self.allowsSelection = allowsSelection
        selectedItemIDs = Set(items.filter(Self.isRecommended).map(\.id))
    }

    func isSelected(_ item: CleanItem) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    func toggleSelection(for item: CleanItem) {
        guard allowsSelection, Self.isSelectable(item), items.contains(item) else {
            return
        }
        setSelected(!isSelected(item), for: item)
    }

    func setSelected(_ isSelected: Bool, for item: CleanItem) {
        guard allowsSelection, Self.isSelectable(item), items.contains(item) else {
            return
        }
        if isSelected {
            selectedItemIDs.insert(item.id)
        } else {
            selectedItemIDs.remove(item.id)
        }
    }

    func selectAll() {
        guard allowsSelection else {
            return
        }
        selectedItemIDs = Set(items.filter(Self.isSelectable).map(\.id))
    }

    func deselectAll() {
        selectedItemIDs.removeAll()
    }

    private static func isRecommended(_ item: CleanItem) -> Bool {
        isSelectable(item) && item.recommendedAction == .trash
    }

    private static func isSelectable(_ item: CleanItem) -> Bool {
        item.isDeletable
            && !item.isProtected
            && item.recommendedAction == .trash
    }
}
