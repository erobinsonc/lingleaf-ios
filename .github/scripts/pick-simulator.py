#!/usr/bin/env python3
"""Picks the simulator the CI uses from `xcrun simctl list devices available -j` (stdin):
the first iPhone of the newest iOS runtime. Prints "<udid> <runtime id>".
Usage: xcrun simctl list devices available -j | pick-simulator.py"""
import json
import re
import sys


def version(runtime):
    """(26, 0) for com.apple.CoreSimulator.SimRuntime.iOS-26-0: numeric, so iOS-100-0 sorts after iOS-26-0."""
    return tuple(int(part) for part in re.findall(r"\d+", runtime.rsplit(".", 1)[-1]))


devices = json.load(sys.stdin)["devices"]
for runtime, found in sorted(devices.items(), key=lambda item: version(item[0]), reverse=True):
    if "iOS" not in runtime:
        continue
    for device in found:
        if device["name"].startswith("iPhone"):
            print(device["udid"], runtime)
            sys.exit(0)
sys.exit("::error::No iPhone simulator on this runner")
