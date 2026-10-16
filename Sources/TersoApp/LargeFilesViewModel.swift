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
import Foundation

/// Runs the Large Files scan only when asked; a scan never outlives its screen.
@MainActor
final class LargeFilesViewModel: ObservableObject {
    @Published private(set) var phase: ScanPhase = .idle
    @Published private(set) var items: [CleanItem] = []

    let homeDirectory: URL
    private let module: any CleanModule
    private let tccManager: TCCManager
    private var scanTask: Task<Void, Never>?

    init(
        module: any CleanModule = LargeFilesModule(),
        tccManager: TCCManager = TCCManager(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.module = module
        self.tccManager = tccManager
        self.homeDirectory = homeDirectory
    }

    var moduleTitle: String { module.title }

    func startScan() {
        guard scanTask == nil else {
            return
        }
        items = []
        phase = .scanning

        let module = self.module
        let tccManager = self.tccManager
        let context = ScanContext(homeDirectory: homeDirectory)
        scanTask = Task { [weak self] in
            let outcome: ScanPhase
            var found: [CleanItem] = []
            do {
                switch try await tccManager.scan(module: module, context: context) {
                case .completed(let scanned):
                    found = scanned
                    outcome = .finished
                case .requiresPermission(let message):
                    outcome = .requiresPermission(message)
                }
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            guard let self else {
                return
            }
            self.items = found
            self.phase = outcome
            self.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }
}
