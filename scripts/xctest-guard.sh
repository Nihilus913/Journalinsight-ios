#!/usr/bin/env bash
# RG-74 (B-109 class): xcodebuild exits 0 with "TEST SUCCEEDED" when an -only-testing filter
# selects nothing (wrong suite name, free @Test func without "()", several filters glued into one
# quoted arg). This wrapper runs xcodebuild and FAILS when the run executed 0 tests.
# Usage: scripts/xctest-guard.sh <xcodebuild args...>      (runs ${XCODEBUILD:-xcodebuild}, tees the log)
#        scripts/xctest-guard.sh --check-log <xcodebuild.log>   (check an existing log)
# Exit: xcodebuild's own non-zero code, else 3 when 0 tests ran, 4 on a glued filter arg, else 0.
set -uo pipefail

count_tests() { # prints the total tests executed (XCTest + swift-testing) in log $1
  local xc st
  xc=$(grep -aoE 'Executed [0-9]+ tests?' "$1" | awk '{ if ($2 > m) m = $2 } END { print m + 0 }')
  st=$(grep -aoE 'Test run with [0-9]+ tests?' "$1" | awk '{ if ($4 > m) m = $4 } END { print m + 0 }')
  echo $((xc + st))
}

verdict() { # log
  local n; n=$(count_tests "$1")
  if [ "$n" -eq 0 ]; then
    echo "xctest-guard: FAIL — 0 tests executed (filter selected nothing?). See B-109 / RG-74." >&2
    return 3
  fi
  echo "xctest-guard: OK — $n tests executed" >&2
}

if [ "${1:-}" = "--check-log" ]; then
  [ -f "${2:-}" ] || { echo "usage: $0 --check-log <log>" >&2; exit 2; }
  verdict "$2"; exit $?
fi

for a in "$@"; do
  case "$a" in
    *-only-testing:*" -only-testing:"*|*" -only-testing:"*)
      echo "xctest-guard: FAIL — several filters glued into one argument: '$a' (pass each -only-testing separately)" >&2
      exit 4 ;;
  esac
done

LOG=$(mktemp -t xctest-guard); trap 'rm -f "$LOG"' EXIT
"${XCODEBUILD:-xcodebuild}" "$@" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
[ "$rc" -ne 0 ] && exit "$rc"
verdict "$LOG"
