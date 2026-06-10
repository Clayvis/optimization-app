#!/bin/sh
#
# Local CI test gate (audit Theme 3: make the green bar real). Runs the unit
# suite + schema-parity + asset guard before a push is allowed to proceed. The
# only CI that existed was an Xcode Cloud archive workflow that never ran the
# tests, so a red suite could reach main and a TestFlight build undetected.
#
# Install once:  scripts/install_git_hooks.sh
# Bypass once:   git push --no-verify   (use sparingly)
# Skip the slow xcodebuild step:  SKIP_TESTS=1 git push   (parity guards still run)

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "[pre-push] schema parity guard"
if [ -x scripts/check_schema_parity.sh ]; then
    sh scripts/check_schema_parity.sh
fi

echo "[pre-push] asset guard"
if [ -x scripts/check_assets.sh ]; then
    sh scripts/check_assets.sh
fi

if [ "${SKIP_TESTS:-0}" = "1" ]; then
    echo "[pre-push] SKIP_TESTS=1 set; skipping unit suite. Parity guards passed."
    exit 0
fi

SIM="${TEST_SIM:-platform=iOS Simulator,name=iPhone 17 Pro}"
echo "[pre-push] running unit suite on: $SIM"

set +e
xcodebuild \
    -project PersonalOptimization.xcodeproj \
    -scheme PersonalOptimization \
    -destination "$SIM" \
    -derivedDataPath .build/dd \
    CODE_SIGNING_ALLOWED=NO \
    test 2>&1 | tee /tmp/pre_push_test.log | grep -E "Executed|TEST (EXECUTE )?(SUCCEEDED|FAILED)|error:|warning:" | tail -12
RESULT=${PIPESTATUS:-$?}
set -e

if grep -q "TEST EXECUTE SUCCEEDED\|TEST SUCCEEDED" /tmp/pre_push_test.log; then
    if grep -q "warning:" /tmp/pre_push_test.log; then
        echo "[pre-push] FAILED: build produced warnings (zero-warning gate). See /tmp/pre_push_test.log"
        exit 1
    fi
    echo "[pre-push] suite green. Push allowed."
    exit 0
fi

echo "[pre-push] FAILED: unit suite did not pass. Push blocked. See /tmp/pre_push_test.log"
echo "[pre-push] (bypass with: git push --no-verify)"
exit 1
