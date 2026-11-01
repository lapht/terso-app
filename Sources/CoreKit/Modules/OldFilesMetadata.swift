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

import CoreServices
import Foundation
import ImageIO

/// What the image header says about where an image came from.
public enum OldFileImageOrigin: Sendable, Hashable {
    /// Camera make/model, lens or GPS data, or a HEIC/HEIF container: treated as a photo.
    case photoLike
    /// The header was read and has no camera information.
    case noCameraInfo
    /// The header could not be read: treated as a photo (when in doubt, it is a photo).
    case unreadable
}

/// Metadata signals used by ``OldFilesScanner``. Injectable so tests do not depend on Spotlight.
public protocol OldFileMetadataReading: Sendable {
    /// Whether the file is a dataless (evicted) iCloud placeholder. Must not read file content.
    func isDataless(_ url: URL) -> Bool
    /// `kMDItemLastUsedDate`, or `nil` when Launch Services recorded none.
    func lastUsedDate(of url: URL) -> Date?
    /// `kMDItemIsScreenCapture`, or `nil` when the flag is absent.
    func isScreenCapture(_ url: URL) -> Bool?
    /// Reads only the image header, never decodes pixels.
    func imageOrigin(of url: URL) -> OldFileImageOrigin
}

/// Production metadata reader. Every call is a metadata read; none of them downloads a file.
public struct SystemOldFileMetadata: OldFileMetadataReading {
    private static let datalessFlag: UInt32 = 0x4000_0000 // SF_DATALESS
    private static let screenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"

    public init() {}

    public func isDataless(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            // Unknown state: do not risk touching the content.
            return true
        }
        return info.st_flags & Self.datalessFlag != 0
    }

    public func lastUsedDate(of url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else {
            return nil
        }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    public func isScreenCapture(_ url: URL) -> Bool? {
        let size = getxattr(url.path, Self.screenCaptureAttribute, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(url.path, Self.screenCaptureAttribute, &buffer, size, 0, XATTR_NOFOLLOW)
        guard read == size,
              let value = try? PropertyListSerialization.propertyList(from: Data(buffer), format: nil)
        else {
            return nil
        }
        return (value as? NSNumber)?.boolValue
    }

    public func imageOrigin(of url: URL) -> OldFileImageOrigin {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source) as String?,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return .unreadable
        }
        if type == "public.heic" || type == "public.heif" {
            return .photoLike
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let hasCameraInfo = tiff[kCGImagePropertyTIFFMake] != nil
            || tiff[kCGImagePropertyTIFFModel] != nil
            || exif[kCGImagePropertyExifLensMake] != nil
            || exif[kCGImagePropertyExifLensModel] != nil
            || properties[kCGImagePropertyGPSDictionary] != nil
        return hasCameraInfo ? .photoLike : .noCameraInfo
    }
}
