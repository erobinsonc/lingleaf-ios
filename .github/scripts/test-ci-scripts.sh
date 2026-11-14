#!/usr/bin/env bash
# Local tests for ci-plan.sh, ci-gate.py, verify-prior-ci.py and test-shards.py.
# Usage: .github/scripts/test-ci-scripts.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT

# --- shards: sources and shard lists agree ---
python3 -I "$here/test-shards.py" --check >/dev/null && ok "shards: every test runs in exactly one shard" || bad "shards: check"

# --- gate ---
needs() { # <plan> <heavy> <verify>
  printf '{"plan":{"result":"%s"},"heavy":{"result":"%s"},"verify":{"result":"%s"}}' "$1" "$2" "$3"; }
gate() { # <want-rc> <mode> <plan> <heavy> <verify>
  local want="$1" mode="$2"; shift 2
  MODE="$mode" NEEDS="$(needs "$@")" python3 -I "$here/ci-gate.py" --heavy heavy --verify verify >/dev/null 2>&1; local rc=$?
  if { [ "$want" = 0 ] && [ $rc -eq 0 ]; } || { [ "$want" != 0 ] && [ $rc -ne 0 ]; }; then ok "gate $mode $* -> $want"; else bad "gate $mode $* (rc=$rc)"; fi
}
gate 0 full success success skipped
gate 1 full success failure skipped
gate 1 full success cancelled skipped
gate 1 full success skipped skipped      # a skipped heavy job in full mode must not pass
gate 1 full failure success skipped      # plan failed
gate 1 full success success success
gate 0 same-tree success skipped skipped
gate 1 same-tree success success skipped
gate 1 same-tree success failure skipped
gate 0 release success skipped success
gate 1 release success skipped failure
gate 1 release success skipped skipped   # release without the prior-run check
gate 1 release success success success
gate 1 "" success success skipped        # unknown mode
gate 1 bogus success skipped skipped
NEEDS='{"plan":{"result":"success"}}' MODE=full python3 -I "$here/ci-gate.py" --heavy heavy >/dev/null 2>&1 && bad "gate: missing job passed" || ok "gate: a missing job fails"

# --- plan: real git repositories ---
git_() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }
o="$t/origin.git"; git_ init -q --bare "$o"
w="$t/w"; git_ clone -q "$o" "$w" 2>/dev/null; cd "$w" || exit 1
echo 1 > a; git_ add a; git_ commit -qm one; git_ push -q origin HEAD:main
git_ checkout -q -b develop; echo 2 > b; git_ add b; git_ commit -qm two; git_ push -q origin develop
dev_sha="$(git rev-parse HEAD)"
plan() { # <event> <base> <head_ref> <sha> <same_repo>  -> prints mode
  rm -f "$t/out"; EVENT_NAME="$1" BASE_REF="$2" HEAD_REF="$3" HEAD_SHA="$4" SAME_REPO="$5" GITHUB_OUTPUT="$t/out" "$here/ci-plan.sh" >/dev/null 2>&1
  sed -n 's/^mode=//p' "$t/out"
}
want() { [ "$2" = "$3" ] && ok "plan $1 -> $3" || bad "plan $1: got '$2', want '$3'"; }
want "push" "$(plan push develop develop "$dev_sha" true)" full
want "release (main is an ancestor of develop)" "$(plan pull_request main develop "$dev_sha" true)" release
want "release from a fork named develop" "$(plan pull_request main develop "$dev_sha" false)" full
# main moves on: no longer an ancestor of develop -> full
git_ checkout -q main; echo 3 > c; git_ add c; git_ commit -qm hotfix; git_ push -q origin main
want "release, main not an ancestor" "$(plan pull_request main develop "$dev_sha" true)" full
# sync PR: a branch whose tree equals develop's tree (merge of main into develop-like branch)
git_ checkout -q -b sync "$dev_sha"; git_ merge -q --no-edit main; git_ checkout -q develop; git_ merge -q --no-edit sync; git_ push -q origin develop
sync_sha="$(git rev-parse HEAD)"   # develop tip now includes main
git_ checkout -q -b fix/sync-again "$sync_sha"; git_ commit -q --allow-empty -m empty
want "sync PR, identical tree" "$(plan pull_request develop fix/sync-again "$(git rev-parse HEAD)" true)" same-tree
echo changed > c; git_ add c; git_ commit -qm "workflow-like change"
want "any difference in tree" "$(plan pull_request develop fix/sync-again "$(git rev-parse HEAD)" true)" full
want "garbage sha" "$(plan pull_request develop fix/x 'not-a-sha' true)" full
want "garbage base" "$(plan pull_request '--upload-pack=x' fix/x "$(git rev-parse HEAD)" true)" full
cd "$t" || exit 1

# --- verify-prior-ci: fake gh ---
sha=0123456789abcdef0123456789abcdef01234567
mkdir -p "$t/bin"
cat > "$t/bin/gh" <<'GH'
#!/bin/sh
# canned responses chosen by $FAKE_CASE
case "$2" in
  *workflows/ios.yml/runs*)
    case "$FAKE_CASE" in
      none) echo '{"workflow_runs":[]}' ;;
      pending) echo '{"workflow_runs":[{"id":7,"run_number":3,"head_sha":"'$SHA'","head_branch":"develop","event":"push","status":"in_progress","conclusion":null}]}' ;;
      failed) echo '{"workflow_runs":[{"id":7,"run_number":3,"head_sha":"'$SHA'","head_branch":"develop","event":"push","status":"completed","conclusion":"failure"}]}' ;;
      otherbranch) echo '{"workflow_runs":[{"id":7,"run_number":3,"head_sha":"'$SHA'","head_branch":"feat/x","event":"push","status":"completed","conclusion":"success"}]}' ;;
      *) echo '{"workflow_runs":[{"id":7,"run_number":3,"head_sha":"'$SHA'","head_branch":"develop","event":"push","status":"completed","conclusion":"success"}]}' ;;
    esac ;;
  *runs/7/jobs*)
    case "$FAKE_CASE" in
      missingjob) echo '{"jobs":[{"name":"CI script tests","conclusion":"success"},{"name":"Core logic (tests, coverage ≥90%)","conclusion":"success"}]}' ;;
      skippedapp) echo '{"jobs":[{"name":"CI script tests","conclusion":"success"},{"name":"Core logic (tests, coverage ≥90%)","conclusion":"success"},{"name":"App (SwiftLint, build, UI + accessibility tests)","conclusion":"skipped"}]}' ;;
      *) echo '{"jobs":[{"name":"CI script tests","conclusion":"success"},{"name":"Core logic (tests, coverage ≥90%)","conclusion":"success"},{"name":"App (SwiftLint, build, UI + accessibility tests)","conclusion":"success"}]}' ;;
    esac ;;
esac
GH
chmod +x "$t/bin/gh"
verify() { FAKE_CASE="$1" SHA="$sha" PATH="$t/bin:$PATH" GITHUB_REPOSITORY=o/r python3 -I "$here/verify-prior-ci.py" "$sha" >/dev/null 2>&1; }
verify good && ok "verify: green develop push run passes" || bad "verify: good case"
for c in none pending failed otherbranch missingjob skippedapp; do verify "$c" && bad "verify: $c passed" || ok "verify: $c fails"; done
exit $fail
