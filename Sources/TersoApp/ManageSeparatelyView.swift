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

import AppKit
import CoreKit
import SwiftUI

extension ManagedItemKind {
    var title: String {
        switch self {
        case .ollamaModels:
            String(localized: "Ollama models")
        case .huggingFaceCache:
            String(localized: "Hugging Face cache")
        case .lmStudioModels:
            String(localized: "LM Studio models")
        case .iosBackup:
            String(localized: "iPhone or iPad backup")
        case .virtualMachine:
            String(localized: "Virtual machine")
        case .dockerDesktopDisk:
            String(localized: "Docker Desktop disk")
        case .macOSInstaller:
            String(localized: "macOS installer")
        }
    }

    /// What is lost if the item is removed.
    var lossExplanation: String {
        switch self {
        case .ollamaModels:
            String(localized: "Downloaded models are removed. You can download them again with ollama pull.")
        case .huggingFaceCache:
            String(
                localized: """
                    Cached models and datasets are removed. \
                    They are downloaded again when a tool needs them.
                    """
            )
        case .lmStudioModels:
            String(localized: "Downloaded models are removed. You can download them again from LM Studio.")
        case .iosBackup:
            String(
                localized: """
                    This backup cannot be recreated if the device is lost \
                    or erased. It is not re-downloadable.
                    """
            )
        case .virtualMachine:
            String(
                localized: """
                    The virtual machine and everything installed inside it \
                    is lost. It is not re-downloadable.
                    """
            )
        case .dockerDesktopDisk:
            String(localized: "All Docker images, containers and volumes are lost. Volumes cannot be re-downloaded.")
        case .macOSInstaller:
            String(
                localized: """
                    The installer is removed. You can download it again \
                    from the App Store or Software Update.
                    """
            )
        }
    }

    /// The owning tool's recommended way to remove the item.
    var removalGuidance: String {
        switch self {
        case .ollamaModels:
            String(localized: "Run “ollama rm” with the model name in Terminal.")
        case .huggingFaceCache:
            String(localized: "Run “hf cache rm” (or “huggingface-cli delete-cache”) in Terminal.")
        case .lmStudioModels:
            String(localized: "In LM Studio, open My Models and delete the model.")
        case .iosBackup:
            String(localized: "In Finder, select your device, then choose Manage Backups.")
        case .virtualMachine:
            String(localized: "Delete it from the virtual machine app that created it (UTM, Parallels or VMware).")
        case .dockerDesktopDisk:
            String(localized: "Run “docker system prune” or use Docker Desktop > Troubleshoot > Clean / Purge data.")
        case .macOSInstaller:
            String(localized: "Quit the installer, then drag it to the Trash in Finder.")
        }
    }
}

/// Read-only. The scan starts only when the user asks, and no item can be selected or removed here.
@MainActor
struct ManageSeparatelyView: View {
    @ObservedObject private var viewModel: ManageSeparatelyViewModel

    init(viewModel: ManageSeparatelyViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScanStateView(
            title: SidebarDestination.manageSeparately.title,
            systemImage: SidebarDestination.manageSeparately.symbol,
            description: SidebarDestination.manageSeparately.description,
            phase: viewModel.phase,
            currentModule: SidebarDestination.manageSeparately.title,
            onScan: viewModel.startScan,
            onCancel: viewModel.cancelScan
        ) {
            results
        }
    }

    private var totalSize: String {
        SizeCalculator.formattedByteCount(viewModel.totalBytes)
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                PageHeader(
                    title: SidebarDestination.manageSeparately.title,
                    systemImage: SidebarDestination.manageSeparately.symbol,
                    description: SidebarDestination.manageSeparately.description
                )
                Text("Items found: \(viewModel.report.items.count) (\(totalSize))")
                    .font(DesignTokens.Typography.sectionTitle)
                if viewModel.report.items.isEmpty && viewModel.report.notScanned.isEmpty {
                    StatusMessage(
                        text: String(localized: "Nothing to manage separately was found."),
                        systemImage: "checkmark.circle"
                    )
                }
                ForEach(viewModel.report.items) { item in
                    ManagedItemCard(item: item)
                }
                if !viewModel.report.notScanned.isEmpty {
                    Text("Not scanned")
                        .font(DesignTokens.Typography.sectionTitle)
                    ForEach(viewModel.report.notScanned) { entry in
                        StatusMessage(
                            text: "\(entry.kind.title) — \(entry.url.path): \(entry.reason)",
                            systemImage: "lock"
                        )
                    }
                }
                Button("Scan Again", systemImage: "arrow.clockwise", action: viewModel.startScan)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, alignment: .leading)
        }
    }
}

private struct ManagedItemCard: View {
    let item: ManagedItem

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
            HStack {
                Text(item.kind.title)
                    .font(DesignTokens.Typography.sectionTitle)
                Spacer()
                Text(SizeCalculator.formattedByteCount(item.sizeBytes))
                    .font(DesignTokens.Typography.rowFigure)
            }
            Text(item.url.path)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let modified = item.lastModified {
                Text("Last modified \(modified.formatted(date: .abbreviated, time: .omitted))")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Text(item.kind.lossExplanation)
                .font(DesignTokens.Typography.metadata)
            Text(item.kind.removalGuidance)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Button("Reveal in Finder", systemImage: "magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            .buttonStyle(.link)
        }
        .tersoCard()
        .accessibilityElement(children: .contain)
    }
}
