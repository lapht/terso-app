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

enum OldFilesRootKind {
    case downloads
    case desktop
    case screenshotFolder
}

/// One read-only pass of ``OldFilesScanner``. Holds the mutable results; performs no write.
struct OldFilesRun {
    private static let imageExtensions: Set = ["png", "jpg", "jpeg"]
    private static let videoExtensions: Set = ["mov", "mp4"]
    private static let installerExtensions: Set = ["dmg", "pkg"]
    private static let archiveExtensions: Set = ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"]

    /// Localized prefixes used by macOS for screenshot / screen recording file names.
    private static let screenshotPrefixes = [
        "Screenshot", "Schermata", "Bildschirmfoto", "Capture d’écran", "Captura de pantalla"
    ]
    private static let recordingPrefixes = [
        "Screen Recording", "Registrazione schermo", "Bildschirmaufnahme",
        "Enregistrement de l’écran", "Grabación de pantalla"
    ]

    private static let projectMarkers: Set = [
        ".git", ".hg", ".svn", "Package.swift", "package.json", "Cargo.toml", "go.mod", "pom.xml",
        "build.gradle", "build.gradle.kts", "pyproject.toml", "Gemfile", "composer.json", "CMakeLists.txt"
    ]
    private static let projectExtensions: Set = ["xcodeproj", "xcworkspace"]
    private static let syncMarkers: Set = [".dropbox", ".dropbox.attr", ".dropbox.cache"]
    private static let syncFolderNames = [
        "dropbox", "google drive", "googledrive", "onedrive", "icloud drive", "box sync", "pcloud", "nextcloud",
        "synology drive", "mega"
    ]

    private let scanner: OldFilesScanner
    private let home: URL
    private let screenshotFolderPath: String
    private let referenceNow: Date
    private var found: [String: OldFileItem] = [:]
    private var notScanned: [String: OldFilesNotScanned] = [:]
    private var datalessCount = 0

    init(scanner: OldFilesScanner, home: URL, screenshotFolderPath: String) {
        self.scanner = scanner
        self.home = home
        self.screenshotFolderPath = screenshotFolderPath
        referenceNow = scanner.now()
    }

    func report() -> OldFilesReport {
        OldFilesReport(
            items: found.values.sorted { $0.url.path < $1.url.path },
            notScanned: notScanned.values.sorted { $0.url.path < $1.url.path },
            skippedDatalessCount: datalessCount
        )
    }

    mutating func addNotScanned(_ url: URL, _ reason: String) {
        notScanned[url.path] = OldFilesNotScanned(url: url, reason: reason)
    }

    static func isInside(_ url: URL, of root: URL) -> Bool {
        let path = url.standardizedFileURL.pathComponents
        let base = root.standardizedFileURL.pathComponents
        return path.count > base.count && zip(path, base).allSatisfy { $0 == $1 }
    }

    /// A custom screenshot folder must be strictly inside the home, outside Documents and Library.
    func isAllowedScreenshotFolder(_ url: URL) -> Bool {
        Self.isInside(url, of: home)
            && !Self.isInside(url, of: home.appendingPathComponent("Documents"))
            && !Self.isInside(url, of: home.appendingPathComponent("Library"))
            && url.path != home.appendingPathComponent("Documents").path
            && url.path != home.appendingPathComponent("Library").path
    }

    // MARK: - Traversal

    mutating func scanRoot(_ root: URL, kind: OldFilesRootKind) {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return
        }
        let values = try? root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values?.isSymbolicLink == true {
            addNotScanned(root, "Folder is a symbolic link and is not followed")
            return
        }
        guard values?.isDirectory == true else {
            return
        }
        walk(root, kind: kind, isRoot: true)
    }

    private mutating func walk(_ directory: URL, kind: OldFilesRootKind, isRoot: Bool) {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey],
                options: []
            )
        } catch {
            addNotScanned(directory, "Not scanned: \(error.localizedDescription)")
            return
        }
        if !isRoot, Self.looksLikeProjectOrSync(entries.map(\.lastPathComponent)) {
            return
        }
        for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
            visit(entry, kind: kind)
        }
    }

    private mutating func visit(_ entry: URL, kind: OldFilesRootKind) {
        let values: URLResourceValues
        do {
            values = try entry.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey]
            )
        } catch {
            addNotScanned(entry, "Not scanned: \(error.localizedDescription)")
            return
        }
        if values.isSymbolicLink == true {
            return
        }
        if values.isDirectory == true {
            let name = entry.lastPathComponent.lowercased()
            // Packages (including `.photoslibrary`) stay opaque, sync folders are never touched.
            if values.isPackage == true || name.hasSuffix(".photoslibrary")
                || Self.isSyncFolderName(name)
                || entry.path.contains("/Library/CloudStorage/") {
                return
            }
            if scanner.metadata.isDataless(entry) {
                datalessCount += 1
                return
            }
            walk(entry, kind: kind, isRoot: false)
        } else if values.isRegularFile == true {
            consider(entry, kind: kind)
        }
    }

    private static func isSyncFolderName(_ lowercasedName: String) -> Bool {
        syncFolderNames.contains {
            lowercasedName == $0 || lowercasedName.hasPrefix($0 + " (") || lowercasedName.hasPrefix($0 + "-")
        }
    }

    private static func looksLikeProjectOrSync(_ names: [String]) -> Bool {
        names.contains { name in
            projectMarkers.contains(name) || syncMarkers.contains(name)
                || projectExtensions.contains((name as NSString).pathExtension.lowercased())
        }
    }

    // MARK: - Classification

    private mutating func consider(_ file: URL, kind: OldFilesRootKind) {
        let ext = file.pathExtension.lowercased()
        let isImage = Self.imageExtensions.contains(ext)
        let isVideo = Self.videoExtensions.contains(ext)
        let isInstaller = Self.installerExtensions.contains(ext) && kind != .screenshotFolder
        let isArchive = Self.archiveExtensions.contains(ext) && kind == .downloads
        guard isImage || isVideo || isInstaller || isArchive else {
            return
        }
        // Nothing below reads content until the placeholder check has passed.
        if scanner.metadata.isDataless(file) {
            datalessCount += 1
            return
        }
        guard let fileDate = fileSystemDate(of: file), referenceNow.timeIntervalSince(fileDate) >= scanner.minimumAge
        else {
            return
        }
        let used = scanner.metadata.lastUsedDate(of: file)
        let activity = max(used ?? .distantPast, fileDate)
        guard referenceNow.timeIntervalSince(activity) >= scanner.minimumAge else {
            return
        }
        let signal: OldFileDateSignal = (used ?? .distantPast) >= fileDate ? .lastUsed : .modified

        let candidate: Candidate = isInstaller ? .installer : isArchive ? .archive : isVideo ? .video : .image
        guard let match = classify(file, ext: ext, candidate: candidate) else {
            return
        }
        guard let size = try? SizeCalculator().calculate(at: file), size.errors.isEmpty else {
            addNotScanned(file, "Size could not be read completely")
            return
        }
        found[file.path] = OldFileItem(
            category: match.category,
            url: file,
            sizeBytes: size.bytes,
            reason: match.reason,
            referenceDate: activity,
            dateSignal: signal
        )
    }

    private mutating func fileSystemDate(of file: URL) -> Date? {
        guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]),
              let date = [values.contentModificationDate, values.creationDate].compactMap({ $0 }).max()
        else {
            addNotScanned(file, "Dates could not be read")
            return nil
        }
        return date
    }

    private enum Candidate {
        case installer, archive, image, video
    }

    private func classify(
        _ file: URL,
        ext: String,
        candidate: Candidate
    ) -> (category: OldFileCategory, reason: String)? {
        let isVideo = candidate == .video
        switch candidate {
        case .installer:
            return (.installer, "Installer (.\(ext))")
        case .archive:
            return (.archive, "Archive (.\(ext)) in Downloads")
        case .image, .video:
            break
        }
        let flag = scanner.metadata.isScreenCapture(file)
        let reason: String
        if flag == true {
            reason = "Marked as a screen capture by macOS"
        } else if flag == nil, isDirectlyInScreenshotFolder(file),
                  let nameReason = nameFallbackReason(file.lastPathComponent, ext: ext, isVideo: isVideo) {
            reason = nameReason
        } else {
            return nil
        }
        if isVideo {
            return (.screenRecording, reason)
        }
        // Photos are never returned: only an image with a readable header and no camera data passes.
        guard scanner.metadata.imageOrigin(of: file) == .noCameraInfo else {
            return nil
        }
        return (.screenshot, reason)
    }

    private func isDirectlyInScreenshotFolder(_ file: URL) -> Bool {
        file.deletingLastPathComponent().standardizedFileURL.path == screenshotFolderPath
    }

    /// Last resort, accepted only for `.png` / `.mov` directly inside the screenshot folder.
    private func nameFallbackReason(_ name: String, ext: String, isVideo: Bool) -> String? {
        if isVideo, ext == "mov", Self.recordingPrefixes.contains(where: name.hasPrefix) {
            return "Named like a screen recording in the screenshot folder"
        }
        if !isVideo, ext == "png", Self.screenshotPrefixes.contains(where: name.hasPrefix) {
            return "Named like a screenshot in the screenshot folder"
        }
        return nil
    }
}
