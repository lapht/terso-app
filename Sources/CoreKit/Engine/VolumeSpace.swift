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

/// The outcome of reading the boot volume's free space. Failures are explicit states,
/// never a placeholder number.
public enum VolumeSpaceState: Equatable, Sendable {
    /// Bytes reported as available by the volume, with the total capacity when known.
    case available(bytes: Int64, totalBytes: Int64?)
    /// The capacity could not be read. `reason` is a human-readable description.
    case unavailable(reason: String)
}

/// Source of the boot volume's available capacity. Read-only: implementations must not
/// scan, clean or modify anything.
public protocol VolumeSpaceProviding: Sendable {
    func currentState() -> VolumeSpaceState
}

/// Reads the capacity of a volume through `URLResourceValues.volumeAvailableCapacityKey`.
///
/// That key reports space that is free right now. It does not include APFS purgeable space
/// (`volumeAvailableCapacityForImportantUsageKey` does), so the value never promises space
/// the system might reclaim later.
public struct VolumeSpaceProvider: VolumeSpaceProviding {
    private let volumeURL: URL

    public init(volumeURL: URL = URL(fileURLWithPath: "/", isDirectory: true)) {
        self.volumeURL = volumeURL
    }

    public func currentState() -> VolumeSpaceState {
        do {
            let values = try volumeURL.resourceValues(
                forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]
            )
            guard let available = values.volumeAvailableCapacity, available >= 0 else {
                return .unavailable(reason: "The volume did not report its available capacity.")
            }
            let total = values.volumeTotalCapacity.map(Int64.init)
            return .available(bytes: Int64(available), totalBytes: total)
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
    }
}

/// Text shown for a `VolumeSpaceState`, kept free of UI types so it can be unit tested.
public struct VolumeSpaceDisplay: Equatable, Sendable {
    /// Short text for the menu bar item.
    public let title: String
    /// Longer text for the menu body.
    public let detail: String
    /// Spoken description of the menu bar item.
    public let accessibilityLabel: String
    /// `true` when the capacity could not be read.
    public let isError: Bool

    public init(state: VolumeSpaceState) {
        switch state {
        case let .available(bytes, totalBytes):
            let free = SizeCalculator.formattedByteCount(bytes)
            title = "\(free) free"
            if let totalBytes {
                let total = SizeCalculator.formattedByteCount(totalBytes)
                detail = "\(free) available of \(total) on the startup disk. Purgeable space is not counted."
            } else {
                detail = "\(free) available on the startup disk. Purgeable space is not counted."
            }
            accessibilityLabel = "Terso: \(free) available on the startup disk"
            isError = false
        case let .unavailable(reason):
            title = "Space unavailable"
            detail = "Could not read the available space: \(reason)"
            accessibilityLabel = "Terso: available space unavailable. \(reason)"
            isError = true
        }
    }
}
