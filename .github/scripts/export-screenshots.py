"""Copies the screenshots attached by ScreenTour out of an .xcresult bundle
into ./screenshots, named <language>-<appearance>-<NN>-<screen>.png."""

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

result = sys.argv[1]
out = Path("screenshots")
out.mkdir(exist_ok=True)
raw = Path(tempfile.mkdtemp())
subprocess.run(
    ["xcrun", "xcresulttool", "export", "attachments", "--path", result, "--output-path", str(raw)],
    check=True,
)
manifest = json.loads((raw / "manifest.json").read_text())
count = 0
for test in manifest:
    for attachment in test.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName", "")
        match = re.match(r"([a-z]{2}-(?:light|dark)-\d\d[a-z]?-[a-z-]+?)(?:_\d+)?(?:_[0-9A-F-]{36})?\.png$", name)
        if match:
            shutil.copy(raw / attachment["exportedFileName"], out / f"{match.group(1)}.png")
            count += 1
print(f"Exported {count} screenshots")
if count == 0:
    # Naming changed in this Xcode version: keep every image so nothing is lost.
    for test in manifest:
        for attachment in test.get("attachments", []):
            if attachment["exportedFileName"].endswith(".png"):
                shutil.copy(raw / attachment["exportedFileName"], out / attachment["exportedFileName"])
                count += 1
    print(f"Exported {count} screenshots with their raw names")
