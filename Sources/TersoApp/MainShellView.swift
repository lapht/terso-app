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

struct MainShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: SidebarDestination? = .smartScan
    @State private var tccStatus: TCCStatus

    private let tccManager: TCCManager

    init(tccManager: TCCManager = TCCManager()) {
        self.tccManager = tccManager
        _tccStatus = State(initialValue: tccManager.status)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            VStack(alignment: .leading, spacing: 20) {
                if tccStatus != .granted {
                    TCCBannerView(status: tccStatus)
                }

                destinationView
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 460)
        .onAppear(perform: refreshTCCStatus)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                refreshTCCStatus()
            }
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        if selection == .smartScan {
            SmartScanView(tccManager: tccManager)
        } else if let selection {
            VStack(alignment: .leading, spacing: 12) {
                Label(selection.title, systemImage: selection.symbol)
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityIdentifier("detail-title")

                Text(selection.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 640, alignment: .leading)
        } else {
            Label("Select a module", systemImage: "sidebar.left")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshTCCStatus() {
        tccStatus = tccManager.status
    }
}

private struct PreviewTCCAccessChecker: TCCAccessChecking {
    let status: TCCStatus

    func fullDiskAccessStatus() -> TCCStatus {
        status
    }
}

struct MainShellView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MainShellView(
                tccManager: TCCManager(accessChecker: PreviewTCCAccessChecker(status: .denied))
            )
            .previewDisplayName("Full Disk Access unavailable")
            MainShellView(
                tccManager: TCCManager(accessChecker: PreviewTCCAccessChecker(status: .granted))
            )
            .previewDisplayName("Full Disk Access granted")
        }
    }
}
