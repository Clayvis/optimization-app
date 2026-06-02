#!/usr/bin/env bash
# Asset gate. App icons must be fully opaque (no alpha channel).
#
# Why this exists: Xcode Archive runs App Store asset validation that Debug
# simulator builds skip. An AppIcon PNG with an alpha channel fails Archive
# with "Invalid App Store Icon. The App Store Icon in the asset catalog ...
# can't be transparent nor contain an alpha channel." This passed every local
# Quality Gate (Debug build + Debug test) and only broke on Xcode Cloud Archive
# (see .work/decisions on the 2026-06 archive failure). This script makes that
# drift a pre-push failure.
#
# Run locally before pushing (triggers Xcode Cloud):
#   ./scripts/check_assets.sh
#
# Exit 0 = all icons opaque. Exit 1 = at least one icon carries alpha.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL=0

# Returns 0 (true) if the file has an alpha channel.
has_alpha() {
    local f="$1"
    if command -v sips >/dev/null 2>&1; then
        # macOS native, no dependencies.
        sips -g hasAlpha "$f" 2>/dev/null | grep -q "hasAlpha: yes"
    elif command -v python3 >/dev/null 2>&1; then
        python3 - "$f" <<'PY'
import sys
from PIL import Image
sys.exit(0 if ("A" in Image.open(sys.argv[1]).getbands()) else 1)
PY
    else
        file "$f" | grep -q "RGBA"
    fi
}

echo "== App icon opacity (no alpha channel) =="
COUNT=0
while IFS= read -r -d '' f; do
    COUNT=$((COUNT + 1))
    if has_alpha "$f"; then
        echo "FAIL: alpha channel present -> $f"
        FAIL=1
    fi
done < <(find PersonalOptimization PersonalOptimizationWatch \
    -path '*AppIcon.appiconset/*.png' -print0 2>/dev/null)

if [ "$COUNT" -eq 0 ]; then
    echo "WARN: no AppIcon PNGs found (check paths)"
elif [ "$FAIL" -eq 0 ]; then
    echo "OK: $COUNT app icons opaque, no alpha channel"
fi

exit $FAIL
