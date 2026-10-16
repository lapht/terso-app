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

import SwiftUI

/// Lifecycle of a user-started scan, shared by every screen that scans on demand.
enum ScanPhase: Equatable {
    case idle
    case scanning
    case finished
    case cancelled
    case failed(String)
    case requiresPermission(String)
}

/// Idle / scanning / failed / permission chrome around a scan; `content` is shown once finished.
///
/// Nothing here starts a scan: the owner does it from `onScan`, which only the button calls.
struct ScanStateView<Content: View>: View {
    let title: String
    let systemImage: String
    let description: String
    let phase: ScanPhase
    var currentModule: String?
    var progress: Double?
    /// False when the owner has nothing to run yet; the button is disabled and `unavailableNote` says why.
    var isScanEnabled = true
    var unavailableNote: String?
    let onScan: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if phase == .finished {
            content()
        } else {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                PageHeader(title: title, systemImage: systemImage, description: description)
                controls
            }
            .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, alignment: .leading)
            .animation(DesignTokens.Motion.standard(reduceMotion: reduceMotion), value: phase)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch phase {
        case .idle:
            if !isScanEnabled, let unavailableNote {
                StatusMessage(text: unavailableNote, systemImage: "info.circle")
            }
            scanButton("Scan")
        case .scanning:
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text(currentModule.map { "Scanning \($0)…" } ?? "Preparing scan…")
                    .font(DesignTokens.Typography.sectionTitle)
                if let progress {
                    ProgressView(value: progress, total: 1)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
            .tint(DesignTokens.Palette.accent)
            .tersoCard()
            Button("Cancel", systemImage: "xmark.circle", action: onCancel)
                .buttonStyle(.bordered)
        case .cancelled:
            StatusMessage(text: "Scan cancelled. No files were changed.", systemImage: "pause.circle")
            scanButton("Scan Again")
        case .failed(let message):
            StatusMessage(text: "Scan failed: \(message)", systemImage: "exclamationmark.triangle", tone: .error)
            scanButton("Scan Again")
        case .requiresPermission(let message):
            StatusMessage(text: message, systemImage: "lock")
            scanButton("Scan Again")
        case .finished:
            EmptyView()
        }
    }

    private func scanButton(_ label: String) -> some View {
        Button(label, systemImage: systemImage, action: onScan)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isScanEnabled)
    }
}

struct ScanStateView_Previews: PreviewProvider {
    static var previews: some View {
        let phases: [(String, ScanPhase)] = [
            ("Idle", .idle),
            ("Scanning", .scanning),
            ("Finished", .finished),
            ("Cancelled", .cancelled),
            ("Failed", .failed("Unable to read the home directory.")),
            ("Requires permission", .requiresPermission("Enable Terso in Full Disk Access."))
        ]
        ForEach(phases, id: \.0) { name, phase in
            ScanStateView(
                title: "Large Files",
                systemImage: "doc.text.magnifyingglass",
                description: "Find big files in your home folder. Scanning only reads files.",
                phase: phase,
                currentModule: "Large Files",
                onScan: {},
                onCancel: {},
                content: { Text("Results go here") }
            )
            .padding(24)
            .frame(width: 520, height: 280, alignment: .topLeading)
            .previewDisplayName(name)
        }
    }
}
