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

import AppKit
import Foundation

/// Finds rebuildable Xcode and CoreSimulator data without deleting files.
public struct XcodeJunkModule: CleanModule {
    public static let minimumArchiveAgeSeconds: TimeInterval = 90 * 24 * 60 * 60

    public let id = "xcode.junk"
    public let title = "Xcode Junk"
    public let requiresFDA = false

    private let isXcodeRunning: @Sendable () async -> Bool
    private let now: @Sendable () -> Date

    public init() {
        self.init(
            isXcodeRunning: {
                await MainActor.run {
                    NSWorkspace.shared.runningApplications.contains {
                        $0.bundleIdentifier == "com.apple.dt.Xcode"
                    }
                }
            },
            now: Date.init
        )
    }

    init(
        isXcodeRunning: @escaping @Sendable () async -> Bool,
        now: @escaping @Sendable () -> Date
    ) {
        self.isXcodeRunning = isXcodeRunning
        self.now = now
    }

    public func scan(context: ScanContext) async throws -> [CleanItem] {
        let developerDirectory = context.homeDirectory
            .appendingPathComponent("Library/Developer", isDirectory: true)
            .standardizedFileURL
        var items: [CleanItem] = []

        if !(await isXcodeRunning()) {
            let derivedData = developerDirectory
                .appendingPathComponent("Xcode/DerivedData", isDirectory: true)
            items.append(contentsOf: try scanGroupedDirectory(
                derivedData,
                ruleID: "xcode.derived-data"
            ))
        }

        let archives = developerDirectory
            .appendingPathComponent("Xcode/Archives", isDirectory: true)
        items.append(contentsOf: try scanOldArchives(under: archives))

        let simulatorCaches = developerDirectory
            .appendingPathComponent("CoreSimulator/Caches", isDirectory: true)
        items.append(contentsOf: try scanGroupedDirectory(
            simulatorCaches,
            ruleID: "xcode.simulator-caches"
        ))

        return items.sorted { $0.url.path < $1.url.path }
    }

    private func scanGroupedDirectory(_ root: URL, ruleID: String) throws -> [CleanItem] {
        guard try isSafeDirectory(root) else {
            return []
        }

        let entries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Self.resourceKeys,
            options: []
        )
        return try entries.sorted { $0.path < $1.path }.compactMap { entry in
            guard try isSafeEntry(entry, under: root) else {
                return nil
            }
            let values = try entry.resourceValues(forKeys: Self.resourceKeySet)
            guard values.isDirectory == true || values.isRegularFile == true else {
                return nil
            }
            return try makeItem(at: entry, ruleID: ruleID)
        }
    }

    private func scanOldArchives(under root: URL) throws -> [CleanItem] {
        guard try isSafeDirectory(root) else {
            return []
        }

        var pendingEntries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Self.resourceKeys,
            options: []
        )
        var archives: [URL] = []

        while let entry = pendingEntries.popLast() {
            guard try isSafeEntry(entry, under: root) else {
                continue
            }
            let values = try entry.resourceValues(forKeys: Self.resourceKeySet)
            guard values.isDirectory == true else {
                continue
            }
            if entry.pathExtension == "xcarchive" {
                archives.append(entry)
            } else {
                pendingEntries.append(contentsOf: try FileManager.default.contentsOfDirectory(
                    at: entry,
                    includingPropertiesForKeys: Self.resourceKeys,
                    options: []
                ))
            }
        }

        let cutoffAge = Self.minimumArchiveAgeSeconds
        let scanDate = now()
        return try archives.sorted { $0.path < $1.path }.compactMap { archive in
            let latestDate = try latestArchiveDate(at: archive)
            guard scanDate.timeIntervalSince(latestDate) >= cutoffAge else {
                return nil
            }
            return try makeItem(at: archive, ruleID: "xcode.old-archives")
        }
    }

    private func latestArchiveDate(at url: URL) throws -> Date {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw XcodeJunkScanFailure.cannotInspect(url.path, error.localizedDescription)
        }

        let dates = [
            attributes[.creationDate] as? Date,
            attributes[.modificationDate] as? Date
        ].compactMap { $0 }
        guard let latestDate = dates.max() else {
            throw XcodeJunkScanFailure.missingArchiveDate(url.path)
        }
        return latestDate
    }

    private func makeItem(at url: URL, ruleID: String) throws -> CleanItem {
        let size = try SizeCalculator().calculate(at: url)
        guard size.errors.isEmpty else {
            throw XcodeJunkScanFailure.incompleteSize(
                path: url.path,
                errors: size.errors.map(\.message)
            )
        }

        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        return CleanItem(
            url: url,
            resolvedURL: resolvedURL,
            sizeBytes: size.bytes,
            moduleId: id,
            ruleId: ruleID
        )
    }

    private func isSafeDirectory(_ url: URL) throws -> Bool {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: Self.resourceKeySet)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return false
        }
        return values.isDirectory == true
            && values.isSymbolicLink != true
            && url.resolvingSymlinksInPath().standardizedFileURL.path == url.path
    }

    private func isSafeEntry(_ url: URL, under root: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: Self.resourceKeySet)
        guard values.isSymbolicLink != true else {
            return false
        }
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        return resolvedURL.path == url.standardizedFileURL.path
            && Self.isDescendant(resolvedURL, of: root)
    }

    private static func isDescendant(_ url: URL, of root: URL) -> Bool {
        let pathComponents = url.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        return pathComponents.count > rootComponents.count
            && zip(pathComponents, rootComponents).allSatisfy { $0 == $1 }
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey
    ]
    private static let resourceKeySet = Set(resourceKeys)
}

private enum XcodeJunkScanFailure: LocalizedError {
    case cannotInspect(String, String)
    case missingArchiveDate(String)
    case incompleteSize(path: String, errors: [String])

    var errorDescription: String? {
        switch self {
        case let .cannotInspect(path, message):
            "Unable to inspect Xcode item at \(path): \(message)."
        case let .missingArchiveDate(path):
            "Unable to determine the creation or modification date for Xcode archive at \(path)."
        case let .incompleteSize(path, errors):
            "Unable to calculate the complete size of \(path): \(errors.joined(separator: "; "))."
        }
    }
}
