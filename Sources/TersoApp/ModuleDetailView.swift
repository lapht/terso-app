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
import SwiftUI

@MainActor
struct ModuleDetailView: View {
    @StateObject private var viewModel: ModuleSelectionViewModel
    @StateObject private var confirmationViewModel: CleanupConfirmationViewModel

    private let title: String
    private let items: [CleanItem]
    private let homeDirectory: URL
    private let allowsSelection: Bool
    private let onMoveToTrash: ([CleanItem]) -> Void
    private let onBack: (() -> Void)?

    init(
        title: String,
        items: [CleanItem],
        homeDirectory: URL,
        allowsSelection: Bool = true,
        selectionViewModel: ModuleSelectionViewModel? = nil,
        onMoveToTrash: @escaping ([CleanItem]) -> Void,
        onBack: (() -> Void)? = nil
    ) {
        self.title = title
        self.items = items
        self.homeDirectory = homeDirectory
        self.allowsSelection = allowsSelection
        self.onMoveToTrash = onMoveToTrash
        self.onBack = onBack
        _viewModel = StateObject(
            wrappedValue: selectionViewModel ?? ModuleSelectionViewModel(
                items: items,
                allowsSelection: allowsSelection
            )
        )
        _confirmationViewModel = StateObject(
            wrappedValue: CleanupConfirmationViewModel(onConfirm: onMoveToTrash)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if items.isEmpty {
                    Text("No items found.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    itemList
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: confirmationSheetBinding) {
            ConfirmationSheetView(
                itemCount: confirmationViewModel.pendingItems.count,
                totalBytes: confirmationViewModel.pendingBytes,
                onCancel: confirmationViewModel.cancel,
                onConfirm: confirmationViewModel.confirm
            )
            .interactiveDismissDisabled()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let onBack {
                Button("Back to Smart Scan", systemImage: "chevron.left", action: onBack)
                    .buttonStyle(.plain)
            }

            Label(title, systemImage: "doc.text.magnifyingglass")
                .font(.largeTitle.weight(.semibold))

            if allowsSelection {
                Text(
                    "\(viewModel.selectedItems.count) selected · "
                        + "\(SizeCalculator.formattedByteCount(viewModel.selectedBytes))"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("module-selected-size")
            } else {
                Label("Read-only — items can only be revealed in Finder.", systemImage: "eye")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if allowsSelection, !items.isEmpty {
                HStack {
                    Button("Select All", action: viewModel.selectAll)
                        .accessibilityIdentifier("module-select-all")
                    Button("Deselect All", action: viewModel.deselectAll)
                        .accessibilityIdentifier("module-deselect-all")
                }
                .buttonStyle(.bordered)

                Button(
                    "Move \(viewModel.selectedItems.count) to Trash",
                    systemImage: "trash",
                    action: {
                        confirmationViewModel.requestConfirmation(for: viewModel.selectedItems)
                    }
                )
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedItems.isEmpty)
                .accessibilityIdentifier("module-move-to-trash")
            }
        }
    }

    private var itemList: some View {
        LazyVStack(spacing: 8) {
            ForEach(items) { item in
                ItemRowView(
                    item: item,
                    homeDirectory: homeDirectory,
                    isSelected: Binding(
                        get: { viewModel.isSelected(item) },
                        set: { viewModel.setSelected($0, for: item) }
                    ),
                    allowsSelection: allowsSelection
                )
            }
        }
    }

    private var confirmationSheetBinding: Binding<Bool> {
        Binding(
            get: { confirmationViewModel.isPresented },
            set: { isPresented in
                if !isPresented {
                    confirmationViewModel.cancel()
                }
            }
        )
    }
}
