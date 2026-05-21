#!/usr/bin/env bash
# Schema-parity guard. Fails if any production target file references a
# SchemaVN.self outside the allowed file set, or if DailyLog is constructed
# outside the sanctioned writer paths, or if `Asia/Tokyo` appears in
# production code beyond the UserProfile seed default.
#
# Run locally before a commit:
#   ./scripts/check_schema_parity.sh
# Run from CI (when one exists):
#   - script step: ./scripts/check_schema_parity.sh
#
# Why this exists: the M-x milestones repeatedly drift to per-target SchemaVN
# references and ad-hoc DailyLog inserts. The same bug almost shipped to
# TestFlight (see .work/decisions/005-pre-testflight-hardening.md). This
# script makes that drift a build failure.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL=0

echo "== CT-1 :: SchemaVN references outside allowed files =="
OFFENDERS=$(grep -rEn 'Schema\(versionedSchema: *SchemaV[0-9]+\.self\)' \
  --include='*.swift' \
  PersonalOptimization PersonalOptimizationWatch \
  PersonalOptimizationWatchComplications PersonalOptimizationLiveActivity 2>/dev/null \
  | grep -vE 'Models/Schema|Models/AppSchema|#Preview|previewContainer' \
  | grep -v Tests || true)
if [ -n "$OFFENDERS" ]; then
  echo "FAIL: SchemaVN.self references outside allowed files:"
  echo "$OFFENDERS"
  FAIL=1
else
  echo "OK"
fi

echo "== Direct DailyLog construction outside sanctioned writers =="
DLOFFENDERS=$(grep -rn 'DailyLog(date:' \
  --include='*.swift' \
  PersonalOptimization PersonalOptimizationWatch 2>/dev/null \
  | grep -v 'DailyLog.swift' \
  | grep -v 'DailyLogStore.swift' \
  | grep -v 'JSONImportService.swift' \
  | grep -v Tests || true)
if [ -n "$DLOFFENDERS" ]; then
  echo "FAIL: DailyLog(date:) outside sanctioned writers:"
  echo "$DLOFFENDERS"
  FAIL=1
else
  echo "OK"
fi

echo "== Asia/Tokyo references in production code =="
TZCOUNT=$(grep -rn 'Asia/Tokyo' --include='*.swift' \
  PersonalOptimization PersonalOptimizationWatch 2>/dev/null \
  | grep -v Tests | wc -l | tr -d ' ')
# Allow 1 (the UserProfile.timezone = "Asia/Tokyo" seed default).
if [ "$TZCOUNT" -gt 1 ]; then
  echo "FAIL: Asia/Tokyo refs beyond the seed default ($TZCOUNT > 1):"
  grep -rn 'Asia/Tokyo' --include='*.swift' \
    PersonalOptimization PersonalOptimizationWatch 2>/dev/null | grep -v Tests
  FAIL=1
else
  echo "OK ($TZCOUNT)"
fi

echo "== Polling Timer.scheduledTimer in production code =="
# Drop the leading file:line: prefix before checking for a comment marker so
# documentation comments mentioning Timer.scheduledTimer don't trip the
# guard.
TIMEROFFENDERS=$(grep -rn 'Timer.scheduledTimer' --include='*.swift' \
  PersonalOptimization PersonalOptimizationWatch 2>/dev/null \
  | grep -v 'LiveWorkoutSessionService.swift' \
  | grep -v Tests \
  | awk -F: '{ rest = ""; for (i = 3; i <= NF; i++) rest = rest $i (i < NF ? ":" : ""); gsub(/^[ \t]+/, "", rest); if (rest !~ /^\/\//) print $0 }' || true)
if [ -n "$TIMEROFFENDERS" ]; then
  echo "FAIL: Timer.scheduledTimer outside the allow-list:"
  echo "$TIMEROFFENDERS"
  FAIL=1
else
  echo "OK"
fi

echo "== @Model count parity across shared sources =="
# Count distinct @Model class declarations under Models/ vs the schema
# manifest in SchemaV2.swift. The expected count is whatever the latest
# AppSchema.current pulls in (SchemaV1 + every additive layer). We just
# check there are no orphan @Model classes that haven't been added to any
# SchemaVN manifest.
MODELS=$(grep -lE '^@Model$' --include='*.swift' -r PersonalOptimization/Models 2>/dev/null \
  | xargs -I{} basename {} .swift | sort -u)
MANIFESTED=$(grep -hE '^\s+[A-Z][A-Za-z0-9]+\.self,?$' \
  PersonalOptimization/Models/SchemaV*.swift 2>/dev/null \
  | tr -d ' ,' | sed 's/\.self$//' | sort -u)
MISSING=$(comm -23 <(echo "$MODELS") <(echo "$MANIFESTED"))
if [ -n "$MISSING" ]; then
  echo "FAIL: @Model classes not listed in any SchemaVN.models manifest:"
  echo "$MISSING"
  FAIL=1
else
  echo "OK"
fi

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "schema-parity guard FAILED"
  exit 1
fi

echo ""
echo "schema-parity guard PASSED"
