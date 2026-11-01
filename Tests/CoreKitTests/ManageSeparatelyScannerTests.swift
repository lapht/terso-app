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

import Foundation
import Testing
@testable import CoreKit

struct ManageSeparatelyScannerTests {
    private final class Fixture {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("terso-manage-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        deinit {
            // Restore permissions a test may have removed, then clean up.
            if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                }
            }
            try? FileManager.default.removeItem(at: root)
        }

        @discardableResult
        func file(_ path: String, bytes: Int = 4_096, under base: URL? = nil) throws -> URL {
            let url = (base ?? home).appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(repeating: 1, count: bytes).write(to: url)
            return url
        }
    }

    private func kinds(_ report: ManageSeparatelyReport) -> [ManagedItemKind] {
        report.items.map(\.kind)
    }

    @Test func emptyHomeFindsNothing() throws {
        let fixture = try Fixture()
        let report = ManageSeparatelyScanner(environment: [:], applicationDirectories: [])
            .scan(homeDirectory: fixture.home)
        #expect(report.items.isEmpty)
        #expect(report.notScanned.isEmpty)
    }

    @Test func findsDefaultLocationsOfEveryKind() throws {
        let fixture = try Fixture()
        try fixture.file(".ollama/models/blobs/sha256-a")
        try fixture.file(".cache/huggingface/hub/models--x/blobs/b")
        try fixture.file(".lmstudio/models/org/model.gguf")
        try fixture.file("Library/Application Support/MobileSync/Backup/UDID-1/Manifest.db")
        try fixture.file("Virtual Machines/linux.utm/Data/disk.img")
        try fixture.file("Parallels/win.pvm/disk.hdd")
        try fixture.file("Virtual Machines.localized/mac.vmwarevm/disk.vmdk")
        try fixture.file("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        let apps = fixture.root.appendingPathComponent("Applications")
        try fixture.file("Install macOS Sequoia.app/Contents/Info.plist", under: apps)
        try fixture.file("Safari.app/Contents/Info.plist", under: apps)

        let report = ManageSeparatelyScanner(environment: [:], applicationDirectories: [apps])
            .scan(homeDirectory: fixture.home)

        #expect(Set(kinds(report)) == Set(ManagedItemKind.allCases))
        #expect(report.items.filter { $0.kind == .virtualMachine }.count == 3)
        #expect(report.items.allSatisfy { $0.sizeBytes > 0 && $0.lastModified != nil })
        #expect(report.notScanned.isEmpty)
        let installer = try #require(report.items.first { $0.kind == .macOSInstaller })
        #expect(installer.url.lastPathComponent == "Install macOS Sequoia.app")
    }

    @Test func eachBackupIsListedSeparately() throws {
        let fixture = try Fixture()
        let backups = "Library/Application Support/MobileSync/Backup"
        try fixture.file("\(backups)/A/Manifest.db")
        try fixture.file("\(backups)/B/Manifest.db")
        try fixture.file("\(backups)/stray.txt")

        let report = ManageSeparatelyScanner(environment: [:], applicationDirectories: [])
            .scan(homeDirectory: fixture.home)

        #expect(report.items.map(\.url.lastPathComponent).sorted() == ["A", "B"])
    }

    @Test func honorsOllamaAndHuggingFaceEnvironmentVariables() throws {
        let fixture = try Fixture()
        let ollama = try fixture.file("external/ollama/blobs/x", under: fixture.root)
        try fixture.file("hf/hub/models--y/blobs/y", under: fixture.root)
        // Defaults must be ignored when a custom path is configured and the default is empty.
        let environment = [
            "OLLAMA_MODELS": fixture.root.appendingPathComponent("external/ollama").path,
            "HF_HOME": fixture.root.appendingPathComponent("hf").path
        ]

        let report = ManageSeparatelyScanner(environment: environment, applicationDirectories: [])
            .scan(homeDirectory: fixture.home)

        let paths = Set(report.items.map(\.url.path))
        #expect(paths == [
            fixture.root.appendingPathComponent("external/ollama").path,
            fixture.root.appendingPathComponent("hf/hub").path
        ])
        #expect(ollama.path.hasPrefix(fixture.root.path))
    }

    @Test func hfHubCacheTakesPrecedenceOverHfHome() throws {
        let fixture = try Fixture()
        try fixture.file("hubcache/models--z/blobs/z", under: fixture.root)
        try fixture.file("hf/hub/models--y/blobs/y", under: fixture.root)
        let environment = [
            "HF_HUB_CACHE": fixture.root.appendingPathComponent("hubcache").path,
            "HF_HOME": fixture.root.appendingPathComponent("hf").path
        ]

        let report = ManageSeparatelyScanner(environment: environment, applicationDirectories: [])
            .scan(homeDirectory: fixture.home)

        #expect(report.items.map(\.url.path) == [fixture.root.appendingPathComponent("hubcache").path])
    }

    @Test func readsLMStudioConfiguredFolder() throws {
        let fixture = try Fixture()
        let custom = fixture.root.appendingPathComponent("lm-custom")
        try fixture.file("m/model.gguf", under: custom)
        try fixture.file(".lmstudio/settings.json", bytes: 0)
        let settings = fixture.home.appendingPathComponent(".lmstudio/settings.json")
        try Data("{\"downloadsFolder\": \"\(custom.path)\"}".utf8).write(to: settings)

        let report = ManageSeparatelyScanner(environment: [:], applicationDirectories: [])
            .scan(homeDirectory: fixture.home)

        #expect(report.items.map(\.url.path) == [custom.path])
        #expect(report.items.first?.kind == .lmStudioModels)
    }

    @Test func sizeIsSumOfFilesAndSortedLargestFirst() throws {
        let fixture = try Fixture()
        try fixture.file(".ollama/models/a", bytes: 8_192)
        try fixture.file(".ollama/models/b", bytes: 8_192)
        try fixture.file(".cache/huggingface/hub/c", bytes: 4_096)

        let report = ManageSeparatelyScanner(environment: [:], applicationDirectories: [])
            .scan(homeDirectory: fixture.home)

        #expect(kinds(report) == [.ollamaModels, .huggingFaceCache])
        #expect(report.items[0].sizeBytes >= 16_384)
    }

    @Test func unreadableLocationIsReportedAsNotScanned() throws {
        let fixture = try Fixture()
        let backups = "Library/Application Support/MobileSync/Backup"
        try fixture.file("\(backups)/A/Manifest.db")
        let directory = fixture.home.appendingPathComponent(backups)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)

        let report = ManageSeparatelyScanner(environment: [:], applicationDirectories: [])
            .scan(homeDirectory: fixture.home)

        #expect(report.items.isEmpty)
        let entry = try #require(report.notScanned.first)
        #expect(entry.kind == .iosBackup)
        #expect(entry.url.path == directory.path)
        #expect(entry.reason.contains("Permission denied"))
    }

    @Test func symlinkedChildrenAreNotFollowed() throws {
        let fixture = try Fixture()
        let outside = fixture.root.appendingPathComponent("outside/other.utm")
        try fixture.file("disk.img", under: outside)
        let vms = fixture.home.appendingPathComponent("Virtual Machines")
        try FileManager.default.createDirectory(at: vms, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: vms.appendingPathComponent("link.utm"),
            withDestinationURL: outside
        )

        let report = ManageSeparatelyScanner(environment: [:], applicationDirectories: [])
            .scan(homeDirectory: fixture.home)

        #expect(report.items.isEmpty)
    }

    @Test func redownloadabilityMatchesKind() {
        #expect(ManagedItemKind.ollamaModels.isRedownloadable)
        #expect(ManagedItemKind.macOSInstaller.isRedownloadable)
        #expect(!ManagedItemKind.iosBackup.isRedownloadable)
        #expect(!ManagedItemKind.virtualMachine.isRedownloadable)
        #expect(!ManagedItemKind.dockerDesktopDisk.isRedownloadable)
    }
}
