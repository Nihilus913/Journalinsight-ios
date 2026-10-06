#!/usr/bin/env bash
# RG-74 (B-109 class): scripts/xctest-guard.sh must exit non-zero when an -only-testing filter
# selects 0 tests, even though xcodebuild itself says TEST SUCCEEDED and exits 0.
set -uo pipefail
cd "$(dirname "$0")/../.."
G=scripts/xctest-guard.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
check() { # name expected-exit actual-exit
  local bad=0
  if [ "$2" = "0" ]; then [ "$3" -eq 0 ] || bad=1; else { [ "$3" -ne 0 ] && [ "$3" -ne 127 ]; } || bad=1; fi
  if [ "$bad" = 1 ]; then echo "FAIL $1 (exit $3)"; fail=1; else echo "ok   $1"; fi
}
fake() { printf '#!/usr/bin/env bash\ncat <<"OUT"\n%s\nOUT\nexit 0\n' "$1" > "$T/xcodebuild"; chmod +x "$T/xcodebuild"; }

fake $'Test Suite \'Selected tests\' passed.\n\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 seconds\n** TEST SUCCEEDED **'
XCODEBUILD="$T/xcodebuild" $G test -scheme X "-only-testing:JIHealthKitTests/NoSuchSuite" >/dev/null 2>&1; check "bogus suite, Executed 0 tests -> non-zero" nz $?

fake $'** TEST EXECUTE SUCCEEDED **'
XCODEBUILD="$T/xcodebuild" $G test -scheme X "-only-testing:JIHealthKitTests/NoSuchSuite" >/dev/null 2>&1; check "no test count at all -> non-zero" nz $?

fake $'\t Executed 12 tests, with 0 failures (0 unexpected) in 0.4 seconds\n** TEST SUCCEEDED **'
XCODEBUILD="$T/xcodebuild" $G test -scheme X "-only-testing:JIHealthKitTests/Real" >/dev/null 2>&1; check "12 XCTest tests -> 0" 0 $?

fake $'\xe2\x9c\x94 Test run with 7 tests in 2 suites passed after 0.1 seconds.\n\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 seconds\n** TEST SUCCEEDED **'
XCODEBUILD="$T/xcodebuild" $G test -scheme X "-only-testing:JournalInsightTests/freeFunc()" >/dev/null 2>&1; check "7 swift-testing tests -> 0" 0 $?

XCODEBUILD="$T/xcodebuild" $G test -scheme X "-only-testing:A/B -only-testing:A/C" >/dev/null 2>&1; check "two filters glued in one arg -> non-zero" nz $?

# The real regression-run log (2026-10-05, 0 tests, TEST EXECUTE SUCCEEDED) fails the log check.
printf '** TEST EXECUTE SUCCEEDED **\n' > "$T/real.log"
$G --check-log "$T/real.log" >/dev/null 2>&1; check "--check-log on a 0-test log -> non-zero" nz $?

exit $fail
