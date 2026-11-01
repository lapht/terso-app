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

/// The kinds of old file Terso reports. Deliberately not "everything old".
public enum OldFileCategory: String, Sendable, CaseIterable, Hashable {
    case screenshot
    case screenRecording
    case installer
    case archive
}

/// Which date decided that a file is old.
public enum OldFileDateSignal: String, Sendable, Hashable {
    /// `kMDItemLastUsedDate` was the most recent signal.
    case lastUsed
    /// Nothing more recent than the modification/creation date was recorded (approximate).
    case modified
}

/// An old file found by ``OldFilesScanner``. Informational: never deletable from this module.
public struct OldFileItem: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let category: OldFileCategory
    public let url: URL
    public let sizeBytes: Int64
    /// Why the file was matched, in plain words.
    public let reason: String
    /// The date compared with the age threshold.
    public let referenceDate: Date
    public let dateSignal: OldFileDateSignal

    public init(
        category: OldFileCategory,
        url: URL,
        sizeBytes: Int64,
        reason: String,
        referenceDate: Date,
        dateSignal: OldFileDateSignal
    ) {
        self.category = category
        self.url = url
        self.sizeBytes = sizeBytes
        self.reason = reason
        self.referenceDate = referenceDate
        self.dateSignal = dateSignal
    }
}

/// A location (or file) that could not be read, so it is NOT reported as empty.
public struct OldFilesNotScanned: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }
}

public struct OldFilesReport: Sendable, Equatable {
    public let items: [OldFileItem]
    public let notScanned: [OldFilesNotScanned]
    /// Candidate files/folders skipped because they are iCloud placeholders (0 bytes on disk).
    public let skippedDatalessCount: Int

    public init(items: [OldFileItem], notScanned: [OldFilesNotScanned], skippedDatalessCount: Int) {
        self.items = items
        self.notScanned = notScanned
        self.skippedDatalessCount = skippedDatalessCount
    }
}

/// Read-only discovery of old screenshots, screen recordings, installers and archives in
/// `~/Downloads`, `~/Desktop` and the configured screenshot folder. It never modifies, moves
/// or deletes anything, and it returns no photo: only screenshots proven by macOS (or, as a last
/// resort, by name inside the screenshot folder) with no camera metadata are eligible images.
public struct OldFilesScanner: Sendable {
    /// Conservative default: one year.
    public static let defaultMinimumAge: TimeInterval = 365 * 24 * 60 * 60

    let minimumAge: TimeInterval
    let screenshotFolder: URL?
    let metadata: any OldFileMetadataReading
    let now: @Sendable () -> Date

    /// - Parameters:
    ///   - minimumAge: Seconds since the last activity before a file is reported (negative → 0).
    ///   - screenshotFolder: Overrides `com.apple.screencapture location` (default `~/Desktop`).
    public init(
        minimumAge: TimeInterval = OldFilesScanner.defaultMinimumAge,
        screenshotFolder: URL? = nil,
        metadata: any OldFileMetadataReading = SystemOldFileMetadata(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.minimumAge = max(0, minimumAge)
        self.screenshotFolder = screenshotFolder
        self.metadata = metadata
        self.now = now
    }

    /// The folder where macOS saves screenshots: the `location` default, else `~/Desktop`.
    public static func configuredScreenshotFolder(home: URL) -> URL {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        if let path = defaults?.string(forKey: "location"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }

    public func scan(homeDirectory: URL) -> OldFilesReport {
        let home = homeDirectory.standardizedFileURL
        let screenshotURL = (screenshotFolder ?? Self.configuredScreenshotFolder(home: home)).standardizedFileURL
        var run = OldFilesRun(scanner: self, home: home, screenshotFolderPath: screenshotURL.path)

        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        run.scanRoot(downloads, kind: .downloads)
        run.scanRoot(desktop, kind: .desktop)

        // The screenshot folder is its own root only when the roots above do not already cover it.
        let covered = OldFilesRun.isInside(screenshotURL, of: downloads)
            || OldFilesRun.isInside(screenshotURL, of: desktop)
            || screenshotURL.path == downloads.path
            || screenshotURL.path == desktop.path
        if !covered {
            if run.isAllowedScreenshotFolder(screenshotURL) {
                run.scanRoot(screenshotURL, kind: .screenshotFolder)
            } else {
                run.addNotScanned(screenshotURL, "Screenshot folder is outside the home folder or in a protected area")
            }
        }
        return run.report()
    }
}
