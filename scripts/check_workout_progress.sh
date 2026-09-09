#!/usr/bin/env bash
# Runs the value-only workout/coach regressions on Macs with Swift but no
# Xcode/XCTest. The exact XCTest scenario bodies are reused with assertion
# shims; this does not replace the iOS SwiftData or UI suites.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR=$(mktemp -d /private/tmp/workout-progress.XXXXXX)
python3 - "$ROOT" "$CHECK_DIR" <<'PY'
from pathlib import Path
import re
import sys
root, output = map(Path, sys.argv[1:])
tests = (root / 'PersonalOptimizationTests/Modules/DailyWorkoutProgressTests.swift').read_text()
tests = tests.replace('import XCTest', 'import Foundation').replace('@testable import PersonalOptimization', '')
shims = '''
class XCTestCase {}
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T) {
    precondition(actual == expected, "Expected \\(expected), got \\(actual)")
}
func XCTAssertTrue(_ value: Bool) { precondition(value, "Expected true") }
func XCTAssertFalse(_ value: Bool) { precondition(!value, "Expected false") }
'''
names = re.findall(r'    func (test_\w+)\(\)', tests)
assert names, 'No regression scenarios discovered'
runner = '\nlet suite = DailyWorkoutProgressTests()\n'
for name in names:
    runner += f'suite.{name}()\nprint("PASS {name}")\n'
runner += f'print("{len(names)} portable workout progress checks passed")\n'
(output / 'main.swift').write_text(shims + tests + runner)
PY
swiftc -module-cache-path "$CHECK_DIR/module-cache" \
    "$ROOT/PersonalOptimization/Modules/Engagement/DailyWorkoutProgress.swift" \
    "$CHECK_DIR/main.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
