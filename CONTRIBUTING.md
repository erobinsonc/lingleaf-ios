# Contributing

Thanks for helping! Code, graded stories, translations of the interface and bug reports are all welcome.

1. Fork and branch: `git checkout -b feat/my-change`.
2. Run the checks before opening a pull request:
   ```bash
   swift test --package-path LingleafCore
   swiftlint lint
   xcodegen generate && xcodebuild test -project Lingleaf.xcodeproj -scheme Lingleaf -destination 'platform=iOS Simulator,name=iPhone 16'
   ```
3. Behaviour changes update [SPEC.md](SPEC.md) here **and** in
   [lingleaf-android](https://github.com/erobinsonc/lingleaf-android), so both apps stay in sync.
4. Every user-facing string is translated in `Lingleaf/Resources/Localizable.xcstrings` (English and Spanish).
5. Open the pull request. CI must be green before merging.

## How the CI decides what to run

`iOS CI` plans each run (`Plan CI`): a normal change runs everything, sharded across macOS runners;
a sync pull request whose tree equals the base branch tip (and whose tip has a green push CI) skips the
macOS jobs; a release pull request `develop` -> `main` verifies that the head commit already passed the
full CI as a push on `develop` instead of repeating it. The required checks `Core logic (…)` and
`App (…)` are gates that pass only on the exact expected result. If you open a release pull request while
the push CI of `develop` is still running, `Verify the develop CI run` fails: re-run that job (or the
failed jobs) when the push run has finished. Shards are listed in `.github/scripts/test-shards.py`; a new
UI test runs in the `ui-rest` shard until someone rebalances.

The accessibility audit accepts a finding next to the translucent tab bar only after measuring the text's own pixels
(`LingleafUITests/GlassContrast.swift`); `GlassContrastTests` checks that measurement on synthetic bitmaps, and the audit
runs in light appearance only. The rule covers the bottom tab bar only for now; the top navigation bar's blur is not
covered yet.

## Principles

- Same behaviour on iOS and Android.
- No analytics, ads or tracking. Any new network host is documented in the README.
- Accessible by default: Dynamic Type, VoiceOver labels, the accessibility audit passes.
