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

/// Metadata stub keyed by file name so tests do not depend on Spotlight or iCloud.
private struct StubMetadata: OldFileMetadataReading {
    var dataless: Set<String> = []
    var lastUsed: [String: Date] = [:]
    var screenCapture: [String: Bool] = [:]
    var origin: [String: OldFileImageOrigin] = [:]

    func isDataless(_ url: URL) -> Bool {
        dataless.contains(url.lastPathComponent)
    }

    func lastUsedDate(of url: URL) -> Date? {
        lastUsed[url.lastPathComponent]
    }

    func isScreenCapture(_ url: URL) -> Bool? {
        screenCapture[url.lastPathComponent]
    }

    func imageOrigin(of url: URL) -> OldFileImageOrigin {
        origin[url.lastPathComponent] ?? .unreadable
    }
}

struct OldFilesScannerTests {
    private static let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private final class Fixture {
        let root: URL
        var home: URL { root.appendingPathComponent("home") }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("terso-oldfiles-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        deinit {
            if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                }
            }
            try? FileManager.default.removeItem(at: root)
        }

        @discardableResult
        func file(_ path: String, ageDays: Double, now: Date, bytes: Int = 2_048) throws -> URL {
            let url = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(repeating: 1, count: bytes).write(to: url)
            let date = now.addingTimeInterval(-ageDays * OldFilesScannerTests.day)
            try FileManager.default.setAttributes(
                [.modificationDate: date, .creationDate: date],
                ofItemAtPath: url.path
            )
            return url
        }
    }

    private func scanner(_ metadata: StubMetadata, folder: URL? = nil, age: TimeInterval? = nil) -> OldFilesScanner {
        let current = now
        return OldFilesScanner(
            minimumAge: age ?? OldFilesScanner.defaultMinimumAge,
            screenshotFolder: folder,
            metadata: metadata,
            now: { current }
        )
    }

    private func names(_ report: OldFilesReport) -> [String] {
        report.items.map { $0.url.lastPathComponent }.sorted()
    }

    @Test func defaultAgeIsOneYear() {
        #expect(OldFilesScanner.defaultMinimumAge == 365 * 86_400)
    }

    @Test func exactResultSetAcrossFixtures() throws {
        let fixture = try Fixture()
        try fixture.file("Desktop/shot-old.png", ageDays: 400, now: now)
        try fixture.file("Desktop/rec-old.mov", ageDays: 400, now: now)
        try fixture.file("Downloads/old.dmg", ageDays: 500, now: now)
        try fixture.file("Downloads/new.dmg", ageDays: 10, now: now)
        try fixture.file("Downloads/old.zip", ageDays: 500, now: now)
        try fixture.file("Desktop/old.zip", ageDays: 500, now: now) // archives: Downloads only
        try fixture.file("Desktop/camera.jpg", ageDays: 900, now: now)
        try fixture.file("Desktop/iphone.heic", ageDays: 900, now: now)
        try fixture.file("Desktop/unflagged.png", ageDays: 900, now: now)
        try fixture.file("Documents/old.dmg", ageDays: 900, now: now)
        try fixture.file("Pictures/Photos Library.photoslibrary/originals/a.jpg", ageDays: 900, now: now)
        try fixture.file("Downloads/Pictures.photoslibrary/old.dmg", ageDays: 900, now: now)
        try fixture.file("Downloads/repo/.git/HEAD", ageDays: 900, now: now)
        try fixture.file("Downloads/repo/installer.dmg", ageDays: 900, now: now)
        try fixture.file("Downloads/proj/Package.swift", ageDays: 900, now: now)
        try fixture.file("Downloads/proj/tool.pkg", ageDays: 900, now: now)
        try fixture.file("Downloads/Dropbox/old.dmg", ageDays: 900, now: now)
        try fixture.file("Downloads/placeholder.dmg", ageDays: 900, now: now)

        var metadata = StubMetadata()
        metadata.screenCapture = ["shot-old.png": true, "rec-old.mov": true, "camera.jpg": true, "iphone.heic": true]
        metadata.origin = ["shot-old.png": .noCameraInfo, "camera.jpg": .photoLike, "unflagged.png": .noCameraInfo]
        metadata.dataless = ["placeholder.dmg"]

        let report = scanner(metadata).scan(homeDirectory: fixture.home)

        #expect(names(report) == ["old.dmg", "old.zip", "rec-old.mov", "shot-old.png"])
        #expect(report.skippedDatalessCount == 1)
        #expect(report.notScanned.isEmpty)
        #expect(report.items.allSatisfy { !$0.reason.isEmpty && $0.sizeBytes > 0 })
        let categories = Dictionary(uniqueKeysWithValues: report.items.map { ($0.url.lastPathComponent, $0.category) })
        #expect(categories["shot-old.png"] == .screenshot)
        #expect(categories["rec-old.mov"] == .screenRecording)
        #expect(categories["old.dmg"] == .installer)
        #expect(categories["old.zip"] == .archive)
    }

    @Test func noPhotoIsEverReturned() throws {
        let fixture = try Fixture()
        // Even flagged as a capture, camera data / HEIC / unreadable headers keep an image out.
        for name in ["cam.jpg", "unreadable.png", "live.heic"] {
            try fixture.file("Desktop/\(name)", ageDays: 900, now: now)
        }
        try fixture.file("Pictures/Photos Library.photoslibrary/Masters/IMG_1.jpg", ageDays: 900, now: now)
        var metadata = StubMetadata()
        metadata.screenCapture = ["cam.jpg": true, "unreadable.png": true, "live.heic": true]
        metadata.origin = ["cam.jpg": .photoLike]
        let report = scanner(metadata).scan(homeDirectory: fixture.home)
        #expect(report.items.isEmpty)
    }

    @Test func recentUseKeepsOldFileOutAndReportsSignal() throws {
        let fixture = try Fixture()
        try fixture.file("Downloads/used.dmg", ageDays: 800, now: now)
        try fixture.file("Downloads/idle.dmg", ageDays: 800, now: now)
        try fixture.file("Downloads/openedLongAgo.dmg", ageDays: 800, now: now)
        var metadata = StubMetadata()
        metadata.lastUsed = [
            "used.dmg": now.addingTimeInterval(-5 * Self.day),
            "openedLongAgo.dmg": now.addingTimeInterval(-500 * Self.day)
        ]
        let report = scanner(metadata).scan(homeDirectory: fixture.home)
        #expect(names(report) == ["idle.dmg", "openedLongAgo.dmg"])
        let byName = Dictionary(uniqueKeysWithValues: report.items.map { ($0.url.lastPathComponent, $0) })
        #expect(byName["idle.dmg"]?.dateSignal == .modified)
        #expect(byName["openedLongAgo.dmg"]?.dateSignal == .lastUsed)
        #expect(byName["openedLongAgo.dmg"]?.referenceDate == now.addingTimeInterval(-500 * Self.day))
    }

    @Test func ageThresholdIsConfigurable() throws {
        let fixture = try Fixture()
        try fixture.file("Downloads/a.dmg", ageDays: 100, now: now)
        let strict = scanner(StubMetadata(), age: 90 * Self.day).scan(homeDirectory: fixture.home)
        let relaxed = scanner(StubMetadata()).scan(homeDirectory: fixture.home)
        #expect(names(strict) == ["a.dmg"])
        #expect(relaxed.items.isEmpty)
    }

    @Test func nameFallbackOnlyDirectlyInConfiguredScreenshotFolder() throws {
        let fixture = try Fixture()
        let folder = fixture.home.appendingPathComponent("Pictures/Shots")
        try fixture.file("Pictures/Shots/Screenshot 2024-01-01 at 10.00.00.png", ageDays: 900, now: now)
        try fixture.file("Pictures/Shots/Schermata 2024.png", ageDays: 900, now: now)
        try fixture.file("Pictures/Shots/sub/Screenshot nested.png", ageDays: 900, now: now)
        try fixture.file("Pictures/Shots/Screenshot jpg.jpg", ageDays: 900, now: now)
        try fixture.file("Pictures/Shots/Screen Recording 2024.mov", ageDays: 900, now: now)
        try fixture.file("Pictures/Shots/holiday.mov", ageDays: 900, now: now)
        try fixture.file("Pictures/Shots/old.dmg", ageDays: 900, now: now) // installers: Downloads/Desktop only
        try fixture.file("Pictures/Other/Screenshot elsewhere.png", ageDays: 900, now: now)
        var metadata = StubMetadata()
        for name in ["Screenshot 2024-01-01 at 10.00.00.png", "Schermata 2024.png", "Screenshot nested.png"] {
            metadata.origin[name] = .noCameraInfo
        }
        let report = scanner(metadata, folder: folder).scan(homeDirectory: fixture.home)
        #expect(names(report) == [
            "Schermata 2024.png", "Screen Recording 2024.mov", "Screenshot 2024-01-01 at 10.00.00.png"
        ])
    }

    @Test func explicitNegativeFlagBeatsNameFallback() throws {
        let fixture = try Fixture()
        try fixture.file("Desktop/Screenshot fake.png", ageDays: 900, now: now)
        var metadata = StubMetadata()
        metadata.screenCapture = ["Screenshot fake.png": false]
        metadata.origin = ["Screenshot fake.png": .noCameraInfo]
        let report = scanner(metadata).scan(homeDirectory: fixture.home)
        #expect(report.items.isEmpty)
    }

    @Test func screenshotFolderOutsideHomeOrInDocumentsIsReportedNotScanned() throws {
        let fixture = try Fixture()
        let outside = fixture.root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let inDocuments = fixture.home.appendingPathComponent("Documents/Shots")
        for folder in [outside, inDocuments, fixture.home] {
            let report = scanner(StubMetadata(), folder: folder).scan(homeDirectory: fixture.home)
            #expect(report.notScanned.map(\.url.path) == [folder.standardizedFileURL.path])
        }
    }

    @Test func unreadableFolderIsNotScannedNeverEmpty() throws {
        let fixture = try Fixture()
        let downloads = try fixture.file("Downloads/old.dmg", ageDays: 900, now: now).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: downloads.path)
        let report = scanner(StubMetadata()).scan(homeDirectory: fixture.home)
        #expect(report.items.isEmpty)
        #expect(report.notScanned.map(\.url.path) == [downloads.path])
    }

    @Test func symlinksAreNeverFollowedOrReported() throws {
        let fixture = try Fixture()
        let target = try fixture.file("Private/old.dmg", ageDays: 900, now: now)
        let downloads = fixture.home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: downloads.appendingPathComponent("link.dmg"), withDestinationURL: target
        )
        try FileManager.default.createSymbolicLink(
            at: downloads.appendingPathComponent("dirlink"),
            withDestinationURL: target.deletingLastPathComponent()
        )
        let report = scanner(StubMetadata()).scan(homeDirectory: fixture.home)
        #expect(report.items.isEmpty)
    }

    @Test func symlinkedRootIsReportedNotScanned() throws {
        let fixture = try Fixture()
        let real = fixture.root.appendingPathComponent("real-downloads")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fixture.home.appendingPathComponent("Downloads"), withDestinationURL: real
        )
        let report = scanner(StubMetadata()).scan(homeDirectory: fixture.home)
        #expect(report.notScanned.count == 1)
    }

    @Test func scanNeverModifiesTheFilesystem() throws {
        let fixture = try Fixture()
        let file = try fixture.file("Downloads/old.dmg", ageDays: 900, now: now)
        _ = scanner(StubMetadata()).scan(homeDirectory: fixture.home)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func systemMetadataReadsScreenCaptureFlagAndRegularFileIsNotDataless() throws {
        let fixture = try Fixture()
        let file = try fixture.file("Desktop/a.png", ageDays: 1, now: now)
        let reader = SystemOldFileMetadata()
        #expect(reader.isScreenCapture(file) == nil)
        #expect(!reader.isDataless(file))
        let plist = try PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        let status = plist.withUnsafeBytes {
            setxattr(file.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, plist.count, 0, 0)
        }
        #expect(status == 0)
        #expect(reader.isScreenCapture(file) == true)
        #expect(reader.imageOrigin(of: file) == .unreadable) // not a real image
    }
}
