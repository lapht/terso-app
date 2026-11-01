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

/// Things Terso found but leaves to the user, each with a command to run themselves.
/// Terso never runs these commands.
struct ModuleAdvisoriesView: View {
    let advisories: [ModuleAdvisory]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            ForEach(advisories) { advisory in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxSmall) {
                    HStack {
                        Text(advisory.title)
                            .font(DesignTokens.Typography.sectionTitle)
                        Spacer(minLength: 0)
                        Text(SizeCalculator.formattedByteCount(advisory.estimatedBytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Text(advisory.detail)
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                    Text(advisory.command)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("module-advisory-command")
                }
                .accessibilityElement(children: .combine)
            }
        }
        .tersoCard()
        .accessibilityIdentifier("smart-scan-advisories")
    }
}
