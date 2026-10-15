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

import Combine
import CoreKit
import Darwin
import Foundation

enum SmartScanViewState: Equatable {
    case idle
    case scanning
    case finished
    case cancelled
    case failed(String)
}

enum SmartScanModuleSummaryStatus: Equatable {
    case completed
    case requiresPermission(String)
    case failed(String)
    case notScanned
}

struct SmartScanModuleSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let itemsFound: Int
    let bytesFound: Int64
    let status: SmartScanModuleSummaryStatus
}

@MainActor
final class SmartScanViewModel: ObservableObject {
    @Published private(set) var state: SmartScanViewState = .idle
    @Published private(set) var progress: SmartScanProgress?
    @Published private(set) var activeModuleTitles: [String] = []
    @Published private(set) var result: SmartScanResult?

    private let aggregator: SmartScanAggregator
    private let deletionPipeline: DeletionPipeline
    private let modules: [any CleanModule]
    private let context: ScanContext
    private var scanTask: Task<Void, Never>?
    private var selectionViewModels: [String: ModuleSelectionViewModel] = [:]

    var reclaimableBytes: Int64 {
        result?.items.reduce(into: Int64.zero) { total, item in
            if item.isDeletable {
                total += item.sizeBytes
            }
        } ?? 0
    }

    var homeDirectory: URL {
        context.homeDirectory
    }

    var moduleSummaries: [SmartScanModuleSummary] {
        guard let result else {
            return []
        }

        return modules.map { module in
            let moduleItems = result.items.filter { $0.moduleId == module.id }
            let status: SmartScanModuleSummaryStatus
            if let requirement = result.permissionRequirements.first(where: {
                $0.moduleID == module.id
            }) {
                status = .requiresPermission(requirement.message)
            } else if let error = result.errors.first(where: { $0.moduleID == module.id }) {
                status = .failed(error.message)
            } else {
                status = .completed
            }

            return SmartScanModuleSummary(
                id: module.id,
                title: module.title,
                itemsFound: moduleItems.count,
                bytesFound: moduleItems.reduce(into: Int64.zero) { $0 += $1.sizeBytes },
                status: status
            )
        }
    }

    func items(for moduleID: String) -> [CleanItem] {
        result?.items.filter { $0.moduleId == moduleID } ?? []
    }

    func selectionViewModel(for moduleID: String) -> ModuleSelectionViewModel {
        if let viewModel = selectionViewModels[moduleID] {
            return viewModel
        }
        let viewModel = ModuleSelectionViewModel(items: items(for: moduleID))
        selectionViewModels[moduleID] = viewModel
        return viewModel
    }

    func moveToTrash(items: [CleanItem]) throws {
        _ = try deletionPipeline.execute(
            items: items,
            allowedRootsByModule: allowedRootsByModule,
            dryRun: false
        )
    }

    init(
        tccManager: TCCManager = TCCManager(),
        aggregator: SmartScanAggregator? = nil,
        modules: [any CleanModule]? = nil,
        context: ScanContext? = nil
    ) {
        self.aggregator = aggregator ?? SmartScanAggregator(tccManager: tccManager)
        self.modules = modules ?? Self.defaultModules
        let resolvedContext = context ?? Self.makeScanContext(tccManager: tccManager)
        self.context = resolvedContext
        deletionPipeline = DeletionPipeline(homeDirectory: resolvedContext.homeDirectory)
    }

    func startScan() {
        guard scanTask == nil else {
            return
        }

        progress = nil
        activeModuleTitles = []
        result = nil
        selectionViewModels.removeAll()
        state = .scanning

        let aggregator = self.aggregator
        let modules = self.modules
        let context = self.context
        scanTask = Task { [weak self] in
            do {
                let scanResult = try await aggregator.scan(
                    modules: modules,
                    context: context,
                    onProgress: { [weak self] update in
                        Task { @MainActor [weak self] in
                            self?.recordProgress(update)
                        }
                    }
                )
                guard let self else {
                    return
                }
                self.result = scanResult
                self.activeModuleTitles.removeAll()
                self.state = .finished
            } catch is CancellationError {
                self?.activeModuleTitles.removeAll()
                self?.state = .cancelled
            } catch {
                self?.activeModuleTitles.removeAll()
                self?.state = .failed(error.localizedDescription)
            }
            self?.scanTask = nil
        }
    }

    func cancelScan() {
        guard state == .scanning else {
            return
        }
        scanTask?.cancel()
    }

    private func recordProgress(_ update: SmartScanProgress) {
        guard state == .scanning else {
            return
        }
        progress = update
        guard let moduleTitle = update.moduleTitle else {
            return
        }

        switch update.moduleStatus {
        case .scanning:
            if !activeModuleTitles.contains(moduleTitle) {
                activeModuleTitles.append(moduleTitle)
            }
        case .completed, .requiresPermission, .failed:
            activeModuleTitles.removeAll { $0 == moduleTitle }
        case nil:
            break
        }
    }

    private var allowedRootsByModule: [String: [URL]] {
        let home = context.homeDirectory
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let developer = library.appendingPathComponent("Developer", isDirectory: true)
        var roots: [String: [URL]] = [
            "caches.user": [
                library.appendingPathComponent("Caches", isDirectory: true)
            ],
            "logs.user": [
                library.appendingPathComponent("Logs", isDirectory: true)
            ],
            "trash.user": [
                home.appendingPathComponent(".Trash", isDirectory: true)
            ],
            "xcode.junk": [
                developer.appendingPathComponent("Xcode/DerivedData", isDirectory: true),
                developer.appendingPathComponent("Xcode/Archives", isDirectory: true),
                developer.appendingPathComponent("CoreSimulator/Caches", isDirectory: true)
            ],
            "caches.packages": [
                home.appendingPathComponent(".npm", isDirectory: true),
                library.appendingPathComponent("Caches", isDirectory: true),
                home.appendingPathComponent(".cache", isDirectory: true)
            ]
        ]

        let userID = String(getuid())
        for volume in context.mountedVolumes where Self.isExternalVolumeMount(volume.mountPath) {
            let volumeTrash = volume.mountPath
                .appendingPathComponent(".Trashes", isDirectory: true)
                .appendingPathComponent(userID, isDirectory: true)
            roots["trash.user", default: []].append(volumeTrash)
        }
        return roots
    }

    private static func isExternalVolumeMount(_ mountPath: URL) -> Bool {
        let standardizedPath = mountPath.standardizedFileURL
        return standardizedPath.deletingLastPathComponent().lastPathComponent == "Volumes"
            && standardizedPath.lastPathComponent != "Volumes"
    }

    private static let defaultModules: [any CleanModule] = [
        UserCachesModule(),
        UserLogsModule(),
        TrashBinsModule(),
        XcodeJunkModule(),
        PackageCachesModule()
    ]

    private static func makeScanContext(tccManager: TCCManager) -> ScanContext {
        let fileManager = FileManager.default
        let mountedVolumes =
            fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [])?
            .map {
                VolumeInfo(
                    mountPath: $0,
                    filesystemType: "unknown",
                    isReadOnly: false,
                    uuid: nil
                )
            } ?? []

        return ScanContext(
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            mountedVolumes: mountedVolumes,
            isDryRun: true,
            tccStatus: tccManager.status
        )
    }
}
