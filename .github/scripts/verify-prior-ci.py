#!/usr/bin/env python3
"""Release shortcut: checks that the head commit already passed the full iOS CI as a push on develop.

Usage: GH_TOKEN=... GITHUB_REPOSITORY=o/r verify-prior-ci.py <head sha>
Reads (GitHub API, read-only): the latest `iOS CI` push run on `develop` for exactly that commit and
its jobs. Fails unless that run completed successfully and each required job concluded success.
"""
import json
import re
import subprocess
import sys

REQUIRED = [
    "CI script tests",
    "Core logic (tests, coverage ≥90%)",
    "App (SwiftLint, build, UI + accessibility tests)",
]
sha = sys.argv[1]
repo = __import__("os").environ["GITHUB_REPOSITORY"]
if not re.fullmatch(r"[0-9a-f]{40}", sha) or not re.fullmatch(r"[\w.-]+/[\w.-]+", repo):
    sys.exit("::error::Unexpected commit or repository name")


def api(path):
    done = subprocess.run(["gh", "api", path], capture_output=True, text=True, check=False)
    if done.returncode != 0:
        sys.exit(f"::error::GitHub API call failed: {done.stderr.strip()[:200]}")
    return json.loads(done.stdout)


runs = api(f"repos/{repo}/actions/workflows/ios.yml/runs?head_sha={sha}&event=push&per_page=50")["workflow_runs"]
runs = [r for r in runs if r["head_sha"] == sha and r["head_branch"] == "develop" and r["event"] == "push"]
if not runs:
    sys.exit(f"::error::No push run of iOS CI on develop for {sha[:7]}. Merge to develop first and wait for its CI.")
run = max(runs, key=lambda r: (r["run_number"], r.get("run_attempt", 1)))
if run["status"] != "completed":
    sys.exit(f"::error::iOS CI on develop for {sha[:7]} is still {run['status']}. Re-run this check when it ends.")
if run["conclusion"] != "success":
    sys.exit(f"::error::iOS CI on develop for {sha[:7]} concluded {run['conclusion']}.")
jobs = api(f"repos/{repo}/actions/runs/{run['id']}/jobs?filter=latest&per_page=100")["jobs"]
result = {j["name"]: j["conclusion"] for j in jobs}
bad = [n for n in REQUIRED if result.get(n) != "success"]
for n in REQUIRED:
    print(f"{n}: {result.get(n, 'missing')}")
if bad:
    sys.exit(f"::error::Required checks not green on the develop run: {', '.join(bad)}")
print(f"Run {run['id']} (push on develop, {sha[:7]}) passed every required check.")
