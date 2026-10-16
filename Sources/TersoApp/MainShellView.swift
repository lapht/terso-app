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

@MainActor
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
            PageContainer(tccStatus: tccStatus) {
                destinationView
            }
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
            SmartScanView(tccManager: tccManager) {
                selection = .auditLogs
            }
        } else if selection == .largeFiles {
            LargeFilesView(tccManager: tccManager)
        } else if selection == .auditLogs {
            AuditLogView()
        } else if let selection,
            let moduleScanView = ModuleScanView(
                destination: selection,
                tccManager: tccManager,
                onViewAuditLog: { self.selection = .auditLogs }
            ) {
            // Each module page keeps its own scan state instead of reusing the previous module's.
            moduleScanView.id(selection)
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
