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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
            Label {
                Text("Cleanup Complete")
                    .font(DesignTokens.Typography.pageTitle)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .font(DesignTokens.Typography.pageTitle)
                    .foregroundStyle(DesignTokens.Palette.success)
            }
            .accessibilityIdentifier("clean-result-title")

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                Text("Moved to Trash")
                    .font(DesignTokens.Typography.sectionTitle)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.small) {
                    Text(formattedBytes)
                        .font(DesignTokens.Typography.heroFigure)
                        .foregroundStyle(DesignTokens.Palette.brandText)
                        .accessibilityIdentifier("clean-result-bytes")
                    Text(
                        "\(result.itemsTrashed.count) "
                            + "\(result.itemsTrashed.count == 1 ? "item" : "items")"
                    )
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                }
                Text("Estimated size of the items moved to Trash. Empty Trash to reclaim disk space.")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                StatusMessage(text: "Completed in \(formattedDuration)", systemImage: "clock")
                    .accessibilityIdentifier("clean-result-duration")
            }
            .tersoCard()

            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                    StatusMessage(
                        text: "Some scan warnings need your attention",
                        systemImage: "exclamationmark.triangle",
                        tone: .warning,
                        font: DesignTokens.Typography.sectionTitle
                    )
                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning)
                            .font(DesignTokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tersoCard()
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

struct CleanResultView_Previews: PreviewProvider {
    private static let result: CleanResult = {
        let url = URL(fileURLWithPath: "/Users/preview/Library/Caches/com.example.preview")
        let item = CleanItem(
            url: url,
            resolvedURL: url,
            sizeBytes: 125_000_000,
            moduleId: "user-caches",
            ruleId: "preview.rule"
        )
        return CleanResult(
            itemsTrashed: [item],
            bytesFreed: item.sizeBytes,
            errors: [.permissionDenied(path: "/Users/preview/Library/Caches/com.example.locked")],
            executionDuration: 1.2
        )
    }()

    static var previews: some View {
        CleanResultView(
            result: result,
            warnings: ["Preview warning"],
            onScanAgain: {},
            onViewAuditLog: {}
        )
        .padding()
    }
}
