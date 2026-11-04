# Dependabot and pinned actions

Every GitHub Action in `.github/workflows` is pinned by full commit SHA, with the version
in a trailing comment (`uses: owner/repo@<40 hex> # vX.Y.Z`). Dependabot
(`.github/dependabot.yml`) opens pull requests against `develop` that change the SHA and the
comment together. A pin only protects us if the new SHA is the real release, so **every bump
is verified by a person before it is merged. Dependabot PRs are never auto-merged.**

## Checklist for each bump

1. **The SHA is the tag.** The SHA in the PR must equal the commit the upstream tag points to:

   ```bash
   git ls-remote --tags https://github.com/<owner>/<repo> "vX.Y.Z" "vX.Y.Z^{}"
   # or
   gh api repos/<owner>/<repo>/git/ref/tags/vX.Y.Z
   ```

   For an annotated tag use the peeled line (`^{}`) from `ls-remote`, or follow the tag object
   (`gh api repos/<owner>/<repo>/git/tags/<sha>`). If they differ, stop.
2. **Read the compare view** linked in the PR ("compare view"): which files changed between the
   old and the new SHA. A release that touches more than its notes say, a new network call, an
   obfuscated or minified-only change, or a changed `action.yml` `runs:` is a stop.
3. **Prefer immutable releases.** Check the release page for the "Immutable" badge. A mutable
   tag can be moved after we verify it; the pin protects us only because we check the SHA once.
4. **Read the release notes** for breaking changes, new inputs with security impact and the
   runtime (Node version, runner minimum).
5. **Extra care for what touches secrets.** `actions/checkout` and anything in
   `.github/workflows/testflight.yml` (the job that holds the App Store Connect key) or in the
   `screenshots` job (write token): run the security validators and, for TestFlight, a
   `workflow_dispatch` dry run before the next release.
6. **Merge on green CI**, by hand, after the maintainer or lead has done 1-5.

## How the config helps

- `target-branch: develop` keeps Git Flow.
- A 7-day cooldown lets a new release age before it is proposed.
- `actions/checkout`, `gitleaks/*` and `github/codeql-action/*` are never grouped: each
  gets its own PR.
- `.github/CODEOWNERS` names the owner for `/.github/`. It only blocks merges once the branch
  ruleset has "Require review from Code Owners" turned on, which only the maintainer can set.

## The `screenshots` jobs

`ios.yml` publishes screenshots in two jobs so bumped actions never run next to a write token:
`screenshots-prepare` (read-only token) downloads and checks the files
(`.github/scripts/verify-screenshots.sh`) and re-uploads them; `screenshots` (write token)
runs a pinned checkout, the `gh` CLI, a second run of the check and `publish-screenshots.sh`, and
nothing else. The verified artifact has an unguessable per-run name, and `screenshots` needs the
prepare job to have succeeded. On `pull_request` the checkout is the merge commit; accepted
because forks are excluded.
