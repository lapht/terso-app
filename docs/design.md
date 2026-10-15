# Terso — Design Document
_License: GPL-3.0 · Language: Swift 6 / SwiftUI · Platform: macOS 13+ · Status: v0 draft_

## 1. Vision
Terso is "the auditable Mac cleaner": a GPL-licensed, telemetry-free, safety-first
macOS cleanup utility. You should not have to trust it — you can read it.

## 2. Non-goals (anti-FUD charter)
- No "malware protection" marketing we cannot honestly deliver (v1 may add a
  configuration audit: Gatekeeper/FileVault/SIP status — read-only).
- No "RAM boost" or other snake-oil performance claims.
- No promise to free APFS purgeable space — impossible for third parties.
- No telemetry, no network calls by default (update check is opt-in).
- No permanent deletion as default. Ever.

## 3. Architecture
Single repo, one Swift Package (`CoreKit`) containing all logic, consumed by:
- `TersoApp` (SwiftUI GUI, primary target)
- `terso-cli` (thin CLI wrapper — post-MVP)

```
terso-app/
  Sources/
    CoreKit/
      Engine/        # scanner, rule evaluation, size accounting
      Safety/        # the guarded deletion pipeline (see §5)
      Rules/         # rule DB loader + validation
      Modules/       # one Swift file per cleanup module
    TersoApp/        # SwiftUI views, minimal logic
  Rules/             # rules/vYYYY.N.json — versioned rule database
  Tests/             # fixtures: fake home dirs with known trees
  docs/              # this file, CONTRIBUTING.md, CODE_OF_CONDUCT.md
  AGENTS.md          # instructions for AI agents (see §8)
```

### Module protocol
```swift
protocol CleanModule {
    var id: String { get }            // e.g. "caches.user"
    var title: String { get }
    var requiresFDA: Bool
    func scan(context: ScanContext) async throws -> [CleanItem]
    // clean() is NOT part of modules: deletion only via Safety pipeline
}
```

Modules only *find* items. Deletion is centralized so the safety layer
cannot be bypassed by a buggy or contributed module.
Scans are requested through `TCCManager`; FDA-dependent modules return an
explicit `requiresPermission` result instead of silently producing partial
results when Full Disk Access is unavailable.

### Rule engine
Cleanup locations are data, not code: a versioned JSON rule DB (categories,
paths, glob patterns, exclusions) that contributors can edit via PR like any
code review. Engine validates schema; snapshot tests catch regressions.

## 4. MVP scope — v0.1
| Module | Notes |
|---|---|
| User Caches | `~/Library/Caches`, denylist for running apps |
| User Logs | rotated `.log`/`.gz`, safe patterns only |
| Trash Bins | all volumes, per-user |
| Xcode Junk | DerivedData, Archives cache, simulator caches |
| Package caches | Homebrew cleanup, npm/yarn/pnpm caches |
| Large files | read-only scanner + reveal in Finder (no delete) |
| Smart Scan | aggregator running modules in parallel |

Post-MVP (v0.2+): app leftovers/uninstaller, duplicates, menu bar extra,
localization, CLI.

## 5. Safety layer — the invariants
These are hard requirements; a PR that weakens any of them is rejected.

1. **Allowlist-only roots.** Deletion may only target paths under allowlisted
   roots defined per module (e.g. `~/Library/Caches`). Everything else = refusal.
2. **Symlink discipline.** Resolve every path; verify the resolved target is
   still inside the allowlist root; never follow symlinks into unknown locations.
3. **Protected paths.** Hard deny: SIP-protected volumes, `/System`,
   `/private/var/db`, the user's Desktop/Documents/Downloads roots, and any
   active application bundle.
4. **Trash-first.** Default destructive op is `FileManager.trashItem` (real
   Trash, recoverable). Permanent delete requires an explicit per-item opt-in
   checkbox, off by default.
5. **Dry-run everywhere.** First run of "Smart Scan" never deletes; every clean
   action has a dry-run mode reporting byte counts.
6. **Confirmation + recap.** GUI must show total size and item count before
   executing; admin escalation (sandboxed helper) is separate and logged.
7. **Graceful TCC.** `TCCManager` checks access to a TCC-protected path without
   modifying it. Missing Full Disk Access disables only the modules that need
   it, with a clear `requiresPermission` status and onboarding — never silently
   scans less than displayed.
8. **No silent failures.** Every deletion is logged (locally) with timestamp,
   rule id, and size; logs are exportable for bug reports.

## 6. Tech decisions (locked)
- Swift 6, SwiftUI, minimum macOS 13 (Ventura) to cover Intel + Apple Silicon.
- GPL-3.0 (`LICENSE`, SPDX headers in sources).
- SwiftLint + SwiftFormat enforced in CI, so agent-generated code stays uniform.
- GitHub Actions on public repo: free unlimited macOS runners (arm64 + Intel).
- Distribution: ad-hoc signed ZIP on GitHub Releases + `homebrew-tap` repo.
  Developer ID + notarization postponed (funding via GitHub Sponsors later).
- No third-party runtime dependencies in v0.1 (SPM only if strictly needed).

## 7. Testing strategy
- Unit: rule engine schema validation, pattern matching, size accounting.
- Integration: fixture filesystem trees with known content; assert exact scan
  results and exact deletion sets; symlink-attack fixtures included.
- Manual: fresh macOS VM (UTM/Tart) before every release; test without FDA,
  with non-English locale, on case-sensitive APFS.
- CI gates: lint, unit tests, integration tests, and a "safety audit" job that
  fails if any code outside `CoreKit/Safety` calls file-deletion APIs.

## 8. AGENTS.md requirements (for AI-assisted development)
Must state: architecture map; the 8 safety invariants (copy them verbatim);
"deletion logic only in CoreKit/Safety"; testing requirements per change;
SwiftLint compliance; commit message convention; that safety-critical PRs
require human maintainer review.

## 9. Roadmap
- **v0.1 (MVP):** modules in §4, safety layer, minimal GUI, dry-run, CI, README,
  first public release (unsigned/ad-hoc).
- **v0.2:** leftovers/uninstaller, duplicates, rule DB v2, menu bar extra,
  Italian + English i18n, homebrew tap.
- **v1.0:** config audit module, update mechanism decision, localization call,
  Product Hunt / Show HN launch, sponsorship setup.

## 10. Governance
PR-only workflow on `main` (branch protection), conventional commits,
CODEOWNERS on `Safety/` and `Rules/`, issue templates (bug / module request /
rule proposal), monthly dependency & rule-DB review cadence.
