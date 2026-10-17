"""Fails when a String(localized:) literal in the app has no Spanish translation.

The key Xcode looks up is the literal with each interpolation replaced by its format
(%@ for text, %lld for numbers), so "“\\(base) not”" looks up "“%@ not”", not "“%@”":
a near miss silently shows English. Run: python3 .github/scripts/check-localized-keys.py
"""
import itertools
import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[2]
strings = json.loads((root / "Lingleaf/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))["strings"]
translated = {
    key for key, entry in strings.items()
    if entry.get("localizations", {}).get("es", {}).get("stringUnit", {}).get("state") == "translated"
    or "variations" in entry.get("localizations", {}).get("es", {})
}
literal = re.compile(r'String\(localized: "((?:[^"\\]|\\.)*)"')
interpolation = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")

missing = []
for path in sorted((root / "Lingleaf").rglob("*.swift")):
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        for text in literal.findall(line):
            parts = interpolation.split(text)
            # Each interpolation is text (%@) or a number (%lld); one combination must be a translated key.
            keys = (
                "".join(part + fmt for part, fmt in zip(parts, formats + ("",)))
                for formats in itertools.product(("%@", "%lld"), repeat=len(parts) - 1)
            )
            if not any(key.replace('\\"', '"') in translated for key in keys):
                missing.append(f"{path.relative_to(root)}:{number}: no Spanish translation for “{text}”")

print("\n".join(missing) or "Every String(localized:) key has a Spanish translation.")
sys.exit(1 if missing else 0)
