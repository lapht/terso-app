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

/// A dotted numeric app version such as `3.2` or `14.1.5`, used by version-conditional exclusions.
///
/// Comparison is component-wise on integers; missing trailing components count as 0,
/// so `1.2` equals `1.2.0`. Anything else (suffixes like `-beta`, empty parts,
/// signs, more than four components, components over nine digits) is not parseable.
public struct AppVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    static let maxComponents = 4
    static let maxDigits = 9

    public let components: [Int]

    /// Returns `nil` unless `string` is 1–4 dot-separated ASCII-digit components.
    public init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...Self.maxComponents).contains(parts.count) else {
            return nil
        }
        var values: [Int] = []
        for part in parts {
            guard (1...Self.maxDigits).contains(part.count),
                  part.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
                  let value = Int(part)
            else {
                return nil
            }
            values.append(value)
        }
        components = values
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == 0
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) < 0
    }

    private static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> Int {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right ? -1 : 1
            }
        }
        return 0
    }
}
