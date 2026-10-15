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
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.url.lastPathComponent)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .help(item.url.lastPathComponent)

                Text(relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(relativePath)
            }

            Spacer(minLength: 12)

            Text(SizeCalculator.formattedByteCount(item.sizeBytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            if allowsSelection, item.isDeletable, !item.isProtected, let isSelected {
                Toggle("Select \(item.url.lastPathComponent)", isOn: isSelected)
                    .labelsHidden()
                    .accessibilityLabel("Select \(item.url.lastPathComponent)")
            } else {
                revealButton
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button("Reveal in Finder", systemImage: "magnifyingglass") {
                revealInFinder()
            }
        }
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
