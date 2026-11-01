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
- Never-clean list: see §12.

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
| Large files | scanner + selected files to Trash via Safety (#117); Reveal in Finder for packages |
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
  The cask source lives in `packaging/homebrew/` (#45); it is ad-hoc signed,
  not notarized, documents the Gatekeeper first-launch step, and installs only
  `Terso.app` with no update checks. Updates are brew-only (§11.6).
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
  - Update-mechanism decision: brew-only, Sparkle deferred (#46, §11.6).
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
  there is no success-shaped fallback. Concretely (`RuleValidator+SchemaV2.swift`):
  - `bundleID` and `groupIdentifier` use only ASCII letters, digits, `-` and
    `.`, with no empty components; `bundleID` has at least two components.
  - `paths` start with `~/Library/`, contain no `..` component, no glob
    characters (`* ? [ ] \`), no control characters, no placeholder other than
    `{bundleID}`, and no literal `.app` component. After substitution and
    normalization a path lies strictly inside a §11.4 root (case-sensitive) and
    inside or equal to one of the rule's `allowlistRoots`.
  - `groupIdentifier` is required when `shared` is `true` and rejected
    otherwise.
  - `provenance.source`, `author` and `rationale` are non-empty; `author` has
    no whitespace; `date` is a valid calendar date in `YYYY-MM-DD` form.
  - `appPatterns`, when present, is non-empty; `appPatterns` and `provenance`
    in a `schemaVersion: 1` database are rejected
    (`schemaV2FieldInV1Database`).
- **Unknown fields** are reported with a diagnostic naming rule and field and
  the database is not loaded; they are never silently ignored. This applies to
  both schema versions and to every level: top level, rule, `appPatterns[i]`
  and `provenance` (`unknownField`).
- **Engine matching.** `RuleEvaluator.evaluateAppPatterns` re-validates the
  rule's v2 fields, applies the same allowlist and symlink checks as
  `evaluate`, and returns candidates whose path equals an app pattern path
  after `{bundleID}` substitution (exact, case-sensitive comparison). Results
  follow candidate order, then pattern and path order. It is read-only and
  does not decide whether an app is removed (§11.4, #36).
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

### 11.5b Audit log: contents and path privacy (#103)

- **What is logged:** one JSON Lines record per item operation (trash or dry-run):
  UTC timestamp, action, module id, rule id, original path, resolved path, size in
  bytes, result and error code. File contents are never read or stored.
- **Where:** `~/Library/Logs/Terso/audit.log`, local only, never transmitted
  (telemetry-free).
- **For how long:** Terso never rotates or prunes it; entries stay until the user
  deletes the file. The in-app view shows the newest 500 records.
- **Local log is complete (invariant 8):** it always keeps full paths.
- **Exports:** the exported report replaces the home directory with `~`. The export
  panel offers "Redact file names below the cleanup root": every path component
  below the matching allowlist root becomes `<redacted>` (e.g.
  `~/Library/Caches/<redacted>/<redacted>`). A path under no known root is redacted
  below the home directory (fail-closed). Timestamp, rule id and size stay readable.

### 11.6 Update mechanism decision (#46)

**Decision (v0.2): brew-only.** Terso ships no updater. Updates are delivered
by `brew upgrade --cask terso` from the `lapht/tap` tap (#45). Self-hosted
Sparkle is **not adopted** now and is deferred, not rejected: it is
re-evaluated when Developer ID signing and notarization exist (§6).
This issue implements nothing: no Sparkle code, framework, appcast endpoint
or update check, and no new dependency or network call.

**Comparison**

| Criterion | Brew-only | Self-hosted Sparkle |
|---|---|---|
| Network surface | None added; Terso makes no network calls (§2). Homebrew does the download, user-initiated. | Adds an HTTPS client to the app, an appcast endpoint and a feed fetch; every release becomes an attack and privacy surface. |
| Opt-in | Inherent: nothing runs unless the user runs `brew upgrade`. | Possible (`SUEnableAutomaticChecks` off, explicit user action), but it must be configured and kept off by default. |
| Maintenance | Per release, bump `version` and `sha256` in the cask (`packaging/homebrew/`). | Adds a hosted appcast, EdDSA key custody and rotation, appcast generation in the release process, and framework upgrades. |
| Signing / notarization | Works with the ad-hoc signed ZIP; Homebrew verifies the SHA-256. | Sparkle's EdDSA signature protects update integrity, but Sparkle documents a Developer ID-signed app as the supported setup. Replacing an ad-hoc signed bundle in place also hits Gatekeeper again, so the user-friendly flow is not guaranteed. |
| Reliability | Depends on the user's Homebrew; no code of ours in the update path. | In-app updater code in the process that deletes files: a bug there is on our side. |
| UX | Terminal command; no in-app prompt. Users who install the ZIP manually update manually. | In-app prompts; better for non-Homebrew users. |
| Architecture support | Fits §2 and §6 as they stand. | Adds the first third-party runtime dependency (§6 says none), a networking path outside CoreKit, and an XPC/installer component. |

**Rationale.** The hard requirement is no network by default with any update
check opt-in (§2). Brew-only meets it with zero code. Sparkle would cost a
dependency, a hosted endpoint and key custody for a project that is ad-hoc
signed and unfunded, and its main benefit (smooth in-app replacement) is
undermined without Developer ID and notarization.

**Network policy.** Terso performs no update check in v0.2. Any future check
must be (a) off by default, (b) started by an explicit user action or a
setting the user turns on, (c) limited to a single documented HTTPS request
with no identifiers, and (d) covered by a design update before implementation.

**Homebrew impact.** The cask stays free of `livecheck`-driven or in-app
update checks (`packaging/homebrew/README.md`). The README tells users to run
`brew upgrade --cask terso` and states that Terso does not check for updates.
Release notes must remind manual-ZIP users to download the new release.

**Next decision.** Owner: the repository maintainer. Trigger: Developer ID
and notarization become available; the question is reopened at the planning
of the release that adopts them (no earlier than v0.3). No calendar date is
set because it depends on the funding and Apple Developer Program membership
in §6. Maintainer confirmation is expected in the PR review of #46.

### 11.7 Protected-area semantics for Desktop, Documents and Downloads (#105)

**Status: proposed — pending maintainer approval.** This issue changes no code
and no test; `PathValidator` is unchanged. The decision below takes effect only
after the maintainer approves it in the review of this PR, and the later
implementation (#40) needs its own `[SAFETY]` issue and review.

**Current behavior (v0.1/v0.2).** Invariant 3 says "the user's
Desktop/Documents/Downloads *roots*", but `PathValidator.checkProtectedPaths`
denies the **whole subtree**: for `~/Desktop`, `~/Documents` and `~/Downloads`
it uses the same `isContained` check as the system prefixes, so the root itself
and every descendant at any depth (e.g. `~/Documents/a/b/file.txt`) throw
`SafetyError.protectedPath`. The check is case-insensitive, runs before the
allowlist, and cannot be overridden by a module's `allowedRoots`: adding
`~/Documents` to an allowlist still fails. `DeletionPipeline` goes through the
same validator, and `..` components are rejected beforehand
(`PathValidatorTests` covers root, file and traversal cases). No other code in
`Safety/` mentions these folders.

**Why it matters.** Duplicates (#40) mostly live exactly in these folders, so
with the current rule they could never be moved to Trash. Options must not
weaken invariants 1–4 and 8.

**Options**

| | A. Keep full deny | B. Per-operation allowlist of user-selected folders | C. Files only, never folders |
|---|---|---|---|
| What changes | Nothing. Duplicates stay read-only (Reveal in Finder). | A folder the user explicitly picks (open panel) becomes a temporary allowed root for that one operation only. | Files inside the protected areas may be trashed; directories (including roots) never. |
| Invariant 1 | Intact. | Intact if the allowlist is built from the user's pick and discarded after the operation; a persisted or rule-defined root would break it. | Needs a root anyway, so alone it does not satisfy it. |
| Invariant 3 | Intact, strictly. | Becomes "deny by default, narrow user-granted exception". Needs a precise written wording. | Same exception, narrower. |
| Main risk | Feature #40 is blocked. | Picking `~`, `~/Documents` itself or a parent of many projects widens the blast radius; a bug in scoping leaks the exception to later operations; symlinks inside the chosen folder can point outside it. | Folder deny alone does not stop trashing many important files one by one; a package/bundle (`.pages`, `.photoslibrary`) is a directory that looks like a file. |
| Recovery | n/a | Trash-first (invariant 4) keeps items recoverable. | Same. |

**Proposed decision (to approve).** Keep **A** for everything that is not a
user-confirmed duplicate operation, and implement **B restricted by C** for
#40:
1. The exception applies only to the duplicates flow, only to **regular files**
   (never directories, packages/bundles or the three roots themselves), and only
   under a folder the user picked in that session. It is held in memory, bound
   to one operation, and never stored, shared with other modules or defined in
   `Rules/*.json`.
2. A picked folder that is `~`, a protected root's parent, or a system path is
   rejected. Picking a protected root (e.g. `~/Documents`) is allowed because
   it is the main use case, but the recap names the folder explicitly.
3. Invariant 2 applies in full: every path is resolved and its target must stay
   inside the picked folder; symlinks are never followed or trashed through.
4. Trash-first only (no permanent delete, see the note after §5); the UI shows
   total size and item count before executing, and a dry-run is available
   (invariants 5 and 6).
5. The audit log (§11.5b) records each item, noting that the protected-area
   exception was used (invariant 8).
6. Always at least one copy per group is kept; the keeper selection and the
   exception scoping are covered by fixture tests, including symlink-attack and
   package cases.
7. The wording of invariant 3 is amended in §5 when #40 is implemented,
   in the same `[SAFETY]` PR as the code.

**Not decided here.** Any change to `PathValidator`, any other module touching
these folders, and the `.app`/`/Applications` denials, which stay unchanged
(§11.1).

**Owner and confirmation.** The repository maintainer. Approval is expected as
an explicit review comment on this PR; until then v0.2 and #40 behave as in
option A.

## 12. Never-clean list (#143)
Things Terso will never clean, so that contributors do not propose them. A rule
proposal or module touching any item below is declined without further review;
reopening an item requires amending this section in a reviewed PR.

| Item | Why Terso never touches it |
|---|---|
| Language files (`*.lproj`) and universal-binary thinning | Modifying files inside an app bundle breaks its code signature (Gatekeeper and TCC may then reject the app), and the files return on the next app update. Also conflicts with the v0.2 rule of never modifying `.app` bundles (§11.1). |
| Document versions (`.DocumentRevisions-V100`) | Part of the user's document history, not a cache; removal is unrecoverable data loss and the store is protected by the system. |
| Swap and sleep image (`/private/var/vm`) | Managed by the kernel; under `/private/var`, outside every allowlisted root. Deleting it can crash or destabilize a running system. |
| APFS purgeable space | The system reclaims it on demand; a third party cannot free it (see §2). Any "cleaned purgeable GB" claim would be misleading. |
| Messages database (`~/Library/Messages`) | User conversations and attachments, not a cache; deletion is unrecoverable and cannot be justified as cleanup. |
| Anything under `/System` | Signed System Volume, SIP-protected; hard-denied by invariant 3. |
| Built-in Apple apps on the Signed System Volume (Tips, Stocks, Chess, etc.) | Cannot be removed safely: workarounds need SIP or authenticated-root changes, can break boot, and are undone by system updates. Removable Apple apps in `/Applications` (Pages, Numbers, Keynote, GarageBand, iMovie) are handled by the uninstaller (#107), not by cleanup rules. |
| Apple Intelligence models (`AssetsV2`) and the Spotlight index | Managed by the system; can only be removed through System Settings. Terso may at most point the user there. |

This list is a product decision on top of the invariants in §5, which remain
the technical enforcement. It is linked from `AGENTS.md` and from the
[contribution guide](./CONTRIBUTING.md).

## Spike #104 — Homebrew cask viability (ad-hoc signed)

**Date:** 2026-10-18
**Outcome:** viable via third-party tap, with documented Gatekeeper step

### Context
Homebrew 4.7 removed `--no-quarantine`. Since September 2026, Homebrew 5.x
requires Developer ID + notarization for the official tap. The official
`homebrew/cask` tap is not an option for an ad-hoc signed app.

### Findings
- Official tap: requires notarization, ruled out.
- Third-party tap (`lapht/homebrew-terso`): not subject to the same rules, viable.
- On first launch, Gatekeeper blocks the app even with an ad-hoc signature.
- User workaround: System Settings → Privacy & Security → "Open Anyway".

### Recommendation for #45
Distribute via a third-party tap `lapht/homebrew-terso`.
Document the Gatekeeper first-launch step in the tap README and release notes.
Defer notarization to a future release if/when an Apple Developer Program
membership is obtained.

### References
- https://workbrew.com/blog/what-homebrew-5-0-0-means-for-your-mac-fleet
- https://feedbagel.com/post/homebrew-to-remove-no-quarantine-flag-support-for-macos-security-compliance
- https://github.com/ivoronin/TomatoBar/issues/102

## Spike #113 — Old-file signals on macOS 13+

**Date:** 2026-11-01
**Outcome:** a usable detection strategy, with one safety conflict to resolve
before any implementation (see "Open decision").

**Method and limits.** Probes were run on macOS 26.6.2 (Apple Silicon) with
`mdls`, `ls -lO` and `defaults`. macOS 13 was **not** available, and the test
machine has no iCloud Drive, so the macOS 13 behavior and the dataless-file
behavior below are taken from Apple documentation and must be re-checked on a
real macOS 13 and an iCloud-enabled account before the feature ships.
Items are marked **[verified]** (observed here) or **[documented]**.

### 1. Last-used date
- `kMDItemLastUsedDate` is written by Launch Services/Finder when a user opens
  a file; it is **absent** for files never opened through them. **[verified]**
  A camera-roll JPEG on the Desktop had `kMDItemLastUsedDate = (null)` while
  `kMDItemContentModificationDate` was set.
- It is **not** set by `cat`, backup tools, scripts or sync clients, so absence
  means "no recorded user open", not "never touched".
- Screenshots get `kMDItemLastUsedDate` = capture time (use count 1). **[verified]**
  A screenshot therefore never looks "used" by that signal alone.
- Spotlight metadata is missing when indexing is off (`mdutil -i off`), the
  volume is excluded in Spotlight privacy settings, the volume is not indexed
  (many external/network volumes), or the file is newer than the indexer.
  **[documented]**
- `kMDItemDateAdded`, `kMDItemUseCount` exist but are Spotlight-only and share
  the same gaps; do not rely on them.

**Strategy.** Read dates with `URLResourceValues`/`NSMetadataItem` only as a
hint, never as the sole proof:
`lastActivity = max(lastUsedDate ?? .distantPast, contentModificationDate,
creationDate)`. If Spotlight returns no attribute, silently falling back to
modification date is allowed **only if the UI states which signal was used**
(invariant 7: never scan less than displayed). Volumes where `mdutil -s` is
disabled are reported as "dates are approximate", not skipped silently.

### 2. Screenshots and screen recordings
- `kMDItemIsScreenCapture = 1` and `kMDItemScreenCaptureType = "selection"`
  are set on screenshots. **[verified]** Recordings carry the same flag
  **[documented]**.
- The save location is `defaults read com.apple.screencapture location`; if the
  key is missing the default is `~/Desktop`. **[verified]** (key absent here).
  Read it with `UserDefaults(suiteName: "com.apple.screencapture")`.
- The filename is localized (here `Screenshot … alle …`, English `Screenshot …
  at …`, other locales differ), and the `name` default can rename the prefix.
  Filename matching is a **last resort**, accepted only for `.png`/`.mov` files
  directly inside the configured screenshot folder.
- Order: `kMDItemIsScreenCapture` → (flag missing **and** file inside the
  configured location) localized-prefix match → otherwise not a screenshot.

### 3. Photo exclusion (rule: when in doubt, it is a photo)
An image/video is treated as a photo and **excluded** if any of these holds:
- it is inside a `.photoslibrary` bundle (never descend into the bundle at
  all; it is a package and must stay opaque);
- `kMDItemAcquisitionMake`/`Model` or EXIF Make/Model (read via ImageIO
  `CGImageSourceCopyPropertiesAtIndex`, header only, no full decode) is present;
- the type is HEIC/HEIF/`public.heic` or a `.mov` Live Photo companion;
- the metadata cannot be read.

Counter-example **[verified]**: a camera-style `IMG_5543.jpg` had **no** Make
or Model (metadata stripped by messaging apps/export). EXIF-absent therefore
does not mean "not a photo". Only screenshots proven by section 2 are eligible
as images; every other image is excluded by default.

### 4. iCloud dataless files
- A dataless (evicted) file reports `SF_DATALESS` (`0x40000000`) in `st_flags`
  from `stat`/`lstat`, and `URLResourceValues.ubiquitousItemDownloadingStatus
  == .notDownloaded` for iCloud items. Both are metadata reads and do not start
  a download. **[documented]**
- Opening, reading or hashing the content, or `Data(contentsOf:)`, materializes
  the file. **Never** read content of a file before its flags are checked.
- `st_size` of a dataless file is the logical size but frees **0 bytes** locally;
  use `totalFileAllocatedSize`/`st_blocks` for reclaimable space.
- Policy: dataless files are listed as "in iCloud, 0 B on disk" and never
  counted toward reclaimable bytes, never opened, never selected.
- Cloud providers under `~/Library/CloudStorage` (e.g. SynologyDrive present
  here) are File Provider roots with the same flag; treat them as out of scope
  unless the allowlist names them.

### 5. TCC prompts and the existing flow (#77)
- First access to `~/Desktop`, `~/Documents`, `~/Downloads` (and removable or
  network volumes) by a non-Full-Disk-Access app raises a per-folder prompt;
  a refusal surfaces as `EACCES`/`EPERM` on enumeration. **[documented]**
  Granting Full Disk Access removes the prompts.
- The current flow does not cover this: `SystemTCCAccessChecker` deliberately
  avoids probes in those folders (see its doc comment) and `TCCManager` only
  reasons about Full Disk Access.
- Recommendation: the old-files module sets `requiresFDA = true` for the
  first version (the UX already exists: `.requiresPermission` + onboarding)
  rather than introducing per-folder prompt handling; if a folder is still
  unreadable the module must report `.requiresPermission`, not a smaller list.

### Recommended detection strategy
1. Enumerate only inside allowlisted old-files roots, never into packages.
2. Skip dataless files via `st_flags` before any content access.
3. Classify screenshots per section 2; exclude everything photo-like per
   section 3; other image types are excluded by default.
4. Compute `lastActivity` per section 1 and show the signal used.
5. Apply an age threshold (default proposal: 90 days, user-adjustable) to
   `lastActivity` only.
6. Everything goes through the existing trash-first pipeline.

### Open decision (blocks the implementation issue)
Invariant 3 hard-denies the user's Desktop/Documents/Downloads roots, but
screenshots live on the Desktop by default and Downloads is the main source of
old files. As written, `PathValidator` would refuse to trash them. Resolving
this needs a maintainer decision and a `[SAFETY]` change (e.g. an explicit,
narrow exception for files matching the screenshot/old-download criteria
rather than the roots). This spike does not change `Safety/`.

### References
- Apple: `NSMetadataItem` / `MDItem` attribute keys (`kMDItemLastUsedDate`,
  `kMDItemIsScreenCapture`, `kMDItemAcquisitionMake`).
- Apple: `URLResourceKey.ubiquitousItemDownloadingStatusKey`, `<sys/stat.h>`
  `SF_DATALESS`.
