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
- `lapht/homebrew-tap` is published with this cask; `brew tap lapht/tap`
  succeeds.
- `brew audit --strict --online --cask lapht/tap/terso` passes with no
  offenses (re-downloads the release and checks the checksum).
- Not yet done: install/upgrade/uninstall on clean Apple Silicon and Intel
  machines, to be run by the maintainer.

The cask installs only `Terso.app`: no hidden components, no `postflight`,
no `livecheck`-driven or in-app update checks (updates are brew-only, see
`docs/design.md` §11.6). The build is ad-hoc signed and
not notarized, so the cask must not claim otherwise or use `--no-quarantine`.
