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

struct ItemRowView: View {
    let item: CleanItem
    let homeDirectory: URL
    let isSelected: Binding<Bool>?
    let allowsSelection: Bool

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.small) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: DesignTokens.Layout.rowIconSize, height: DesignTokens.Layout.rowIconSize)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxSmall) {
                Text(item.url.lastPathComponent)
                    .font(DesignTokens.Typography.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.url.lastPathComponent)

                Text(relativePath)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(relativePath)
            }

            Spacer(minLength: DesignTokens.Spacing.small)

            Text(SizeCalculator.formattedByteCount(item.sizeBytes))
                .font(DesignTokens.Typography.rowFigure.weight(.medium))
                .foregroundStyle(isRowSelected ? DesignTokens.Palette.brandText : Color.primary)
                .frame(minWidth: 72, alignment: .trailing)

            if allowsSelection, item.isDeletable, !item.isProtected, let isSelected {
                Toggle("Select \(item.url.lastPathComponent)", isOn: isSelected)
                    .labelsHidden()
                    .accessibilityLabel("Select \(item.url.lastPathComponent)")
            } else {
                revealButton
            }
        }
        .padding(DesignTokens.Spacing.small)
        .background(
            isRowSelected ? DesignTokens.Palette.brandWash : DesignTokens.Palette.rowFill,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.row)
                .strokeBorder(isRowSelected ? DesignTokens.Palette.brandStroke : .clear, lineWidth: 1)
        }
        .contextMenu {
            Button("Reveal in Finder", systemImage: "magnifyingglass") {
                revealInFinder()
            }
        }
    }

    private var isRowSelected: Bool {
        allowsSelection && (isSelected?.wrappedValue ?? false)
    }

    private var relativePath: String {
        let path = item.url.standardizedFileURL.path
        let homePath = homeDirectory.standardizedFileURL.path
        if path == homePath {
            return "~"
        }
        if path.hasPrefix(homePath + "/") {
            return "~" + path.dropFirst(homePath.count)
        }
        return String(path.dropFirst()).isEmpty ? "/" : String(path.dropFirst())
    }

    private var revealButton: some View {
        Button("Reveal in Finder", systemImage: "magnifyingglass") {
            revealInFinder()
        }
        .labelStyle(.iconOnly)
        .help("Reveal in Finder")
        .accessibilityLabel("Reveal \(item.url.lastPathComponent) in Finder")
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}

struct ItemRowView_Previews: PreviewProvider {
    private static let homeDirectory = URL(fileURLWithPath: "/Users/preview", isDirectory: true)
    private static let item: CleanItem = {
        let url = homeDirectory.appendingPathComponent("Library/Caches/com.example.preview")
        return CleanItem(
            url: url,
            resolvedURL: url,
            sizeBytes: 48_000_000,
            moduleId: "user-caches",
            ruleId: "preview.rule"
        )
    }()

    static var previews: some View {
        Group {
            ItemRowView(
                item: item,
                homeDirectory: homeDirectory,
                isSelected: .constant(true),
                allowsSelection: true
            )
            .previewDisplayName("Selectable")
            ItemRowView(
                item: item,
                homeDirectory: homeDirectory,
                isSelected: nil,
                allowsSelection: false
            )
            .previewDisplayName("Read-only")
        }
        .padding()
        .frame(width: 560)
    }
}
