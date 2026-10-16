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
    /// Owned by the app, not the pages, so each page's last scan survives switching destinations
    /// and the menu bar launches the same Smart Scan the window shows.
    @ObservedObject private var coordinator: MenuBarScanCoordinator

    private var scanSessions: ScanSessionStore { coordinator.scanSessions }
    private let tccManager: TCCManager

    init(coordinator: MenuBarScanCoordinator, tccManager: TCCManager = TCCManager()) {
        self.coordinator = coordinator
        self.tccManager = tccManager
        _tccStatus = State(initialValue: tccManager.status)
    }

    init(tccManager: TCCManager = TCCManager()) {
        self.init(
            coordinator: MenuBarScanCoordinator(scanSessions: ScanSessionStore(tccManager: tccManager)),
            tccManager: tccManager
        )
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
        .onChange(of: coordinator.focusRequestCount) { _ in
            selection = .smartScan
            refreshTCCStatus()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                refreshTCCStatus()
            }
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        if selection == .smartScan {
            SmartScanView(viewModel: scanSessions.smartScan) {
                selection = .auditLogs
            }
        } else if selection == .leftovers {
            ToolScanView(destination: .leftovers, viewModel: scanSessions.leftovers)
        } else if selection == .duplicates {
            DuplicatesView(viewModel: scanSessions.duplicates)
        } else if selection == .largeFiles {
            LargeFilesView(viewModel: scanSessions.largeFiles)
        } else if selection == .auditLogs {
            AuditLogView()
        } else if let selection,
            let moduleScanView = ModuleScanView(
                destination: selection,
                scanSessions: scanSessions,
                onViewAuditLog: { self.selection = .auditLogs }
            ) {
            // Each module page keeps its own scan state instead of reusing the previous module's.
            moduleScanView.id(selection)
        } else {
            EmptyStateView(
                systemImage: "sidebar.left",
                title: String(localized: "Select a module"),
                message: String(localized: "Choose Smart Scan or a module in the sidebar to get started.")
            )
            .frame(maxWidth: DesignTokens.Layout.contentMaxWidth)
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
