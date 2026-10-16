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

/// Duplicates never scans on appear: the user picks folders and starts it. Results are read-only,
/// like Large Files: groups and copies can be inspected and revealed in Finder, nothing more.
@MainActor
struct DuplicatesView: View {
    @ObservedObject private var viewModel: DuplicatesViewModel

    init(viewModel: DuplicatesViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        let destination = SidebarDestination.duplicates
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
            ScanStateView(
                title: destination.title,
                systemImage: destination.symbol,
                description: destination.description,
                phase: viewModel.phase,
                currentModule: "Duplicates",
                isScanEnabled: viewModel.canScan,
                unavailableNote: "Choose at least one folder to scan.",
                onScan: viewModel.startScan,
                onCancel: viewModel.cancelScan
            ) {
                DuplicatesResultsView(
                    summary: viewModel.summary,
                    homeDirectory: viewModel.homeDirectory,
                    onScanAgain: viewModel.chooseFoldersAgain
                )
            }
            if viewModel.phase != .scanning, viewModel.phase != .finished {
                folderChoice
            }
        }
        .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, maxHeight: .infinity, alignment: .topLeading)
    }

    private var folderChoice: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Folders to scan")
                .font(DesignTokens.Typography.sectionTitle)
            ForEach(viewModel.roots, id: \.path) { root in
                HStack {
                    Image(systemName: "folder")
                        .accessibilityHidden(true)
                    Text(DuplicatePathFormatter.displayPath(root, homeDirectory: viewModel.homeDirectory))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(root.path)
                    Spacer(minLength: DesignTokens.Spacing.small)
                    Button("Remove", systemImage: "minus.circle") {
                        viewModel.removeRoot(root)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(root.lastPathComponent) from the folders to scan")
                }
            }
            Button("Add Folder…", systemImage: "folder.badge.plus", action: chooseFolders)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("duplicates-add-folder")
        }
        .tersoCard()
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose the folders to search for identical files. Terso only reads them."
        if panel.runModal() == .OK {
            viewModel.addRoots(panel.urls)
        }
    }
}

enum DuplicatePathFormatter {
    static func displayPath(_ url: URL, homeDirectory: URL) -> String {
        let path = url.standardizedFileURL.path
        let homePath = homeDirectory.standardizedFileURL.path
        if path == homePath {
            return "~"
        }
        if path.hasPrefix(homePath + "/") {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }

    /// "Modified 3 Mar 2026", or an explicit note when the file's date could not be read.
    static func modificationText(_ date: Date?) -> String {
        guard let date else {
            return "Modification date unavailable"
        }
        return "Modified " + date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Group list plus everything the scan skipped or failed on (invariant 7: never silently scan less).
@MainActor
struct DuplicatesResultsView: View {
    let summary: DuplicateScanSummary
    let homeDirectory: URL
    let onScanAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            PageHeader(
                title: "Duplicates",
                systemImage: SidebarDestination.duplicates.symbol,
                description: "Read-only — copies can only be revealed in Finder."
            )
            summaryCard
            if summary.groups.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.seal",
                    title: "No duplicates found",
                    message: "No identical files were found in the folders that were scanned."
                )
            } else {
                groupList
            }
        }
        .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, maxHeight: .infinity, alignment: .topLeading)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxSmall) {
                    Text(SizeCalculator.formattedByteCount(summary.totalReclaimableBytes))
                        .font(DesignTokens.Typography.figure)
                        .foregroundStyle(DesignTokens.Palette.brandText)
                    Text("\(summary.groups.count) groups · estimated reclaimable, clones excluded")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("duplicates-total")
                Spacer(minLength: DesignTokens.Spacing.small)
                Button("Choose Folders Again", systemImage: "folder", action: onScanAgain)
                    .buttonStyle(.bordered)
            }
            if summary.isCancelled {
                StatusMessage(
                    text: "Partial results: the scan was cancelled before every file was compared.",
                    systemImage: "exclamationmark.circle",
                    tone: .warning
                )
            }
            if summary.skippedDatalessFileCount > 0 {
                StatusMessage(
                    text: "\(summary.skippedDatalessFileCount) cloud files were skipped because they are not "
                        + "downloaded. Terso never downloads them.",
                    systemImage: "icloud.slash"
                )
            }
        }
        .tersoCard(padding: DesignTokens.Spacing.small)
    }

    private var groupList: some View {
        List {
            Section {
                ForEach(summary.groups) { group in
                    DuplicateGroupRowView(group: group, homeDirectory: homeDirectory)
                        .listRowSeparator(.hidden)
                }
            }
            if !summary.issues.isEmpty {
                Section {
                    ForEach(summary.issues, id: \.self) { issue in
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxSmall) {
                            Text(DuplicatePathFormatter.displayPath(
                                URL(fileURLWithPath: issue.path),
                                homeDirectory: homeDirectory
                            ))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(issue.path)
                            Text(issue.message)
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    StatusMessage(
                        text: "\(summary.issues.count) files could not be read and are not in any group.",
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("duplicates-group-list")
    }
}

private struct DuplicateGroupRowView: View {
    let group: DuplicateGroupRow
    let homeDirectory: URL

    var body: some View {
        DisclosureGroup {
            ForEach(group.copies) { copy in
                DuplicateCopyRowView(copy: copy, homeDirectory: homeDirectory)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxSmall) {
                    Text(group.copies.first?.url.lastPathComponent ?? "Duplicate group")
                        .font(DesignTokens.Typography.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(group.copyCount) copies · \(SizeCalculator.formattedByteCount(group.fileSizeBytes)) each")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: DesignTokens.Spacing.small)
                Text(SizeCalculator.formattedByteCount(group.reclaimableBytes))
                    .font(DesignTokens.Typography.rowFigure.weight(.medium))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(group.copies.first?.url.lastPathComponent ?? "Duplicate group"), \(group.copyCount) copies, "
                    + "\(SizeCalculator.formattedByteCount(group.fileSizeBytes)) each, "
                    + "\(SizeCalculator.formattedByteCount(group.reclaimableBytes)) reclaimable"
            )
        }
    }
}

private struct DuplicateCopyRowView: View {
    let copy: DuplicateCopy
    let homeDirectory: URL

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxSmall) {
                Text(copy.url.lastPathComponent)
                    .font(DesignTokens.Typography.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(copy.url.lastPathComponent)
                Text(DuplicatePathFormatter.displayPath(copy.url, homeDirectory: homeDirectory))
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(copy.url.path)
                Text(
                    SizeCalculator.formattedByteCount(copy.sizeBytes) + " · "
                        + DuplicatePathFormatter.modificationText(copy.modificationDate)
                        + (copy.isClone ? " · APFS clone, shares storage" : "")
                )
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: DesignTokens.Spacing.small)
            Button("Reveal in Finder", systemImage: "magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting([copy.url])
            }
            .labelStyle(.iconOnly)
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal \(copy.url.lastPathComponent) in Finder")
        }
        .contextMenu {
            Button("Reveal in Finder", systemImage: "magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting([copy.url])
            }
        }
        .accessibilityElement(children: .contain)
    }
}
