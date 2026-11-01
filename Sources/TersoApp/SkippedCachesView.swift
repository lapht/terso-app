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
import CoreKit
import SwiftUI

/// Caches left out of a scan because their app is open, with a rescan for after the user has
/// quit them. Terso never quits apps itself.
struct SkippedCachesView: View {
    let skippedCaches: [SkippedCache]
    let onRescan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Skipped because the app is open")
                .font(DesignTokens.Typography.sectionTitle)
            Text("Quit these apps yourself, then rescan to include their caches.")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
            ForEach(skippedCaches) { cache in
                HStack {
                    Text(cache.displayName ?? Self.appName(for: cache.bundleIdentifier))
                    Spacer(minLength: 0)
                    Text(SizeCalculator.formattedByteCount(cache.estimatedBytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(DesignTokens.Typography.metadata)
                .accessibilityElement(children: .combine)
            }
            Button("Rescan After Quitting", systemImage: "arrow.clockwise", action: onRescan)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("smart-scan-rescan-skipped")
        }
        .tersoCard()
        .accessibilityIdentifier("smart-scan-skipped-caches")
    }

    private static func appName(for bundleIdentifier: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first?.localizedName ?? bundleIdentifier
    }
}
