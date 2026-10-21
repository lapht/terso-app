# AGENTS.md — Instructions for AI agents working on Terso

Read this file in its entirety before touching any file. The design document
is `docs/design.md` and takes precedence over any interpretation of yours.

## Project
Terso: open-source macOS cleaner, GPL-3.0, Swift 6 + SwiftUI, macOS 13+.
The app lives in the Xcode project; `Package.swift` contains only CoreKit and tests.

## Opening, running, and testing
- Open `Terso.xcodeproj` in Xcode and select the `TersoApp` scheme.
- Run the app and SwiftUI Preview in Xcode. `CoreKit` is provided by the
  local package defined in `Package.swift`.
- Run package tests from the root with `swift test`.
- Run UI/ViewModel tests as CI does (without `ONLY_ACTIVE_ARCH=YES` and `ARCHS` the
  test target compiles for both x86_64 and fails with "Unable to resolve module dependency"):
  `xcodebuild -project Terso.xcodeproj -scheme TersoApp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test`
  (on Intel use `ARCHS=x86_64`).

## Starting a new chat or issue
At the beginning of any new chat that must modify code, and before starting
implementation of an issue, prepare the repository from an updated `main`:

1. Check current branch and `git status`. If there are unsaved changes,
   do not switch branches or overwrite them: stop and ask the user how to
   proceed.
2. Run `git fetch origin --prune`, then `git switch main` and
   `git pull --ff-only origin main`. If `main` does not exist, the pull fails, or
   the update requires manual resolution, stop and report the problem; do not
   use reset or force-push to work around it.
3. Examine `git branch -vv` and remove local branches whose upstream is
   `[gone]`, after ensuring they contain no unique local work.
   Use `git branch -d`; do not force-delete with `-D`. If a branch
   contains unintegrated commits, keep it and ask the user before
   deleting it.
4. Create a new branch dedicated to the chat/issue from updated `main`,
   e.g., with `git switch -c <issue-name> main`. Choose an unused name and do not
   reuse or overwrite an existing branch.

Do not start implementation until the work branch has been created
from updated `main`. Do not delete or discard user changes during
this preparation.

## Mappa dell'architettura (da docs/design.md §3)
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

## Le 8 invarianti di sicurezza (NON negoziabili — verbatim da docs/design.md §5)
1. **Allowlist-only roots.** Deletion may only target paths under allowlisted roots defined per module (e.g. `~/Library/Caches`). Everything else = refusal.
2. **Symlink discipline.** Resolve every path; verify the resolved target is still inside the allowlist root; never follow symlinks into unknown locations.
3. **Protected paths.** Hard deny: SIP-protected volumes, `/System`, `/private/var/db`, the user's Desktop/Documents/Downloads roots, and any active application bundle.
4. **Trash-first.** Default destructive op is `FileManager.trashItem` (real Trash, recoverable). Permanent delete requires an explicit per-item opt-in checkbox, off by default.
5. **Dry-run everywhere.** First run of "Smart Scan" never deletes; every clean action has a dry-run mode reporting byte counts.
6. **Confirmation + recap.** GUI must show total size and item count before executing; admin escalation (sandboxed helper) is separate and logged.
7. **Graceful TCC.** Missing Full Disk Access disables only the modules that need it, with clear onboarding — never silently scans less than displayed.
8. **No silent failures.** Every deletion is logged (locally) with timestamp, rule id, and size; logs are exportable for bug reports.

> **v0.1/v0.2 note (not an invariant).** Permanent delete is not offered in v0.1 or v0.2, even though invariant 4 allows an explicit per-item opt-in. Every destructive action is trash-first through `Sources/CoreKit/Safety/`.

## v0.2 boundaries (from docs/design.md §11)
- v0.2 never removes `.app` bundles and never modifies, moves or trashes anything in `/Applications` or `~/Applications`; the only access is read-only installed-app discovery. The current Safety denials (`PathValidator`) stay unchanged. Real uninstall is v0.3 (#107).
- Leftovers are reported only for apps that are no longer installed (bundle ID absent from a complete discovery), only under the `~/Library` roots listed in design.md §11.4, and acted on only through the existing Safety pipeline, trash-first.
- Duplicates are read-only in v0.2: list, details, Reveal in Finder. No selection, no deletion (v0.3, #40).
- Leftovers and duplicates are separate sidebar sections and are not part of Smart Scan.
- Rule DB v2 follows the contract in design.md §11.2; version-conditional exclusions are out of scope for v0.2 (#106).
- Changes to `Safety/` or `Rules/` (including `Rules/*.json`) keep requiring the `[SAFETY]` flag and human review.

## Release procedure
A release needs two PRs, because the cask `sha256` only exists after the Release workflow has built the ZIP (builds are not reproducible, so it cannot be computed beforehand):
1. **Before the release** (`chore/release-X.Y.Z`): bump `MARKETING_VERSION` in `Terso.xcodeproj/project.pbxproj` (both configurations) and update README. Do not touch the cask: it must keep pointing at the last published release until the new ZIP exists.
2. After the maintainer merges it and says "confermo", run the Release workflow from `main` (never tag manually), verify the downloaded ZIP against its `.sha256`.
3. **After the release** (`chore/cask-X.Y.Z`): one PR that updates `version` and `sha256` in `packaging/homebrew/Casks/terso.rb` with the value from the published `.sha256` sidecar. The same file is then copied to `lapht/homebrew-tap` (maintainer-owned) and audited there; see `packaging/homebrew/README.md`.
Never merge, tag or run the Release workflow without the maintainer's explicit confirmation.

## Rules of engagement
- **Absolute ban:** no file deletion logic or APIs outside `Sources/CoreKit/Safety/`. CI blocks violations: do not look for workarounds, just report.
- Do not expand an issue's scope. If other work is needed, propose a new issue instead of implementing it here.
- Any change to `Safety/` or `Rules/` requires mandatory human review: flag it explicitly in the PR description with `[SAFETY]`.
- Code conforms to SwiftLint; run tests before proposing the PR.
- Commits in Conventional Commits format (`feat:`, `fix:`, `test:`...).
- One issue = one PR. Small, readable PRs.

## Mandatory tests for any change
- Rule engine: schema and pattern validation with fixtures in `Tests/`.
- Any new module: fixture tree with known content + test on exact scan and deletion set results. Include a symlink-attack case when relevant.
