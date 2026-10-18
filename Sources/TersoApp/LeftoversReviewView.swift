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

/// Lists found leftovers with an unchecked box each, a recap, a dry-run and a confirmed
/// move to Trash. Refusals from the Safety pipeline are shown under the recap.
@MainActor
struct LeftoversReviewView: View {
    @ObservedObject private var viewModel: LeftoversViewModel
    @StateObject private var confirmation: CleanupConfirmationViewModel

    private let title: String
    private let systemImage: String

    init(title: String, systemImage: String, viewModel: LeftoversViewModel) {
        self.title = title
        self.systemImage = systemImage
        self.viewModel = viewModel
        _confirmation = StateObject(
            wrappedValue: CleanupConfirmationViewModel(onConfirm: { _ in viewModel.moveSelectedToTrash() })
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
            PageHeader(title: title, systemImage: systemImage)
            if viewModel.items.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.seal",
                    title: "No items found",
                    message: "This scan found no items that match Terso's rules here."
                )
            } else {
                recap
            }
            outcome
            if !viewModel.items.isEmpty {
                itemList
            }
        }
        .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: confirmationBinding) {
            ConfirmationSheetView(
                itemCount: confirmation.pendingItems.count,
                totalBytes: confirmation.pendingBytes,
                onCancel: confirmation.cancel,
                onConfirm: confirmation.confirm
            )
            .interactiveDismissDisabled()
        }
    }

    private var recap: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxSmall) {
                Text(SizeCalculator.formattedByteCount(viewModel.selectedBytes))
                    .font(DesignTokens.Typography.figure)
                    .foregroundStyle(DesignTokens.Palette.brandText)
                Text("\(viewModel.selectedItems.count) of \(viewModel.items.count) selected")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("leftovers-selected-size")

            Spacer(minLength: DesignTokens.Spacing.small)

            Button("Deselect All", action: viewModel.deselectAll)
                .accessibilityIdentifier("leftovers-deselect-all")
            Button("Dry Run", systemImage: "doc.text.magnifyingglass", action: viewModel.performDryRun)
                .disabled(viewModel.selectedItems.isEmpty)
                .accessibilityIdentifier("leftovers-dry-run")
            Button(
                "Move \(viewModel.selectedItems.count) to Trash",
                systemImage: "trash",
                action: { confirmation.requestConfirmation(for: viewModel.selectedItems) }
            )
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedItems.isEmpty)
            .accessibilityIdentifier("leftovers-move-to-trash")
        }
        .buttonStyle(.bordered)
        .tersoCard(padding: DesignTokens.Spacing.small)
    }

    @ViewBuilder
    private var outcome: some View {
        if let report = viewModel.report {
            switch report {
            case let .dryRun(itemCount, bytes):
                let size = SizeCalculator.formattedByteCount(bytes)
                StatusMessage(
                    text: String(
                        localized: "Dry run: \(itemCount) items, \(size) would move to Trash. Nothing was changed."
                    ),
                    systemImage: "doc.text.magnifyingglass"
                )
            case let .trashed(itemCount, bytes):
                let size = SizeCalculator.formattedByteCount(bytes)
                StatusMessage(
                    text: String(localized: "Moved \(itemCount) items (\(size)) to Trash."),
                    systemImage: "trash"
                )
            }
        }
        if !viewModel.rejections.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                StatusMessage(
                    text: String(localized: "Some items were refused and left untouched. See the audit log."),
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
                ForEach(viewModel.rejections) { rejection in
                    Text("\(rejection.path) — \(rejection.message)")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .tersoCard()
            .accessibilityIdentifier("leftovers-rejections")
        }
    }

    private var itemList: some View {
        List(viewModel.items) { item in
            LeftoverRowView(
                item: item,
                homeDirectory: viewModel.homeDirectory,
                reason: viewModel.reasons[item.id],
                isSelected: Binding(
                    get: { viewModel.isSelected(item) },
                    set: { viewModel.setSelected($0, for: item) }
                )
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("leftovers-item-list")
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { confirmation.isPresented },
            set: { isPresented in
                if !isPresented {
                    confirmation.cancel()
                }
            }
        )
    }
}

/// One leftover: path, why it was found, size and an unchecked-by-default box.
private struct LeftoverRowView: View {
    let item: CleanItem
    let homeDirectory: URL
    let reason: String?
    let isSelected: Binding<Bool>

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxSmall) {
                Text(displayPath)
                    .font(DesignTokens.Typography.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.url.path)
                if let reason {
                    Text(reason)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: DesignTokens.Spacing.small)

            Text(SizeCalculator.formattedByteCount(item.sizeBytes))
                .font(DesignTokens.Typography.rowFigure.weight(.medium))
                .frame(minWidth: 72, alignment: .trailing)

            Toggle("Select \(item.url.lastPathComponent)", isOn: isSelected)
                .labelsHidden()
                .accessibilityLabel("Select \(item.url.lastPathComponent)")
        }
        .padding(DesignTokens.Spacing.small)
        .background(
            isSelected.wrappedValue ? DesignTokens.Palette.brandWash : DesignTokens.Palette.rowFill,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
        )
    }

    private var displayPath: String {
        let path = item.url.standardizedFileURL.path
        let home = homeDirectory.standardizedFileURL.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
