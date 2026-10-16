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

/// Large Files never scans on appear: the user starts it. The view model is owned by the shell,
/// so a running or finished scan survives switching to another page; only Cancel stops it.
@MainActor
struct LargeFilesView: View {
    @ObservedObject private var viewModel: LargeFilesViewModel

    init(viewModel: LargeFilesViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScanStateView(
            title: SidebarDestination.largeFiles.title,
            systemImage: "doc.text.magnifyingglass",
            description: String(
                localized: """
                    Find large files in your home folder. This scanner is read-only: \
                    you can reveal files in Finder, but Terso does not remove them from here.
                    """
            ),
            phase: viewModel.phase,
            currentModule: viewModel.moduleTitle,
            onScan: viewModel.startScan,
            onCancel: viewModel.cancelScan
        ) {
            ModuleDetailView(
                title: SidebarDestination.largeFiles.title,
                systemImage: SidebarDestination.largeFiles.symbol,
                items: viewModel.items,
                homeDirectory: viewModel.homeDirectory,
                allowsSelection: false,
                onMoveToTrash: { _ in }
            )
        }
    }
}
