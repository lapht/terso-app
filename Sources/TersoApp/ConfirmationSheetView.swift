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
import SwiftUI

@MainActor
final class CleanupConfirmationViewModel: ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var pendingItems: [CleanItem] = []

    private let onConfirm: ([CleanItem]) -> Void

    var pendingBytes: Int64 {
        pendingItems.reduce(into: Int64.zero) { total, item in
            let (sum, overflow) = total.addingReportingOverflow(item.sizeBytes)
            total = overflow ? .max : sum
        }
    }

    init(onConfirm: @escaping ([CleanItem]) -> Void) {
        self.onConfirm = onConfirm
    }

    func requestConfirmation(for items: [CleanItem]) {
        let trashableItems = items.filter {
            $0.isDeletable && !$0.isProtected && $0.recommendedAction == .trash
        }
        guard !trashableItems.isEmpty else {
            return
        }
        pendingItems = trashableItems
        isPresented = true
    }

    func cancel() {
        pendingItems = []
        isPresented = false
    }

    func confirm() {
        guard isPresented, !pendingItems.isEmpty else {
            return
        }
        let confirmedItems = pendingItems
        cancel()
        onConfirm(confirmedItems)
    }
}

struct ConfirmationSheetView: View {
    let itemCount: Int
    let totalBytes: Int64
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Confirm Cleanup", systemImage: "trash")
                .font(.title2.weight(.semibold))

            Text(
                "Will move \(itemCount) \(itemCount == 1 ? "item" : "items") "
                    + "totaling \(formattedGigabytes) to Trash."
            )
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("cleanup-confirmation-summary")

            Text("All items will be moved to the Trash and can be restored at any time.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("cleanup-confirmation-reassurance")

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cleanup-confirmation-cancel")
                Button("Move to Trash", systemImage: "trash", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("cleanup-confirmation-confirm")
            }
        }
        .padding(24)
        .frame(minWidth: 420, maxWidth: 520)
        .accessibilityIdentifier("cleanup-confirmation-sheet")
    }

    private var formattedGigabytes: String {
        String(format: "%.2f GB", Double(totalBytes) / 1_000_000_000)
    }
}
