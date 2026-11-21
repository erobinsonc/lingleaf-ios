#!/usr/bin/env python3
"""Final verdict of a required check that is only a gate (the heavy work runs in other jobs).

Usage: MODE=<plan mode> NEEDS='<toJSON(needs)>' ci-gate.py --heavy a,b --verify c
  heavy jobs : must succeed in `full`, must be skipped in `same-tree` and `release`
  verify jobs: must succeed in `release`, must be skipped otherwise
  plan       : must have succeeded, so a missing or failed plan can never pass
A failed, cancelled, or unexpectedly skipped job never passes: only the exact expected result does.
"""
import argparse
import json
import os
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--heavy", default="")
parser.add_argument("--verify", default="")
args = parser.parse_args()
needs = json.loads(os.environ["NEEDS"])
mode = os.environ.get("MODE", "")
heavy = [j for j in args.heavy.split(",") if j]
verify = [j for j in args.verify.split(",") if j]

expect = {}
if mode == "full":
    expect.update({j: "success" for j in heavy}); expect.update({j: "skipped" for j in verify})
elif mode == "same-tree":
    expect.update({j: "skipped" for j in heavy + verify})
elif mode == "release":
    expect.update({j: "skipped" for j in heavy}); expect.update({j: "success" for j in verify})
else:
    sys.exit(f"::error::Unknown CI mode '{mode[:20]}': the plan job did not succeed.")

bad = []
if needs.get("plan", {}).get("result") != "success":
    bad.append("plan")
for job, want in expect.items():
    got = needs.get(job, {}).get("result", "missing")
    print(f"{job}: {got} (expected {want})")
    if got != want:
        bad.append(job)
if bad:
    sys.exit(f"::error::CI gate failed in mode '{mode}': {', '.join(bad)}")
print(f"CI gate passed in mode '{mode}'")
