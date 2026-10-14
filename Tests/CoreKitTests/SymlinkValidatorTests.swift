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

// MARK: - Test Environment Fixture

/// Temporary sandbox filesystem fixture for testing symlinks and traversal attacks.
final class SymlinkFixture: Sendable {
    let rootURL: URL
    let cachesRoot: URL
    let userHome: URL
    let documentsRoot: URL

    init() throws {
        let uniqueID = UUID().uuidString
        let tempDir = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("terso-symlink-tests-\(uniqueID)")
            .standardizedFileURL

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        self.rootURL = tempDir
        self.userHome = tempDir.appendingPathComponent("Users/testuser").standardizedFileURL
        self.cachesRoot = userHome.appendingPathComponent("Library/Caches").standardizedFileURL
        self.documentsRoot = userHome.appendingPathComponent("Documents").standardizedFileURL

        try fileManager.createDirectory(at: cachesRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: documentsRoot, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makeValidator() -> SymlinkValidator {
        SymlinkValidator(homeDirectory: userHome)
    }

    func createFile(at url: URL, content: String = "sample-content") throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func createSymbolicLink(at linkURL: URL, destinationURL: URL) throws {
        try FileManager.default.createDirectory(
            at: linkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: destinationURL)
    }

    func createSymbolicLink(at linkURL: URL, destinationPath: String) throws {
        try FileManager.default.createDirectory(
            at: linkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: destinationPath)
    }
}

// MARK: - Invariant §2: Symlink Discipline Tests

struct SymlinkValidatorTests {

    // MARK: 1. Symlink to /etc/passwd (System protected path)

    @Test func symlinkToEtcPasswdIsRejected() throws {
        let fixture = try SymlinkFixture()
        let validator = fixture.makeValidator()
        let linkURL = fixture.cachesRoot.appendingPathComponent("evil_passwd_link")

        try fixture.createSymbolicLink(at: linkURL, destinationURL: URL(fileURLWithPath: "/etc/passwd"))

        #expect(throws: SafetyError.self) {
            try validator.resolveAndValidate(path: linkURL, allowedRoots: [fixture.cachesRoot])
        }

        let resolution = validator.evaluate(path: linkURL, allowedRoots: [fixture.cachesRoot])
        guard case let .rejected(warning) = resolution else {
            Issue.record("Expected .rejected, got \(resolution)")
            return
        }
        guard case .externalSymlinkTarget = warning else {
            Issue.record("Expected .externalSymlinkTarget warning, got \(warning)")
            return
        }
    }

    // MARK: 2. Symlink to ~/Documents (Personal protected path)

    @Test func symlinkToUserDocumentsIsRejected() throws {
        let fixture = try SymlinkFixture()
        let validator = fixture.makeValidator()
        let privateDoc = fixture.documentsRoot.appendingPathComponent("tax_return.pdf")
        try fixture.createFile(at: privateDoc, content: "sensitive financial data")

        let linkURL = fixture.cachesRoot.appendingPathComponent("link_to_documents")
        try fixture.createSymbolicLink(at: linkURL, destinationURL: privateDoc)

        #expect(throws: SafetyError.self) {
            try validator.resolveAndValidate(path: linkURL, allowedRoots: [fixture.cachesRoot])
        }

        let resolution = validator.evaluate(path: linkURL, allowedRoots: [fixture.cachesRoot])
        guard case let .rejected(warning) = resolution else {
            Issue.record("Expected .rejected, got \(resolution)")
            return
        }
        guard case .externalSymlinkTarget = warning else {
            Issue.record("Expected .externalSymlinkTarget warning, got \(warning)")
            return
        }
    }

    // MARK: 3. Circular Symlink (A -> B -> A)

    @Test func circularSymlinkIsRejected() throws {
        let fixture = try SymlinkFixture()
        let validator = fixture.makeValidator()
        let linkA = fixture.cachesRoot.appendingPathComponent("circA")
        let linkB = fixture.cachesRoot.appendingPathComponent("circB")

        try fixture.createSymbolicLink(at: linkA, destinationURL: linkB)
        try fixture.createSymbolicLink(at: linkB, destinationURL: linkA)

        do {
            _ = try validator.resolveAndValidate(path: linkA, allowedRoots: [fixture.cachesRoot])
            Issue.record("Expected circular symlink to throw SafetyError")
        } catch let error as SafetyError {
            guard case .circularSymlink = error else {
                Issue.record("Expected SafetyError.circularSymlink, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let resolution = validator.evaluate(path: linkA, allowedRoots: [fixture.cachesRoot])
        guard case let .rejected(warning) = resolution else {
            Issue.record("Expected .rejected for circular symlink, got \(resolution)")
            return
        }
        guard case .circularSymlink = warning else {
            Issue.record("Expected SafetyWarning.circularSymlink, got \(warning)")
            return
        }
    }

    // MARK: 4. Broken Symlink (Target does not exist)

    @Test func brokenSymlinkIsRejected() throws {
        let fixture = try SymlinkFixture()
        let validator = fixture.makeValidator()
        let missingTarget = fixture.cachesRoot.appendingPathComponent("nonexistent_target.tmp")
        let brokenLink = fixture.cachesRoot.appendingPathComponent("broken_link")

        try fixture.createSymbolicLink(at: brokenLink, destinationURL: missingTarget)

        do {
            _ = try validator.resolveAndValidate(path: brokenLink, allowedRoots: [fixture.cachesRoot])
            Issue.record("Expected broken symlink to throw SafetyError")
        } catch let error as SafetyError {
            guard case .brokenSymlink = error else {
                Issue.record("Expected SafetyError.brokenSymlink, got \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let resolution = validator.evaluate(path: brokenLink, allowedRoots: [fixture.cachesRoot])
        guard case let .rejected(warning) = resolution else {
            Issue.record("Expected .rejected for broken symlink, got \(resolution)")
            return
        }
        guard case .brokenSymlink = warning else {
            Issue.record("Expected SafetyWarning.brokenSymlink, got \(warning)")
            return
        }
    }

    // MARK: 5. Internal Symlink (Within allowed root — Happy Path)

    @Test func internalSymlinkIsAllowed() throws {
        let fixture = try SymlinkFixture()
        let validator = fixture.makeValidator()
        let cacheTarget = fixture.cachesRoot.appendingPathComponent("real_cache_folder/cache.db")
        try fixture.createFile(at: cacheTarget, content: "cached-data")

        let linkURL = fixture.cachesRoot.appendingPathComponent("cache_link")
        try fixture.createSymbolicLink(at: linkURL, destinationURL: cacheTarget)

        let resolved = try validator.resolveAndValidate(path: linkURL, allowedRoots: [fixture.cachesRoot])
        #expect(resolved.path == cacheTarget.path)

        let resolution = validator.evaluate(path: linkURL, allowedRoots: [fixture.cachesRoot])
        guard case let .valid(validURL, isSymlink) = resolution else {
            Issue.record("Expected .valid resolution, got \(resolution)")
            return
        }
        #expect(validURL.path == cacheTarget.path)
        #expect(isSymlink == true)
    }

    // MARK: 6. Relative Symlink escaping to /etc via `../../`

    @Test func relativeSymlinkEscapingAllowlistIsRejected() throws {
        let fixture = try SymlinkFixture()
        let validator = fixture.makeValidator()
        let linkURL = fixture.cachesRoot.appendingPathComponent("rel_escape_link")

        try fixture.createSymbolicLink(at: linkURL, destinationPath: "../../../../../../../etc/passwd")

        #expect(throws: SafetyError.self) {
            try validator.resolveAndValidate(path: linkURL, allowedRoots: [fixture.cachesRoot])
        }

        let resolution = validator.evaluate(path: linkURL, allowedRoots: [fixture.cachesRoot])
        guard case let .rejected(warning) = resolution else {
            Issue.record("Expected .rejected, got \(resolution)")
            return
        }
        guard case .externalSymlinkTarget = warning else {
            Issue.record("Expected .externalSymlinkTarget warning, got \(warning)")
            return
        }
    }

    // MARK: 7. Chained Symlinks leading to outside directory

    @Test func chainedSymlinkEscapingIsRejected() throws {
        let fixture = try SymlinkFixture()
        let validator = fixture.makeValidator()
        let linkA = fixture.cachesRoot.appendingPathComponent("chainA")
        let linkB = fixture.cachesRoot.appendingPathComponent("chainB")
        let outsideTarget = fixture.rootURL.appendingPathComponent("outside_secret.txt")
        try fixture.createFile(at: outsideTarget, content: "outside")

        try fixture.createSymbolicLink(at: linkA, destinationURL: linkB)
        try fixture.createSymbolicLink(at: linkB, destinationURL: outsideTarget)

        #expect(throws: SafetyError.self) {
            try validator.resolveAndValidate(path: linkA, allowedRoots: [fixture.cachesRoot])
        }

        let resolution = validator.evaluate(path: linkA, allowedRoots: [fixture.cachesRoot])
        guard case let .rejected(warning) = resolution else {
            Issue.record("Expected .rejected, got \(resolution)")
            return
        }
        guard case .externalSymlinkTarget = warning else {
            Issue.record("Expected .externalSymlinkTarget warning, got \(warning)")
            return
        }
    }

    // MARK: 8. Regular File (Not a Symlink)

    @Test func regularFileIsValidAndNotSymlink() throws {
        let fixture = try SymlinkFixture()
        let validator = fixture.makeValidator()
        let regularFile = fixture.cachesRoot.appendingPathComponent("com.test.app/data.bin")
        try fixture.createFile(at: regularFile, content: "123456")

        let resolved = try validator.resolveAndValidate(path: regularFile, allowedRoots: [fixture.cachesRoot])
        #expect(resolved.path == regularFile.path)

        let resolution = validator.evaluate(path: regularFile, allowedRoots: [fixture.cachesRoot])
        guard case let .valid(validURL, isSymlink) = resolution else {
            Issue.record("Expected .valid, got \(resolution)")
            return
        }
        #expect(validURL.path == regularFile.path)
        #expect(isSymlink == false)
    }

    // MARK: 9. Warning and Error Sendable & Hashable conformance

    @Test func warningAndErrorConformance() {
        let warning = SafetyWarning.externalSymlinkTarget(
            originalPath: "/a/b",
            resolvedPath: "/etc/passwd"
        )
        let error = SafetyError.symlinkEscape(
            originalPath: "/a/b",
            resolvedPath: "/etc/passwd"
        )

        #expect(!warning.description.isEmpty)
        #expect(!error.description.isEmpty)
        #expect(warning == SafetyWarning.externalSymlinkTarget(originalPath: "/a/b", resolvedPath: "/etc/passwd"))
    }
}
