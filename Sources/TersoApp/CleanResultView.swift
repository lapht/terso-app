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

import CoreKit
import SwiftUI

struct CleanResultView: View {
    let result: CleanResult
    let warnings: [String]
    let onScanAgain: () -> Void
    let onViewAuditLog: () -> Void

    var formattedBytes: String {
        SizeCalculator.formattedByteCount(result.bytesFreed)
    }

    var formattedDuration: String {
        String(format: "%.1f seconds", result.executionDuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Cleanup Complete", systemImage: "checkmark.circle.fill")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.green)
                .accessibilityIdentifier("clean-result-title")

            VStack(alignment: .leading, spacing: 8) {
                Text("Moved to Trash")
                    .font(.headline)
                Text(formattedBytes)
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("clean-result-bytes")
                Text("Estimated size of the items moved to Trash. Empty Trash to reclaim disk space.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    "\(result.itemsTrashed.count) "
                        + "\(result.itemsTrashed.count == 1 ? "item" : "items") moved to Trash"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Label("Completed in \(formattedDuration)", systemImage: "clock")
                .accessibilityIdentifier("clean-result-duration")

            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Some scan warnings need your attention", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("clean-result-warnings")
            }

            HStack {
                Button("View Audit Log", systemImage: "list.bullet.rectangle", action: onViewAuditLog)
                    .accessibilityIdentifier("clean-result-audit-log")
                Button("Scan Again", systemImage: "arrow.clockwise", action: onScanAgain)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("clean-result-scan-again")
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .accessibilityIdentifier("clean-result")
    }
}
