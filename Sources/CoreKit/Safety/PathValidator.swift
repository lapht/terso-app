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

/// Validates filesystem paths against the two structural invariants that
/// form the first line of defence in the Terso safety pipeline.
///
/// **Invariant §1 — Allowlist-only roots**
/// A path is only accepted if it is strictly contained within one of
/// the caller-supplied `allowedRoots`. Anything outside is rejected with
/// ``SafetyError/pathNotAllowlisted(path:allowedRoots:)``.
///
/// **Invariant §3 — Protected paths**
/// A hard-coded denylist of system and personal locations is checked
/// *before* the allowlist. A match always produces
/// ``SafetyError/protectedPath(path:reason:)``, regardless of what the
/// caller has in its allowlist.
///
/// Both checks operate on the **standardized** absolute path
/// (`URL.standardizedFileURL`) to prevent path-traversal bypasses and to
/// handle APFS case-insensitive vs. case-sensitive filesystems correctly.
///
/// ### Usage
/// ```swift
/// let validator = PathValidator(homeDirectory: URL(fileURLWithPath: "/Users/alice"))
/// try validator.validate(path: url, allowedRoots: [URL(fileURLWithPath: "/Users/alice/Library/Caches")])
/// ```
public struct PathValidator: Sendable {

    // MARK: - Static protected-path catalogue

    /// Absolute path prefixes that are always denied (Invariant §3).
    ///
    /// These are compared case-insensitively so that an APFS
    /// case-insensitive volume cannot be used to circumvent the check.
    private static let systemProtectedPrefixes: [(prefix: String, reason: String)] = [
        ("/System", "SIP-protected macOS system volume"),
        ("/private/var/db", "private system database directory"),
        ("/Library", "shared macOS Library directory"),
        ("/Applications", "applications directory"),
        ("/bin", "system binary directory"),
        ("/sbin", "system sbin directory"),
        ("/usr", "system usr directory"),
        ("/etc", "system etc directory"),
        ("/var", "system var directory"),
        ("/private/etc", "private system etc directory"),
        ("/private/var", "private system var directory")
    ]

    /// Path suffixes that are always denied regardless of location (§3).
    private static let protectedSuffixes: [(suffix: String, reason: String)] = [
        (".app", "active application bundle"),
        (".framework", "framework bundle"),
        (".kext", "kernel extension"),
        (".plugin", "plugin bundle"),
        (".appex", "app extension bundle")
    ]

    // MARK: - State

    /// The user's home directory, used to expand `~/…` personal protected paths.
    private let homeDirectory: URL

    // MARK: - Init

    /// Creates a new `PathValidator`.
    ///
    /// - Parameter homeDirectory: The current user's home directory
    ///   (e.g. `URL(fileURLWithPath: "/Users/alice")`).
    public init(homeDirectory: URL) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    // MARK: - Public API

    /// Validates that `path` is safe to operate on.
    ///
    /// The validation pipeline runs in this order:
    /// 1. **Normalization** — standardize the URL and reject bare relative paths.
    /// 2. **Path-traversal guard** — reject any raw path component equal to `..`.
    /// 3. **Protected-path check** (§3) — hard deny against the system denylist.
    /// 4. **Allowlist check** (§1) — verify the path lives under an allowed root.
    ///
    /// - Parameters:
    ///   - path: The URL to validate. May be either the original or the
    ///     symlink-resolved URL; the caller is responsible for symlink
    ///     resolution (Invariant §2, handled elsewhere in the pipeline).
    ///   - allowedRoots: The set of root URLs that are acceptable for the
    ///     calling module. Must be non-empty. Each root is also standardized
    ///     before comparison.
    /// - Throws: ``SafetyError`` if any check fails.
    public func validate(path: URL, allowedRoots: [URL]) throws {
        // 1. Normalize
        let standardized = path.standardizedFileURL
        let rawPath = standardized.path

        // 2. Path-traversal guard — scan *original* path components before
        //    standardization resolves them, so we catch attempts like
        //    "~/Library/Caches/../../Desktop/secret.txt".
        let originalComponents = path.path
            .components(separatedBy: "/")
        if originalComponents.contains("..") {
            throw SafetyError.invalidPath(path: path.path)
        }

        // Guard: path must be absolute after standardization.
        guard rawPath.hasPrefix("/") else {
            throw SafetyError.invalidPath(path: rawPath)
        }

        // 3. Protected-path check (§3).
        try checkProtectedPaths(standardizedPath: rawPath)

        // 4. Allowlist check (§1).
        try checkAllowlist(standardizedPath: rawPath, allowedRoots: allowedRoots)
    }

    // MARK: - Private helpers

    /// Checks `standardizedPath` against all hard-denied prefixes and suffixes.
    ///
    /// Comparison is case-insensitive to handle APFS case-insensitive volumes.
    private func checkProtectedPaths(standardizedPath: String) throws {
        let lowerPath = standardizedPath.lowercased()

        // System-level prefixes
        for (prefix, reason) in Self.systemProtectedPrefixes
            where isContained(path: lowerPath, underPrefix: prefix.lowercased()) {
            throw SafetyError.protectedPath(path: standardizedPath, reason: reason)
        }

        // Personal protected roots: ~/Desktop, ~/Documents, ~/Downloads
        let personalProtected: [(URL, String)] = [
            (homeDirectory.appendingPathComponent("Desktop"), "user Desktop root"),
            (homeDirectory.appendingPathComponent("Documents"), "user Documents root"),
            (homeDirectory.appendingPathComponent("Downloads"), "user Downloads root"),
        ]
        for (protectedURL, reason) in personalProtected {
            let protectedPath = protectedURL.standardizedFileURL.path
            if isContained(path: lowerPath, underPrefix: protectedPath.lowercased()) {
                throw SafetyError.protectedPath(path: standardizedPath, reason: reason)
            }
        }

        // Suffix-based check (e.g. .app bundles).
        //
        // Only the *last* path component is checked. Intermediate directories
        // like `com.example.app/` are common Xcode / system cache directory
        // names and must NOT be blocked; only a terminal bundle component (e.g.
        // `MyApp.app`, `SomeLib.framework`) is hard-denied.
        let lastComponent = standardizedPath
            .components(separatedBy: "/")
            .last(where: { !$0.isEmpty }) ?? ""
        for (suffix, reason) in Self.protectedSuffixes
            where lastComponent.lowercased().hasSuffix(suffix.lowercased()) {
            throw SafetyError.protectedPath(path: standardizedPath, reason: reason)
        }
    }

    /// Checks that `standardizedPath` is strictly under at least one of
    /// the provided `allowedRoots`.
    ///
    /// A path is "strictly under" a root when the root is a proper prefix
    /// of the path at a directory boundary (i.e. the next character after
    /// the root is `/`), preventing `/Users/alice-evil` from matching a
    /// root of `/Users/alice`.
    private func checkAllowlist(standardizedPath: String, allowedRoots: [URL]) throws {
        let lowerPath = standardizedPath.lowercased()

        let standardizedRoots = allowedRoots.map { $0.standardizedFileURL.path }

        for root in standardizedRoots
            where isContained(path: lowerPath, underPrefix: root.lowercased()) {
            return // ✅ Found a valid root
        }

        throw SafetyError.pathNotAllowlisted(
            path: standardizedPath,
            allowedRoots: standardizedRoots
        )
    }

    /// Returns `true` when `path` is equal to or strictly contained under `prefix`.
    ///
    /// "Strictly contained" means the path starts with the prefix followed by `/`
    /// or equals the prefix exactly, preventing directory-name prefix collisions.
    ///
    /// Both arguments must already be lowercased for case-insensitive comparison.
    private func isContained(path: String, underPrefix prefix: String) -> Bool {
        if path == prefix { return true }
        let normalizedPrefix = prefix.hasSuffix("/") ? prefix : prefix + "/"
        return path.hasPrefix(normalizedPrefix)
    }
}
