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

/// Validates symbolic links against Invariant §2 (Symlink discipline) and
/// Invariant §3 (Protected paths) of the Terso safety specification (`docs/design.md §5`).
///
/// **Invariant §2 — Symlink discipline:**
/// Resolve every path; verify the resolved target is still inside the allowlist root;
/// never follow symlinks into unknown locations.
///
/// If a symlink resolves to a target outside the module's allowlist root, or points to
/// a protected location (Invariant §3), or cannot be resolved because it is broken or
/// cyclic, it is rejected to prevent traversal or escalation attacks.
public struct SymlinkValidator: Sendable {
    /// Result of evaluating a symlink or regular file.
    public enum Resolution: Sendable, Hashable {
        /// The path is a safe item (either regular file or symlink whose target is valid).
        ///
        /// - Parameters:
        ///   - resolvedURL: The target URL after following all symlinks.
        ///   - isSymlink: Whether the original path was a symlink.
        case valid(resolvedURL: URL, isSymlink: Bool)

        /// The path is a symlink that was rejected due to an invariant violation or resolution error.
        case rejected(SafetyWarning)
    }

    /// Maximum number of symlink hops to follow before declaring a circular reference.
    private static let maxResolutionDepth = 32

    /// The underlying path validator used to verify allowlists and protected paths.
    private let pathValidator: PathValidator

    /// Creates a new `SymlinkValidator`.
    ///
    /// - Parameters:
    ///   - homeDirectory: The current user's home directory.
    ///   - pathValidator: An optional preconfigured `PathValidator`. If omitted,
    ///     one is constructed from `homeDirectory`.
    public init(homeDirectory: URL, pathValidator: PathValidator? = nil) {
        self.pathValidator = pathValidator ?? PathValidator(homeDirectory: homeDirectory)
    }

    // MARK: - Public API

    /// Resolves `path`, following symbolic links iteratively, and validates that
    /// the final resolved target resides strictly within `allowedRoots` and does
    /// not violate protected paths.
    ///
    /// - Parameters:
    ///   - path: The URL to validate and resolve.
    ///   - allowedRoots: Allowed root URLs for the calling module.
    /// - Returns: The fully resolved `URL` conforming to all safety invariants.
    /// - Throws: ``SafetyError`` if the symlink is cyclic, broken, escapes allowlisted roots,
    ///   or points to a protected system/user directory.
    public func resolveAndValidate(path: URL, allowedRoots: [URL]) throws -> URL {
        // Step 1: Pre-validate original path format & structure
        try pathValidator.validate(path: path, allowedRoots: allowedRoots)

        // Step 2: Iteratively resolve symlinks
        let (resolvedURL, isSymlink) = try fullyResolve(path: path)

        // Step 3: Validate resolved target against protected paths and allowlist
        do {
            try pathValidator.validate(path: resolvedURL, allowedRoots: allowedRoots)
        } catch {
            if isSymlink {
                throw SafetyError.symlinkEscape(
                    originalPath: path.standardizedFileURL.path,
                    resolvedPath: resolvedURL.standardizedFileURL.path
                )
            }
            throw error
        }

        return resolvedURL
    }

    /// Evaluates `path` and returns a ``Resolution`` without throwing.
    ///
    /// If the item is invalid, broken, cyclic, or escapes allowlisted roots,
    /// returns `.rejected(warning)` with an appropriate ``SafetyWarning``.
    ///
    /// - Parameters:
    ///   - path: The URL to evaluate.
    ///   - allowedRoots: Allowed root URLs for the calling module.
    /// - Returns: A ``Resolution`` indicating whether the item is valid or rejected.
    public func evaluate(path: URL, allowedRoots: [URL]) -> Resolution {
        do {
            // First check basic validity of the original path
            try pathValidator.validate(path: path, allowedRoots: allowedRoots)

            let (resolvedURL, isSymlink) = try fullyResolve(path: path)
            try pathValidator.validate(path: resolvedURL, allowedRoots: allowedRoots)
            return .valid(resolvedURL: resolvedURL, isSymlink: isSymlink)
        } catch let error as SafetyError {
            switch error {
            case let .brokenSymlink(symlinkPath, destination):
                return .rejected(.brokenSymlink(path: symlinkPath, destination: destination))
            case let .circularSymlink(symlinkPath):
                return .rejected(.circularSymlink(path: symlinkPath))
            case let .symlinkEscape(orig, res):
                return .rejected(.externalSymlinkTarget(originalPath: orig, resolvedPath: res))
            case .pathNotAllowlisted, .protectedPath, .invalidPath:
                return .rejected(.externalSymlinkTarget(
                    originalPath: path.standardizedFileURL.path,
                    resolvedPath: path.resolvingSymlinksInPath().path
                ))
            }
        } catch {
            return .rejected(.brokenSymlink(
                path: path.standardizedFileURL.path,
                destination: "unresolvable"
            ))
        }
    }

    // MARK: - Private Helpers

    /// Resolves symbolic links iteratively up to `maxResolutionDepth`.
    ///
    /// - Parameter path: The original URL.
    /// - Returns: A tuple of the resolved target URL and a flag indicating if any symlink was followed.
    /// - Throws: ``SafetyError.circularSymlink`` or ``SafetyError.brokenSymlink``.
    private func fullyResolve(path: URL) throws -> (resolvedURL: URL, isSymlink: Bool) {
        let fileManager = FileManager.default
        var currentURL = path.standardizedFileURL
        var visitedPaths = Set<String>()
        var didTraverseSymlink = false

        for _ in 0..<Self.maxResolutionDepth {
            let currentPath = currentURL.path

            if visitedPaths.contains(currentPath) {
                throw SafetyError.circularSymlink(path: path.standardizedFileURL.path)
            }
            visitedPaths.insert(currentPath)

            // Check if current path is a symbolic link
            guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: currentPath) else {
                // Not a symlink (or destination couldn't be read).
                // If it was already identified as symlink or it's a regular file:
                return (currentURL, didTraverseSymlink)
            }

            didTraverseSymlink = true

            // Compute target URL from destination string
            let parentURL = currentURL.deletingLastPathComponent()
            let nextURL: URL
            if destination.hasPrefix("/") {
                nextURL = URL(fileURLWithPath: destination).standardizedFileURL
            } else {
                nextURL = URL(fileURLWithPath: destination, relativeTo: parentURL).standardizedFileURL
            }

            // Check if destination exists or is itself another symlink
            let destinationPath = nextURL.path
            var isDir: ObjCBool = false
            let exists = fileManager.fileExists(atPath: destinationPath, isDirectory: &isDir)
            let isTargetSymlink = (try? fileManager.destinationOfSymbolicLink(atPath: destinationPath)) != nil

            if !exists && !isTargetSymlink {
                throw SafetyError.brokenSymlink(
                    path: path.standardizedFileURL.path,
                    destination: destination
                )
            }

            currentURL = nextURL
        }

        // Exceeded maxResolutionDepth
        throw SafetyError.circularSymlink(path: path.standardizedFileURL.path)
    }
}
