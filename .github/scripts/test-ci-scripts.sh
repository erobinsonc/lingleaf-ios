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

# --- fake gh (canned API answers chosen by $FAKE_CASE; the commit comes from the query) ---
mkdir -p "$t/bin"
cat > "$t/bin/gh" <<'GH'
#!/bin/sh
sha=$(printf '%s' "$2" | sed -n 's/.*head_sha=\([0-9a-f]*\).*/\1/p')
case "$2" in
  *workflows/ios.yml/runs*)
    run() { echo '{"workflow_runs":[{"id":7,"run_number":3,"head_sha":"'$sha'","head_branch":"'$1'","event":"push","status":"'$2'","conclusion":'$3'}]}'; }
    case "$FAKE_CASE" in
      none) echo '{"workflow_runs":[]}' ;;
      pending) run develop in_progress null ;;
      failed) run develop completed '"failure"' ;;
      otherbranch) run feat/x completed '"success"' ;;
      *) run "${FAKE_BRANCH:-develop}" completed '"success"' ;;
    esac ;;
  *runs/7/jobs*)
    ok='{"name":"CI script tests","conclusion":"success"},{"name":"Core logic (tests, coverage ≥90%)","conclusion":"success"}'
    app='{"name":"App (SwiftLint, build, UI + accessibility tests)","conclusion":"success"}'
    case "$FAKE_CASE" in
      missingjob) echo '{"jobs":['"$ok"']}' ;;
      skippedapp) echo '{"jobs":['"$ok"',{"name":"App (SwiftLint, build, UI + accessibility tests)","conclusion":"skipped"}]}' ;;
      duplicate) echo '{"jobs":['"$ok,$app,$app"']}' ;;
      *) echo '{"jobs":['"$ok,$app"']}' ;;
    esac ;;
esac
GH
chmod +x "$t/bin/gh"
export GITHUB_REPOSITORY=o/r

# --- plan: real git repositories ---
git_() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }
o="$t/origin.git"; git_ init -q --bare "$o"
w="$t/w"; git_ clone -q "$o" "$w" 2>/dev/null; cd "$w" || exit 1
echo 1 > a; git_ add a; git_ commit -qm one; git_ push -q origin HEAD:main
git_ checkout -q -b develop; echo 2 > b; git_ add b; git_ commit -qm two; git_ push -q origin develop
dev_sha="$(git rev-parse HEAD)"
plan() { # <event> <base> <head_ref> <sha> <same_repo>  -> prints mode
  rm -f "$t/out"; PATH="$t/bin:$PATH" EVENT_NAME="$1" BASE_REF="$2" HEAD_REF="$3" HEAD_SHA="$4" SAME_REPO="$5" GITHUB_OUTPUT="$t/out" "$here/ci-plan.sh" >/dev/null 2>&1
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
want "sync PR, identical tree, base tip CI green" "$(FAKE_CASE=good plan pull_request develop fix/sync-again "$(git rev-parse HEAD)" true)" same-tree
want "sync PR, identical tree, base tip CI failed" "$(FAKE_CASE=failed plan pull_request develop fix/sync-again "$(git rev-parse HEAD)" true)" full
want "sync PR, identical tree, base tip CI pending" "$(FAKE_CASE=pending plan pull_request develop fix/sync-again "$(git rev-parse HEAD)" true)" full
want "sync PR, identical tree, base tip has no push run" "$(FAKE_CASE=none plan pull_request develop fix/sync-again "$(git rev-parse HEAD)" true)" full
echo changed > c; git_ add c; git_ commit -qm "workflow-like change"
want "any difference in tree" "$(FAKE_CASE=good plan pull_request develop fix/sync-again "$(git rev-parse HEAD)" true)" full
want "garbage sha" "$(plan pull_request develop fix/x 'not-a-sha' true)" full
want "garbage base" "$(plan pull_request '--upload-pack=x' fix/x "$(git rev-parse HEAD)" true)" full
cd "$t" || exit 1

sha=0123456789abcdef0123456789abcdef01234567
verify() { FAKE_CASE="$1" PATH="$t/bin:$PATH" python3 -I "$here/verify-prior-ci.py" "$sha" "${@:2}" >/dev/null 2>&1; }
verify good && ok "verify: green develop push run passes" || bad "verify: good case"
for c in none pending failed otherbranch missingjob skippedapp duplicate; do verify "$c" && bad "verify: $c passed" || ok "verify: $c fails"; done
FAKE_BRANCH=main verify good --branch main && ok "verify: --branch main passes for a main run" || bad "verify: --branch"
verify good --branch "--evil" && bad "verify: option-like branch accepted" || ok "verify: option-like branch refused"
# ancestry re-check at verify time (inside the sandbox repo: origin/main vs develop's tip)
cd "$w" || exit 1
git_ checkout -q main; git_ pull -q origin main 2>/dev/null
sha_main="$(git rev-parse HEAD)"
git_ checkout -q -b rel develop 2>/dev/null; git_ merge -q --no-edit main 2>/dev/null; sha_rel="$(git rev-parse HEAD)"
FAKE_CASE=good PATH="$t/bin:$PATH" python3 -I "$here/verify-prior-ci.py" "$sha_rel" --require-ancestor main >/dev/null 2>&1 && ok "verify: main is an ancestor -> passes" || bad "verify: ancestor case"
git_ checkout -q main; echo more > d; git_ add d; git_ commit -qm "main moved"; git_ push -q origin main 2>/dev/null
FAKE_CASE=good PATH="$t/bin:$PATH" python3 -I "$here/verify-prior-ci.py" "$sha_rel" --require-ancestor main >/dev/null 2>&1 && bad "verify: moved main accepted" || ok "verify: main moved since the plan -> fails"
cd "$t" || exit 1

# --- merge-screenshots ---
png() { printf '\x89PNG\r\n\x1a\nxx' > "$1"; }
mk() { rm -rf "$t/parts" "$t/merged"; mkdir -p "$t/parts/a" "$t/parts/b"; png "$t/parts/a/en-light-01-x.png"; png "$t/parts/b/es-light-01-x.png"; }
mk; "$here/merge-screenshots.sh" "$t/parts" "$t/merged" >/dev/null 2>&1 && [ "$(ls "$t/merged" | wc -l)" = 2 ] && ok "merge: two shards flatten" || bad "merge: good"
mk; png "$t/parts/b/en-light-01-x.png"; "$here/merge-screenshots.sh" "$t/parts" "$t/merged" >/dev/null 2>&1 && bad "merge: duplicate accepted" || ok "merge: a name from two shards fails"
mk; ln -s /proc/self/environ "$t/parts/a/l.png"; "$here/merge-screenshots.sh" "$t/parts" "$t/merged" >/dev/null 2>&1 && bad "merge: symlink accepted" || ok "merge: symlink fails"
mk; mkdir "$t/parts/a/sub"; "$here/merge-screenshots.sh" "$t/parts" "$t/merged" >/dev/null 2>&1 && bad "merge: nested dir accepted" || ok "merge: nested directory fails"
mk; png "$t/parts/loose.png"; "$here/merge-screenshots.sh" "$t/parts" "$t/merged" >/dev/null 2>&1 && bad "merge: loose file accepted" || ok "merge: file outside artifact folders fails"
rm -rf "$t/parts"; "$here/merge-screenshots.sh" "$t/parts" "$t/merged" >/dev/null 2>&1 && ok "merge: nothing downloaded is fine" || bad "merge: empty"

# --- pick-simulator ---
sim='{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-6":[{"name":"iPhone 16","udid":"A"}],"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[{"name":"iPad Air","udid":"B"},{"name":"iPhone 17","udid":"C"}],"com.apple.CoreSimulator.SimRuntime.watchOS-26-0":[{"name":"iPhone-like","udid":"D"}]}}'
[ "$(printf '%s' "$sim" | python3 -I "$here/pick-simulator.py")" = "C com.apple.CoreSimulator.SimRuntime.iOS-26-0" ] && ok "simulator: newest iOS runtime, first iPhone" || bad "simulator pick"
printf '{"devices":{}}' | python3 -I "$here/pick-simulator.py" >/dev/null 2>&1 && bad "simulator: none accepted" || ok "simulator: none fails"

# --- shards: modifiers and attributes on classes and tests, and the per-shard count ---
mkdir -p "$t/src/LingleafUITests"
cat > "$t/src/LingleafUITests/A.swift" <<'SW'
@MainActor
final class First: XCTestCase {
    func testOne() {}
    @available(iOS 18, *) func testTwo() {}
    private func helper() {}
}
private final class Second: XCTestCase {
    override func testThree() {}
}
@MainActor final class Third: XCTestCase {
    func testFour() {}
}
extension First {
    func testFive() throws {}
}
SW
n="$(python3 -I - "$here" "$t/src" <<'PY'
import sys, importlib.util
spec = importlib.util.spec_from_file_location("ts", sys.argv[1] + "/test-shards.py"); ts = importlib.util.module_from_spec(spec); spec.loader.exec_module(ts)
print(len(ts.tests_in_sources(sys.argv[2])))
PY
)"
[ "$n" = 5 ] && ok "shards: attributes and modifiers are understood (5 tests)" || bad "shards: parsed $n tests, want 5"
python3 -I "$here/test-shards.py" --matrix | python3 -I -c "import json,sys; m=json.load(sys.stdin)['include']; assert all(isinstance(x['count'],int) and x['count']>0 for x in m)" && ok "shards: every shard has a count" || bad "shards: counts"
exit $fail
