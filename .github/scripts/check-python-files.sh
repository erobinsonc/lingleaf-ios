#!/usr/bin/env bash
# The CI runs Python (-I -B) from this repository. Any other Python file, extension module or .pth in the tree could
# be picked up by an interpreter started without -I, so only the scripts in .github/scripts may exist.
# Usage: check-python-files.sh <repo root>
set -euo pipefail
root="${1:?repo root}"
found="$(find "$root" -path "$root/.git" -prune -o \( -name '*.py' -o -name '*.pyw' -o -name '*.so' -o -name '*.pyd' -o -name '*.pth' \
  -o -name '*.pyc' -o -name '*.pyo' -o -name '__pycache__' \) -print 2>/dev/null \
  | grep -vE "^$root/\.github/scripts/[A-Za-z0-9_-]+\.py$" || true)"
if [ -n "$found" ]; then
  printf '%s\n' "$found" | head -5
  echo "::error::Python files outside .github/scripts (or bytecode) in the repository"
  exit 1
fi
echo "Python files only in .github/scripts"
