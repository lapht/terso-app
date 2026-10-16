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
import Combine
import CoreKit
import SwiftUI
import UniformTypeIdentifiers

private struct AuditLogEntry: Identifiable {
    let id: Int
    let record: AuditRecord
}

@MainActor
struct AuditLogView: View {
    @StateObject private var viewModel: AuditLogViewModel
    @State private var exportError: String?

    init(logger: AuditLogger = AuditLogger()) {
        _viewModel = StateObject(wrappedValue: AuditLogViewModel(logger: logger))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Audit Log", systemImage: "list.bullet.rectangle")
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityIdentifier("audit-log-title")
                Spacer()
                Button("Export Audit Log", systemImage: "square.and.arrow.up", action: exportLog)
                    .accessibilityIdentifier("audit-log-export")
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("audit-log-error")
            } else if viewModel.records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Audit Events")
                        .font(.headline)
                    Text("Cleanup operations will appear here.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("audit-log-empty")
            } else {
                Table(viewModel.records.enumerated().map {
                    AuditLogEntry(id: $0.offset, record: $0.element)
                }) {
                    TableColumn("Timestamp") { entry in
                        Text(entry.record.timestamp)
                            .lineLimit(1)
                    }
                    .width(min: 190)

                    TableColumn("Rule") { entry in
                        Text(entry.record.ruleId)
                            .lineLimit(1)
                    }
                    .width(min: 150)

                    TableColumn("Path") { entry in
                        Text(entry.record.originalPath)
                            .lineLimit(1)
                            .help(entry.record.originalPath)
                    }

                    TableColumn("Result") { entry in
                        Label(
                            entry.record.result.rawValue.capitalized,
                            systemImage: entry.record.result == .success
                                ? "checkmark.circle"
                                : "exclamationmark.circle"
                        )
                        .foregroundStyle(entry.record.result == .success ? Color.secondary : Color.red)
                    }
                    .width(min: 110)
                }
                .accessibilityIdentifier("audit-log-table")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: viewModel.refresh)
        .alert(
            "Unable to Export Audit Log",
            isPresented: Binding(
                get: { exportError != nil },
                set: { isPresented in
                    if !isPresented {
                        exportError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                exportError = nil
            }
        } message: {
            if let exportError {
                Text(exportError)
            }
        }
    }

    private func exportLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "terso-audit-report.txt"
        panel.title = "Export Audit Log"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try viewModel.export(to: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

@MainActor
final class AuditLogViewModel: ObservableObject {
    @Published private(set) var records: [AuditRecord] = []
    @Published private(set) var errorMessage: String?

    private let logger: AuditLogger

    init(logger: AuditLogger = AuditLogger()) {
        self.logger = logger
    }

    func refresh() {
        do {
            records = try logger.readRecords()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func export(to url: URL) throws {
        try logger.exportReport(to: url)
        errorMessage = nil
    }
}

struct AuditLogView_Previews: PreviewProvider {
    static var previews: some View {
        AuditLogView()
            .frame(width: 720, height: 480)
    }
}
