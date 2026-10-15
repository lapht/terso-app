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

/// The current state of one module in a Smart Scan.
public enum SmartScanModuleStatus: Sendable, Equatable {
    /// The module has started scanning.
    case scanning

    /// The module completed successfully.
    case completed

    /// The module could not scan completely without Full Disk Access.
    case requiresPermission(message: String)

    /// The module failed; other modules continue scanning.
    case failed(message: String)
}

/// A progress update emitted as Smart Scan modules start and finish.
public struct SmartScanProgress: Sendable, Equatable {
    /// The module associated with this update, if any.
    public let moduleID: String?

    /// The user-facing module name associated with this update, if any.
    public let moduleTitle: String?

    /// The status of the associated module, if any.
    public let moduleStatus: SmartScanModuleStatus?

    /// Number of modules that reached a terminal state.
    public let completedModules: Int

    /// Number of registered modules.
    public let totalModules: Int

    /// Number of items found by modules completed so far.
    public let itemsFound: Int

    /// Total bytes found by modules completed so far.
    public let bytesFound: Int64

    /// Completion fraction between zero and one.
    public var fractionCompleted: Double {
        guard totalModules > 0 else {
            return 1
        }
        return Double(completedModules) / Double(totalModules)
    }

    init(
        moduleID: String?,
        moduleTitle: String?,
        moduleStatus: SmartScanModuleStatus?,
        completedModules: Int,
        totalModules: Int,
        itemsFound: Int,
        bytesFound: Int64
    ) {
        self.moduleID = moduleID
        self.moduleTitle = moduleTitle
        self.moduleStatus = moduleStatus
        self.completedModules = completedModules
        self.totalModules = totalModules
        self.itemsFound = itemsFound
        self.bytesFound = bytesFound
    }
}

/// A module scan failure retained in the aggregate result.
public struct SmartScanModuleError: Error, Sendable, Equatable {
    /// Identifier of the module that failed.
    public let moduleID: String

    /// User-facing name of the module that failed.
    public let moduleTitle: String

    /// Description supplied by the module's error.
    public let message: String
}

/// A module that was skipped because Full Disk Access is unavailable.
public struct SmartScanPermissionRequirement: Sendable, Equatable {
    /// Identifier of the module that requires permission.
    public let moduleID: String

    /// User-facing name of the module that requires permission.
    public let moduleTitle: String

    /// Instructions for enabling the required permission.
    public let message: String
}

/// The read-only results of one Smart Scan.
public struct SmartScanResult: Sendable, Equatable {
    /// All discovered items, ordered by module registration and scan order.
    public let items: [CleanItem]

    /// Failures from modules that did not complete successfully.
    public let errors: [SmartScanModuleError]

    /// Modules skipped because Full Disk Access is unavailable.
    public let permissionRequirements: [SmartScanPermissionRequirement]

    /// Number of modules that reached a terminal state.
    public let completedModules: Int

    /// Number of registered modules.
    public let totalModules: Int

    /// Total bytes represented by `items`.
    public let bytesFound: Int64
}

/// Runs registered cleanup modules concurrently and aggregates their read-only scan results.
public struct SmartScanAggregator: Sendable {
    private enum ModuleOutcome: Sendable {
        case completed([CleanItem])
        case requiresPermission(String)
        case failed(String)
    }

    private struct IndexedOutcome: Sendable {
        let index: Int
        let moduleID: String
        let moduleTitle: String
        let outcome: ModuleOutcome
    }

    private struct ProgressState {
        let totalModules: Int
        var completedModules = 0
        var itemsFound = 0
        var bytesFound: Int64 = 0

        func update(
            moduleID: String,
            moduleTitle: String,
            status: SmartScanModuleStatus
        ) -> SmartScanProgress {
            SmartScanProgress(
                moduleID: moduleID,
                moduleTitle: moduleTitle,
                moduleStatus: status,
                completedModules: completedModules,
                totalModules: totalModules,
                itemsFound: itemsFound,
                bytesFound: bytesFound
            )
        }

        mutating func record(_ outcome: IndexedOutcome) -> SmartScanModuleStatus {
            completedModules += 1
            switch outcome.outcome {
            case let .completed(items):
                itemsFound += items.count
                bytesFound += items.reduce(into: Int64.zero) { $0 += $1.sizeBytes }
                return .completed
            case let .requiresPermission(message):
                return .requiresPermission(message: message)
            case let .failed(message):
                return .failed(message: message)
            }
        }
    }

    private let tccManager: TCCManager

    public init(tccManager: TCCManager = TCCManager()) {
        self.tccManager = tccManager
    }

    /// Scans all modules concurrently. Smart Scan always forces dry-run mode,
    /// regardless of the value passed in `context`.
    ///
    /// Progress is reported on the calling task as each module starts and completes.
    /// A module failure is included in the result and does not stop other modules.
    /// Cancelling the calling task cancels child scans cooperatively and throws
    /// `CancellationError` instead of returning a partial result.
    public func scan(
        modules: [any CleanModule],
        context: ScanContext,
        onProgress: (@Sendable (SmartScanProgress) -> Void)? = nil
    ) async throws -> SmartScanResult {
        let outcomes = try await scanModules(
            modules,
            context: Self.dryRunContext(from: context),
            onProgress: onProgress
        )
        return Self.makeResult(outcomes: outcomes, totalModules: modules.count)
    }

    private func scanModules(
        _ modules: [any CleanModule],
        context: ScanContext,
        onProgress: (@Sendable (SmartScanProgress) -> Void)?
    ) async throws -> [IndexedOutcome] {
        var progressState = ProgressState(totalModules: modules.count)
        var outcomes: [IndexedOutcome] = []

        try await withThrowingTaskGroup(of: IndexedOutcome.self) { group in
            for (index, module) in modules.enumerated() {
                try Task.checkCancellation()
                onProgress?(progressState.update(
                    moduleID: module.id,
                    moduleTitle: module.title,
                    status: .scanning
                ))
                group.addTask { [tccManager] in
                    try await Self.scanModule(
                        module,
                        index: index,
                        context: context,
                        tccManager: tccManager
                    )
                }
            }

            while let outcome = try await group.next() {
                try Task.checkCancellation()
                outcomes.append(outcome)
                let status = progressState.record(outcome)
                onProgress?(progressState.update(
                    moduleID: outcome.moduleID,
                    moduleTitle: outcome.moduleTitle,
                    status: status
                ))
            }
        }

        return outcomes
    }

    private static func scanModule(
        _ module: any CleanModule,
        index: Int,
        context: ScanContext,
        tccManager: TCCManager
    ) async throws -> IndexedOutcome {
        do {
            try Task.checkCancellation()
            switch try await tccManager.scan(module: module, context: context) {
            case let .completed(items):
                return IndexedOutcome(
                    index: index,
                    moduleID: module.id,
                    moduleTitle: module.title,
                    outcome: .completed(items)
                )
            case let .requiresPermission(message):
                return IndexedOutcome(
                    index: index,
                    moduleID: module.id,
                    moduleTitle: module.title,
                    outcome: .requiresPermission(message)
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return IndexedOutcome(
                index: index,
                moduleID: module.id,
                moduleTitle: module.title,
                outcome: .failed(error.localizedDescription)
            )
        }
    }

    private static func makeResult(
        outcomes: [IndexedOutcome],
        totalModules: Int
    ) -> SmartScanResult {
        var items: [CleanItem] = []
        var errors: [SmartScanModuleError] = []
        var permissionRequirements: [SmartScanPermissionRequirement] = []

        for outcome in outcomes.sorted(by: { $0.index < $1.index }) {
            switch outcome.outcome {
            case let .completed(moduleItems):
                items.append(contentsOf: moduleItems)
            case let .requiresPermission(message):
                permissionRequirements.append(
                    SmartScanPermissionRequirement(
                        moduleID: outcome.moduleID,
                        moduleTitle: outcome.moduleTitle,
                        message: message
                    )
                )
            case let .failed(message):
                errors.append(
                    SmartScanModuleError(
                        moduleID: outcome.moduleID,
                        moduleTitle: outcome.moduleTitle,
                        message: message
                    )
                )
            }
        }

        return SmartScanResult(
            items: items,
            errors: errors,
            permissionRequirements: permissionRequirements,
            completedModules: outcomes.count,
            totalModules: totalModules,
            bytesFound: items.reduce(into: Int64.zero) { $0 += $1.sizeBytes }
        )
    }

    private static func dryRunContext(from context: ScanContext) -> ScanContext {
        ScanContext(
            homeDirectory: context.homeDirectory,
            mountedVolumes: context.mountedVolumes,
            isDryRun: true,
            exclusions: context.exclusions,
            tccStatus: context.tccStatus
        )
    }
}
