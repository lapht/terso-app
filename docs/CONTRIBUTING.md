# Contributing to Terso

Thank you for helping improve Terso. Contributions are made through forks and
pull requests to `main`; maintainer @lapht decides whether to merge and performs
all merges.

## Before starting

1. Search existing issues and pull requests. Open an issue to report a bug,
   discuss a feature, or propose a cleanup rule before investing in a larger
   change.
2. Keep each pull request focused on one coherent change. Discuss unrelated
   work in a separate issue rather than expanding the scope.
3. Read the [design document](./design.md), especially its safety invariants.
   Changes to `Sources/CoreKit/Safety/` or `Rules/` require particular human
   review by the maintainer.

Use the GitHub issue forms for [bugs](../.github/ISSUE_TEMPLATE/bug_report.yml),
[feature requests](../.github/ISSUE_TEMPLATE/feature_request.yml), and
[rule proposals](../.github/ISSUE_TEMPLATE/rule_proposal.yml).

## Development setup

- macOS 13 or later is the app's deployment target.
- Open [`Terso.xcodeproj`](../Terso.xcodeproj) in Xcode and use the shared
  `TersoApp` scheme for the app and its unit tests. CI currently selects
  Xcode 16.4.
- The app consumes `CoreKit` from the local Swift package in
  [`Package.swift`](../Package.swift).

Create a fork on GitHub, then clone your fork and add the project repository as
`upstream`:

```bash
git clone https://github.com/<your-user>/terso-app.git
cd terso-app
git remote add upstream https://github.com/lapht/terso-app.git
git fetch upstream
git switch -c <type>/<short-description> upstream/main
```

Make the change on that branch. Use a descriptive branch name such as
`fix/cache-scan` or `docs/contributing`.

## Test your changes

Run the CoreKit Swift Package tests from the repository root:

```bash
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

`swift test` runs the package tests; it does not run the app's Xcode unit tests.
For app tests, run the `TersoApp` scheme through Xcode or use:

```bash
xcodebuild \
  -project Terso.xcodeproj \
  -scheme TersoApp \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Run tests relevant to your change and report precisely what you ran. The
automated CI also builds the app with Xcode for both architectures.

## Open a pull request

Push your branch to your fork and open a pull request with base
`lapht/terso-app:main`. Include the issue it addresses, a concise explanation,
test results, screenshots for UI changes, and any effects on `Safety/`, `Rules/`,
permissions, or workflows. Follow the
[pull request template](../.github/PULL_REQUEST_TEMPLATE.md).

The current CI workflow runs on pushes to `main` and on `pull_request` events
targeting `main` (not `pull_request_target`). Its matrix jobs are named
`Quality Gates (arm64)` and `Quality Gates (x86_64)`. Each runs SwiftLint,
SwiftFormat checks, an app build, app tests, package tests, and the Safety
Audit plus its tests. These are the checks configured in the workflow; this
guide does not claim that GitHub branch protection makes them mandatory.

The maintainer reviews and decides whether to merge a pull request. Contributors
must not merge pull requests or publish releases. Release creation is a
maintainer-controlled workflow.

## Commit messages and review

Use [Conventional Commits](https://www.conventionalcommits.org/), for example:

```text
fix: handle an empty cache directory
docs: clarify local test commands
```

Changes affecting `Sources/CoreKit/Safety/` or `Rules/` must be called out in
the pull request and receive particular human review. Do not bypass the
guarded deletion design or weaken the documented safety invariants.

## Reporting security concerns

Do not report vulnerabilities or data-loss risks in a public issue. Check
[SECURITY.md](../SECURITY.md) for the current private reporting status and
instructions.
