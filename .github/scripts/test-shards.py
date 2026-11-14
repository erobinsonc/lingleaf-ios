#!/usr/bin/env python3
"""The UI test shards of the App job: one source of truth for the workflow and for its check.

  test-shards.py --matrix   prints the GitHub matrix JSON ({"include":[{name, args}]})
  test-shards.py --check    checks the shards against LingleafUITests/*.swift: every name exists,
                            no test is listed twice and every test runs in exactly one shard.

A shard runs `xcodebuild test-without-building` with its -only-testing/-skip-testing arguments.
The shard marked `rest` runs the whole UI test target minus everything the other shards name, so a
test added later is never left out: it lands there until someone rebalances.
"""
import json
import re
import sys
from pathlib import Path

T = "LingleafUITests"  # the UI test target
# Balanced from measured times (seconds, macos-15): tours EnglishLight 403, EnglishDark 465,
# SpanishLight 396, EnglishLargestText 251, SpanishLargestText 243; accessibility audit 198,
# listen 92; the other UI tests 20-55 each. Each shard targets ~11 minutes of tests.
SHARDS = [
    {"name": "tours-1", "only": ["ScreenTour/testTourEnglishDark", "ScreenTour/testTourSpanishLargestText"]},
    {"name": "tours-2", "only": ["ScreenTour/testTourEnglishLight", "ScreenTour/testTourEnglishLargestText"]},
    {"name": "tour-3-audit", "only": [
        "ScreenTour/testTourSpanishLight",
        # The audit has failed on a cold simulator when it ran first or second in a fresh shard
        # (contrast of the Library row next to the tab bar) and passed after these four tests, which is
        # the order the unsharded run had. Keep them together until the audit itself is made robust.
        "LingleafUITests/testAContractionSaysWhatItStandsFor",
        "LingleafUITests/testAModalVerbShowsItsVerbGroupAndWhatItDoes",
        "LingleafUITests/testAPerfectSaysWhatItDoes",
        "LingleafUITests/testAboutSaysTheRecommendedBooksArePublicDomainWorldwide",
        "LingleafUITests/testAccessibilityAudit",
    ]},
    {"name": "ui-rest", "rest": True},
]


def explicit():
    return [f"{T}/{n}" for s in SHARDS for n in s.get("only", [])]


def selectors(shard):
    if shard.get("rest"):
        return [T], explicit()
    return [f"{T}/{n}" for n in shard["only"]], []


def matrix():
    include = []
    for s in SHARDS:
        only, skip = selectors(s)
        args = [f"-only-testing:{x}" for x in only] + [f"-skip-testing:{x}" for x in skip]
        include.append({"name": s["name"], "args": " ".join(args)})
    return {"include": include}


def tests_in_sources(root):
    found = []
    for path in sorted(Path(root, T).glob("*.swift")):
        current = None
        for line in path.read_text().splitlines():
            m = re.match(r"\s*(?:final\s+)?(?:class|extension)\s+(\w+)", line)
            if m:
                current = m.group(1)
            m = re.match(r"\s*func\s+(test\w*)\s*\(", line)
            if m and current:
                found.append(f"{T}/{current}/{m.group(1)}")
    return found


def selected(shard, test):
    only, skip = selectors(shard)
    hit = lambda ids: any(test == i or test.startswith(i + "/") for i in ids)  # noqa: E731
    return hit(only) and not hit(skip)


def check(root):
    tests = tests_in_sources(root)
    problems = []
    if not tests:
        problems.append("no tests found in the sources")
    names = explicit()
    for dup in {n for n in names if names.count(n) > 1}:
        problems.append(f"listed in more than one shard: {dup}")
    for n in names:
        if n not in tests:
            problems.append(f"does not exist in the sources: {n}")
    if sum(1 for s in SHARDS if s.get("rest")) != 1:
        problems.append("exactly one shard must be the `rest` shard")
    for t in tests:
        where = [s["name"] for s in SHARDS if selected(s, t)]
        if len(where) != 1:
            problems.append(f"{t} runs in {len(where)} shards: {where}")
    for p in problems:
        print(f"::error::{p}")
    print(f"{len(tests)} tests in {len(SHARDS)} shards" + (": problems found" if problems else ": OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    if "--matrix" in sys.argv:
        print(json.dumps(matrix(), separators=(",", ":")))
    elif "--check" in sys.argv:
        sys.exit(check(root))
    else:
        sys.exit(__doc__)
