#!/usr/bin/env python3
"""Picks the simulator the CI uses from `xcrun simctl list devices available -j` (stdin):
the first iPhone of the newest iOS runtime. Prints "<udid> <runtime id>".
Usage: xcrun simctl list devices available -j | pick-simulator.py"""
import json
import sys

devices = json.load(sys.stdin)["devices"]
for runtime, found in sorted(devices.items(), reverse=True):
    if "iOS" not in runtime:
        continue
    for device in found:
        if device["name"].startswith("iPhone"):
            print(device["udid"], runtime)
            sys.exit(0)
sys.exit("::error::No iPhone simulator on this runner")
