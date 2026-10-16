# Terso — Manual UI checklist

Run this checklist before merging any PR that changes `Sources/TersoApp/`, and attach the
screenshots to the PR. It complements the automated tests: it checks what only a person
looking at the app can judge.

## Visual spec (reference)

The tokens live in `Sources/TersoApp/DesignTokens.swift`; shared components in
`Sources/TersoApp/TersoComponents.swift`. Views must not hardcode colors, spacing or radii.

| Area | Rule |
|---|---|
| Brand | The teal drop of `docs/assets/logo.png`. Page headers show a `BrandBadge` (gradient `#0FB5AE` → `#0A6F8A`, white glyph). |
| Accent | `AccentColor` asset: `#08756F` light / `#0A7F7A` dark. Used for buttons, selection, progress. White labels on it meet WCAG AA (5.55 : 1 / 4.85 : 1). |
| Brand text | `BrandText` asset: `#08756F` light / `#2CCFC7` dark, for figures and icons. AA on the window background (4.7 : 1 / 8.6 : 1). |
| Semantic colors | Green = completed cleanup, orange = warning, red = actual failure. Never used for urgency or to push the user to clean. |
| Typography | System font. Page title `largeTitle` semibold; section `headline`; metadata `callout`; figures rounded with monospaced digits. |
| Spacing | 4 / 8 / 12 / 16 / 20 / 24 pt. Page padding 24, cards 16, rows 12. |
| Radii | Rows 10, cards and badges 12. |
| Content width | At most 720 pt on wide windows. |
| Motion | State transitions ease 0.25 s; none when *Reduce motion* is on. |
| Tone | Calm and factual (design.md §1–§2). No absolute safety claims, no alarming copy. |

## Environment

- [ ] Build from the PR branch with the `TersoApp` scheme.
- [ ] Note macOS version and Mac model (Intel / Apple Silicon) in the PR.

## Full Disk Access

- [ ] **Without FDA** (System Settings › Privacy & Security › Full Disk Access, Terso off):
  the banner is shown on every page, in brand tint (not red/orange), and *Open System
  Settings* opens the right pane.
- [ ] Modules that need FDA show the permission message on their card; the other modules
  still scan. The total never claims to include modules that were not scanned (§5.7).
- [ ] **With FDA**: the banner disappears after returning to the app; all modules scan.

## Flows

- [ ] Smart Scan idle: header with badge, read-only note, "Ready when you are" empty state.
- [ ] Scanning: progress card with current module, items and bytes; Cancel works.
- [ ] Finished: reclaimable total and item count in evidence; breakdown bar and legend
  match the module cards.
- [ ] Nothing found: "Nothing to clean right now" empty state.
- [ ] Module detail: selected rows highlighted; selection recap shows size and "n of m".
- [ ] Confirmation sheet shows item count and total size before moving to Trash (§5.6).
- [ ] Cleanup result: size moved to Trash, item count, duration; warnings in their own card.
- [ ] Each module page (User Caches, User Logs, Trash Bins, Xcode Junk, Package Caches)
  uses its own sidebar icon in the header and on the Scan button.
- [ ] Large Files: read-only copy, no Trash action.
- [ ] Audit Log: empty state when there are no events; table and export otherwise.

## Window sizes

- [ ] **Minimum size** (720 × 460): nothing is clipped; banner text wraps; cards reflow.
- [ ] **Large window** (full screen on a large display): content stays within 720 pt and
  anchored top-leading.

## Appearance

- [ ] **Light mode**: screenshots of Smart Scan (idle, finished), a module detail, the
  confirmation sheet and the cleanup result.
- [ ] **Dark mode**: the same screenshots.
- [ ] Sidebar selection and icons use the teal accent in both modes.

## Accessibility

- [ ] **Contrast**: check accent and brand text with Accessibility Inspector (or a
  contrast checker) in both modes; text must be ≥ 4.5 : 1, large figures and controls ≥ 3 : 1.
- [ ] **Increase contrast** (System Settings › Accessibility › Display): accent and brand
  text switch to their high-contrast variants; separators remain visible.
- [ ] **Reduce motion**: scan state changes and progress update without animation.
- [ ] **VoiceOver**: page titles are announced as headings; badges and decorative icons are
  skipped; the reclaimable total, item count and selection recap are read; the breakdown
  legend is read as "module, size".
- [ ] Keyboard: Tab reaches every button; Return confirms and Esc cancels the
  confirmation sheet.

## Result

Paste screenshots (before/after, light and dark) and list any item that failed, with a
follow-up issue if it is out of scope for the PR.
