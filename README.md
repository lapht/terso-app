<p align="center">
  <img src="docs/assets/logo.png" width="128" alt="Terso logo"/>
</p>

<h1 align="center">Terso</h1>

<p align="center">
  <strong>Clean code, clean Mac.</strong><br/>
  The auditable macOS cleaner you don't have to trust — you can read it.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-0FB5AE" alt="GPL-3.0"/></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-0B1B2B" alt="macOS 13+"/>
  <a href="https://github.com/lapht/terso-app/actions/workflows/ci.yml"><img src="https://github.com/lapht/terso-app/actions/workflows/ci.yml/badge.svg" alt="Build"/></a>
  <img src="https://img.shields.io/badge/telemetry-none-success" alt="No telemetry"/>
</p>

---

## Why Terso?

Commercial Mac cleaners moved to subscriptions, run closed-source code with full
access to your disk, and market fear ("1,247 threats found!"). Terso is the
answer: **GPL-3.0, free forever, zero telemetry, trash-first deletions.**

- 🔍 **Auditable** — every cleanup rule lives in a readable JSON database you can review
- 🛡️ **Safe by design** — deletions go through a guarded pipeline, Trash-first, dry-run everywhere
- 🤫 **Private** — no network calls by default, no analytics, no accounts
- 🧰 **Native** — SwiftUI, small binary, respects macOS

> ⚠️ **Status: v0.1 in development.** Not ready for daily use yet. Watch the repo or
> check the [v0.1 MVP milestone](../../milestones) to follow progress — contributions welcome!

## Roadmap

| Version | Contents |
|---|---|
| **v0.1** | Caches, logs, trash bins, Xcode/dev junk, large-files scanner, Smart Scan (dry-run) |
| v0.2 | App leftovers, duplicates, menu bar extra, IT/EN localization, Homebrew tap |
| v1.0 | Security configuration audit, localization call, public launch |

Full details: [docs/design.md](docs/design.md)

## Run Terso on your Mac

**Requires:** macOS 13+ and Xcode 16 or later (including the Swift 6 toolchain).

```bash
git clone https://github.com/lapht/terso-app.git
cd terso-app
swift run TersoApp
```

SwiftPM builds and launches the macOS app and brings its window to the
foreground. Keep the terminal open while using it; press `Ctrl-C` there to stop
it.

To run from Xcode instead, open the package and run the `TersoApp` scheme:

```bash
open Package.swift
```

Full Disk Access is not needed just to launch Terso. Modules that need it will
tell you when permission is unavailable rather than showing an incomplete scan.

## Install a release build

Download `Terso-v0.1-macOS.zip` from the
[GitHub Releases](https://github.com/lapht/terso-app/releases) page and open the
ZIP to extract `Terso.app`. The release is an ad-hoc-signed universal build for
Apple silicon and Intel Macs. It is not notarized. On first launch, use
Control-click > **Open**, then confirm **Open** in the macOS dialog. Only install
apps from a release you trust.

To build the same app bundle and archive from source on macOS 13 or later with
Swift 6.1.2 installed:

```bash
./scripts/build-release.sh
```

The script creates `dist/Terso-v0.1-macOS.zip` and its SHA-256 sidecar file.
Verify the downloaded archive with:

```bash
shasum -a 256 -c Terso-v0.1-macOS.zip.sha256
```

## Release verification checklist

Complete these checks on a clean macOS test environment before publishing a
release. They require manual verification and are not implied by the automated
build:

- [ ] Launch on a clean VM without Full Disk Access, then grant Full Disk Access
  and verify permission-dependent modules.
- [ ] Test on a case-sensitive APFS volume.
- [ ] Test with a non-English system locale.
- [ ] Verify all cleanup candidates stay within their allowlisted roots.

To build without launching the app and run the test suite:

```bash
swift build
swift test
```

## Contributing

See [CONTRIBUTING.md](docs/CONTRIBUTING.md). Rules for the safety layer are strict:
any change to `Sources/CoreKit/Safety` or `Rules/` requires maintainer review.

## License

GPL-3.0 — free forever, and forks must stay free too. See [LICENSE](LICENSE).
