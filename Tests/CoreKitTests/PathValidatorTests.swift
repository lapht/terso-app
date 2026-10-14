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

// MARK: - Helpers

private let fakeHome = URL(fileURLWithPath: "/Users/testuser")
private let userCachesRoot = fakeHome.appendingPathComponent("Library/Caches")
private let userLogsRoot = fakeHome.appendingPathComponent("Library/Logs")

private func makeValidator(home: URL = fakeHome) -> PathValidator {
    PathValidator(homeDirectory: home)
}

// MARK: - Invariant §3: Protected Paths — System Prefixes

struct PathValidatorProtectedSystemTests {
    /// Matrix of paths that must always be hard-denied.
    private static let forbiddenPaths: [(path: String, description: String)] = [
        ("/System/Library/Frameworks/AppKit.framework", "/System prefix"),
        ("/System/Library", "/System prefix"),
        ("/System", "/System itself"),
        ("/private/var/db", "/private/var/db prefix"),
        ("/private/var/db/receipts", "child of /private/var/db"),
        ("/Library/Application Support", "/Library prefix"),
        ("/Library", "/Library itself"),
        ("/Applications/Safari.app", "/Applications prefix"),
        ("/Applications", "/Applications itself"),
        ("/bin/bash", "/bin prefix"),
        ("/sbin/launchd", "/sbin prefix"),
        ("/usr/local/bin/brew", "/usr prefix"),
        ("/etc/hosts", "/etc prefix"),
        ("/var/log/system.log", "/var prefix"),
        ("/private/etc/passwd", "/private/etc prefix"),
        ("/private/var/root", "/private/var prefix"),
    ]

    @Test(arguments: forbiddenPaths)
    func systemPathIsHardDenied(entry: (path: String, description: String)) {
        let validator = makeValidator()
        let url = URL(fileURLWithPath: entry.path)
        // Even if the caller includes the path inside allowedRoots, §3 wins.
        let allowedRoots = [url]
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: allowedRoots)
        }
    }

    @Test func systemPathThrowsProtectedPathError() {
        let validator = makeValidator()
        let url = URL(fileURLWithPath: "/System/Library")
        do {
            try validator.validate(path: url, allowedRoots: [url])
            Issue.record("Expected SafetyError.protectedPath to be thrown")
        } catch let error as SafetyError {
            guard case .protectedPath = error else {
                Issue.record("Expected .protectedPath, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - Invariant §3: Protected Paths — Personal Folders

struct PathValidatorProtectedPersonalTests {
    @Test func desktopRootIsDenied() {
        let validator = makeValidator()
        let url = fakeHome.appendingPathComponent("Desktop")
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [url])
        }
    }

    @Test func desktopChildIsDenied() {
        let validator = makeValidator()
        let url = fakeHome.appendingPathComponent("Desktop/secret.txt")
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [userCachesRoot])
        }
    }

    @Test func documentsRootIsDenied() {
        let validator = makeValidator()
        let url = fakeHome.appendingPathComponent("Documents")
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [url])
        }
    }

    @Test func documentsChildIsDenied() {
        let validator = makeValidator()
        let url = fakeHome.appendingPathComponent("Documents/file.txt")
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [userCachesRoot])
        }
    }

    @Test func downloadsRootIsDenied() {
        let validator = makeValidator()
        let url = fakeHome.appendingPathComponent("Downloads")
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [url])
        }
    }

    @Test func downloadsChildIsDenied() {
        let validator = makeValidator()
        let url = fakeHome.appendingPathComponent("Downloads/archive.zip")
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [userCachesRoot])
        }
    }
}

// MARK: - Invariant §3: Protected Paths — Bundle Suffixes

struct PathValidatorProtectedBundleTests {
    @Test func appBundleInCachesIsDenied() {
        let validator = makeValidator()
        // Even if it sits under an allowed root, .app suffix is hard-denied.
        let url = userCachesRoot.appendingPathComponent("Wrapper/MyApp.app")
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [userCachesRoot])
        }
    }

    @Test func frameworkBundleIsDenied() {
        let validator = makeValidator()
        let url = userCachesRoot.appendingPathComponent("MyFramework.framework")
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [userCachesRoot])
        }
    }

    @Test func kextBundleIsDenied() {
        let validator = makeValidator()
        let url = URL(fileURLWithPath: "/Library/Extensions/MyDriver.kext")
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [url])
        }
    }

    @Test func pluginBundleIsDenied() {
        let validator = makeValidator()
        let url = userCachesRoot.appendingPathComponent("Plugins/MyPlugin.plugin")
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [userCachesRoot])
        }
    }

    @Test func appExtensionBundleIsDenied() {
        let validator = makeValidator()
        let url = userCachesRoot.appendingPathComponent("Extensions/MyExt.appex")
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [userCachesRoot])
        }
    }
}

// MARK: - Invariant §1: Allowlist-only Roots

struct PathValidatorAllowlistTests {
    @Test func pathOutsideAllowedRootIsRejected() {
        let validator = makeValidator()
        // Path is in Logs, but root only covers Caches.
        let url = userLogsRoot.appendingPathComponent("com.example.log")
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [userCachesRoot])
        }
    }

    @Test func pathOutsideAllowedRootThrowsCorrectError() {
        let validator = makeValidator()
        let url = userLogsRoot.appendingPathComponent("com.example.log")
        do {
            try validator.validate(path: url, allowedRoots: [userCachesRoot])
            Issue.record("Expected SafetyError.pathNotAllowlisted to be thrown")
        } catch let error as SafetyError {
            guard case .pathNotAllowlisted = error else {
                Issue.record("Expected .pathNotAllowlisted, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func directoryPrefixCollisionIsRejected() {
        // "/Users/alice-evil" must NOT be accepted for root "/Users/alice"
        let validator = makeValidator(home: URL(fileURLWithPath: "/Users/alice"))
        let allowedRoot = URL(fileURLWithPath: "/Users/alice/Library/Caches")
        let evilURL = URL(fileURLWithPath: "/Users/alice-evil/Library/Caches/file.tmp")
        #expect(throws: SafetyError.self) {
            try validator.validate(path: evilURL, allowedRoots: [allowedRoot])
        }
    }

    @Test func multipleAllowedRootsAcceptsAny() throws {
        let validator = makeValidator()
        let allowedRoots = [userCachesRoot, userLogsRoot]
        let url = userLogsRoot.appendingPathComponent("com.example.log")
        // Must NOT throw — path is under userLogsRoot which is allowlisted.
        try validator.validate(path: url, allowedRoots: allowedRoots)
    }

    @Test func pathExactlyAtRootIsAllowed() throws {
        let validator = makeValidator()
        // The root itself should be accepted.
        try validator.validate(path: userCachesRoot, allowedRoots: [userCachesRoot])
    }

    @Test func pathStrictlyUnderRootIsAllowed() throws {
        let validator = makeValidator()
        let url = userCachesRoot.appendingPathComponent("com.example/Cache.db")
        try validator.validate(path: url, allowedRoots: [userCachesRoot])
    }
}

// MARK: - Path Traversal Attacks

struct PathValidatorTraversalTests {
    /// Attack: escape from Caches to Desktop via `..` components.
    @Test func dotDotTraversalIsRejected() {
        let validator = makeValidator()
        // Raw path: ~/Library/Caches/../../Desktop/secret.txt
        let rawPath = fakeHome.path + "/Library/Caches/../../Desktop/secret.txt"
        let url = URL(fileURLWithPath: rawPath)
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [userCachesRoot])
        }
    }

    @Test func dotDotTraversalThrowsInvalidPath() {
        let validator = makeValidator()
        let rawPath = fakeHome.path + "/Library/Caches/../../Desktop/secret.txt"
        let url = URL(fileURLWithPath: rawPath)
        do {
            try validator.validate(path: url, allowedRoots: [userCachesRoot])
            Issue.record("Expected SafetyError.invalidPath to be thrown")
        } catch let error as SafetyError {
            guard case .invalidPath = error else {
                Issue.record("Expected .invalidPath, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func dotDotInMiddleOfPathIsRejected() {
        let validator = makeValidator()
        let rawPath = fakeHome.path + "/Library/Caches/../../../etc/passwd"
        let url = URL(fileURLWithPath: rawPath)
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [userCachesRoot])
        }
    }

    @Test func dotDotPrefixedFilenameIsAllowed() throws {
        // A filename like "..hidden" does NOT contain a `..` component —
        // it is a regular filename starting with two dots; must not be blocked.
        let validator = makeValidator()
        let url = userCachesRoot.appendingPathComponent("..hiddenfile")
        try validator.validate(path: url, allowedRoots: [userCachesRoot])
    }
}

// MARK: - Case-insensitive Comparison

struct PathValidatorCaseInsensitiveTests {
    @Test func uppercasedSystemPrefixIsDenied() {
        let validator = makeValidator()
        // APFS case-insensitive: /SYSTEM should still be denied.
        let url = URL(fileURLWithPath: "/SYSTEM/Library/Frameworks")
        #expect(throws: SafetyError.self) {
            try validator.validate(path: url, allowedRoots: [url])
        }
    }

    @Test func mixedCaseAllowedRootIsAccepted() throws {
        // Allowlist root with mixed case should still match.
        let validator = makeValidator()
        let rootMixedCase = URL(fileURLWithPath: fakeHome.path + "/Library/Caches")
        let url = rootMixedCase.appendingPathComponent("com.example/Cache.db")
        try validator.validate(path: url, allowedRoots: [userCachesRoot])
    }
}

// MARK: - Allowed Paths (Happy Path)

struct PathValidatorAllowedPathTests {
    @Test func userCacheFileIsAllowed() throws {
        let validator = makeValidator()
        let url = userCachesRoot.appendingPathComponent("com.example.app/Cache.db")
        try validator.validate(path: url, allowedRoots: [userCachesRoot])
    }

    @Test func userLogFileIsAllowed() throws {
        let validator = makeValidator()
        let url = userLogsRoot.appendingPathComponent("com.example.log")
        try validator.validate(path: url, allowedRoots: [userLogsRoot])
    }

    @Test func tempFileIsAllowed() throws {
        let validator = makeValidator()
        let tmpRoot = URL(fileURLWithPath: "/tmp")
        let url = tmpRoot.appendingPathComponent("terso-test/scratch.bin")
        try validator.validate(path: url, allowedRoots: [tmpRoot])
    }

    @Test func nestedCacheDirectoryIsAllowed() throws {
        let validator = makeValidator()
        let url = userCachesRoot
            .appendingPathComponent("com.apple.dt.Xcode")
            .appendingPathComponent("DerivedData")
            .appendingPathComponent("MyProject-abc123")
            .appendingPathComponent("Build/Intermediates.noindex")
        try validator.validate(path: url, allowedRoots: [userCachesRoot])
    }
}
