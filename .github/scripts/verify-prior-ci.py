#!/usr/bin/env python3
"""Release shortcut: checks that the head commit already passed the full iOS CI as a push on develop.

Usage: GH_TOKEN=... GITHUB_REPOSITORY=o/r verify-prior-ci.py <sha> [--branch develop] [--require-ancestor main]
Reads (GitHub API, read-only): the latest `iOS CI` push run on <branch> for exactly that commit and
its jobs. Fails unless that run completed successfully and each required job concluded success once
(a name that appears twice is ambiguous and fails). With --require-ancestor REF, also fails unless
origin/REF is an ancestor of <sha> right now (the release merge tree is the head tree only then).
"""
import argparse
import json
import os
import re
import subprocess
import sys

REQUIRED = [
    "CI script tests",
    "Core logic (tests, coverage ≥90%)",
    "App (SwiftLint, build, UI + accessibility tests)",
]
parser = argparse.ArgumentParser()
parser.add_argument("sha")
parser.add_argument("--branch", default="develop")
parser.add_argument("--require-ancestor", default="")
args = parser.parse_args()
sha, branch = args.sha, args.branch
repo = os.environ["GITHUB_REPOSITORY"]
if not re.fullmatch(r"[0-9a-f]{40}", sha) or not re.fullmatch(r"[\w.-]+/[\w.-]+", repo) \
        or not re.fullmatch(r"[A-Za-z0-9._/-]+", branch) or branch.startswith("-"):
    sys.exit("::error::Unexpected commit, branch or repository name")

if args.require_ancestor:
    ref = args.require_ancestor
    if not re.fullmatch(r"[A-Za-z0-9._/-]+", ref) or ref.startswith("-"):
        sys.exit("::error::Unexpected ref name")
    fetched = subprocess.run(["git", "fetch", "--quiet", "--no-tags", "origin", f"+refs/heads/{ref}:refs/remotes/origin/{ref}"],
                             capture_output=True, text=True, check=False)
    ancestor = subprocess.run(["git", "merge-base", "--is-ancestor", f"refs/remotes/origin/{ref}", sha], check=False)
    if fetched.returncode != 0 or ancestor.returncode != 0:
        sys.exit(f"::error::{ref} is not an ancestor of {sha[:7]} now (it moved since the plan): re-run the CI so it runs in full.")


def api(path):
    done = subprocess.run(["gh", "api", path], capture_output=True, text=True, check=False)
    if done.returncode != 0:
        sys.exit(f"::error::GitHub API call failed: {done.stderr.strip()[:200]}")
    return json.loads(done.stdout)


runs = api(f"repos/{repo}/actions/workflows/ios.yml/runs?head_sha={sha}&event=push&per_page=50")["workflow_runs"]
runs = [r for r in runs if r["head_sha"] == sha and r["head_branch"] == branch and r["event"] == "push"]
if not runs:
    sys.exit(f"::error::No push run of iOS CI on {branch} for {sha[:7]}. Merge first and wait for its CI.")
run = max(runs, key=lambda r: (r["run_number"], r.get("run_attempt", 1)))
if run["status"] != "completed":
    sys.exit(f"::error::iOS CI on {branch} for {sha[:7]} is still {run['status']}. Re-run this check when it ends.")
if run["conclusion"] != "success":
    sys.exit(f"::error::iOS CI on {branch} for {sha[:7]} concluded {run['conclusion']}.")
jobs = api(f"repos/{repo}/actions/runs/{run['id']}/jobs?filter=latest&per_page=100")["jobs"]
names = [j["name"] for j in jobs]
result = {j["name"]: j["conclusion"] for j in jobs}
bad = [n for n in REQUIRED if names.count(n) != 1 or result.get(n) != "success"]
for n in REQUIRED:
    print(f"{n}: {result.get(n, 'missing')}" + (f" (listed {names.count(n)} times)" if names.count(n) > 1 else ""))
if bad:
    sys.exit(f"::error::Required checks not green exactly once on the {branch} run: {', '.join(bad)}")
print(f"Run {run['id']} (push on {branch}, {sha[:7]}) passed every required check.")
