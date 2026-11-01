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
import QuickLook
import SwiftUI

extension OldFileCategory {
    var title: String {
        switch self {
        case .screenshot:
            String(localized: "Screenshots")
        case .screenRecording:
            String(localized: "Screen recordings")
        case .installer:
            String(localized: "Installers")
        case .archive:
            String(localized: "Archives")
        }
    }
}

extension OldFileDateSignal {
    var title: String {
        switch self {
        case .lastUsed:
            String(localized: "Last used")
        case .modified:
            String(localized: "Modified (approximate)")
        }
    }
}

/// Read-only. The scan starts only when the user asks; there is no selection and no action button.
@MainActor
struct OldFilesView: View {
    @ObservedObject private var viewModel: OldFilesViewModel

    init(viewModel: OldFilesViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScanStateView(
            title: SidebarDestination.oldFiles.title,
            systemImage: SidebarDestination.oldFiles.symbol,
            description: SidebarDestination.oldFiles.description,
            phase: viewModel.phase,
            currentModule: SidebarDestination.oldFiles.title,
            onScan: viewModel.startScan,
            onCancel: viewModel.cancelScan
        ) {
            OldFilesResultsView(report: viewModel.report, onScanAgain: viewModel.startScan)
        }
    }
}

struct OldFilesResultsView: View {
    let report: OldFilesReport
    var onScanAgain: () -> Void = {}

    @State private var previewURL: URL?

    private var totalSize: String {
        SizeCalculator.formattedByteCount(report.items.reduce(0) { $0 + $1.sizeBytes })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                PageHeader(
                    title: SidebarDestination.oldFiles.title,
                    systemImage: SidebarDestination.oldFiles.symbol,
                    description: SidebarDestination.oldFiles.description
                )
                Text("Items found: \(report.items.count) (\(totalSize))")
                    .font(DesignTokens.Typography.sectionTitle)
                if report.items.isEmpty && report.notScanned.isEmpty && report.skippedDatalessCount == 0 {
                    StatusMessage(
                        text: String(localized: "No old files were found."),
                        systemImage: "checkmark.circle"
                    )
                }
                ForEach(report.groups) { group in
                    OldFilesGroupView(group: group) { previewURL = $0 }
                }
                skipped
                Button("Scan Again", systemImage: "arrow.clockwise", action: onScanAgain)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, alignment: .leading)
        }
        .quickLookPreview($previewURL)
    }

    @ViewBuilder
    private var skipped: some View {
        if !report.notScanned.isEmpty || report.skippedDatalessCount > 0 {
            Text("Not scanned")
                .font(DesignTokens.Typography.sectionTitle)
            if report.skippedDatalessCount > 0 {
                StatusMessage(
                    text: String(
                        localized: "\(report.skippedDatalessCount) items stored only in iCloud were skipped."
                    ),
                    systemImage: "icloud"
                )
            }
            ForEach(report.notScanned) { entry in
                StatusMessage(text: "\(entry.url.path): \(entry.reason)", systemImage: "lock")
            }
        }
    }
}

private struct OldFilesGroupView: View {
    let group: OldFilesGroup
    let onQuickLook: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack {
                Text(group.category.title)
                    .font(DesignTokens.Typography.sectionTitle)
                Spacer()
                Text("\(group.items.count) items · \(SizeCalculator.formattedByteCount(group.totalBytes))")
                    .font(DesignTokens.Typography.rowFigure)
            }
            .accessibilityElement(children: .combine)
            ForEach(group.items) { item in
                OldFileRow(item: item, onQuickLook: onQuickLook)
            }
        }
        .tersoCard()
        .accessibilityElement(children: .contain)
    }
}

private struct OldFileRow: View {
    let item: OldFileItem
    let onQuickLook: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
            HStack {
                Text(item.url.lastPathComponent)
                    .font(DesignTokens.Typography.metadata)
                Spacer()
                Text(SizeCalculator.formattedByteCount(item.sizeBytes))
                    .font(DesignTokens.Typography.rowFigure)
            }
            Text(item.url.path)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(item.reason)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
            Text("\(item.dateSignal.title): \(item.referenceDate.formatted(date: .abbreviated, time: .omitted))")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Quick Look", systemImage: "eye") { onQuickLook(item.url) }
                Button("Reveal in Finder", systemImage: "magnifyingglass") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
            }
            .buttonStyle(.link)
        }
        .accessibilityElement(children: .contain)
    }
}

struct OldFilesView_Previews: PreviewProvider {
    private static func item(_ category: OldFileCategory, _ name: String, _ bytes: Int64) -> OldFileItem {
        OldFileItem(
            category: category,
            url: URL(fileURLWithPath: "/Users/preview/Downloads/\(name)"),
            sizeBytes: bytes,
            reason: "Installer (.dmg)",
            referenceDate: Date(timeIntervalSinceNow: -400 * 86_400),
            dateSignal: .lastUsed
        )
    }

    static var previews: some View {
        OldFilesResultsView(report: OldFilesReport(items: [], notScanned: [], skippedDatalessCount: 0))
            .previewDisplayName("Empty")
        OldFilesResultsView(
            report: OldFilesReport(
                items: [item(.installer, "App.dmg", 80_000_000)],
                notScanned: [
                    OldFilesNotScanned(
                        url: URL(fileURLWithPath: "/Users/preview/Desktop"),
                        reason: "Not scanned: permission denied"
                    )
                ],
                skippedDatalessCount: 3
            )
        )
        .previewDisplayName("Partial permission")
        OldFilesResultsView(
            report: OldFilesReport(
                items: [
                    item(.installer, "App.dmg", 80_000_000),
                    item(.archive, "backup.zip", 1_200_000_000),
                    item(.screenshot, "Screenshot.png", 900_000)
                ],
                notScanned: [],
                skippedDatalessCount: 0
            )
        )
        .previewDisplayName("Populated")
    }
}
