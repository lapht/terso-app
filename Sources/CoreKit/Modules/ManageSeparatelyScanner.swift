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

/// The kinds of large item Terso only reports, because the owning tool should remove them.
public enum ManagedItemKind: String, Sendable, CaseIterable, Hashable {
    case ollamaModels
    case huggingFaceCache
    case lmStudioModels
    case iosBackup
    case virtualMachine
    case dockerDesktopDisk
    case macOSInstaller

    /// Whether the content can be downloaded or generated again if removed.
    public var isRedownloadable: Bool {
        switch self {
        case .ollamaModels, .huggingFaceCache, .lmStudioModels, .macOSInstaller:
            true
        case .iosBackup, .virtualMachine, .dockerDesktopDisk:
            false
        }
    }
}

/// A large item found by ``ManageSeparatelyScanner``. It is informational: never deletable from Terso.
public struct ManagedItem: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let kind: ManagedItemKind
    public let url: URL
    public let sizeBytes: Int64
    /// Modification date of the item itself (not of every file inside it).
    public let lastModified: Date?

    public init(kind: ManagedItemKind, url: URL, sizeBytes: Int64, lastModified: Date?) {
        self.kind = kind
        self.url = url
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
    }
}

/// A location that exists but could not be fully read, so its size is not shown.
public struct ManageSeparatelyNotScanned: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let kind: ManagedItemKind
    public let url: URL
    public let reason: String

    public init(kind: ManagedItemKind, url: URL, reason: String) {
        self.kind = kind
        self.url = url
        self.reason = reason
    }
}

public struct ManageSeparatelyReport: Sendable, Equatable {
    public let items: [ManagedItem]
    public let notScanned: [ManageSeparatelyNotScanned]

    public init(items: [ManagedItem], notScanned: [ManageSeparatelyNotScanned]) {
        self.items = items
        self.notScanned = notScanned
    }
}

/// Read-only discovery of local AI models, device backups, virtual machines, Docker's disk and
/// macOS installers. It never modifies, moves or deletes anything and never preselects anything.
///
/// A location that exists but cannot be read is reported as not scanned instead of being
/// silently omitted or shown with a partial size.
public struct ManageSeparatelyScanner: Sendable {
    private let environment: [String: String]
    private let applicationDirectories: [URL]?

    /// - Parameters:
    ///   - environment: Source of `OLLAMA_MODELS`, `HF_HUB_CACHE` and `HF_HOME`.
    ///   - applicationDirectories: Where to look for `Install macOS *.app`; defaults to
    ///     `/Applications` and `~/Applications`.
    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        applicationDirectories: [URL]? = nil
    ) {
        self.environment = environment
        self.applicationDirectories = applicationDirectories
    }

    public func scan(homeDirectory: URL) -> ManageSeparatelyReport {
        var collector = ManageSeparatelyCollector()
        let home = homeDirectory.standardizedFileURL

        collector.addTree(
            .ollamaModels,
            at: expandedPath(environment["OLLAMA_MODELS"]) ?? home.appendingPathComponent(".ollama/models")
        )
        collector.addTree(.huggingFaceCache, at: huggingFaceCache(home: home))
        for url in lmStudioFolders(home: home) {
            collector.addTree(.lmStudioModels, at: url)
        }
        collector.addChildren(
            .iosBackup,
            of: home.appendingPathComponent("Library/Application Support/MobileSync/Backup"),
            matching: { _, isDirectory in isDirectory }
        )
        let vmExtensions: Set<String> = ["utm", "pvm", "vmwarevm"]
        for root in virtualMachineRoots(home: home) {
            collector.addChildren(
                .virtualMachine,
                of: root,
                matching: { name, _ in vmExtensions.contains((name as NSString).pathExtension.lowercased()) }
            )
        }
        collector.addDockerDisk(home: home)
        let installerRoots = applicationDirectories
            ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        for directory in installerRoots {
            collector.addChildren(
                .macOSInstaller,
                of: directory,
                matching: { name, _ in name.hasPrefix("Install macOS ") && name.hasSuffix(".app") }
            )
        }
        return collector.report()
    }

    private func expandedPath(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
    }

    private func huggingFaceCache(home: URL) -> URL {
        if let explicit = expandedPath(environment["HF_HUB_CACHE"]) {
            return explicit
        }
        if let hfHome = expandedPath(environment["HF_HOME"]) {
            return hfHome.appendingPathComponent("hub")
        }
        return home.appendingPathComponent(".cache/huggingface/hub")
    }

    /// The configured downloads folder from LM Studio's settings, plus its default locations.
    private func lmStudioFolders(home: URL) -> [URL] {
        var folders: [URL] = []
        let settings = home.appendingPathComponent(".lmstudio/settings.json")
        if let data = try? Data(contentsOf: settings),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let configured = expandedPath(object["downloadsFolder"] as? String) {
            folders.append(configured)
        }
        for fallback in [".lmstudio/models", ".cache/lm-studio/models"] {
            let url = home.appendingPathComponent(fallback)
            if !folders.contains(where: { $0.standardizedFileURL.path == url.standardizedFileURL.path }) {
                folders.append(url)
            }
        }
        return folders
    }

    private func virtualMachineRoots(home: URL) -> [URL] {
        [
            "Library/Containers/com.utmapp.UTM/Data/Documents",
            "Parallels",
            "Documents/Parallels",
            "Virtual Machines.localized",
            "Virtual Machines",
            "Documents/Virtual Machines.localized",
            "Documents/Virtual Machines"
        ].map { home.appendingPathComponent($0) }
    }
}

private struct ManageSeparatelyCollector {
    private var items: [ManagedItem] = []
    private var notScanned: [ManageSeparatelyNotScanned] = []
    private var seen: Set<String> = []

    func report() -> ManageSeparatelyReport {
        ManageSeparatelyReport(
            items: items.sorted { lhs, rhs in
                lhs.sizeBytes != rhs.sizeBytes ? lhs.sizeBytes > rhs.sizeBytes : lhs.url.path < rhs.url.path
            },
            notScanned: notScanned.sorted { $0.url.path < $1.url.path }
        )
    }

    /// Reports `url` itself as one item when it exists.
    mutating func addTree(_ kind: ManagedItemKind, at url: URL) {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            return
        }
        measure(kind, at: resolved)
    }

    /// Reports each matching child of `directory` as one item.
    mutating func addChildren(
        _ kind: ManagedItemKind,
        of directory: URL,
        matching predicate: (String, Bool) -> Bool
    ) {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.path) else {
            return
        }
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            notScanned.append(.init(kind: kind, url: root, reason: Self.describe(error)))
            return
        }
        for child in children.sorted(by: { $0.path < $1.path }) {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isSymbolicLink != true,
                  predicate(child.lastPathComponent, values?.isDirectory == true) else {
                continue
            }
            measure(kind, at: child.standardizedFileURL)
        }
    }

    mutating func addDockerDisk(home: URL) {
        let root = home.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms")
            .resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.path) else {
            return
        }
        var failure: String?
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, error in
                failure = Self.describe(error)
                return false
            }
        )
        let diskNames: Set<String> = ["Docker.raw", "Docker.qcow2", "DockerDesktop.raw"]
        var disks: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if diskNames.contains(url.lastPathComponent) {
                disks.append(url.standardizedFileURL)
            }
        }
        if let failure {
            notScanned.append(.init(kind: .dockerDesktopDisk, url: root, reason: failure))
        }
        for disk in disks {
            measure(.dockerDesktopDisk, at: disk)
        }
    }

    private mutating func measure(_ kind: ManagedItemKind, at url: URL) {
        guard seen.insert(url.path).inserted else {
            return
        }
        do {
            let size = try SizeCalculator().calculate(at: url)
            guard size.errors.isEmpty else {
                notScanned.append(.init(
                    kind: kind,
                    url: url,
                    reason: size.errors.first?.message ?? "Some files could not be read."
                ))
                return
            }
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            items.append(ManagedItem(kind: kind, url: url, sizeBytes: size.bytes, lastModified: modified))
        } catch {
            notScanned.append(.init(kind: kind, url: url, reason: Self.describe(error)))
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        let isCocoaDenied = nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError
        let isPOSIXDenied = nsError.domain == NSPOSIXErrorDomain
            && (nsError.code == Int(EPERM) || nsError.code == Int(EACCES))
        if isCocoaDenied || isPOSIXDenied {
            return "Permission denied. Grant Full Disk Access to scan this location."
        }
        return error.localizedDescription
    }
}
