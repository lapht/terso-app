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
        title: String = SidebarDestination.smartScan.title,
        systemImage: String = "sparkles",
        description: String = SidebarDestination.smartScan.description,
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
                title: displayTitle(for: summary),
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
                backTitle: String(localized: "Back to \(title)")
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
                text: String(
                    localized: """
                        Scanning is designed to only read files. Nothing is moved to Trash \
                        until you review the results and confirm.
                        """
                ),
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
            Button(
                viewModel.state == .idle ? String(localized: "Scan") : String(localized: "Scan Again"),
                systemImage: systemImage
            ) {
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
            return String(localized: "Preparing available modules…")
        }
        let titles = viewModel.activeModuleTitles.formatted(.list(type: .and, width: .narrow))
        return String(localized: "Scanning \(titles)…")
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
                    title: String(localized: "Ready when you are"),
                    message: String(
                        localized: """
                            Your files stay as they are until you review the scan results \
                            and choose what to do.
                            """
                    )
                )
            case .scanning:
                EmptyView()
            case .finished:
                finishedResults
            case .cancelled:
                StatusMessage(
                    text: String(localized: "Scan cancelled. No files were changed."),
                    systemImage: "pause.circle"
                )
            case .failed(let message):
                StatusMessage(
                    text: String(localized: "Scan failed: \(message)"),
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
                    title: String(localized: "Nothing to clean right now"),
                    message: String(localized: "This scan found no items that match Terso's rules.")
                )
            } else {
                ReclaimableSummaryView(
                    title: String(localized: "Potentially reclaimable"),
                    totalBytes: viewModel.reclaimableBytes,
                    itemCount: deletableItemCount,
                    segments: viewModel.moduleSummaries.map {
                        BreakdownSegment(id: $0.id, title: displayTitle(for: $0), bytes: $0.bytesFound)
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

    /// Module titles come from CoreKit in English; the sidebar owns their localized names.
    private func displayTitle(for summary: SmartScanModuleSummary) -> String {
        SidebarDestination(moduleID: summary.id)?.title ?? summary.title
    }

    private func moduleCard(_ summary: SmartScanModuleSummary) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
            HStack(spacing: DesignTokens.Spacing.xSmall) {
                Image(systemName: SidebarDestination(moduleID: summary.id)?.symbol ?? "folder")
                    .foregroundStyle(DesignTokens.Palette.brandText)
                    .accessibilityHidden(true)
                Text(displayTitle(for: summary))
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
            Text("\(summary.itemsFound) items")
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
