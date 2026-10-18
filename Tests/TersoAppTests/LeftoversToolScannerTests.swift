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

private enum ScannerFixture {
    static let rulesJSON = """
    {"version": "2026.2", "schemaVersion": 2, "rules": [{
      "id": "leftovers.example.editor", "module": "leftovers", "category": "Leftovers",
      "name": "Example Editor leftovers", "description": "Files left by Example Editor.",
      "allowlistRoots": ["~/Library/Application Support", "~/Library/Caches"],
      "paths": [], "patterns": [], "exclusions": [], "isTrashSafe": true,
      "appPatterns": [{"bundleID": "com.example.Editor",
        "paths": ["~/Library/Application Support/Example Editor", "~/Library/Caches/{bundleID}"]}],
      "provenance": {"source": "https://example.com", "author": "tester", "date": "2026-10-16",
        "rationale": "Documented locations."}
    }]}
    """

    static func rules() throws -> [CleanupRule] {
        try RuleValidator.decode(Data(rulesJSON.utf8)).rules
    }

    static func makeHome() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".terso-scanner-\(UUID().uuidString)", isDirectory: true)
        for file in ["Library/Application Support/Example Editor/data", "Library/Caches/com.example.Editor/c"] {
            let url = home.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("x".utf8).write(to: url)
        }
        return home
    }

    static func discovery(installed: [String] = [], issues: [AppDiscoveryIssue] = []) -> InstalledAppDiscoveryResult {
        InstalledAppDiscoveryResult(
            roots: [URL(fileURLWithPath: "/Applications")],
            apps: installed.map {
                InstalledApp(
                    name: $0,
                    bundleIdentifier: .known($0),
                    url: URL(fileURLWithPath: "/Applications/\($0).app")
                )
            },
            issues: issues
        )
    }

    static func context(_ home: URL, tcc: TCCStatus = .granted) -> ScanContext {
        ScanContext(homeDirectory: home, tccStatus: tcc)
    }
}

struct LeftoversToolScannerTests {
    @Test func reportsLeftoversOfARemovedAppWithTheirReason() async throws {
        let home = try ScannerFixture.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let scanner = LeftoversToolScanner(
            loadRules: ScannerFixture.rules,
            discoverApps: { _ in ScannerFixture.discovery() }
        )

        let outcome = try await scanner.scan(context: ScannerFixture.context(home))

        #expect(outcome.items.count == 2)
        #expect(outcome.items.allSatisfy { $0.moduleId == "leftovers" && $0.recommendedAction == .trash })
        #expect(outcome.items.allSatisfy { outcome.reasons[$0.id]?.contains("com.example.Editor") == true })
    }

    @Test func installedAppFilesAreNotReported() async throws {
        let home = try ScannerFixture.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let scanner = LeftoversToolScanner(
            loadRules: ScannerFixture.rules,
            discoverApps: { _ in ScannerFixture.discovery(installed: ["com.example.Editor"]) }
        )

        let outcome = try await scanner.scan(context: ScannerFixture.context(home))

        #expect(outcome.items.isEmpty)
    }

    @Test func skippedRootsStayVisibleWithoutFullDiskAccess() async throws {
        let home = try ScannerFixture.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let scanner = LeftoversToolScanner(
            loadRules: ScannerFixture.rules,
            discoverApps: { _ in ScannerFixture.discovery() }
        )

        let outcome = try await scanner.scan(context: ScannerFixture.context(home, tcc: .denied))

        let protected = outcome.notScanned.filter(\.needsFullDiskAccess).map(\.name)
        #expect(protected == ["~/Library/Containers", "~/Library/Group Containers"])
    }

    @Test func incompleteDiscoveryFailsInsteadOfReportingAnEmptyList() async throws {
        let home = try ScannerFixture.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let issue = AppDiscoveryIssue(
            kind: .unreadableLocation,
            url: URL(fileURLWithPath: "/Applications"),
            message: "denied"
        )
        let scanner = LeftoversToolScanner(
            loadRules: ScannerFixture.rules,
            discoverApps: { _ in ScannerFixture.discovery(issues: [issue]) }
        )

        await #expect(throws: LeftoversToolScanner.ScanError.discoveryIncomplete) {
            try await scanner.scan(context: ScannerFixture.context(home))
        }
    }

    @Test func unreadableRulesFailWithAVisibleError() async throws {
        let scanner = LeftoversToolScanner(
            loadRules: { throw CocoaError(.fileReadNoSuchFile) },
            discoverApps: { _ in ScannerFixture.discovery() }
        )

        await #expect(throws: LeftoversToolScanner.ScanError.self) {
            try await scanner.scan(context: ScannerFixture.context(URL(fileURLWithPath: "/tmp")))
        }
    }

    @Test func theBundledRuleDatabaseIsPartOfTheApp() throws {
        let rules = try LeftoversToolScanner.loadBundledRules()

        #expect(rules.contains { $0.appPatterns != nil })
    }
}
