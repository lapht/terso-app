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

SwiftPM builds and launches the macOS app. Keep the terminal open while using
it; press `Ctrl-C` there to stop it.

To run from Xcode instead, open the package and run the `TersoApp` scheme:

```bash
open Package.swift
```

Full Disk Access is not needed just to launch Terso. Modules that need it will
tell you when permission is unavailable rather than showing an incomplete scan.

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
