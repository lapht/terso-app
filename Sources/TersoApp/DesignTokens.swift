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
import SwiftUI

/// The single source of Terso's visual language: colors, type, spacing, radii and motion.
///
/// Views read these tokens instead of hardcoding values, so the brand (the teal drop of the app
/// icon) stays consistent across pages and in both light and dark mode.
enum DesignTokens {
    enum Spacing {
        static let xxSmall: CGFloat = 4
        static let xSmall: CGFloat = 8
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
        static let xLarge: CGFloat = 24
    }

    enum Radius {
        static let row: CGFloat = 10
        static let card: CGFloat = 12
        static let badge: CGFloat = 12
    }

    enum Layout {
        /// Readable line length for page content on wide windows.
        static let contentMaxWidth: CGFloat = 720
        static let pageMinWidth: CGFloat = 420
        static let cardMinWidth: CGFloat = 220
        static let badgeSize: CGFloat = 48
        static let rowIconSize: CGFloat = 32
        static let breakdownBarHeight: CGFloat = 10
    }

    enum Typography {
        static let pageTitle = Font.largeTitle.weight(.semibold)
        static let sectionTitle = Font.headline
        static let body = Font.body
        static let metadata = Font.callout
        static let caption = Font.caption
        /// Byte counts and totals: rounded and with fixed-width digits so figures do not jitter.
        static let heroFigure = Font.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit()
        static let figure = Font.system(.title3, design: .rounded).weight(.semibold).monospacedDigit()
        static let rowFigure = Font.callout.monospacedDigit()
    }

    enum Palette {
        /// Interactive tint (buttons, selection, progress). Defined in the asset catalog as
        /// `AccentColor`, with light/dark values chosen so white labels on it meet WCAG AA.
        static let accent = Color.accentColor
        /// Brand teal for figures, icons and short emphasis text; AA-compliant on the window
        /// background in both appearances (`BrandText` in the asset catalog).
        static let brandText = Color("BrandText")
        /// The drop in the app icon: bright teal fading into the deep blue of its background.
        static let brandGradient = LinearGradient(
            colors: [
                Color(red: 15 / 255, green: 181 / 255, blue: 174 / 255),
                Color(red: 10 / 255, green: 111 / 255, blue: 138 / 255)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let cardFill = Color(nsColor: .controlBackgroundColor)
        static let cardStroke = Color(nsColor: .separatorColor)
        static let rowFill = Color.primary.opacity(0.04)
        static let brandWash = Color.accentColor.opacity(0.08)
        static let brandStroke = Color.accentColor.opacity(0.3)
        /// Semantic colors are used sparingly: only for an actual outcome, never for urgency.
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
    }

    enum Motion {
        /// State transitions; `nil` when the user asked macOS to reduce motion.
        static func standard(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 0.25)
        }
    }
}
