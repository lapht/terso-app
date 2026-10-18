# Homebrew cask

`Casks/terso.rb` is the source of truth for the cask published in the
`lapht/homebrew-tap` repository (created and owned by the maintainer).
Copy it to `Casks/terso.rb` in the tap on each release.

Per release, update only `version` and `sha256` (from the release's
`Terso-vX.Y.Z-macOS.zip.sha256` sidecar), then in the tap run:

```bash
brew audit --strict --online --cask lapht/tap/terso
brew style lapht/tap/terso
brew install --cask lapht/tap/terso
```

## Verification status (v0.1.2)

- URL and SHA-256 checked against the published release artifact: match.
- The app bundle passes `codesign --verify --deep` and contains `arm64` and
  `x86_64`.
- Not yet done: `brew audit --strict --online --cask` on the published tap
  and install/upgrade/uninstall on clean Apple Silicon and Intel machines.
- The `lapht/homebrew-tap` repository must be created by the maintainer
  before the README install commands work.

The cask installs only `Terso.app`: no hidden components, no `postflight`,
no `livecheck`-driven or in-app update checks. The build is ad-hoc signed and
not notarized, so the cask must not claim otherwise or use `--no-quarantine`.
