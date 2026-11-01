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

struct ContainerCachesModuleTests {
    private struct Fixture {
        let home: URL
        let containers: URL
        let groupContainers: URL
        let outside: URL
    }

    private struct StubMembershipReader: AppGroupMembershipReading {
        var groups: [String: [String]] = [:]
        var failing: Set<String> = []

        func membership(of app: InstalledApp) throws -> AppGroupMembership {
            let identifier = app.bundleIdentifier.value ?? ""
            if failing.contains(identifier) {
                throw CodeSignatureReadError(path: app.url.path, status: -1)
            }
            return AppGroupMembership(teamIdentifier: nil, applicationGroups: groups[identifier] ?? [])
        }
    }

    private func app(_ name: String, _ identifier: String) -> InstalledApp {
        InstalledApp(
            name: name,
            bundleIdentifier: .known(identifier),
            url: URL(fileURLWithPath: "/Applications/\(name).app")
        )
    }

    private func module(
        running: [InstalledApp] = [],
        installed: [InstalledApp] = [],
        reader: StubMembershipReader = StubMembershipReader()
    ) -> ContainerCachesModule {
        ContainerCachesModule(
            runningApps: { running },
            installedApps: { _ in installed },
            membershipReader: reader
        )
    }

    @Test func returnsOnlyTheCachesFolderOfEachContainer() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        let appCaches = fixture.containers.appendingPathComponent("com.example.Notes/Data/Library/Caches")
        let cacheFile = appCaches.appendingPathComponent("blob.data")
        try createFile(at: cacheFile, contents: "cache")
        try createFile(
            at: fixture.containers.appendingPathComponent("com.example.Notes/Data/Documents/keep.txt"),
            contents: "documents"
        )
        try createFile(
            at: fixture.containers.appendingPathComponent("com.example.Notes/Data/Library/Preferences/p.plist"),
            contents: "prefs"
        )
        let groupCaches = fixture.groupContainers
            .appendingPathComponent("ABCDE12345.shared/Library/Caches")
        try createFile(at: groupCaches.appendingPathComponent("g.data"), contents: "group cache")
        try createFile(
            at: fixture.groupContainers.appendingPathComponent("ABCDE12345.shared/Library/Application Support/a"),
            contents: "support"
        )

        let result = try await module(installed: [app("Notes", "com.example.Notes")])
            .scan(context: ScanContext(homeDirectory: fixture.home))

        #expect(result.map(\.url.path) == [appCaches.path, groupCaches.path])
        #expect(result.first?.sizeBytes == (try allocatedSize(of: cacheFile)))
        #expect(result.map(\.moduleId) == ["caches.containers", "caches.containers"])
        #expect(result.map(\.ruleId) == ["caches.containers.app", "caches.containers.group"])
        #expect(result.allSatisfy { $0.recommendedAction == .trash && !$0.isProtected })
    }

    @Test func resolvesOwnerNameAndFallsBackToTheIdentifier() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        try createFile(
            at: fixture.containers.appendingPathComponent("com.example.Notes/Data/Library/Caches/a"),
            contents: "a"
        )
        try createFile(
            at: fixture.containers.appendingPathComponent("com.example.Unknown/Data/Library/Caches/a"),
            contents: "a"
        )
        try createFile(
            at: fixture.groupContainers.appendingPathComponent("group.com.example.Notes/Library/Caches/a"),
            contents: "a"
        )

        let result = try await module(installed: [app("Notes", "com.example.Notes")])
            .scan(context: ScanContext(homeDirectory: fixture.home))

        #expect(result.map(\.ownerName) == ["Notes", "com.example.Unknown", "Notes"])
    }

    @Test func skipsAndReportsRunningAppsAndSharedGroups() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        let runningFile = fixture.containers.appendingPathComponent("com.example.Open/Data/Library/Caches/a")
        try createFile(at: runningFile, contents: "running")
        try createFile(
            at: fixture.containers.appendingPathComponent("com.example.Closed/Data/Library/Caches/a"),
            contents: "closed"
        )
        let sharedFile = fixture.groupContainers.appendingPathComponent("group.shared/Library/Caches/a")
        try createFile(at: sharedFile, contents: "shared")
        try createFile(
            at: fixture.groupContainers.appendingPathComponent("group.free/Library/Caches/a"),
            contents: "free"
        )

        let open = app("Open", "com.example.Open")
        let reader = StubMembershipReader(groups: ["com.example.Open": ["group.shared"]])
        let report = try await module(running: [open], installed: [open], reader: reader)
            .scanReport(context: ScanContext(homeDirectory: fixture.home))

        #expect(report.items.map(\.ownerName) == ["com.example.Closed", "group.free"])
        #expect(report.skippedCaches == [
            SkippedCache(
                moduleID: "caches.containers",
                bundleIdentifier: "com.example.Open",
                estimatedBytes: try allocatedSize(of: runningFile),
                displayName: "Open"
            ),
            SkippedCache(
                moduleID: "caches.containers",
                bundleIdentifier: "group.shared",
                estimatedBytes: try allocatedSize(of: sharedFile)
            )
        ])
    }

    @Test func unreadableSignatureOfARunningAppKeepsEveryGroupCache() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        try createFile(
            at: fixture.groupContainers.appendingPathComponent("group.any/Library/Caches/a"),
            contents: "x"
        )

        let report = try await module(
            running: [app("Odd", "com.example.Odd")],
            reader: StubMembershipReader(failing: ["com.example.Odd"])
        ).scanReport(context: ScanContext(homeDirectory: fixture.home))

        #expect(report.items.isEmpty)
        #expect(report.skippedCaches.map(\.bundleIdentifier) == ["group.any"])
    }

    @Test func ignoresSymlinkedCachesAndContainersPointingOutside() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        let fileManager = FileManager.default

        // Caches itself is a symlink to somewhere outside.
        let outsideCache = fixture.outside.appendingPathComponent("stolen", isDirectory: true)
        try createFile(at: outsideCache.appendingPathComponent("a"), contents: "outside")
        let linkedLibrary = fixture.containers.appendingPathComponent("com.example.Linked/Data/Library")
        try fileManager.createDirectory(at: linkedLibrary, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: linkedLibrary.appendingPathComponent("Caches"),
            withDestinationURL: outsideCache
        )
        // Data is a symlink to an outside tree that has a real Library/Caches.
        let outsideData = fixture.outside.appendingPathComponent("data", isDirectory: true)
        try createFile(at: outsideData.appendingPathComponent("Library/Caches/a"), contents: "outside")
        try fileManager.createDirectory(
            at: fixture.containers.appendingPathComponent("com.example.LinkedData"),
            withIntermediateDirectories: true
        )
        try fileManager.createSymbolicLink(
            at: fixture.containers.appendingPathComponent("com.example.LinkedData/Data"),
            withDestinationURL: outsideData
        )
        // The whole container is a symlink.
        try fileManager.createSymbolicLink(
            at: fixture.containers.appendingPathComponent("com.example.LinkedContainer"),
            withDestinationURL: fixture.outside.appendingPathComponent("data", isDirectory: true)
        )
        // A group container whose Library is a symlink.
        try fileManager.createDirectory(
            at: fixture.groupContainers.appendingPathComponent("group.linked"),
            withIntermediateDirectories: true
        )
        try fileManager.createSymbolicLink(
            at: fixture.groupContainers.appendingPathComponent("group.linked/Library"),
            withDestinationURL: outsideData.appendingPathComponent("Library")
        )

        let target = module()
        let result = try await target.scan(context: ScanContext(homeDirectory: fixture.home))

        #expect(result.isEmpty)
        #expect(ContainerCachesModule.allowedRoots(homeDirectory: fixture.home).isEmpty)
    }

    @Test func ignoresContainersWithoutCachesAndLooseFiles() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        try createFile(
            at: fixture.containers.appendingPathComponent("com.example.NoCaches/Data/Documents/a"),
            contents: "doc"
        )
        try createFile(at: fixture.containers.appendingPathComponent("loose.txt"), contents: "loose")

        let result = try await module().scan(context: ScanContext(homeDirectory: fixture.home))

        #expect(result.isEmpty)
    }

    @Test func missingContainerRootsAreEmptyNotAnError() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("terso-containers-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let result = try await module().scan(context: ScanContext(homeDirectory: home))

        #expect(result.isEmpty)
    }

    @Test func deniedContainerRootIsReportedAsNotScannedNeverAsEmpty() async throws {
        let fixture = try makeFixture()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.containers.path)
            cleanUp(fixture)
        }
        try createFile(
            at: fixture.containers.appendingPathComponent("com.example.A/Data/Library/Caches/a"),
            contents: "x"
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fixture.containers.path)

        await #expect(throws: (any Error).self) {
            _ = try await module().scan(context: ScanContext(homeDirectory: fixture.home))
        }
        #expect(ContainerCachesModule.allowedRoots(homeDirectory: fixture.home).isEmpty)
    }

    @Test func requiresFullDiskAccessSoDeniedAccessNeverLooksEmpty() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }
        try createFile(
            at: fixture.containers.appendingPathComponent("com.example.A/Data/Library/Caches/a"),
            contents: "x"
        )

        let aggregator = SmartScanAggregator(
            tccManager: TCCManager(accessChecker: DeniedAccessChecker())
        )
        let result = try await aggregator.scan(
            modules: [module()],
            context: ScanContext(homeDirectory: fixture.home)
        )

        #expect(result.items.isEmpty)
        #expect(result.permissionRequirements.map(\.moduleID) == ["caches.containers"])
    }

    @Test func pipelineAcceptsOnlyTheCachesFolderAndRefusesTheRestOfTheContainer() async throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        let container = fixture.containers.appendingPathComponent("com.example.Notes", isDirectory: true)
        try createFile(at: container.appendingPathComponent("Data/Library/Caches/a"), contents: "cache")
        try createFile(at: container.appendingPathComponent("Data/Documents/keep.txt"), contents: "documents")

        let items = try await module().scan(context: ScanContext(homeDirectory: fixture.home))
        let roots = ["caches.containers": ContainerCachesModule.allowedRoots(homeDirectory: fixture.home)]
        let pipeline = DeletionPipeline(
            homeDirectory: fixture.home,
            auditLogger: AuditLogger(fileURL: fixture.outside.appendingPathComponent("audit.log"))
        )

        let dryRun = try pipeline.execute(items: items, allowedRootsByModule: roots, dryRun: true)
        #expect(dryRun.items.count == 1)

        let documents = container.appendingPathComponent("Data/Documents", isDirectory: true)
        let intruder = CleanItem(
            url: documents,
            resolvedURL: documents.resolvingSymlinksInPath().standardizedFileURL,
            sizeBytes: 9,
            moduleId: "caches.containers",
            ruleId: "caches.containers.app"
        )
        #expect(throws: (any Error).self) {
            _ = try pipeline.execute(items: [intruder], allowedRootsByModule: roots, dryRun: true)
        }
    }

    private struct DeniedAccessChecker: TCCAccessChecking {
        func fullDiskAccessStatus() -> TCCStatus {
            .denied
        }
    }

    private func makeFixture() throws -> Fixture {
        // Under /tmp, not /var/folders: the pipeline hard-denies /var.
        let base = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let home = base.appendingPathComponent("terso-containers-\(UUID().uuidString)", isDirectory: true)
        let outside = base.appendingPathComponent("terso-containers-outside-\(UUID().uuidString)", isDirectory: true)
        let containers = home.appendingPathComponent("Library/Containers", isDirectory: true)
        let groupContainers = home.appendingPathComponent("Library/Group Containers", isDirectory: true)
        try FileManager.default.createDirectory(at: containers, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: groupContainers, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        return Fixture(home: home, containers: containers, groupContainers: groupContainers, outside: outside)
    }

    private func cleanUp(_ fixture: Fixture) {
        try? FileManager.default.removeItem(at: fixture.home)
        try? FileManager.default.removeItem(at: fixture.outside)
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    private func allocatedSize(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}
