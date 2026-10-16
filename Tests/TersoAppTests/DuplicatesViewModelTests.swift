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

import CoreKit
import Foundation
import Testing

@testable import TersoApp

struct DuplicatesViewModelTests {
    @MainActor
    @Test func creatingTheViewModelDoesNotScanAndNeedsFolders() async throws {
        let viewModel = DuplicatesViewModel(scanner: FixedScanner(result: Self.emptyResult))

        try await Task.sleep(for: .milliseconds(30))
        viewModel.startScan()

        #expect(viewModel.phase == .idle)
        #expect(!viewModel.canScan)
    }

    @MainActor
    @Test func foldersAreDeduplicatedAndRemovable() {
        let viewModel = DuplicatesViewModel(scanner: FixedScanner(result: Self.emptyResult))
        let folder = URL(fileURLWithPath: "/tmp/a", isDirectory: true)

        viewModel.addRoots([folder, folder])
        #expect(viewModel.roots.count == 1)
        viewModel.removeRoot(folder)
        #expect(viewModel.roots.isEmpty)
    }

    @MainActor
    @Test func detailsMatchTheFinderOutputExactly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let big = Data(repeating: 7, count: 4_096)
        let first = try fixture.write("a/report.bin", big)
        let second = try fixture.write("b/report copy.bin", big)
        _ = try fixture.write("c/unique.bin", Data(repeating: 9, count: 4_096))

        let finder = DuplicateFinder()
        let expected = try await finder.scan(roots: [fixture.root])
        let viewModel = DuplicatesViewModel(scanner: finder, homeDirectory: fixture.root)
        viewModel.addRoots([fixture.root])

        viewModel.startScan()
        try await waitForFinished(viewModel)

        let summary = viewModel.summary
        #expect(summary.groups.count == expected.groups.count)
        let paths = Set(summary.groups.flatMap { $0.copies.map(\.url.path) })
        #expect(paths == Set(expected.groups.flatMap { $0.files.map(\.url.path) }))
        // /var and /private/var spell the same temp folder, so compare by file name.
        let names = Set(paths.map { URL(fileURLWithPath: $0).lastPathComponent })
        #expect(names == [first.lastPathComponent, second.lastPathComponent])
        #expect(summary.totalReclaimableBytes == expected.totalReclaimableBytes)
        #expect(summary.groups.first?.fileSizeBytes == 4_096)
        #expect(summary.groups.first?.copies.allSatisfy { $0.sizeBytes == 4_096 && $0.modificationDate != nil } == true)
        #expect(summary.examinedFileCount == expected.examinedFileCount)
    }

    @MainActor
    @Test func issuesSkippedFilesAndMissingMetadataStayVisible() async throws {
        let url = URL(fileURLWithPath: "/tmp/gone.bin")
        let result = DuplicateScanResult(
            groups: [DuplicateGroup(
                contentHash: "abc",
                fileSizeBytes: 100,
                files: [DuplicateFile(url: url, isClone: false), DuplicateFile(url: url, isClone: true)]
            )],
            examinedFileCount: 5,
            skippedDatalessFileCount: 2,
            issues: [DuplicateScanIssue(path: "/tmp/x", message: "Permission denied")],
            isCancelled: false
        )
        let viewModel = DuplicatesViewModel(scanner: FixedScanner(result: result), modificationDate: { _ in nil })
        viewModel.addRoots([URL(fileURLWithPath: "/tmp", isDirectory: true)])

        viewModel.startScan()
        try await waitForFinished(viewModel)

        #expect(viewModel.summary.isPartial)
        #expect(viewModel.summary.skippedDatalessFileCount == 2)
        #expect(viewModel.summary.issues.count == 1)
        #expect(viewModel.summary.groups[0].copies.allSatisfy { $0.modificationDate == nil })
        #expect(viewModel.summary.groups[0].reclaimableBytes == 0)
        #expect(DuplicatePathFormatter.modificationText(nil) == "Modification date unavailable")
    }

    @MainActor
    @Test func scannerErrorMovesToFailed() async throws {
        let viewModel = DuplicatesViewModel(scanner: FailingScanner())
        viewModel.addRoots([URL(fileURLWithPath: "/tmp", isDirectory: true)])

        viewModel.startScan()
        for _ in 0..<100 where viewModel.phase == .scanning {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.phase == .failed(DuplicateScanError.noRoots.localizedDescription))
    }

    private static let emptyResult = DuplicateScanResult(
        groups: [],
        examinedFileCount: 0,
        skippedDatalessFileCount: 0,
        issues: [],
        isCancelled: false
    )

    @MainActor
    private func waitForFinished(_ viewModel: DuplicatesViewModel) async throws {
        for _ in 0..<300 where viewModel.phase != .finished {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(viewModel.phase == .finished)
    }
}

private struct FixedScanner: DuplicateScanning {
    let result: DuplicateScanResult

    func scan(roots: [URL]) async throws -> DuplicateScanResult {
        result
    }
}

private struct FailingScanner: DuplicateScanning {
    func scan(roots: [URL]) async throws -> DuplicateScanResult {
        throw DuplicateScanError.noRoots
    }
}

private struct Fixture {
    let root: URL

    init() throws {
        let created = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-dupview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
        root = created.resolvingSymlinksInPath()
    }

    func write(_ relativePath: String, _ data: Data) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
