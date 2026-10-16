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

struct InstalledAppDiscoveryTests {
    private struct Fixture {
        let root: URL
        let systemApplications: URL
        let home: URL

        var userApplications: URL {
            home.appendingPathComponent("Applications", isDirectory: true)
        }

        var discovery: InstalledAppDiscovery {
            InstalledAppDiscovery(roots: [systemApplications, userApplications])
        }
    }

    @Test func discoversAppsWithKnownIdentifiersInBothRootsAndSubfolders() throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        let alpha = try makeApp(in: fixture.systemApplications, "Alpha", info: [
            "CFBundleIdentifier": "com.example.alpha",
            "CFBundleName": "Alpha"
        ])
        let beta = try makeApp(in: fixture.systemApplications.appendingPathComponent("Utilities"), "Beta", info: [
            "CFBundleIdentifier": "com.example.beta",
            "CFBundleName": "Beta",
            "CFBundleDisplayName": "Beta Pro"
        ])
        let gamma = try makeApp(in: fixture.userApplications, "Gamma", info: [
            "CFBundleIdentifier": "com.example.gamma"
        ])

        let result = fixture.discovery.discover()

        #expect(result.apps == [
            InstalledApp(name: "Alpha", bundleIdentifier: .known("com.example.alpha"), url: alpha),
            InstalledApp(name: "Beta Pro", bundleIdentifier: .known("com.example.beta"), url: beta),
            InstalledApp(name: "Gamma", bundleIdentifier: .known("com.example.gamma"), url: gamma)
        ])
        #expect(result.isComplete)
        #expect(result.issues.isEmpty)
        #expect(result.installationStatus(ofBundleIdentifier: "com.example.gamma") == .installed)
        #expect(result.installationStatus(ofBundleIdentifier: "com.example.removed") == .notInstalled)
        #expect(result.app(withBundleIdentifier: "com.example.beta") == .unique(result.apps[1]))
        #expect(result.app(withBundleIdentifier: "com.example.removed") == .notFound)
    }

    @Test func doesNotReportBundlesNestedInsideAnApp() throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        let host = try makeApp(in: fixture.systemApplications, "Host", info: ["CFBundleIdentifier": "com.example.host"])
        try makeApp(in: host.appendingPathComponent("Contents/Library/LoginItems"), "Helper", info: [
            "CFBundleIdentifier": "com.example.host.helper"
        ])

        let result = fixture.discovery.discover()

        #expect(result.apps.map(\.url) == [host])
        #expect(result.installationStatus(ofBundleIdentifier: "com.example.host.helper") == .notInstalled)
    }

    @Test func reportsMissingAndBlankIdentifiersWithoutMatchingThem() throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        let noID = try makeApp(in: fixture.systemApplications, "NoID", info: ["CFBundleName": "No ID"])
        let blankID = try makeApp(in: fixture.userApplications, "BlankID", info: ["CFBundleIdentifier": "  "])

        let result = fixture.discovery.discover()

        #expect(result.apps == [
            InstalledApp(name: "BlankID", bundleIdentifier: .missing, url: blankID),
            InstalledApp(name: "No ID", bundleIdentifier: .missing, url: noID)
        ].sorted { $0.url.path < $1.url.path })
        #expect(result.appsWithoutBundleIdentifier.count == 2)
        #expect(result.isComplete)
        #expect(result.app(withBundleIdentifier: "").isNotFound)
        #expect(result.app(withBundleIdentifier: "  ").isNotFound)
        #expect(result.ambiguousBundleIdentifiers.isEmpty)
    }

    @Test func reportsTheSameIdentifierInTwoLocationsAsAmbiguous() throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        let system = try makeApp(in: fixture.systemApplications, "Editor", info: [
            "CFBundleIdentifier": "com.example.editor"
        ])
        let user = try makeApp(in: fixture.userApplications, "Editor Copy", info: [
            "CFBundleIdentifier": "com.example.editor"
        ])

        let result = fixture.discovery.discover()
        let expected = [
            InstalledApp(name: "Editor", bundleIdentifier: .known("com.example.editor"), url: system),
            InstalledApp(name: "Editor Copy", bundleIdentifier: .known("com.example.editor"), url: user)
        ]

        #expect(result.apps == expected)
        #expect(result.ambiguousBundleIdentifiers == ["com.example.editor": expected])
        #expect(result.app(withBundleIdentifier: "com.example.editor") == .ambiguous(expected))
        #expect(result.installationStatus(ofBundleIdentifier: "com.example.editor") == .installed)
    }

    @Test func identifiersAreMatchedExactly() throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        try makeApp(in: fixture.systemApplications, "Alpha", info: ["CFBundleIdentifier": "com.example.Alpha"])

        let result = fixture.discovery.discover()

        #expect(result.installationStatus(ofBundleIdentifier: "com.example.Alpha") == .installed)
        #expect(result.installationStatus(ofBundleIdentifier: "com.example.alpha") == .notInstalled)
    }

    @Test func missingUserApplicationsFolderKeepsDiscoveryComplete() throws {
        let fixture = try makeFixture(createUserApplications: false)
        defer { cleanUp(fixture) }

        try makeApp(in: fixture.systemApplications, "Alpha", info: ["CFBundleIdentifier": "com.example.alpha"])

        let result = fixture.discovery.discover()

        #expect(result.apps.count == 1)
        #expect(result.isComplete)
    }

    @Test func followsASymlinkedUserApplicationsRoot() throws {
        let fixture = try makeFixture(createUserApplications: false)
        defer { cleanUp(fixture) }

        let target = fixture.root.appendingPathComponent("RealApplications", isDirectory: true)
        try makeApp(in: target, "Gamma", info: ["CFBundleIdentifier": "com.example.gamma"])
        try FileManager.default.createSymbolicLink(at: fixture.userApplications, withDestinationURL: target)

        let result = fixture.discovery.discover()

        #expect(result.apps.map(\.bundleIdentifier) == [.known("com.example.gamma")])
        #expect(result.isComplete)
    }

    @Test func unreadableSubfolderMarksDiscoveryIncomplete() throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        try makeApp(in: fixture.systemApplications, "Alpha", info: ["CFBundleIdentifier": "com.example.alpha"])
        let locked = fixture.systemApplications.appendingPathComponent("Locked", isDirectory: true)
        try makeApp(in: locked, "Hidden", info: ["CFBundleIdentifier": "com.example.hidden"])
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        let result = fixture.discovery.discover()

        #expect(!result.isComplete)
        #expect(result.issues.map(\.kind) == [.unreadableLocation])
        #expect(result.issues.map(\.url.lastPathComponent) == ["Locked"])
        #expect(result.installationStatus(ofBundleIdentifier: "com.example.alpha") == .installed)
        #expect(result.installationStatus(ofBundleIdentifier: "com.example.hidden") == .undetermined)
        #expect(result.app(withBundleIdentifier: "com.example.hidden") == .undetermined)
    }

    @Test func rootThatIsNotADirectoryMarksDiscoveryIncomplete() throws {
        let fixture = try makeFixture(createUserApplications: false)
        defer { cleanUp(fixture) }

        try Data().write(to: fixture.userApplications)

        let result = fixture.discovery.discover()

        #expect(result.issues.map(\.kind) == [.unreadableLocation])
        #expect(result.installationStatus(ofBundleIdentifier: "com.example.alpha") == .undetermined)
    }

    @Test func metadataErrorsAreReportedAndMarkDiscoveryIncomplete() throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        let noPlist = fixture.systemApplications.appendingPathComponent("NoPlist.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: noPlist, withIntermediateDirectories: true)
        let corrupt = fixture.systemApplications.appendingPathComponent("Corrupt.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: corrupt.appendingPathComponent("Info.plist"))
        try makeApp(in: fixture.userApplications, "NumericID", info: ["CFBundleIdentifier": 42])

        let result = fixture.discovery.discover()

        #expect(!result.isComplete)
        #expect(result.apps.isEmpty)
        #expect(result.issues.map(\.kind) == Array(repeating: .unreadableMetadata, count: 3))
        #expect(result.issues.map(\.url.lastPathComponent) == ["Corrupt.app", "NoPlist.app", "NumericID.app"])
        #expect(result.installationStatus(ofBundleIdentifier: "com.example.any") == .undetermined)
    }

    @Test func readsWrappedIOSAppsAndSymlinkedApps() throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        let wrapped = fixture.systemApplications.appendingPathComponent("Phone.app", isDirectory: true)
        let inner = try makeFlatApp(in: wrapped.appendingPathComponent("Wrapper"), "Phone", info: [
            "CFBundleIdentifier": "com.example.phone"
        ])
        try FileManager.default.createSymbolicLink(
            at: wrapped.appendingPathComponent("WrappedBundle"),
            withDestinationURL: inner
        )
        let target = try makeApp(in: fixture.root.appendingPathComponent("Elsewhere"), "Linked", info: [
            "CFBundleIdentifier": "com.example.linked"
        ])
        let link = fixture.userApplications.appendingPathComponent("Linked.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let result = fixture.discovery.discover()

        #expect(result.apps == [
            InstalledApp(name: "Linked", bundleIdentifier: .known("com.example.linked"), url: link),
            InstalledApp(name: "Phone", bundleIdentifier: .known("com.example.phone"), url: wrapped)
        ].sorted { $0.url.path < $1.url.path })
        #expect(result.isComplete)
    }

    @Test func discoveryDoesNotModifyTheFilesystem() throws {
        let fixture = try makeFixture()
        defer { cleanUp(fixture) }

        try makeApp(in: fixture.systemApplications, "Alpha", info: ["CFBundleIdentifier": "com.example.alpha"])
        try makeApp(in: fixture.userApplications, "NoID", info: [:])
        let corrupt = fixture.userApplications.appendingPathComponent("Corrupt.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: corrupt.appendingPathComponent("Info.plist"))
        let before = try snapshot(of: fixture.root)

        _ = fixture.discovery.discover()

        #expect(try snapshot(of: fixture.root) == before)
    }

    @Test func standardRootsAreSystemAndUserApplications() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        let discovery = InstalledAppDiscovery.standard(homeDirectory: home)

        #expect(discovery.roots.map(\.path) == ["/Applications", "/Users/example/Applications"])
    }

    // MARK: - Fixture helpers

    private func makeFixture(createUserApplications: Bool = true) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstalledAppDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = Fixture(
            root: root,
            systemApplications: root.appendingPathComponent("Applications", isDirectory: true),
            home: root.appendingPathComponent("home", isDirectory: true)
        )
        try FileManager.default.createDirectory(at: fixture.systemApplications, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixture.home, withIntermediateDirectories: true)
        if createUserApplications {
            try FileManager.default.createDirectory(at: fixture.userApplications, withIntermediateDirectories: true)
        }
        return fixture
    }

    private func cleanUp(_ fixture: Fixture) {
        if let enumerator = FileManager.default.enumerator(atPath: fixture.root.path) {
            while let relative = enumerator.nextObject() as? String {
                let path = fixture.root.appendingPathComponent(relative).path
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            }
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fixture.systemApplications.appendingPathComponent("Locked").path
        )
        try? FileManager.default.removeItem(at: fixture.root)
    }

    @discardableResult
    private func makeApp(in directory: URL, _ name: String, info: [String: Any]) throws -> URL {
        let app = directory.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try writePlist(info, to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    private func makeFlatApp(in directory: URL, _ name: String, info: [String: Any]) throws -> URL {
        let app = directory.appendingPathComponent("\(name).app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try writePlist(info, to: app.appendingPathComponent("Info.plist"))
        return app
    }

    private func writePlist(_ info: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url)
    }

    private func snapshot(of root: URL) throws -> [String: String] {
        var entries: [String: String] = [:]
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            return entries
        }
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: Set(keys))
            let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            entries[url.path] = "\(values.fileSize ?? -1)|\(modified)|\(values.isSymbolicLink ?? false)"
        }
        return entries
    }
}

private extension InstalledAppLookup {
    var isNotFound: Bool {
        self == .notFound
    }
}
