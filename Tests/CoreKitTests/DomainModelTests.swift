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

// MARK: - CleanAction

struct CleanActionTests {
    @Test func jsonRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for action in CleanAction.allCases {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(CleanAction.self, from: data)
            #expect(decoded == action)
        }
    }

    @Test func defaultIsTrash() {
        // Safety Invariant §4: default action is trash.
        let item = CleanItem(
            url: URL(fileURLWithPath: "/tmp/a"),
            resolvedURL: URL(fileURLWithPath: "/tmp/a"),
            sizeBytes: 100,
            moduleId: "test",
            ruleId: "test.rule"
        )
        #expect(item.recommendedAction == .trash)
    }
}

// MARK: - CleanItem

struct CleanItemTests {
    static let fixtureURL = URL(fileURLWithPath: "/Users/test/Library/Caches/com.example")
    static let fixtureID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

    static func makeItem(
        isProtected: Bool = false,
        recommendedAction: CleanAction = .trash
    ) -> CleanItem {
        CleanItem(
            id: fixtureID,
            url: fixtureURL,
            resolvedURL: fixtureURL,
            sizeBytes: 4096,
            moduleId: "caches.user",
            ruleId: "caches.user.comExample",
            isProtected: isProtected,
            recommendedAction: recommendedAction
        )
    }

    @Test func identifiable() {
        let item = Self.makeItem()
        #expect(item.id == Self.fixtureID)
    }

    @Test func hashableEquality() {
        let a = Self.makeItem()
        let b = Self.makeItem()
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)

        let c = Self.makeItem(isProtected: true)
        #expect(a != c)
    }

    @Test func jsonRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let decoder = JSONDecoder()

        let original = Self.makeItem()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(CleanItem.self, from: data)

        #expect(decoded == original)
        #expect(decoded.id == original.id)
        #expect(decoded.url == original.url)
        #expect(decoded.resolvedURL == original.resolvedURL)
        #expect(decoded.sizeBytes == original.sizeBytes)
        #expect(decoded.moduleId == original.moduleId)
        #expect(decoded.ruleId == original.ruleId)
        #expect(decoded.isProtected == original.isProtected)
        #expect(decoded.recommendedAction == original.recommendedAction)
    }

    @Test func jsonContainsExpectedKeys() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let item = Self.makeItem()
        let data = try encoder.encode(item)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let expectedKeys: Set<String> = [
            "id", "url", "resolvedURL", "sizeBytes",
            "moduleId", "ruleId", "isProtected", "recommendedAction"
        ]
        #expect(Set(json.keys) == expectedKeys)
    }

    @Test func defaultIsProtectedIsFalse() {
        let item = CleanItem(
            url: URL(fileURLWithPath: "/tmp/x"),
            resolvedURL: URL(fileURLWithPath: "/tmp/x"),
            sizeBytes: 0,
            moduleId: "test",
            ruleId: "test.rule"
        )
        #expect(item.isProtected == false)
    }

    @Test func sendableConformance() async {
        // Verify CleanItem can cross actor boundaries without issues.
        let item = Self.makeItem()
        let transferred: CleanItem = await Task.detached {
            return item
        }.value
        #expect(transferred == item)
    }
}

// MARK: - CleanError

struct CleanErrorTests {
    @Test func jsonRoundTripPermissionDenied() throws {
        let error = CleanError.permissionDenied(path: "/protected")
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(CleanError.self, from: data)
        #expect(decoded == error)
    }

    @Test func jsonRoundTripProtectedPath() throws {
        let error = CleanError.protectedPath(path: "/System/Library")
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(CleanError.self, from: data)
        #expect(decoded == error)
    }

    @Test func jsonRoundTripSymlinkEscape() throws {
        let error = CleanError.symlinkEscape(
            originalPath: "/Users/test/link",
            resolvedPath: "/etc/passwd"
        )
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(CleanError.self, from: data)
        #expect(decoded == error)
    }

    @Test func jsonRoundTripItemNotFound() throws {
        let error = CleanError.itemNotFound(path: "/gone")
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(CleanError.self, from: data)
        #expect(decoded == error)
    }

    @Test func jsonRoundTripUnderlyingError() throws {
        let error = CleanError.underlyingError(
            path: "/tmp/fail",
            description: "I/O error"
        )
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(CleanError.self, from: data)
        #expect(decoded == error)
    }

    @Test func hashableEquality() {
        let a = CleanError.permissionDenied(path: "/x")
        let b = CleanError.permissionDenied(path: "/x")
        let c = CleanError.permissionDenied(path: "/y")
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - VolumeInfo

struct VolumeInfoTests {
    static func makeVolume(uuid: String? = "VOL-UUID-1") -> VolumeInfo {
        VolumeInfo(
            mountPath: URL(fileURLWithPath: "/Volumes/External"),
            filesystemType: "apfs",
            isReadOnly: false,
            uuid: uuid
        )
    }

    @Test func identifiableUsesUUIDWhenPresent() {
        let vol = Self.makeVolume(uuid: "ABC-123")
        #expect(vol.id == "ABC-123")
    }

    @Test func identifiableFallsBackToMountPath() {
        let vol = Self.makeVolume(uuid: nil)
        #expect(vol.id == "/Volumes/External")
    }

    @Test func jsonRoundTrip() throws {
        let original = Self.makeVolume()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VolumeInfo.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - ScanContext

struct ScanContextTests {
    static func makeContext(isDryRun: Bool = true) -> ScanContext {
        ScanContext(
            homeDirectory: URL(fileURLWithPath: "/Users/test"),
            mountedVolumes: [
                VolumeInfo(
                    mountPath: URL(fileURLWithPath: "/"),
                    filesystemType: "apfs",
                    isReadOnly: false,
                    uuid: "ROOT-UUID"
                )
            ],
            isDryRun: isDryRun,
            exclusions: ["/Users/test/skip"],
            tccStatus: .granted
        )
    }

    @Test func defaultIsDryRunIsTrue() {
        // Safety Invariant §5: dry-run by default.
        let ctx = ScanContext(
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        )
        #expect(ctx.isDryRun == true)
    }

    @Test func defaultTCCStatusIsUnknown() {
        let ctx = ScanContext(
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        )
        #expect(ctx.tccStatus == .unknown)
    }

    @Test func jsonRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let decoder = JSONDecoder()

        let original = Self.makeContext()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ScanContext.self, from: data)

        #expect(decoded == original)
        #expect(decoded.homeDirectory == original.homeDirectory)
        #expect(decoded.mountedVolumes == original.mountedVolumes)
        #expect(decoded.isDryRun == original.isDryRun)
        #expect(decoded.exclusions == original.exclusions)
        #expect(decoded.tccStatus == original.tccStatus)
    }

    @Test func sendableConformance() async {
        let ctx = Self.makeContext()
        let transferred: ScanContext = await Task.detached {
            return ctx
        }.value
        #expect(transferred == ctx)
    }
}

// MARK: - TCCStatus

struct TCCStatusTests {
    @Test func jsonRoundTrip() throws {
        for status in [TCCStatus.granted, .denied, .unknown] {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(TCCStatus.self, from: data)
            #expect(decoded == status)
        }
    }
}

// MARK: - CleanResult

struct CleanResultTests {
    @Test func jsonRoundTrip() throws {
        let item = CleanItem(
            url: URL(fileURLWithPath: "/tmp/cache"),
            resolvedURL: URL(fileURLWithPath: "/tmp/cache"),
            sizeBytes: 2048,
            moduleId: "caches.user",
            ruleId: "caches.user.test"
        )
        let result = CleanResult(
            itemsTrashed: [item],
            bytesFreed: 2048,
            errors: [.permissionDenied(path: "/denied")],
            executionDuration: 1.5
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(CleanResult.self, from: data)
        #expect(decoded == result)
        #expect(decoded.itemsTrashed.count == 1)
        #expect(decoded.bytesFreed == 2048)
        #expect(decoded.errors.count == 1)
        #expect(decoded.executionDuration == 1.5)
    }

    @Test func defaultsAreEmpty() {
        let result = CleanResult()
        #expect(result.itemsTrashed.isEmpty)
        #expect(result.bytesFreed == 0)
        #expect(result.errors.isEmpty)
        #expect(result.executionDuration == 0)
    }

    @Test func sendableConformance() async {
        let result = CleanResult(
            itemsTrashed: [],
            bytesFreed: 0,
            errors: [],
            executionDuration: 0
        )
        let transferred: CleanResult = await Task.detached {
            return result
        }.value
        #expect(transferred == result)
    }
}
