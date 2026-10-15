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
struct LargeFilesView: View {
    @State private var items: [CleanItem]?
    @State private var failureMessage: String?

    private let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

    var body: some View {
        Group {
            if let items {
                ModuleDetailView(
                    title: "Large Files",
                    items: items,
                    homeDirectory: homeDirectory,
                    allowsSelection: false,
                    onMoveToTrash: { _ in }
                )
            } else if let failureMessage {
                Label("Scan failed: \(failureMessage)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView("Scanning for large files…")
            }
        }
        .task {
            await scan()
        }
    }

    private func scan() async {
        do {
            items = try await LargeFilesModule().scan(
                context: ScanContext(homeDirectory: homeDirectory)
            )
        } catch is CancellationError {
            return
        } catch {
            failureMessage = error.localizedDescription
        }
    }
}
