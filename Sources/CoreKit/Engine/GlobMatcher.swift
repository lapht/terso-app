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

/// A compiled glob pattern for matching relative file paths.
///
/// `*` and `?` do not match `/`; `**` does, and `**/` also matches zero
/// directory components. Character classes support ranges and `!`/`^` negation.
public struct GlobMatcher: Sendable {
    /// Errors found while compiling a glob pattern.
    public enum PatternError: Error, CustomStringConvertible, Equatable, Sendable {
        case trailingEscape
        case unclosedCharacterClass
        case emptyCharacterClass
        case nestedCharacterClass
        case descendingCharacterRange(Character, Character)

        public var description: String {
            switch self {
            case .trailingEscape:
                "Glob pattern ends with an escape character"
            case .unclosedCharacterClass:
                "Glob pattern contains an unclosed character class"
            case .emptyCharacterClass:
                "Glob pattern contains an empty character class"
            case .nestedCharacterClass:
                "Glob pattern contains a nested character class"
            case let .descendingCharacterRange(lower, upper):
                "Glob character range '\(lower)-\(upper)' is descending"
            }
        }
    }

    private enum Token: Sendable {
        case literal(Character)
        case oneCharacter
        case characterClass(CharacterClass)
        case star
        case recursiveStar
        case recursiveDirectory
    }

    private struct CharacterClass: Sendable {
        let ranges: [ClosedRange<Character>]
        let isNegated: Bool

        func contains(_ character: Character) -> Bool {
            let isMember = ranges.contains { $0.contains(character) }
            return isNegated ? !isMember : isMember
        }
    }

    private let tokens: [Token]

    /// Compiles `pattern`, throwing if its escapes or character classes are malformed.
    public init(pattern: String) throws {
        tokens = try Self.compile(pattern)
    }

    /// Returns whether `path` matches this glob. Matching is case-sensitive.
    public func matches(path: String) -> Bool {
        let characters = Array(path)
        var states = Array(repeating: false, count: characters.count + 1)
        states[0] = true

        for token in tokens {
            states = advance(states, through: token, characters: characters)
        }

        return states[characters.count]
    }

    private func advance(
        _ states: [Bool],
        through token: Token,
        characters: [Character]
    ) -> [Bool] {
        switch token {
        case .star:
            return advanceStar(states, characters: characters, canCrossSlash: false)
        case .recursiveStar:
            return advanceStar(states, characters: characters, canCrossSlash: true)
        case .recursiveDirectory:
            return advanceRecursiveDirectory(states, characters: characters)
        case .literal(let expected):
            return advanceLiteral(states, characters: characters, expected: expected)
        case .oneCharacter:
            return advanceSingleCharacter(states, characters: characters)
        case .characterClass(let characterClass):
            return advanceCharacterClass(states, characters: characters, characterClass: characterClass)
        }
    }

    private func advanceStar(
        _ states: [Bool],
        characters: [Character],
        canCrossSlash: Bool
    ) -> [Bool] {
        var nextStates = states
        for index in characters.indices
            where nextStates[index] && (canCrossSlash || characters[index] != "/") {
            nextStates[index + 1] = true
        }
        return nextStates
    }

    private func advanceRecursiveDirectory(
        _ states: [Bool],
        characters: [Character]
    ) -> [Bool] {
        var nextStates = Array(repeating: false, count: states.count)
        var canConsumeDirectory = false
        for index in characters.indices {
            if (index == 0 || characters[index - 1] == "/") && states[index] {
                nextStates[index] = true
                canConsumeDirectory = true
            }
            if canConsumeDirectory && characters[index] == "/" {
                nextStates[index + 1] = true
            }
        }
        return nextStates
    }

    private func advanceLiteral(
        _ states: [Bool],
        characters: [Character],
        expected: Character
    ) -> [Bool] {
        var nextStates = Array(repeating: false, count: states.count)
        for index in characters.indices where states[index] && characters[index] == expected {
            nextStates[index + 1] = true
        }
        return nextStates
    }

    private func advanceSingleCharacter(
        _ states: [Bool],
        characters: [Character]
    ) -> [Bool] {
        var nextStates = Array(repeating: false, count: states.count)
        for index in characters.indices where states[index] && characters[index] != "/" {
            nextStates[index + 1] = true
        }
        return nextStates
    }

    private func advanceCharacterClass(
        _ states: [Bool],
        characters: [Character],
        characterClass: CharacterClass
    ) -> [Bool] {
        var nextStates = Array(repeating: false, count: states.count)
        for index in characters.indices
            where states[index] &&
                characters[index] != "/" &&
                characterClass.contains(characters[index]) {
            nextStates[index + 1] = true
        }
        return nextStates
    }

    private static func compile(_ pattern: String) throws -> [Token] {
        let characters = Array(pattern)
        var tokens: [Token] = []
        var index = 0

        while index < characters.count {
            switch characters[index] {
            case "\\":
                index += 1
                guard index < characters.count else {
                    throw PatternError.trailingEscape
                }
                tokens.append(.literal(characters[index]))
                index += 1
            case "*":
                if index + 1 < characters.count && characters[index + 1] == "*" {
                    index += 2
                    if index < characters.count && characters[index] == "/" {
                        tokens.append(.recursiveDirectory)
                        index += 1
                    } else {
                        tokens.append(.recursiveStar)
                    }
                } else {
                    tokens.append(.star)
                    index += 1
                }
            case "?":
                tokens.append(.oneCharacter)
                index += 1
            case "[":
                let (characterClass, nextIndex) = try compileCharacterClass(
                    characters,
                    startingAt: index
                )
                tokens.append(.characterClass(characterClass))
                index = nextIndex
            default:
                tokens.append(.literal(characters[index]))
                index += 1
            }
        }

        return tokens
    }

    private static func compileCharacterClass(
        _ characters: [Character],
        startingAt startIndex: Int
    ) throws -> (characterClass: CharacterClass, nextIndex: Int) {
        var index = startIndex + 1
        var isNegated = false
        if index < characters.count && (characters[index] == "!" || characters[index] == "^") {
            isNegated = true
            index += 1
        }

        var members: [Character] = []
        var isEscaped = false
        while index < characters.count {
            let character = characters[index]
            if isEscaped {
                members.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "]" {
                guard !members.isEmpty else {
                    throw PatternError.emptyCharacterClass
                }
                let ranges = try compileRanges(from: members)
                return (CharacterClass(ranges: ranges, isNegated: isNegated), index + 1)
            } else if character == "[" {
                throw PatternError.nestedCharacterClass
            } else {
                members.append(character)
            }
            index += 1
        }

        if isEscaped {
            throw PatternError.trailingEscape
        }
        throw PatternError.unclosedCharacterClass
    }

    private static func compileRanges(from members: [Character]) throws -> [ClosedRange<Character>] {
        var ranges: [ClosedRange<Character>] = []
        var index = 0

        while index < members.count {
            if index + 2 < members.count && members[index + 1] == "-" {
                let lower = members[index]
                let upper = members[index + 2]
                guard lower <= upper else {
                    throw PatternError.descendingCharacterRange(lower, upper)
                }
                ranges.append(lower...upper)
                index += 3
            } else {
                ranges.append(members[index]...members[index])
                index += 1
            }
        }

        return ranges
    }
}
