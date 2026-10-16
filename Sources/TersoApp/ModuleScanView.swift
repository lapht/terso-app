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

extension SidebarDestination {
    /// The cleanup module a sidebar entry scans on its own, or `nil` for pages that are not modules.
    var cleanModule: (any CleanModule)? {
        switch self {
        case .userCaches:
            UserCachesModule()
        case .userLogs:
            UserLogsModule()
        case .trashBins:
            TrashBinsModule()
        case .xcodeJunk:
            XcodeJunkModule()
        case .packageCaches:
            PackageCachesModule()
        case .smartScan, .largeFiles, .auditLogs:
            nil
        }
    }

    /// The sidebar entry for a CoreKit module id, so cards and detail pages reuse its title and icon.
    init?(moduleID: String) {
        switch moduleID {
        case "caches.user":
            self = .userCaches
        case "logs.user":
            self = .userLogs
        case "trash.user":
            self = .trashBins
        case "xcode.junk":
            self = .xcodeJunk
        case "caches.packages":
            self = .packageCaches
        case "files.large":
            self = .largeFiles
        default:
            return nil
        }
    }
}

/// A single module's page: the Smart Scan flow scoped to one module, so scanning, review,
/// confirmation and Trash all go through the same view model and Safety pipeline.
@MainActor
struct ModuleScanView: View {
    private let destination: SidebarDestination
    private let viewModel: SmartScanViewModel
    private let onViewAuditLog: () -> Void

    /// The view model comes from `scanSessions`, so the module's last scan survives navigation.
    init?(
        destination: SidebarDestination,
        scanSessions: ScanSessionStore,
        onViewAuditLog: @escaping () -> Void = {}
    ) {
        guard let viewModel = scanSessions.moduleScan(for: destination) else {
            return nil
        }
        self.destination = destination
        self.viewModel = viewModel
        self.onViewAuditLog = onViewAuditLog
    }

    var body: some View {
        SmartScanView(
            title: destination.title,
            systemImage: destination.symbol,
            description: destination.description,
            viewModel: viewModel,
            onViewAuditLog: onViewAuditLog
        )
    }
}

private struct ModuleScanPreviewTCCAccessChecker: TCCAccessChecking {
    let status: TCCStatus

    func fullDiskAccessStatus() -> TCCStatus {
        status
    }
}

struct ModuleScanView_Previews: PreviewProvider {
    static var previews: some View {
        ModuleScanView(
            destination: .userCaches,
            scanSessions: ScanSessionStore(
                tccManager: TCCManager(accessChecker: ModuleScanPreviewTCCAccessChecker(status: .granted))
            )
        )
        .frame(width: 760, height: 560)
    }
}
