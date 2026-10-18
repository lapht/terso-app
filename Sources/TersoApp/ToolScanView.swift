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
/// With a `review` model the results can be selected and moved to Trash through the Safety
/// pipeline (#37); without one they stay read-only.
@MainActor
struct ToolScanView: View {
    @ObservedObject private var viewModel: ToolScanViewModel
    private let destination: SidebarDestination
    private let review: LeftoversViewModel?

    init(destination: SidebarDestination, viewModel: ToolScanViewModel, review: LeftoversViewModel? = nil) {
        self.destination = destination
        self.viewModel = viewModel
        self.review = review
    }

    var body: some View {
        ScanStateView(
            title: destination.title,
            systemImage: destination.symbol,
            description: destination.description,
            phase: viewModel.phase,
            currentModule: viewModel.tool.title,
            isScanEnabled: viewModel.isScanAvailable,
            unavailableNote: String(
                localized: "Detection for \(viewModel.tool.title) is not available in this build yet."
            ),
            onScan: viewModel.startScan,
            onCancel: viewModel.cancelScan
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                if viewModel.isPartial {
                    partialNotice
                }
                if let review {
                    LeftoversReviewView(
                        title: destination.title,
                        systemImage: destination.symbol,
                        viewModel: review
                    )
                } else {
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
        .onChange(of: viewModel.phase) { phase in
            if phase == .finished {
                review?.load(items: viewModel.items, reasons: viewModel.reasons)
            }
        }
    }

    private var partialNotice: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            StatusMessage(
                text: String(
                    localized: "Partial results: some areas were not scanned, so this list may be incomplete."
                ),
                systemImage: "exclamationmark.circle",
                tone: .warning
            )
            ForEach(viewModel.notScanned, id: \.name) { area in
                StatusMessage(
                    text: area.needsFullDiskAccess
                        ? String(localized: "\(area.name) — needs Full Disk Access")
                        : String(localized: "\(area.name) — could not be read"),
                    systemImage: area.needsFullDiskAccess ? "lock" : "questionmark.circle"
                )
            }
        }
        .tersoCard()
        .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, alignment: .leading)
    }
}
