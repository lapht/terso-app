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

/// Page chrome for the detail column: the FDA banner pinned on top, then the page anchored top-leading.
///
/// This is the only place that pads the page. It never scrolls: each page owns at most one scroll
/// (`PageScrollView`, `List` or `Table`), so the banner stays visible without scrolling.
struct PageContainer<Content: View>: View {
    let tccStatus: TCCStatus
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if tccStatus != .granted {
                TCCBannerView(status: tccStatus)
            }

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        // A minimum width keeps wrapped text (e.g. the FDA banner) from measuring as a
        // tall column while the split view computes its minimum size.
        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Vertical scroll for a page's content, anchored top-leading; it only bounces when content overflows.
struct PageScrollView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        let scrollView = ScrollView {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }

        if #available(macOS 13.3, *) {
            scrollView.scrollBounceBehavior(.basedOnSize)
        } else {
            scrollView
        }
    }
}

struct PageContainer_Previews: PreviewProvider {
    static var previews: some View {
        PageContainer(tccStatus: .denied) {
            PageScrollView {
                Text("Page content starts at the top-left corner.")
            }
        }
        .frame(width: 640, height: 420)
    }
}
