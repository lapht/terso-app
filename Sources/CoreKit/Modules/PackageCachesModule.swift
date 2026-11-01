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

/// Finds known package-manager download caches without invoking external tools.
public struct PackageCachesModule: CleanModule {
    private struct CacheLocation {
        let relativePath: String
        let ruleID: String
    }

    public let id = "caches.packages"
    public let title = "Package Caches"
    public let requiresFDA = false

    /// Rule whose items are never preselected because they may not be re-downloadable.
    public static let mavenRuleID = "packages.maven"

    private static let mavenRepositoryPath = ".m2/repository"

    public init() {}

    /// Whether items matched by `ruleID` may be preselected in a clean action.
    public static func isPreselected(ruleID: String) -> Bool {
        ruleID != mavenRuleID
    }

    /// A caution to show next to items matched by `ruleID`, or `nil` when none applies.
    public static func warning(forRuleID ruleID: String) -> String? {
        guard ruleID == mavenRuleID else {
            return nil
        }
        return "Artifacts installed locally with mvn install may not be re-downloadable."
    }

    public func scan(context: ScanContext) async throws -> [CleanItem] {
        let locations = [
            CacheLocation(relativePath: "Library/Caches/Homebrew", ruleID: "packages.homebrew"),
            CacheLocation(relativePath: ".npm/_cacache", ruleID: "packages.npm"),
            CacheLocation(relativePath: "Library/Caches/Yarn", ruleID: "packages.yarn"),
            CacheLocation(relativePath: ".cache/yarn", ruleID: "packages.yarn"),
            CacheLocation(relativePath: "Library/Caches/pnpm", ruleID: "packages.pnpm"),
            CacheLocation(relativePath: ".gradle/caches", ruleID: "packages.gradle"),
            CacheLocation(relativePath: Self.mavenRepositoryPath, ruleID: Self.mavenRuleID),
            CacheLocation(relativePath: ".cargo/registry/cache", ruleID: "packages.cargo"),
            CacheLocation(relativePath: ".cargo/registry/src", ruleID: "packages.cargo"),
            CacheLocation(relativePath: "go/pkg/mod", ruleID: "packages.go-modules"),
            CacheLocation(relativePath: ".bun/install/cache", ruleID: "packages.bun"),
            CacheLocation(relativePath: ".cache/uv", ruleID: "packages.uv"),
            CacheLocation(relativePath: "miniconda3/pkgs", ruleID: "packages.conda"),
            CacheLocation(relativePath: "anaconda3/pkgs", ruleID: "packages.conda"),
            CacheLocation(relativePath: "miniforge3/pkgs", ruleID: "packages.conda"),
            CacheLocation(relativePath: "mambaforge/pkgs", ruleID: "packages.conda"),
            CacheLocation(relativePath: ".conda/pkgs", ruleID: "packages.conda")
        ]

        return try locations.compactMap { location in
            let directory = context.homeDirectory
                .appendingPathComponent(location.relativePath, isDirectory: true)
                .standardizedFileURL
            return try makeItem(at: directory, ruleID: location.ruleID)
        }
        .sorted { $0.url.path < $1.url.path }
    }

    private func makeItem(at url: URL, ruleID: String) throws -> CleanItem? {
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: resourceKeys)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }

        guard values.isDirectory == true,
              values.isSymbolicLink != true else {
            return nil
        }

        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedURL.path == url.path else {
            return nil
        }

        let size = try SizeCalculator().calculate(at: resolvedURL)
        guard size.errors.isEmpty else {
            throw PackageCachesScanFailure.incompleteSize(
                path: resolvedURL.path,
                errors: size.errors.map(\.message)
            )
        }

        return CleanItem(
            url: url,
            resolvedURL: resolvedURL,
            sizeBytes: size.bytes,
            moduleId: id,
            ruleId: ruleID
        )
    }
}

private enum PackageCachesScanFailure: LocalizedError {
    case incompleteSize(path: String, errors: [String])

    var errorDescription: String? {
        switch self {
        case let .incompleteSize(path, errors):
            "Unable to calculate the complete size of \(path): \(errors.joined(separator: "; "))"
        }
    }
}
