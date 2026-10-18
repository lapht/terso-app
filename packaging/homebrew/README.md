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

The cask installs only `Terso.app`: no hidden components, no `postflight`,
no `livecheck`-driven or in-app update checks. The build is ad-hoc signed and
not notarized, so the cask must not claim otherwise or use `--no-quarantine`.
