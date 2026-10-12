# CLAUDE.md

Lingleaf: learn English by reading real books. Two native apps share one product
spec: this repo (lingleaf-ios) and [lingleaf-android](https://github.com/erobinsonc/lingleaf-android).

## Git flow (mandatory)

```
feat/*, fix/*  ──PR──▶  develop  ──release PR──▶  main
```

- Never commit or push directly to `develop` or `main`.
- Start every change from `develop`: `git checkout develop && git pull && git checkout -b feat/short-name`.
- Open the pull request against `develop`. Merge only when CI is green and the validators below approve.
- Releases: a pull request `develop → main`, approved by the maintainer. Tag `vX.Y.Z` on `main`.
- Hotfixes: `fix/*` from `main`, merged into `main` and back into `develop`.

## Checks before every push

```bash
swift test --package-path LingleafCore        # logic tests (CI enforces coverage ≥90%)
swiftlint lint
xcodegen generate && xcodebuild test -project Lingleaf.xcodeproj -scheme Lingleaf -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Validators (subagents in `.claude/agents/`) — run before asking to merge

| Change touches | Run |
|---|---|
| Networking, storage, manifests, dependencies, CI | `security-reviewer` |
| Any screen or component | `accessibility-reviewer`, `usability-reviewer`, `platform-guidelines-reviewer`, `ux-experience-reviewer` |
| Any flow or user-facing text, and every release PR (develop → main) | `ux-experience-reviewer` (both apps, simplicity first) |
| Any user-facing text (Lingleaf/Resources/Localizable.xcstrings) | `ux-writing-reviewer` |
| Behaviour, shared logic or SPEC.md | `parity-reviewer` |
| Stories, levels, learning features | `learning-content-reviewer` |
| Learning features, word card, review, saved-word data | `learning-science-reviewer` (memory and learning evidence, no neuromyths) |

A 🔴 or 🟠 finding blocks the merge. Validators don't edit code; fix and re-run.

## Parity rule

SPEC.md is identical in both repos. A behaviour change updates SPEC.md, the
tests and the code **in both repos** (two pull requests that reference each other).

## Conventions

- All user-facing text is localized (English source, Spanish translation).
- No analytics, ads or tracking. New network hosts must be documented in README.
- Commit messages in English, imperative mood.
