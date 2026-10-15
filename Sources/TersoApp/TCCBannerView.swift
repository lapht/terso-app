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

struct TCCBannerView: View {
    let status: TCCStatus

    @State private var settingsError = ""
    @State private var isShowingSettingsError = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button("Open System Settings", action: openPrivacySettings)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("open-full-disk-access-settings")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .alert(isPresented: $isShowingSettingsError) {
            Alert(
                title: Text("Unable to Open System Settings"),
                message: Text(settingsError),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var title: String {
        switch status {
        case .granted:
            "Full Disk Access is enabled"
        case .denied:
            "Full Disk Access is off"
        case .unknown:
            "Full Disk Access status is unavailable"
        }
    }

    private var message: String {
        switch status {
        case .granted:
            "Terso can scan modules that require this permission."
        case .denied:
            "Some modules need this permission to scan completely. You can enable it in System Settings."
        case .unknown:
            "Terso could not verify this permission. You can check it in System Settings."
        }
    }

    private func openPrivacySettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else {
            settingsError = "The System Settings address is invalid."
            isShowingSettingsError = true
            return
        }

        guard NSWorkspace.shared.open(settingsURL) else {
            settingsError = "Open System Settings and enable Terso under Privacy & Security > Full Disk Access."
            isShowingSettingsError = true
            return
        }
    }
}

struct TCCBannerView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TCCBannerView(status: .denied)
                .previewDisplayName("Permission denied")
            TCCBannerView(status: .unknown)
                .previewDisplayName("Permission status unknown")
            TCCBannerView(status: .granted)
                .previewDisplayName("Permission granted")
        }
        .padding()
    }
}
