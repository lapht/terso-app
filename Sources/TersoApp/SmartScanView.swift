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
struct SmartScanView: View {
    /// Owned by the shell so scan results survive switching sidebar destinations.
    @ObservedObject private var viewModel: SmartScanViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedModuleID: String?
    @State private var cleanupError: String?
    private let title: String
    private let systemImage: String
    private let description: String
    private let onViewAuditLog: () -> Void

    /// A view model created with specific `modules` scopes the page to those modules.
    init(
        title: String = "Smart Scan",
        systemImage: String = "sparkles",
        description: String = "Review cleanup candidates from Terso's available modules in one place.",
        viewModel: SmartScanViewModel,
        onViewAuditLog: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.onViewAuditLog = onViewAuditLog
    }

    var body: some View {
        page.alert(
            "Unable to Move Items to Trash",
            isPresented: Binding(
                get: { cleanupError != nil },
                set: { isPresented in
                    if !isPresented {
                        cleanupError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                cleanupError = nil
            }
        } message: {
            if let cleanupError {
                Text(cleanupError)
            }
        }
    }

    /// A selected module replaces the overview, so its item list is the page's only scroll.
    @ViewBuilder
    private var page: some View {
        if let summary = selectedModuleSummary {
            ModuleDetailView(
                title: summary.title,
                systemImage: SidebarDestination(moduleID: summary.id)?.symbol ?? systemImage,
                items: viewModel.items(for: summary.id),
                homeDirectory: viewModel.homeDirectory,
                selectionViewModel: viewModel.selectionViewModel(for: summary.id),
                onMoveToTrash: { items in
                    do {
                        try viewModel.moveToTrash(items: items)
                        selectedModuleID = nil
                    } catch {
                        cleanupError = error.localizedDescription
                    }
                },
                onBack: { selectedModuleID = nil },
                backTitle: "Back to \(title)"
            )
            .id(summary.id)
        } else {
            PageScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xLarge) {
                    header
                    scanControls
                    scanContent
                }
                .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, alignment: .leading)
                .animation(DesignTokens.Motion.standard(reduceMotion: reduceMotion), value: viewModel.state)
            }
        }
    }

    private var selectedModuleSummary: SmartScanModuleSummary? {
        guard viewModel.cleanupResult == nil, viewModel.state == .finished else {
            return nil
        }
        return viewModel.moduleSummaries.first { $0.id == selectedModuleID }
    }

    private var header: some View {
        PageHeader(
            title: title,
            systemImage: systemImage,
            description: description,
            titleIdentifier: "smart-scan-title"
        ) {
            StatusMessage(
                text: "Scanning is designed to only read files. Nothing is moved to Trash "
                    + "until you review the results and confirm.",
                systemImage: "checkmark.shield",
                tone: .brand
            )
            .padding(.top, DesignTokens.Spacing.xxSmall)
        }
    }

    @ViewBuilder
    private var scanControls: some View {
        if viewModel.state == .scanning {
            scanningProgress
            Button("Cancel", systemImage: "xmark.circle") {
                viewModel.cancelScan()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("smart-scan-cancel")
        } else {
            Button(viewModel.state == .idle ? "Scan" : "Scan Again", systemImage: systemImage) {
                selectedModuleID = nil
                viewModel.startScan()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("smart-scan-start")
        }
    }

    private var scanningProgress: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(scanningModuleMessage)
                .font(DesignTokens.Typography.sectionTitle)
                .accessibilityIdentifier("smart-scan-current-module")

            ProgressView(value: viewModel.progress?.fractionCompleted ?? 0, total: 1)
                .progressViewStyle(.linear)
                .tint(DesignTokens.Palette.accent)
                .animation(
                    DesignTokens.Motion.standard(reduceMotion: reduceMotion),
                    value: viewModel.progress?.fractionCompleted
                )
                .accessibilityIdentifier("smart-scan-progress")

            HStack(spacing: DesignTokens.Spacing.large) {
                Label("\(viewModel.progress?.itemsFound ?? 0) items found", systemImage: "doc")
                Label(
                    "\(SizeCalculator.formattedByteCount(viewModel.progress?.bytesFound ?? 0)) reclaimable",
                    systemImage: "internaldrive"
                )
            }
            .font(DesignTokens.Typography.metadata.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .tersoCard()
    }

    private var scanningModuleMessage: String {
        if viewModel.activeModuleTitles.isEmpty {
            return "Preparing available modules…"
        }
        return "Scanning \(viewModel.activeModuleTitles.joined(separator: ", "))…"
    }

    @ViewBuilder
    private var scanContent: some View {
        if let cleanupResult = viewModel.cleanupResult {
            CleanResultView(
                result: cleanupResult,
                warnings: viewModel.cleanupWarnings,
                onScanAgain: {
                    selectedModuleID = nil
                    viewModel.startScan()
                },
                onViewAuditLog: {
                    onViewAuditLog()
                }
            )
        } else {
            switch viewModel.state {
            case .idle:
                EmptyStateView(
                    systemImage: "drop",
                    title: "Ready when you are",
                    message: "Your files stay as they are until you review the scan results and choose what to do."
                )
            case .scanning:
                EmptyView()
            case .finished:
                finishedResults
            case .cancelled:
                StatusMessage(text: "Scan cancelled. No files were changed.", systemImage: "pause.circle")
            case .failed(let message):
                StatusMessage(
                    text: "Scan failed: \(message)",
                    systemImage: "exclamationmark.triangle",
                    tone: .error
                )
            }
        }
    }

    private var deletableItemCount: Int {
        viewModel.result?.items.filter(\.isDeletable).count ?? 0
    }

    private var finishedResults: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            if deletableItemCount == 0 {
                EmptyStateView(
                    systemImage: "checkmark.seal",
                    title: "Nothing to clean right now",
                    message: "This scan found no items that match Terso's rules."
                )
            } else {
                ReclaimableSummaryView(
                    title: "Potentially reclaimable",
                    totalBytes: viewModel.reclaimableBytes,
                    itemCount: deletableItemCount,
                    segments: viewModel.moduleSummaries.map {
                        BreakdownSegment(id: $0.id, title: $0.title, bytes: $0.bytesFound)
                    },
                    sizeIdentifier: "smart-scan-reclaimable-size"
                )
            }

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: DesignTokens.Layout.cardMinWidth),
                        spacing: DesignTokens.Spacing.small
                    )
                ],
                spacing: DesignTokens.Spacing.small
            ) {
                ForEach(viewModel.moduleSummaries) { summary in
                    Button {
                        selectedModuleID = summary.id
                    } label: {
                        moduleCard(summary)
                    }
                    .buttonStyle(.plain)
                    .disabled(summary.status != .completed)
                    .accessibilityIdentifier("module-card-\(summary.id)")
                }
            }
        }
    }

    private func moduleCard(_ summary: SmartScanModuleSummary) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
            HStack(spacing: DesignTokens.Spacing.xSmall) {
                Image(systemName: SidebarDestination(moduleID: summary.id)?.symbol ?? "folder")
                    .foregroundStyle(DesignTokens.Palette.brandText)
                    .accessibilityHidden(true)
                Text(summary.title)
                    .font(DesignTokens.Typography.sectionTitle)
                Spacer(minLength: 0)
                if summary.status == .completed {
                    Image(systemName: "chevron.right")
                        .font(DesignTokens.Typography.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            Text(SizeCalculator.formattedByteCount(summary.bytesFound))
                .font(DesignTokens.Typography.figure)
            Text("\(summary.itemsFound) \(summary.itemsFound == 1 ? "item" : "items")")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)

            switch summary.status {
            case .completed:
                EmptyView()
            case .requiresPermission(let message):
                StatusMessage(text: message, systemImage: "lock", font: DesignTokens.Typography.caption)
            case .failed(let message):
                StatusMessage(
                    text: message,
                    systemImage: "exclamationmark.triangle",
                    tone: .error,
                    font: DesignTokens.Typography.caption
                )
            case .notScanned:
                EmptyView()
            }
        }
        .tersoCard()
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }
}

private struct SmartScanPreviewTCCAccessChecker: TCCAccessChecking {
    let status: TCCStatus

    func fullDiskAccessStatus() -> TCCStatus {
        status
    }
}

struct SmartScanView_Previews: PreviewProvider {
    static var previews: some View {
        SmartScanView(
            viewModel: SmartScanViewModel(
                tccManager: TCCManager(accessChecker: SmartScanPreviewTCCAccessChecker(status: .granted))
            )
        )
        .frame(width: 760, height: 560)
    }
}
