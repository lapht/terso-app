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

enum SidebarDestination: String, CaseIterable, Identifiable {
    case smartScan
    case userCaches
    case userLogs
    case trashBins
    case xcodeJunk
    case packageCaches
    case largeFiles
    case auditLogs

    var id: Self { self }

    var title: String {
        switch self {
        case .smartScan:
            "Smart Scan"
        case .userCaches:
            "User Caches"
        case .userLogs:
            "User Logs"
        case .trashBins:
            "Trash Bins"
        case .xcodeJunk:
            "Xcode Junk"
        case .packageCaches:
            "Package Caches"
        case .largeFiles:
            "Large Files"
        case .auditLogs:
            "Audit Logs"
        }
    }

    var symbol: String {
        switch self {
        case .smartScan:
            "sparkles"
        case .userCaches:
            "externaldrive"
        case .userLogs:
            "doc.text"
        case .trashBins:
            "trash"
        case .xcodeJunk:
            "hammer"
        case .packageCaches:
            "shippingbox"
        case .largeFiles:
            "doc.magnifyingglass"
        case .auditLogs:
            "list.bullet.rectangle"
        }
    }

    var description: String {
        switch self {
        case .smartScan:
            "Review cleanup candidates from Terso's available modules in one place."
        case .userCaches:
            "Find rebuildable caches in your user Library, excluding caches used by running apps."
        case .userLogs:
            "Find older rotated logs while avoiding files that are currently open for writing."
        case .trashBins:
            "Review items in your Trash, including supported mounted volumes."
        case .xcodeJunk:
            "Find rebuildable Xcode and simulator data."
        case .packageCaches:
            "Review known Homebrew, npm, Yarn, and pnpm download caches."
        case .largeFiles:
            "Find large files in your home folder. This scanner is read-only."
        case .auditLogs:
            "Review local records of cleanup activity."
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarDestination?

    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarDestination.allCases) { destination in
                Label(destination.title, systemImage: destination.symbol)
                    .tag(destination)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Terso")
        .accessibilityIdentifier("navigation-sidebar")
    }
}

struct SidebarView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationSplitView {
            SidebarView(selection: .constant(.smartScan))
        } detail: {
            Text("Select a module")
        }
    }
}
