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

struct RuleDatabaseSnapshotTests {
    @Test func validatesV2026RuleDatabaseAgainstSnapshot() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let databaseURL = repositoryRoot.appendingPathComponent("Rules/v2026.1.json")
        let databaseData = try Data(contentsOf: databaseURL)
        let snapshotURL = try #require(
            Bundle.module.url(forResource: "rules-v2026.1.snapshot", withExtension: "json")
        )
        let snapshotData = try Data(contentsOf: snapshotURL)

        #expect(databaseData == snapshotData)

        let database = try RuleValidator.decode(databaseData)
        #expect(database.version == "2026.1")
        #expect(database.schemaVersion == 1)
        #expect(!database.rules.isEmpty)
        #expect(database.rules.allSatisfy { !$0.allowlistRoots.isEmpty && $0.isTrashSafe })
        #expect(Set(database.rules.map(\.module)) == ["caches.user", "logs.user", "xcode.junk", "packages"])

        let allowlistRoots = Set(database.rules.flatMap(\.allowlistRoots))
        #expect(
            Set([
                "~/Library/Caches/com.apple.Safari",
                "~/Library/Caches/com.google.Chrome",
                "~/Library/Caches/org.mozilla.firefox",
                "~/Library/Caches/com.microsoft.VSCode",
                "~/Library/Logs",
                "~/Library/Developer/Xcode/DerivedData",
                "~/Library/Developer/Xcode/Archives",
                "~/Library/Developer/CoreSimulator/Caches",
                "~/Library/Caches/Homebrew",
                "~/.npm/_cacache",
                "~/Library/Caches/Yarn",
                "~/.cache/yarn",
                "~/Library/Caches/pnpm"
            ]).isSubset(of: allowlistRoots)
        )

        let logRule = try #require(database.rules.first { $0.id == "logs.user.rotated" })
        #expect(logRule.patterns.contains("**/*.log"))
        #expect(logRule.patterns.contains("**/*.gz"))
        #expect(logRule.patterns.contains("**/*.crash"))
        #expect(logRule.patterns.contains("**/*.log.[0-9]*"))
        #expect(logRule.minAgeSeconds == 86_400)
        #expect(logRule.exclusions.contains("Terso/**"))

        let oldArchivesRule = try #require(database.rules.first { $0.id == "xcode.old-archives" })
        #expect(oldArchivesRule.patterns == ["**/*.xcarchive"])
        #expect(oldArchivesRule.minAgeSeconds == 7_776_000)
    }
}
