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
import Security

/// The team and app groups an installed app declares in its code signature.
public struct AppGroupMembership: Sendable, Hashable {
    /// Apple Developer team identifier, `nil` for unsigned or ad-hoc signed apps.
    public let teamIdentifier: String?

    /// Values of the `com.apple.security.application-groups` entitlement.
    public let applicationGroups: [String]

    public init(teamIdentifier: String?, applicationGroups: [String]) {
        self.teamIdentifier = teamIdentifier
        self.applicationGroups = applicationGroups
    }

    /// Whether the app may use the shared location identified by `groupIdentifier`.
    ///
    /// The app shares it when it declares the group, or when the group carries a
    /// team prefix (`TEAMID.…`) equal to the app's team: same-vendor apps are
    /// assumed to share their vendor's groups, which errs on the side of keeping data.
    public func shares(groupIdentifier: String) -> Bool {
        if applicationGroups.contains(groupIdentifier) {
            return true
        }
        guard let teamIdentifier, let prefix = Self.teamPrefix(of: groupIdentifier) else {
            return false
        }
        return prefix == teamIdentifier
    }

    /// The leading team identifier (10 uppercase letters or digits) of a group identifier.
    static func teamPrefix(of groupIdentifier: String) -> String? {
        guard let first = groupIdentifier.split(separator: ".", maxSplits: 1).first,
              first.count == 10,
              first.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else {
            return nil
        }
        return String(first)
    }
}

/// Reads the app-group membership of an installed app.
public protocol AppGroupMembershipReading: Sendable {
    /// - Throws: when the signature exists but cannot be read; callers must then
    ///   treat the app as possibly sharing every group (fail-closed).
    func membership(of app: InstalledApp) throws -> AppGroupMembership
}

/// Error raised when a code signature cannot be inspected.
public struct CodeSignatureReadError: Error, Sendable, Hashable, CustomStringConvertible {
    public let path: String
    public let status: Int32

    public var description: String {
        "Unable to read the code signature of '\(path)' (OSStatus \(status))"
    }
}

/// Reads team and app groups from the static code signature, without validating or running the app.
public struct CodeSignatureGroupMembershipReader: AppGroupMembershipReading {
    private static let applicationGroupsEntitlement = "com.apple.security.application-groups"

    public init() {}

    public func membership(of app: InstalledApp) throws -> AppGroupMembership {
        // Following a symlinked .app only reads metadata, as discovery does.
        let bundleURL = app.url.resolvingSymlinksInPath()
        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)
        guard status == errSecSuccess, let staticCode else {
            throw CodeSignatureReadError(path: app.url.path, status: status)
        }

        var information: CFDictionary?
        status = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )
        if status == errSecCSUnsigned {
            return AppGroupMembership(teamIdentifier: nil, applicationGroups: [])
        }
        guard status == errSecSuccess, let information = information as? [String: Any] else {
            throw CodeSignatureReadError(path: app.url.path, status: status)
        }

        let entitlements = information[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        return AppGroupMembership(
            teamIdentifier: information[kSecCodeInfoTeamIdentifier as String] as? String,
            applicationGroups: entitlements?[Self.applicationGroupsEntitlement] as? [String] ?? []
        )
    }
}
