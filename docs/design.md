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

Post-MVP: see the roadmap in §9 and the v0.2 decisions in §11. The CLI
remains post-MVP and is not scheduled for v0.2.

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

> **v0.1/v0.2 note (not an invariant).** Invariant 4 allows permanent delete
> behind an explicit per-item opt-in, but v0.1 and v0.2 do not offer permanent
> delete at all: every destructive action is trash-first through the existing
> pipeline in `Sources/CoreKit/Safety/`. Offering the opt-in later requires its
> own issue, a design update and a `[SAFETY]` review.

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
- **v0.2** (decisions and boundaries in §11):
  - Rule DB v2: bundle-ID app patterns + provenance metadata (#33, #34),
    seeded leftover rules (#101).
  - Leftovers of apps that are already removed: installed-app discovery (#35),
    read-only detection (#36), review and move to Trash via Safety (#37).
  - Duplicates, observation only: content-hash detection (#38) and read-only
    groups view (#39).
  - Leftovers and Duplicates sidebar sections, separate from Smart Scan (#102).
  - Menu bar extra (#41, #42).
  - EN/IT localization (#44, #43).
  - Audit log path privacy for exports (#103).
  - Homebrew tap (#104 spike, #45).
  - Update-mechanism decision: self-hosted Sparkle vs brew-only (#46).
  - Release (#47).
- **v0.3:** real app uninstall by moving the `.app` to Trash via Safety (#107),
  moving duplicates to Trash (#40, after the protected-area decision in #105),
  version-conditional exclusions in the rule DB (#106).
- **v1.0:** config audit module, localization call, Product Hunt / Show HN
  launch, sponsorship setup.

## 10. Governance
PR-only workflow on `main` (branch protection), conventional commits,
CODEOWNERS on `Safety/` and `Rules/`, issue templates (bug / module request /
rule proposal), monthly dependency & rule-DB review cadence.

## 11. v0.2 decisions
Decisions recorded before v0.2 code is written (#32). Issues #33–#107
implement these decisions; a disagreement must be resolved by amending this
section in a reviewed PR, not in code.
The invariants in §5 are unchanged by everything below.

### 11.1 Boundaries
- **No app removal.** v0.2 never removes `.app` bundles and never modifies,
  moves or trashes anything in `/Applications` (or `~/Applications`). The only
  access to app locations is the read-only discovery in §11.3. Real uninstall
  is v0.3 (#107) and starts from a threat-model update.
- **Safety denials unchanged.** `PathValidator` keeps denying `/Applications`,
  every `.app` bundle and the other protected paths exactly as in v0.1. No v0.2
  issue changes those denials.
- **No permanent delete** in v0.1/v0.2 (see the note after §5).
- **Separate sections, not Smart Scan.** Leftovers (uninstaller) and Duplicates
  are separate sidebar sections. Neither is part of Smart Scan; each scan starts
  only from an explicit user action in its own section (#102).
- **Single deletion path.** The only destructive action in v0.2 is moving
  selected leftovers to Trash through the existing pipeline in
  `Sources/CoreKit/Safety/` (#37). No new deletion API is added anywhere.

### 11.2 Rule DB v2 contract
Implemented by #33 (schema) and #34 (loader/validation); content by #101.

- **Versioning.** A v2 database sets `"schemaVersion": 2`. The loader accepts
  `schemaVersion` 1 and 2; any other value is rejected
  (`unsupportedSchemaVersion`).
- **Top level.** Unchanged: `version` (String, `YYYY.N`), `schemaVersion`
  (Int), `rules` ([Rule]).
- **Existing rule fields.** Unchanged in name, type and meaning: `id`,
  `module`, `category`, `name`, `description` (String); `allowlistRoots`,
  `paths`, `patterns`, `exclusions` ([String]); `minAgeSeconds` (Int64,
  optional); `isTrashSafe` (Bool).
- **New optional rule fields (v2 only):**

  | Field | Type | Meaning |
  |---|---|---|
  | `appPatterns` | [AppPattern] | Paths associated with an app, keyed by bundle ID |
  | `provenance` | Provenance | Where the rule comes from and why it is correct |

  `AppPattern`:

  | Field | Type | Required | Meaning |
  |---|---|---|---|
  | `bundleID` | String | yes | Reverse-DNS bundle ID, exact match (case-sensitive), no wildcards |
  | `paths` | [String] | yes, non-empty | `~/Library/...` paths; the only placeholder allowed is `{bundleID}` |
  | `shared` | Bool | no (default `false`) | Location used by several apps (vendor data, group containers) |
  | `groupIdentifier` | String | when `shared` is `true` | Team/group identifier used to detect other installed apps sharing it |

  `Provenance`:

  | Field | Type | Required | Meaning |
  |---|---|---|---|
  | `source` | String | yes | URL or reference (vendor docs, observed install, issue) |
  | `author` | String | yes | Who proposed the rule (GitHub handle) |
  | `date` | String | yes | ISO 8601 date (`YYYY-MM-DD`) of the last review |
  | `rationale` | String | yes | Why these paths belong to the app and are safe to propose |

- **Required provenance.** In a v2 database, `provenance` is required on every
  rule that has `appPatterns`; it is optional on other rules.
- **Validation.** Every `appPatterns` path, after `{bundleID}` substitution and
  normalization, must lie under one of the rule's `allowlistRoots` and under
  one of the leftover roots in §11.4. App patterns cannot add or widen
  allowlist roots, cannot contain `..`, absolute paths outside `~/Library`, or
  globs in the bundle ID, and cannot authorize protected paths. Invalid rules
  are rejected with a diagnostic naming the rule, the field and the reason;
  there is no success-shaped fallback.
- **Unknown fields** are reported with a diagnostic naming rule and field and
  the database is not loaded; they are never silently ignored.
- **Compatibility with v0.1.** A `schemaVersion: 1` database (e.g.
  `Rules/v2026.1.json`) loads with unchanged behavior. A v1 rule copied into a
  v2 database without the new fields keeps its meaning.
- **Out of scope for v0.2:** version-conditional exclusions (excluding paths
  only for certain versions of an installed app). Fields for them are not part
  of the v2 contract and are rejected as unknown; tracked in #106 (v0.3).

### 11.3 Installed-app discovery
- Read-only scan of `/Applications`, `~/Applications` and their subfolders,
  reporting name, bundle ID and path for each app (#35).
- Missing or ambiguous bundle IDs are reported as such and never produce
  matches.
- Unreadable locations or metadata errors are exposed. A discovery with any
  such error is marked **incomplete**; an incomplete discovery is never
  treated as "app not installed".

### 11.4 Leftovers flow
- **Definition of removed.** An app counts as removed only when its bundle ID
  is absent from every scanned app location and the discovery (§11.3) is
  complete. If discovery is incomplete, no item is reported as a leftover.
- **Detection (#36).** Read-only. A candidate is reported only when its bundle
  ID matches a Rule DB v2 app pattern (§11.2) and the app is removed.
- **Allowed roots** — only these `~/Library` subfolders:
  - `~/Library/Application Support`
  - `~/Library/Caches`
  - `~/Library/Preferences`
  - `~/Library/Containers`
  - `~/Library/Group Containers`
  - `~/Library/Saved Application State`
  - `~/Library/Logs`
  - `~/Library/HTTPStorages`
  - `~/Library/WebKit`

  `/Library`, `/private`, `/System` and every other system location are out of
  scope for v0.2. Adding a root requires a design update and `[SAFETY]` review.
- **Shared locations.** Group containers and other `shared` patterns are
  reported only if no installed app shares the same `groupIdentifier`;
  otherwise they are excluded with a visible reason.
- **TCC.** Missing Full Disk Access and macOS 14+ App Data protection on
  `~/Library/Containers` are handled per invariant 7: affected roots are shown
  as not scanned, never silently skipped.
- **Results.** Each item shows path, association reason (rule id + bundle ID)
  and size. Nothing is preselected. Symlinks are not followed outside the root;
  protected paths are never candidates.
- **Action (#37).** The user selects items, sees a dry-run and a recap (count
  and total size), and confirms. Only selected items are passed to the
  existing pipeline in `Sources/CoreKit/Safety/`, trash-first. The leftovers
  module registers the roots above through the existing per-module allowlist
  mechanism; Safety code is not modified. Rejections and errors are visible in
  the UI and in the audit log.

### 11.5 Duplicates (read-only)
- Detection (#38) runs only on user-chosen folders: size pre-filter, partial
  hash, full streaming hash. Hard links are not duplicates; APFS clones are
  marked and not counted as reclaimable; dataless iCloud/File Provider files are
  skipped and counted, never downloaded; packages are not traversed; symlinks
  are not followed; read errors are exposed, never treated as hashes.
- View (#39): list of groups, group details, Reveal in Finder — like Large
  Files. **No selection and no deletion in v0.2.**
- Moving duplicates to Trash is v0.3 (#40) and depends on the protected-area
  decision for Desktop/Documents/Downloads (#105).

### 11.6 Update mechanism decision
- #46 compares **self-hosted Sparkle** and **brew-only** updates, using at
  least: compatibility with ad-hoc signing (no Developer ID/notarization, §6),
  update signing and integrity, the no-network-by-default rule (§2: any update
  check is opt-in), hosting and maintenance cost, interaction with the Homebrew
  tap (#104, #45), and auditability.
- The outcome is recorded in this section by #46. Issue #32 only documents the
  decision process; it does not implement Sparkle or any update check.
