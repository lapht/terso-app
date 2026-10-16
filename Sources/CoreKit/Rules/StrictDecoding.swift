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

/// Coding key accepting any JSON key, used to list the keys actually present in an object.
struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// Raised by nested decoders; `CleanupRule` and `RuleDatabase` rewrite it as `RuleValidationError.unknownField`.
struct UnknownFieldError: Error {
    let codingPath: [any CodingKey]
    let key: String

    /// Formats the field path relative to `base`, for example `appPatterns[1].version`.
    func field(relativeTo base: [any CodingKey]) -> String {
        let relativePath = codingPath.dropFirst(base.count)
        var field = ""
        for component in relativePath {
            if let index = component.intValue {
                field += "[\(index)]"
            } else {
                field += field.isEmpty ? component.stringValue : ".\(component.stringValue)"
            }
        }
        return field.isEmpty ? key : "\(field).\(key)"
    }
}

extension Decoder {
    /// Throws `UnknownFieldError` for the first key, in sorted order, that `Keys` does not declare.
    func rejectUnknownKeys<Keys: CodingKey & CaseIterable>(_: Keys.Type) throws {
        let container = try container(keyedBy: AnyCodingKey.self)
        let allowedKeys = Set(Keys.allCases.map(\.stringValue))
        let unknownKey = container.allKeys
            .map(\.stringValue)
            .sorted()
            .first { !allowedKeys.contains($0) }
        if let unknownKey {
            throw UnknownFieldError(codingPath: codingPath, key: unknownKey)
        }
    }
}
