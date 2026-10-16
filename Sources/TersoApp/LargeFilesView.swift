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
    @Environment(\.scenePhase) private var scenePhase
    @State private var items: [CleanItem]?
    @State private var failureMessage: String?
    @State private var permissionMessage: String?

    private let tccManager: TCCManager

    init(tccManager: TCCManager = TCCManager()) {
        self.tccManager = tccManager
    }

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
            } else if let permissionMessage {
                Label(permissionMessage, systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("large-files-requires-fda")
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
        .onChange(of: scenePhase) { newPhase in
            // Rescan on return to the app only if FDA was missing, so a grant is picked up.
            if newPhase == .active, permissionMessage != nil {
                Task { await scan() }
            }
        }
    }

    private func scan() async {
        do {
            let result = try await tccManager.scan(
                module: LargeFilesModule(),
                context: ScanContext(homeDirectory: homeDirectory)
            )
            switch result {
            case let .completed(scanned):
                permissionMessage = nil
                failureMessage = nil
                items = scanned
            case let .requiresPermission(message):
                permissionMessage = message
            }
        } catch is CancellationError {
            return
        } catch {
            failureMessage = error.localizedDescription
        }
    }
}
