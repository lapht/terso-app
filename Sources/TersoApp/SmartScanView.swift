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
    @StateObject private var viewModel: SmartScanViewModel
    @State private var selectedModuleID: String?
    @State private var cleanupError: String?
    private let onViewAuditLog: () -> Void

    init(
        tccManager: TCCManager = TCCManager(),
        onViewAuditLog: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: SmartScanViewModel(tccManager: tccManager))
        self.onViewAuditLog = onViewAuditLog
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        scanControls
                        scanContent
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .frame(minHeight: geometry.size.height)
            }
        }
        .alert(
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Smart Scan", systemImage: "sparkles")
                .font(.largeTitle.weight(.semibold))
                .accessibilityIdentifier("smart-scan-title")

            Text("Review cleanup candidates from Terso's available modules in one place.")
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
            Button(viewModel.state == .idle ? "Scan" : "Scan Again", systemImage: "sparkles") {
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
        Group {
            if let summary = viewModel.moduleSummaries.first(where: { $0.id == selectedModuleID }) {
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
                    onBack: { selectedModuleID = nil }
                )
                .id(summary.id)
            } else {
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
