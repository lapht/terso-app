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

@testable import CoreKit

extension LeftoverRulesTests {
    /// Every leftover rule with the exact paths it must match, in app pattern order.
    static let expectedMatches: [String: (bundleID: String, paths: [String])] = [
        "leftovers.google.chrome": ("com.google.Chrome", [
            "Library/Application Support/Google/Chrome",
            "Library/Caches/Google/Chrome",
            "Library/Caches/com.google.Chrome",
            "Library/Preferences/com.google.Chrome.plist",
            "Library/Saved Application State/com.google.Chrome.savedState",
            "Library/HTTPStorages/com.google.Chrome",
            "Library/WebKit/com.google.Chrome"
        ]),
        "leftovers.microsoft.vscode": ("com.microsoft.VSCode", [
            "Library/Application Support/Code",
            "Library/Caches/com.microsoft.VSCode.ShipIt",
            "Library/Caches/com.microsoft.VSCode",
            "Library/Preferences/com.microsoft.VSCode.plist",
            "Library/Saved Application State/com.microsoft.VSCode.savedState",
            "Library/HTTPStorages/com.microsoft.VSCode",
            "Library/WebKit/com.microsoft.VSCode"
        ]),
        "leftovers.spotify.client": ("com.spotify.client", [
            "Library/Application Support/Spotify",
            "Library/Caches/com.spotify.client",
            "Library/Preferences/com.spotify.client.plist",
            "Library/Saved Application State/com.spotify.client.savedState",
            "Library/HTTPStorages/com.spotify.client",
            "Library/WebKit/com.spotify.client"
        ]),
        "leftovers.bitwarden.desktop": ("com.bitwarden.desktop", [
            "Library/Containers/com.bitwarden.desktop",
            "Library/Containers/com.bitwarden.desktop.loginhelper",
            "Library/Containers/com.bitwarden.desktop.safari",
            "Library/Group Containers/LTZ2PFU5D6.com.bitwarden.desktop"
        ]),
        "leftovers.c3.theunarchiver": ("cx.c3.theunarchiver", [
            "Library/Containers/cx.c3.theunarchiver"
        ]),
        "leftovers.slack.desktop": ("com.tinyspeck.slackmacgap", [
            "Library/Application Support/Slack",
            "Library/Containers/com.tinyspeck.slackmacgap"
        ]),
        "leftovers.discord.client": ("com.hnc.Discord", [
            "Library/Application Support/discord",
            "Library/Caches/com.hnc.Discord",
            "Library/Preferences/com.hnc.Discord.plist",
            "Library/Saved Application State/com.hnc.Discord.savedState",
            "Library/HTTPStorages/com.hnc.Discord",
            "Library/WebKit/com.hnc.Discord"
        ]),
        "leftovers.zoom.client": ("us.zoom.xos", [
            "Library/Application Support/zoom.us",
            "Library/Caches/us.zoom.xos",
            "Library/Preferences/us.zoom.xos.plist",
            "Library/Saved Application State/us.zoom.xos.savedState",
            "Library/HTTPStorages/us.zoom.xos",
            "Library/WebKit/us.zoom.xos"
        ]),
        "leftovers.notion.desktop": ("notion.id", [
            "Library/Application Support/Notion",
            "Library/Caches/notion.id",
            "Library/Preferences/notion.id.plist",
            "Library/Saved Application State/notion.id.savedState",
            "Library/HTTPStorages/notion.id",
            "Library/WebKit/notion.id"
        ]),
        "leftovers.figma.desktop": ("com.figma.Desktop", [
            "Library/Application Support/Figma",
            "Library/Caches/com.figma.Desktop",
            "Library/Preferences/com.figma.Desktop.plist",
            "Library/Saved Application State/com.figma.Desktop.savedState",
            "Library/HTTPStorages/com.figma.Desktop",
            "Library/WebKit/com.figma.Desktop"
        ]),
        "leftovers.telegram.desktop": ("ru.keepcoder.Telegram", [
            "Library/Containers/ru.keepcoder.Telegram",
            "Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram"
        ]),
        "leftovers.skype.client": ("com.skype.skype", [
            "Library/Application Support/Skype",
            "Library/Caches/com.skype.skype",
            "Library/Preferences/com.skype.skype.plist",
            "Library/Saved Application State/com.skype.skype.savedState",
            "Library/HTTPStorages/com.skype.skype",
            "Library/WebKit/com.skype.skype"
        ]),
        "leftovers.microsoft.teams": ("com.microsoft.teams", [
            "Library/Application Support/Microsoft/Teams",
            "Library/Caches/com.microsoft.teams",
            "Library/Preferences/com.microsoft.teams.plist",
            "Library/Saved Application State/com.microsoft.teams.savedState",
            "Library/HTTPStorages/com.microsoft.teams",
            "Library/WebKit/com.microsoft.teams"
        ]),
        "leftovers.mozilla.firefox": ("org.mozilla.firefox", [
            "Library/Application Support/Firefox",
            "Library/Caches/Firefox",
            "Library/Caches/org.mozilla.firefox",
            "Library/Preferences/org.mozilla.firefox.plist",
            "Library/Saved Application State/org.mozilla.firefox.savedState",
            "Library/HTTPStorages/org.mozilla.firefox",
            "Library/WebKit/org.mozilla.firefox"
        ]),
        "leftovers.brave.browser": ("com.brave.Browser", [
            "Library/Application Support/BraveSoftware/Brave-Browser",
            "Library/Caches/BraveSoftware/Brave-Browser",
            "Library/Caches/com.brave.Browser",
            "Library/Preferences/com.brave.Browser.plist",
            "Library/Saved Application State/com.brave.Browser.savedState",
            "Library/HTTPStorages/com.brave.Browser",
            "Library/WebKit/com.brave.Browser"
        ]),
        "leftovers.microsoft.edge": ("com.microsoft.edgemac", [
            "Library/Application Support/Microsoft Edge",
            "Library/Caches/Microsoft Edge",
            "Library/Caches/com.microsoft.edgemac",
            "Library/Preferences/com.microsoft.edgemac.plist",
            "Library/Saved Application State/com.microsoft.edgemac.savedState",
            "Library/HTTPStorages/com.microsoft.edgemac",
            "Library/WebKit/com.microsoft.edgemac"
        ]),
        "leftovers.opera.browser": ("com.operasoftware.Opera", [
            "Library/Application Support/com.operasoftware.Opera",
            "Library/Caches/com.operasoftware.Opera",
            "Library/Preferences/com.operasoftware.Opera.plist",
            "Library/Saved Application State/com.operasoftware.Opera.savedState",
            "Library/HTTPStorages/com.operasoftware.Opera",
            "Library/WebKit/com.operasoftware.Opera"
        ]),
        "leftovers.vivaldi.browser": ("com.vivaldi.Vivaldi", [
            "Library/Application Support/Vivaldi",
            "Library/Caches/Vivaldi",
            "Library/Caches/com.vivaldi.Vivaldi",
            "Library/Preferences/com.vivaldi.Vivaldi.plist",
            "Library/Saved Application State/com.vivaldi.Vivaldi.savedState",
            "Library/HTTPStorages/com.vivaldi.Vivaldi",
            "Library/WebKit/com.vivaldi.Vivaldi"
        ]),
        "leftovers.thebrowser.arc": ("company.thebrowser.Browser", [
            "Library/Application Support/Arc",
            "Library/Caches/company.thebrowser.Browser",
            "Library/Preferences/company.thebrowser.Browser.plist",
            "Library/Saved Application State/company.thebrowser.Browser.savedState",
            "Library/HTTPStorages/company.thebrowser.Browser",
            "Library/WebKit/company.thebrowser.Browser"
        ]),
        "leftovers.agilebits.onepassword": ("com.1password.1password", [
            "Library/Containers/com.1password.1password",
            "Library/Group Containers/2BUA8C4S2C.com.1password"
        ]),
        "leftovers.sublimetext.editor": ("com.sublimetext.4", [
            "Library/Application Support/Sublime Text",
            "Library/Caches/com.sublimetext.4",
            "Library/Preferences/com.sublimetext.4.plist",
            "Library/Saved Application State/com.sublimetext.4.savedState",
            "Library/HTTPStorages/com.sublimetext.4",
            "Library/WebKit/com.sublimetext.4"
        ]),
        "leftovers.postman.desktop": ("com.postmanlabs.mac", [
            "Library/Application Support/Postman",
            "Library/Caches/com.postmanlabs.mac",
            "Library/Preferences/com.postmanlabs.mac.plist",
            "Library/Saved Application State/com.postmanlabs.mac.savedState",
            "Library/HTTPStorages/com.postmanlabs.mac",
            "Library/WebKit/com.postmanlabs.mac"
        ]),
        "leftovers.docker.desktop": ("com.docker.docker", [
            "Library/Application Support/Docker Desktop",
            "Library/Containers/com.docker.docker"
        ]),
        "leftovers.iterm2.terminal": ("com.googlecode.iterm2", [
            "Library/Application Support/iTerm2",
            "Library/Caches/com.googlecode.iterm2",
            "Library/Preferences/com.googlecode.iterm2.plist",
            "Library/Saved Application State/com.googlecode.iterm2.savedState",
            "Library/HTTPStorages/com.googlecode.iterm2",
            "Library/WebKit/com.googlecode.iterm2"
        ]),
        "leftovers.alfred.launcher": ("com.runningwithcrayons.Alfred", [
            "Library/Application Support/Alfred",
            "Library/Caches/com.runningwithcrayons.Alfred",
            "Library/Preferences/com.runningwithcrayons.Alfred.plist",
            "Library/Saved Application State/com.runningwithcrayons.Alfred.savedState",
            "Library/HTTPStorages/com.runningwithcrayons.Alfred",
            "Library/WebKit/com.runningwithcrayons.Alfred"
        ]),
        "leftovers.knollsoft.rectangle": ("com.knollsoft.Rectangle", [
            "Library/Caches/com.knollsoft.Rectangle",
            "Library/Preferences/com.knollsoft.Rectangle.plist",
            "Library/Saved Application State/com.knollsoft.Rectangle.savedState",
            "Library/HTTPStorages/com.knollsoft.Rectangle",
            "Library/WebKit/com.knollsoft.Rectangle"
        ]),
        "leftovers.videolan.vlc": ("org.videolan.vlc", [
            "Library/Application Support/org.videolan.vlc",
            "Library/Caches/org.videolan.vlc",
            "Library/Preferences/org.videolan.vlc.plist",
            "Library/Saved Application State/org.videolan.vlc.savedState",
            "Library/HTTPStorages/org.videolan.vlc",
            "Library/WebKit/org.videolan.vlc"
        ]),
        "leftovers.obsidian.desktop": ("md.obsidian", [
            "Library/Application Support/obsidian",
            "Library/Caches/md.obsidian",
            "Library/Preferences/md.obsidian.plist",
            "Library/Saved Application State/md.obsidian.savedState",
            "Library/HTTPStorages/md.obsidian",
            "Library/WebKit/md.obsidian"
        ]),
        "leftovers.signal.desktop": ("org.whispersystems.signal-desktop", [
            "Library/Application Support/Signal",
            "Library/Caches/org.whispersystems.signal-desktop",
            "Library/Preferences/org.whispersystems.signal-desktop.plist",
            "Library/Saved Application State/org.whispersystems.signal-desktop.savedState",
            "Library/HTTPStorages/org.whispersystems.signal-desktop",
            "Library/WebKit/org.whispersystems.signal-desktop"
        ]),
        "leftovers.audacity.editor": ("org.audacityteam.audacity", [
            "Library/Application Support/audacity",
            "Library/Caches/org.audacityteam.audacity",
            "Library/Preferences/org.audacityteam.audacity.plist",
            "Library/Saved Application State/org.audacityteam.audacity.savedState",
            "Library/HTTPStorages/org.audacityteam.audacity",
            "Library/WebKit/org.audacityteam.audacity"
        ]),
        "leftovers.transmission.client": ("org.m0k.transmission", [
            "Library/Application Support/Transmission",
            "Library/Caches/org.m0k.transmission",
            "Library/Preferences/org.m0k.transmission.plist",
            "Library/Saved Application State/org.m0k.transmission.savedState",
            "Library/HTTPStorages/org.m0k.transmission",
            "Library/WebKit/org.m0k.transmission"
        ]),
        "leftovers.cursor.editor": ("com.todesktop.230313mzl4w4u92", [
            "Library/Application Support/Cursor",
            "Library/Caches/com.todesktop.230313mzl4w4u92",
            "Library/Preferences/com.todesktop.230313mzl4w4u92.plist",
            "Library/Saved Application State/com.todesktop.230313mzl4w4u92.savedState",
            "Library/HTTPStorages/com.todesktop.230313mzl4w4u92",
            "Library/WebKit/com.todesktop.230313mzl4w4u92"
        ]),
        "leftovers.warp.terminal": ("dev.warp.Warp-Stable", [
            "Library/Application Support/dev.warp.Warp-Stable",
            "Library/Caches/dev.warp.Warp-Stable",
            "Library/Preferences/dev.warp.Warp-Stable.plist",
            "Library/Saved Application State/dev.warp.Warp-Stable.savedState",
            "Library/HTTPStorages/dev.warp.Warp-Stable",
            "Library/WebKit/dev.warp.Warp-Stable"
        ]),
        "leftovers.raycast.launcher": ("com.raycast.macos", [
            "Library/Application Support/com.raycast.macos",
            "Library/Caches/com.raycast.macos",
            "Library/Preferences/com.raycast.macos.plist",
            "Library/Saved Application State/com.raycast.macos.savedState",
            "Library/HTTPStorages/com.raycast.macos",
            "Library/WebKit/com.raycast.macos"
        ])
    ]
}
