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

/// Page for a tool that scans only on an explicit user action (Leftovers).
/// Results are read-only here: moving to Trash arrives with #37.
@MainActor
struct ToolScanView: View {
    @ObservedObject private var viewModel: ToolScanViewModel
    private let destination: SidebarDestination

    init(destination: SidebarDestination, viewModel: ToolScanViewModel) {
        self.destination = destination
        self.viewModel = viewModel
    }

    var body: some View {
        ScanStateView(
            title: destination.title,
            systemImage: destination.symbol,
            description: destination.description,
            phase: viewModel.phase,
            currentModule: viewModel.tool.title,
            isScanEnabled: viewModel.isScanAvailable,
            unavailableNote: "Detection for \(viewModel.tool.title) is not available in this build yet.",
            onScan: viewModel.startScan,
            onCancel: viewModel.cancelScan
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                if viewModel.isPartial {
                    partialNotice
                }
                ModuleDetailView(
                    title: destination.title,
                    systemImage: destination.symbol,
                    items: viewModel.items,
                    homeDirectory: viewModel.homeDirectory,
                    allowsSelection: false,
                    onMoveToTrash: { _ in }
                )
            }
        }
    }

    private var partialNotice: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            StatusMessage(
                text: "Partial results: some areas were not scanned, so this list may be incomplete.",
                systemImage: "exclamationmark.circle",
                tone: .warning
            )
            ForEach(viewModel.notScanned, id: \.name) { area in
                StatusMessage(
                    text: area.needsFullDiskAccess
                        ? "\(area.name) — needs Full Disk Access"
                        : "\(area.name) — could not be read",
                    systemImage: area.needsFullDiskAccess ? "lock" : "questionmark.circle"
                )
            }
        }
        .tersoCard()
        .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, alignment: .leading)
    }
}
