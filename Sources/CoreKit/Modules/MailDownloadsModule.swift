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

/// Finds the copies Mail keeps of attachments the user opened, without deleting anything.
///
/// Only the children of `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` are
/// reported. Mailboxes and the Mail database are never read: the originals stay in Mail and are
/// downloaded again when an attachment is reopened. While Mail is running the folder is left
/// untouched and reported as skipped.
public struct MailDownloadsModule: SkippedCacheReporting {
    public static let mailBundleIdentifier = "com.apple.mail"
    public static let relativeRoot = "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"

    public let id = "mail.downloads"
    public let title = "Mail Downloads"
    public let requiresFDA = true

    private let isMailRunning: @Sendable () async -> Bool

    public init() {
        self.init(isMailRunning: {
            await MainActor.run {
                NSWorkspace.shared.runningApplications.contains {
                    $0.bundleIdentifier == Self.mailBundleIdentifier
                }
            }
        })
    }

    init(isMailRunning: @escaping @Sendable () async -> Bool) {
        self.isMailRunning = isMailRunning
    }

    public func scan(context: ScanContext) async throws -> [CleanItem] {
        try await scanReport(context: context).items
    }

    public func scanReport(context: ScanContext) async throws -> ModuleScanReport {
        // Invariant 7: without FDA the container cannot be read, so say so instead of scanning less.
        guard context.tccStatus == .granted else {
            throw MailDownloadsScanFailure.fullDiskAccessRequired
        }

        let root = context.homeDirectory
            .appendingPathComponent(Self.relativeRoot, isDirectory: true)
            .standardizedFileURL
        let rootValues: URLResourceValues
        do {
            rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return ModuleScanReport(items: [])
        }
        guard rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              root.resolvingSymlinksInPath().standardizedFileURL.path == root.path else {
            return ModuleScanReport(items: [])
        }

        let children = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        let mailIsRunning = await isMailRunning()
        var items: [CleanItem] = []
        var skippedBytes: Int64 = 0
        var skippedAny = false
        for child in children {
            let values = try child.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                continue
            }
            let resolved = child.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path == child.standardizedFileURL.path,
                  resolved.deletingLastPathComponent().path == root.path else {
                continue
            }

            let size = try SizeCalculator().calculate(at: resolved)
            if mailIsRunning {
                skippedBytes += size.bytes
                skippedAny = true
                continue
            }
            guard size.errors.isEmpty else {
                throw MailDownloadsScanFailure.incompleteSize(
                    path: resolved.path,
                    errors: size.errors.map(\.message)
                )
            }
            items.append(CleanItem(
                url: child.standardizedFileURL,
                resolvedURL: resolved,
                sizeBytes: size.bytes,
                moduleId: id,
                ruleId: id
            ))
        }

        let skipped = skippedAny
            ? [SkippedCache(moduleID: id, bundleIdentifier: Self.mailBundleIdentifier, estimatedBytes: skippedBytes)]
            : []
        return ModuleScanReport(items: items, skippedCaches: skipped)
    }
}

private enum MailDownloadsScanFailure: LocalizedError {
    case fullDiskAccessRequired
    case incompleteSize(path: String, errors: [String])

    var errorDescription: String? {
        switch self {
        case .fullDiskAccessRequired:
            "Mail Downloads not scanned: Full Disk Access is required to read Mail's container."
        case let .incompleteSize(path, errors):
            "Unable to calculate the complete size of \(path): \(errors.joined(separator: "; "))."
        }
    }
}
