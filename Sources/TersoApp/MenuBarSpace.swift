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

/// Polls the boot volume's free space. Informational only: it never starts a scan or a cleanup.
@MainActor
final class MenuBarSpaceModel: ObservableObject {
    @Published private(set) var display: VolumeSpaceDisplay

    private let provider: any VolumeSpaceProviding

    init(provider: any VolumeSpaceProviding = VolumeSpaceProvider(), refreshInterval: TimeInterval = 60) {
        self.provider = provider
        display = VolumeSpaceDisplay(state: provider.currentState())
        // Ends by itself once the weak model is gone.
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
                guard let self else {
                    return
                }
                self.refresh()
            }
        }
    }

    func refresh() {
        display = VolumeSpaceDisplay(state: provider.currentState())
    }
}

struct MenuBarSpaceLabel: View {
    @ObservedObject var model: MenuBarSpaceModel

    var body: some View {
        Label(
            model.display.title,
            systemImage: model.display.isError ? "exclamationmark.triangle" : "internaldrive"
        )
        .accessibilityLabel(model.display.accessibilityLabel)
    }
}

struct MenuBarSpaceContent: View {
    static let mainWindowID = "main"

    @ObservedObject var model: MenuBarSpaceModel
    @ObservedObject var scanCoordinator: MenuBarScanCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.display.detail)
        Divider()
        // Read-only scan: opens the window on Smart Scan and never starts a cleanup.
        Button(scanCoordinator.isScanning ? "Smart Scan Running…" : "Run Smart Scan") {
            scanCoordinator.launchSmartScan()
            openWindow(id: Self.mainWindowID)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        if let status = scanCoordinator.statusText {
            Text(status)
        }
        Divider()
        Button("Refresh") { model.refresh() }
        Button("Quit Terso") { NSApplication.shared.terminate(nil) }
    }
}
