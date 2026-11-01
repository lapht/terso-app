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
import Testing

@testable import TersoApp

struct ManageSeparatelyViewModelTests {
    @MainActor
    @Test func creatingTheViewModelDoesNotScan() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let viewModel = ManageSeparatelyViewModel(
            scanner: ManageSeparatelyScanner(environment: [:], applicationDirectories: []),
            homeDirectory: home
        )

        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.phase == .idle)
        #expect(viewModel.report.items.isEmpty)
    }

    @MainActor
    @Test func scanFindsItemsAndOffersNothingToSelect() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let models = home.appendingPathComponent(".ollama/models")
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8_192).write(to: models.appendingPathComponent("blob"))
        let viewModel = ManageSeparatelyViewModel(
            scanner: ManageSeparatelyScanner(environment: [:], applicationDirectories: []),
            homeDirectory: home
        )

        viewModel.startScan()
        #expect(viewModel.phase == .scanning)
        for _ in 0..<200 where viewModel.phase != .finished {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(viewModel.phase == .finished)
        #expect(viewModel.report.items.map(\.kind) == [.ollamaModels])
        #expect(viewModel.totalBytes == viewModel.report.items[0].sizeBytes)
        // The files are untouched: the scan is read-only.
        #expect(FileManager.default.fileExists(atPath: models.appendingPathComponent("blob").path))
    }

    @Test func everyKindHasLossAndRemovalGuidance() {
        for kind in ManagedItemKind.allCases {
            #expect(!kind.title.isEmpty)
            #expect(!kind.lossExplanation.isEmpty)
            #expect(!kind.removalGuidance.isEmpty)
        }
    }

    private static func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-manage-vm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home.resolvingSymlinksInPath()
    }
}
