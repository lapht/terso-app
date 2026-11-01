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

struct OldFilesViewModelTests {
    private func item(_ category: OldFileCategory, _ name: String, _ bytes: Int64) -> OldFileItem {
        OldFileItem(
            category: category,
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            sizeBytes: bytes,
            reason: "r",
            referenceDate: Date(),
            dateSignal: .modified
        )
    }

    @Test func groupsAreOrderedByCategoryWithTotalsAndLargestFirst() {
        let report = OldFilesReport(
            items: [
                item(.archive, "a.zip", 10),
                item(.screenshot, "s1.png", 5),
                item(.screenshot, "s2.png", 50)
            ],
            notScanned: [],
            skippedDatalessCount: 0
        )

        let groups = report.groups

        #expect(groups.map(\.category) == [.screenshot, .archive])
        #expect(groups[0].items.map(\.sizeBytes) == [50, 5])
        #expect(groups[0].totalBytes == 55)
    }

    @MainActor
    @Test func creatingTheViewModelDoesNotScan() async throws {
        let viewModel = OldFilesViewModel(homeDirectory: FileManager.default.temporaryDirectory)

        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.phase == .idle)
        #expect(viewModel.report.items.isEmpty)
    }

    @MainActor
    @Test func scanFindsOldInstallerAndLeavesItUntouched() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-oldfiles-vm-\(UUID().uuidString)").resolvingSymlinksInPath()
        let downloads = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = downloads.appendingPathComponent("old.dmg")
        try Data(repeating: 1, count: 4_096).write(to: installer)
        let viewModel = OldFilesViewModel(
            scanner: OldFilesScanner(
                minimumAge: 0,
                screenshotFolder: home.appendingPathComponent("Desktop"),
                metadata: StubMetadata()
            ),
            homeDirectory: home
        )

        viewModel.startScan()
        for _ in 0..<200 where viewModel.phase != .finished {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(viewModel.phase == .finished)
        #expect(viewModel.report.items.map(\.category) == [.installer])
        #expect(viewModel.totalBytes == viewModel.report.items[0].sizeBytes)
        #expect(FileManager.default.fileExists(atPath: installer.path))
    }

    @Test func everyCategoryAndDateSignalHasATitle() {
        for category in OldFileCategory.allCases {
            #expect(!category.title.isEmpty)
        }
        #expect(!OldFileDateSignal.lastUsed.title.isEmpty)
        #expect(!OldFileDateSignal.modified.title.isEmpty)
    }
}

private struct StubMetadata: OldFileMetadataReading {
    func isDataless(_ url: URL) -> Bool { false }
    func lastUsedDate(of url: URL) -> Date? { nil }
    func isScreenCapture(_ url: URL) -> Bool? { nil }
    func imageOrigin(of url: URL) -> OldFileImageOrigin { .unreadable }
}
