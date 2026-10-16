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

import Foundation
import Testing

@testable import CoreKit

struct VolumeSpaceTests {
    @Test func availableStateShowsReadableUnitsAndNoPurgeablePromise() {
        let display = VolumeSpaceDisplay(state: .available(bytes: 42_000_000_000, totalBytes: 500_000_000_000))

        #expect(display.title == "\(SizeCalculator.formattedByteCount(42_000_000_000)) free")
        #expect(display.title.contains("GB"))
        #expect(display.detail.contains("Purgeable space is not counted."))
        #expect(display.accessibilityLabel.contains("available"))
        #expect(!display.isError)
    }

    @Test func availableStateWithoutTotalStillReports() {
        let display = VolumeSpaceDisplay(state: .available(bytes: 0, totalBytes: nil))

        #expect(!display.isError)
        #expect(display.detail.contains("available"))
    }

    @Test func unavailableStateIsExplicitWithNoDummyValue() {
        let display = VolumeSpaceDisplay(state: .unavailable(reason: "boom"))

        #expect(display.isError)
        #expect(display.title == "Space unavailable")
        #expect(display.detail.contains("boom"))
        #expect(display.accessibilityLabel.contains("unavailable"))
        #expect(!display.title.contains("0"))
    }

    @Test func providerMatchesTheVolumeCapacitySource() throws {
        let url = URL(fileURLWithPath: "/", isDirectory: true)
        let expected = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity

        guard case let .available(bytes, total) = VolumeSpaceProvider(volumeURL: url).currentState() else {
            Issue.record("Expected an available state for the boot volume")
            return
        }
        #expect(expected != nil)
        #expect(bytes > 0)
        #expect(total.map { $0 >= bytes } ?? true)
    }

    @Test func providerReportsUnavailableForMissingVolume() {
        let missing = URL(fileURLWithPath: "/definitely/not/a/volume-\(UUID().uuidString)")

        guard case let .unavailable(reason) = VolumeSpaceProvider(volumeURL: missing).currentState() else {
            Issue.record("Expected an unavailable state")
            return
        }
        #expect(!reason.isEmpty)
    }
}
