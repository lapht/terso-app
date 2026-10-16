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
    private let systemImage: String
    private let items: [CleanItem]
    private let homeDirectory: URL
    private let allowsSelection: Bool
    private let onMoveToTrash: ([CleanItem]) -> Void
    private let onBack: (() -> Void)?
    private let backTitle: String

    init(
        title: String,
        systemImage: String = "doc.text.magnifyingglass",
        items: [CleanItem],
        homeDirectory: URL,
        allowsSelection: Bool = true,
        selectionViewModel: ModuleSelectionViewModel? = nil,
        onMoveToTrash: @escaping ([CleanItem]) -> Void,
        onBack: (() -> Void)? = nil,
        backTitle: String = String(localized: "Back to Smart Scan")
    ) {
        self.title = title
        self.systemImage = systemImage
        self.items = items
        self.homeDirectory = homeDirectory
        self.allowsSelection = allowsSelection
        self.onMoveToTrash = onMoveToTrash
        self.onBack = onBack
        self.backTitle = backTitle
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
        // The header stays put; only the item list scrolls, so the page never nests scroll views.
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
            header
            if items.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.seal",
                    title: "No items found",
                    message: "This scan found no items that match Terso's rules here."
                )
            } else {
                itemList
            }
        }
        .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, maxHeight: .infinity, alignment: .topLeading)
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            if let onBack {
                Button(backTitle, systemImage: "chevron.left", action: onBack)
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.Palette.brandText)
            }

            PageHeader(title: title, systemImage: systemImage)

            if allowsSelection {
                if !items.isEmpty {
                    selectionBar
                }
            } else {
                StatusMessage(
                    text: String(localized: "Read-only — items can only be revealed in Finder."),
                    systemImage: "eye"
                )
            }
        }
    }

    /// Selection recap and actions; the Trash button repeats count and size (design.md §5.6).
    private var selectionBar: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxSmall) {
                Text(SizeCalculator.formattedByteCount(viewModel.selectedBytes))
                    .font(DesignTokens.Typography.figure)
                    .foregroundStyle(DesignTokens.Palette.brandText)
                Text("\(viewModel.selectedItems.count) of \(items.count) selected")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("module-selected-size")

            Spacer(minLength: DesignTokens.Spacing.small)

            Button("Select All", action: viewModel.selectAll)
                .accessibilityIdentifier("module-select-all")
            Button("Deselect All", action: viewModel.deselectAll)
                .accessibilityIdentifier("module-deselect-all")

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
        .buttonStyle(.bordered)
        .tersoCard(padding: DesignTokens.Spacing.small)
    }

    private var itemList: some View {
        List(items) { item in
            ItemRowView(
                item: item,
                homeDirectory: homeDirectory,
                isSelected: Binding(
                    get: { viewModel.isSelected(item) },
                    set: { viewModel.setSelected($0, for: item) }
                ),
                allowsSelection: allowsSelection
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("module-item-list")
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

struct ModuleDetailView_Previews: PreviewProvider {
    private static let homeDirectory = URL(fileURLWithPath: "/Users/preview", isDirectory: true)
    private static let items: [CleanItem] = (1...3).map { index in
        let url = homeDirectory.appendingPathComponent("Library/Caches/com.example.app\(index)")
        return CleanItem(
            url: url,
            resolvedURL: url,
            sizeBytes: Int64(index) * 48_000_000,
            moduleId: "user-caches",
            ruleId: "preview.rule"
        )
    }

    static var previews: some View {
        // The preview never deletes anything: the trash action is a no-op.
        ModuleDetailView(
            title: "User Caches",
            items: items,
            homeDirectory: homeDirectory,
            onMoveToTrash: { _ in }
        )
        .frame(width: 720, height: 480)
    }
}
