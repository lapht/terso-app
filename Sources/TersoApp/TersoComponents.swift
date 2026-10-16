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

// Shared building blocks of the visual pass. They hold no logic beyond layout.

/// A rounded square with the brand gradient and a white glyph, echoing the app icon.
struct BrandBadge: View {
    let systemImage: String
    var size: CGFloat = DesignTokens.Layout.badgeSize

    var body: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.badge * size / DesignTokens.Layout.badgeSize)
            .fill(DesignTokens.Palette.brandGradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// Title block shared by every page: brand badge, page title and a one-line description.
struct PageHeader<Accessory: View>: View {
    let title: String
    let systemImage: String
    var description: String?
    var titleIdentifier: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.medium) {
            BrandBadge(systemImage: systemImage)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxSmall) {
                Text(title)
                    .font(DesignTokens.Typography.pageTitle)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(titleIdentifier ?? "page-title")

                if let description {
                    Text(description)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                accessory()
            }
        }
    }
}

extension PageHeader where Accessory == EmptyView {
    init(title: String, systemImage: String, description: String? = nil, titleIdentifier: String? = nil) {
        self.init(
            title: title,
            systemImage: systemImage,
            description: description,
            titleIdentifier: titleIdentifier,
            accessory: { EmptyView() }
        )
    }
}

/// Raised surface used for summaries, progress and module cards.
struct CardModifier: ViewModifier {
    var padding: CGFloat = DesignTokens.Spacing.medium

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Palette.cardFill, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    .strokeBorder(DesignTokens.Palette.cardStroke, lineWidth: 1)
            }
    }
}

extension View {
    func tersoCard(padding: CGFloat = DesignTokens.Spacing.medium) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

/// Calm, centered placeholder for "nothing here yet" and "nothing to clean" states.
struct EmptyStateView<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.small) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DesignTokens.Palette.brandText)
                .accessibilityHidden(true)
            Text(title)
                .font(DesignTokens.Typography.sectionTitle)
            Text(message)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions()
                .padding(.top, DesignTokens.Spacing.xxSmall)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.xLarge)
        .tersoCard()
        .accessibilityElement(children: .contain)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.init(systemImage: systemImage, title: title, message: message, actions: { EmptyView() })
    }
}

/// Inline status message. `info` is neutral; the other tones report an actual outcome.
struct StatusMessage: View {
    enum Tone {
        case info
        case brand
        case warning
        case error
    }

    let text: String
    let systemImage: String
    var tone: Tone = .info
    var font: Font = DesignTokens.Typography.metadata

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(tone == .info ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
        }
        .font(font)
    }

    private var iconColor: Color {
        switch tone {
        case .info:
            .secondary
        case .brand:
            DesignTokens.Palette.brandText
        case .warning:
            DesignTokens.Palette.warning
        case .error:
            DesignTokens.Palette.error
        }
    }
}

/// One module's share of the reclaimable total.
struct BreakdownSegment: Identifiable, Equatable {
    let id: String
    let title: String
    let bytes: Int64
}

/// Total size and item count in evidence, with a per-module breakdown (design.md §5.6 recap).
struct ReclaimableSummaryView: View {
    let title: String
    let totalBytes: Int64
    let itemCount: Int
    var segments: [BreakdownSegment] = []
    var sizeIdentifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxSmall) {
                Text(title)
                    .font(DesignTokens.Typography.sectionTitle)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.small) {
                    Text(SizeCalculator.formattedByteCount(totalBytes))
                        .font(DesignTokens.Typography.heroFigure)
                        .foregroundStyle(DesignTokens.Palette.brandText)
                        .accessibilityIdentifier(sizeIdentifier ?? "reclaimable-size")
                    Text("\(itemCount) items")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
            }

            if visibleSegments.count > 1 {
                breakdownBar
                legend
            }
        }
        .tersoCard()
    }

    private var visibleSegments: [BreakdownSegment] {
        segments.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
    }

    private var breakdownBar: some View {
        let segments = visibleSegments
        let total = Double(max(segments.reduce(Int64.zero) { $0 + $1.bytes }, 1))
        let gap: CGFloat = 2

        return GeometryReader { proxy in
            let usableWidth = max(proxy.size.width - gap * CGFloat(segments.count - 1), 0)
            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    Rectangle()
                        .fill(segmentColor(at: index))
                        .frame(width: max(usableWidth * Double(segment.bytes) / total, 2))
                }
            }
        }
        .frame(height: DesignTokens.Layout.breakdownBarHeight)
        .clipShape(Capsule())
        // The legend below carries the same information in text.
        .accessibilityHidden(true)
    }

    private var legend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), spacing: DesignTokens.Spacing.small, alignment: .leading)],
            alignment: .leading,
            spacing: DesignTokens.Spacing.xSmall
        ) {
            ForEach(Array(visibleSegments.enumerated()), id: \.element.id) { index, segment in
                HStack(spacing: DesignTokens.Spacing.xSmall) {
                    Circle()
                        .fill(segmentColor(at: index))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(segment.title)
                        .lineLimit(1)
                    Text(SizeCalculator.formattedByteCount(segment.bytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(DesignTokens.Typography.caption)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// One hue (the brand teal) in decreasing strength: calm, and never confused with a warning.
    private func segmentColor(at index: Int) -> Color {
        let opacities = [1.0, 0.72, 0.52, 0.38, 0.28, 0.2]
        return DesignTokens.Palette.accent.opacity(opacities[min(index, opacities.count - 1)])
    }
}

struct TersoComponents_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xLarge) {
            PageHeader(
                title: "Smart Scan",
                systemImage: "sparkles",
                description: "Review cleanup candidates from Terso's available modules in one place."
            )
            ReclaimableSummaryView(
                title: "Potentially reclaimable",
                totalBytes: 3_400_000_000,
                itemCount: 42,
                segments: [
                    BreakdownSegment(id: "caches.user", title: "User Caches", bytes: 1_900_000_000),
                    BreakdownSegment(id: "xcode.junk", title: "Xcode Junk", bytes: 1_100_000_000),
                    BreakdownSegment(id: "logs.user", title: "User Logs", bytes: 400_000_000)
                ]
            )
            EmptyStateView(
                systemImage: "checkmark.seal",
                title: "Nothing to clean here",
                message: "This scan found no items that match Terso's rules."
            )
            StatusMessage(text: "Scan cancelled. No files were changed.", systemImage: "pause.circle")
        }
        .padding(DesignTokens.Spacing.xLarge)
        .frame(width: 640)
    }
}
