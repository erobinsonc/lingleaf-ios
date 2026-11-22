#!/usr/bin/env bash
# The UI tests trust the frame an element reports when they decide what a finding is about (GlassContrast).
# App code that overrides it could move a finding onto a harmless place, so the app may not set it.
# Usage: check-accessibility-frames.sh <repo root>
set -euo pipefail
root="${1:?repo root}"
hits="$(grep -rnE 'accessibilityFrame|accessibilityPath|accessibilityActivationPoint' --include='*.swift' "$root/Lingleaf" "$root/LingleafCore/Sources" 2>/dev/null || true)"
if [ -n "$hits" ]; then
  printf '%s\n' "$hits" | head -5
  echo "::error::App code sets an accessibility frame or path: the audit tests trust element frames"
  exit 1
fi
echo "No accessibility frame overrides"
