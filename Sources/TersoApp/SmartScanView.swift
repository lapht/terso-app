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
                VStack(alignment: .leading, spacing: 24) {
                    header
                    scanControls
                    scanContent
                }
                .frame(maxWidth: 720, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.largeTitle.weight(.semibold))
                .accessibilityIdentifier("smart-scan-title")

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(
                "Scanning is completely safe: it only reads files and never changes or deletes them.",
                systemImage: "checkmark.shield"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: 12) {
            ProgressView(value: viewModel.progress?.fractionCompleted ?? 0, total: 1)
                .progressViewStyle(.linear)
                .animation(.easeInOut(duration: 0.25), value: viewModel.progress?.fractionCompleted)
                .accessibilityIdentifier("smart-scan-progress")

            Text(scanningModuleMessage)
                .font(.headline)
                .accessibilityIdentifier("smart-scan-current-module")

            HStack(spacing: 20) {
                Label("\(viewModel.progress?.itemsFound ?? 0) items found", systemImage: "doc")
                Label(
                    "\(SizeCalculator.formattedByteCount(viewModel.progress?.bytesFound ?? 0)) reclaimable",
                    systemImage: "internaldrive"
                )
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
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
                Text("Your files stay untouched until you review scan results and choose what to do.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .scanning:
                EmptyView()
            case .finished:
                finishedResults
            case .cancelled:
                Label("Scan cancelled. No files were changed.", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Label("Scan failed: \(message)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var finishedResults: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Potentially reclaimable")
                    .font(.headline)
                Text(SizeCalculator.formattedByteCount(viewModel.reclaimableBytes))
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("smart-scan-reclaimable-size")
                Text("\(viewModel.result?.items.filter(\.isDeletable).count ?? 0) items found")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
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
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.title)
                .font(.headline)
            Text(SizeCalculator.formattedByteCount(summary.bytesFound))
                .font(.title3.weight(.medium))
            Text("\(summary.itemsFound) \(summary.itemsFound == 1 ? "item" : "items")")
                .font(.callout)
                .foregroundStyle(.secondary)

            switch summary.status {
            case .completed:
                EmptyView()
            case .requiresPermission(let message):
                Label(message, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            case .notScanned:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
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
