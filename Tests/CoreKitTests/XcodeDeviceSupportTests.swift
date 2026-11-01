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

@testable import CoreKit
import Foundation
import Testing

struct XcodeDeviceSupportTests {
    private let platforms = ["iOS", "watchOS", "tvOS", "visionOS"]

    private struct Fixture {
        let root: URL
        let home: URL
        let xcode: URL
        let developer: URL
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-xcode-ds-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("Users/test-user", isDirectory: true)
        let developer = home.appendingPathComponent("Library/Developer", isDirectory: true)
        let xcode = developer.appendingPathComponent("Xcode", isDirectory: true)
        try FileManager.default.createDirectory(at: xcode, withIntermediateDirectories: true)
        return Fixture(root: root, home: home, xcode: xcode, developer: developer)
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    private func module(running: Bool) -> XcodeJunkModule {
        XcodeJunkModule(isXcodeRunning: { running }, now: Date.init)
    }

    @Test func newestDeviceSupportPerPlatformIsNotPreselectedAndHasNote() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        for platform in platforms {
            for version in ["15.7 (19H12)", "16.4.1 (20E252)", "9.0 (13A340)", "17.2 (21C62)"] {
                try createFile(
                    at: fixture.xcode.appendingPathComponent("\(platform) DeviceSupport/\(version)/Symbols/lib"),
                    contents: "\(platform)-\(version)"
                )
            }
        }

        let items = try await module(running: false).scan(context: ScanContext(homeDirectory: fixture.home))
            .filter { $0.ruleId == "xcode.device-support" }

        #expect(items.count == 16)
        #expect(items.allSatisfy { $0.moduleId == "xcode.junk" && $0.sizeBytes > 0 })
        let notPreselected = items.filter { !$0.isPreselected }
        #expect(notPreselected.map(\.url.lastPathComponent) == Array(repeating: "17.2 (21C62)", count: 4))
        #expect(
            Set(notPreselected.map { $0.url.deletingLastPathComponent().lastPathComponent })
                == Set(platforms.map { "\($0) DeviceSupport" })
        )
        #expect(notPreselected.allSatisfy { $0.note != nil })
        #expect(items.filter(\.isPreselected).allSatisfy { $0.note == nil })
        #expect(items.filter(\.isPreselected).count == 12)
    }

    @Test func singleDeviceSupportEntryIsTheNewestAndNotPreselected() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try createFile(
            at: fixture.xcode.appendingPathComponent("iOS DeviceSupport/17.2 (21C62)/lib"),
            contents: "only"
        )

        let items = try await module(running: false).scan(context: ScanContext(homeDirectory: fixture.home))
        #expect(items.count == 1)
        #expect(items.first?.isPreselected == false)
    }

    @Test func scansDeviceLogsAndDocumentationCache() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try createFile(at: fixture.xcode.appendingPathComponent("iOS Device Logs/phone.crash"), contents: "crash log")
        try createFile(at: fixture.xcode.appendingPathComponent("DocumentationCache/v1/index"), contents: "docs index")

        let items = try await module(running: false).scan(context: ScanContext(homeDirectory: fixture.home))

        #expect(items.map(\.ruleId).sorted() == ["xcode.device-logs", "xcode.documentation-cache"])
        #expect(items.allSatisfy { $0.isPreselected })
        let expected = try [
            fixture.xcode.appendingPathComponent("iOS Device Logs/phone.crash"),
            fixture.xcode.appendingPathComponent("DocumentationCache/v1")
        ].map { try SizeCalculator().calculate(at: $0).bytes }
        #expect(items.map(\.sizeBytes).sorted() == expected.sorted())
        #expect(expected.allSatisfy { $0 > 0 })
    }

    @Test func xcodeRunningSkipsItemsWithVisibleReason() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try createFile(at: fixture.xcode.appendingPathComponent("iOS DeviceSupport/16.0/lib"), contents: "device")
        try createFile(at: fixture.xcode.appendingPathComponent("iOS Device Logs/a.log"), contents: "logs")
        try createFile(at: fixture.xcode.appendingPathComponent("DocumentationCache/x"), contents: "docs")
        try createFile(at: fixture.xcode.appendingPathComponent("DerivedData/P-1/b"), contents: "derived")
        try createFile(at: fixture.developer.appendingPathComponent("CoreSimulator/Caches/c"), contents: "sim")

        let report = try await module(running: true).scanReport(context: ScanContext(homeDirectory: fixture.home))

        #expect(report.items.map(\.ruleId) == ["xcode.simulator-caches"])
        let skippedBytes = try [
            "iOS DeviceSupport/16.0", "iOS Device Logs/a.log", "DocumentationCache/x", "DerivedData/P-1"
        ].map { try SizeCalculator().calculate(at: fixture.xcode.appendingPathComponent($0)).bytes }
        .reduce(0, +)
        #expect(report.skippedCaches == [
            SkippedCache(moduleID: "xcode.junk", bundleIdentifier: "com.apple.dt.Xcode", estimatedBytes: skippedBytes)
        ])
    }

    @Test func xcodeNotRunningReportsNoSkips() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try createFile(at: fixture.xcode.appendingPathComponent("iOS Device Logs/a.log"), contents: "logs")

        let report = try await module(running: false).scanReport(context: ScanContext(homeDirectory: fixture.home))
        #expect(report.skippedCaches.isEmpty)
        #expect(report.items.count == 1)
    }

    @Test func symlinkedEntriesAndRootsAreIgnored() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
        try createFile(at: outside.appendingPathComponent("17.0/lib"), contents: "outside")
        try createFile(at: outside.appendingPathComponent("log"), contents: "outside")

        let supportRoot = fixture.xcode.appendingPathComponent("iOS DeviceSupport", isDirectory: true)
        try FileManager.default.createDirectory(at: supportRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: supportRoot.appendingPathComponent("17.0"),
            withDestinationURL: outside.appendingPathComponent("17.0")
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.xcode.appendingPathComponent("iOS Device Logs"),
            withDestinationURL: outside
        )

        let items = try await module(running: false).scan(context: ScanContext(homeDirectory: fixture.home))
        #expect(items.isEmpty)
    }

    @Test func unavailableSimulatorsAreAdvisoryOnly() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let device = fixture.developer.appendingPathComponent("CoreSimulator/Devices/UDID-1/data/file")
        try createFile(at: device, contents: "simulator data")

        let report = try await module(running: false).scanReport(context: ScanContext(homeDirectory: fixture.home))

        #expect(report.items.isEmpty)
        #expect(report.advisories.count == 1)
        #expect(report.advisories.first?.command == "xcrun simctl delete unavailable")
        let devices = fixture.developer.appendingPathComponent("CoreSimulator/Devices")
        #expect(report.advisories.first?.estimatedBytes == (try SizeCalculator().calculate(at: devices).bytes))
        #expect(FileManager.default.fileExists(atPath: device.path))
    }

    @Test func ruleDatabaseV20264DeclaresDeviceSupportRulesWithExplicitRoots() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("Rules/v2026.4.json"))
        let snapshot = try #require(Bundle.module.url(forResource: "rules-v2026.4.snapshot", withExtension: "json"))
        #expect(try data == Data(contentsOf: snapshot))

        let database = try RuleValidator.decode(data)
        #expect(database.version == "2026.4")
        let byID = Dictionary(uniqueKeysWithValues: database.rules.map { ($0.id, $0) })
        let support = try #require(byID["xcode.device-support"])
        #expect(support.allowlistRoots == platforms.map { "~/Library/Developer/Xcode/\($0) DeviceSupport" })
        #expect(byID["xcode.device-logs"]?.allowlistRoots == ["~/Library/Developer/Xcode/iOS Device Logs"])
        #expect(byID["xcode.documentation-cache"]?.allowlistRoots == ["~/Library/Developer/Xcode/DocumentationCache"])
        #expect(database.rules.allSatisfy { $0.isTrashSafe && !$0.allowlistRoots.contains { $0.contains("*") } })
    }
}
