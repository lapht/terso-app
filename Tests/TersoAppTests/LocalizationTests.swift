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
@testable import TersoApp

struct LocalizationTests {
    private static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/TersoApp/Localizable.xcstrings")

    private static func loadCatalog() throws -> [String: Any] {
        let data = try Data(contentsOf: catalogURL)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    /// Every value of a localization, flattening plural variations.
    private static func values(of localization: [String: Any]) -> [String] {
        if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            return [value]
        }
        guard let variations = localization["variations"] as? [String: Any] else {
            return []
        }
        return variations.values
            .compactMap { $0 as? [String: Any] }
            .flatMap { $0.values.compactMap { $0 as? [String: Any] } }
            .flatMap { values(of: $0) }
    }

    private static func placeholders(in value: String) -> [String] {
        value.matches(of: /%(?:lld|@|d)/).map { String($0.output) }
    }

    @Test func catalogUsesEnglishAsSourceLanguage() throws {
        let catalog = try Self.loadCatalog()
        #expect(catalog["sourceLanguage"] as? String == "en")
    }

    @Test func everyKeyHasNonEmptyEnglishAndItalianValues() throws {
        let catalog = try Self.loadCatalog()
        let strings = try #require(catalog["strings"] as? [String: Any])
        #expect(!strings.isEmpty)
        for (key, entry) in strings {
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            for language in ["en", "it"] {
                let localization = localizations[language] as? [String: Any] ?? [:]
                let values = Self.values(of: localization)
                #expect(!values.isEmpty, "\(key) is missing \(language)")
                for value in values {
                    #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty, "\(key) is empty in \(language)")
                }
            }
        }
    }

    @Test func translationsKeepTheSamePlaceholdersAsEnglish() throws {
        let catalog = try Self.loadCatalog()
        let strings = try #require(catalog["strings"] as? [String: Any])
        for (key, entry) in strings {
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            let english = Self.values(of: localizations["en"] as? [String: Any] ?? [:])
            let italian = Self.values(of: localizations["it"] as? [String: Any] ?? [:])
            let expected = Set(english.map { Self.placeholders(in: $0).sorted() })
            for value in italian {
                #expect(expected.contains(Self.placeholders(in: value).sorted()), "\(key): placeholders differ in it")
            }
        }
    }

    @Test func appBundleDeclaresEnglishAndItalian() {
        let localizations = Bundle.main.localizations
        #expect(localizations.contains("en"))
        #expect(localizations.contains("it"))
    }

    @Test func unsupportedLocaleFallsBackToEnglish() {
        let available = Bundle.main.localizations
        let chosen = Bundle.preferredLocalizations(from: available, forPreferences: ["fr", "de"])
        #expect(chosen.first == "en")
    }

    @Test func missingKeyShowsEnglishTextInsteadOfATechnicalKey() {
        let text = String(localized: "This sentence is not in the catalog.")
        #expect(text == "This sentence is not in the catalog.")
        #expect(!text.isEmpty)
    }

    @Test func mainScreensExposeNoRawKeysOrEmptyStrings() {
        for destination in SidebarDestination.allCases {
            for text in [destination.title, destination.description] {
                #expect(!text.isEmpty)
                #expect(!text.contains("%"))
                #expect(text.first?.isUppercase == true)
            }
        }
        for section in SidebarSection.allCases {
            #expect(!section.title.isEmpty)
        }
    }
}
