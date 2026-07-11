#!/usr/bin/env bash
#
# cxxopts/mayhem/test.sh — RUN cxxopts' own Catch unit-test suite (built by mayhem/build.sh with
# normal flags) and emit a CTRF summary. exit 0 iff no test failed.
#
# PATCH-grade oracle: test/options.cpp is cxxopts' real Catch2 behavioural suite — it constructs
# Options specs, parses synthetic argv vectors, and asserts on the parsed values, counts, types,
# error/throw behaviour, help text, positional handling, etc. (REQUIRE/CHECK assertions). A no-op /
# "return early" patch to the parser cannot pass these — they assert concrete parse RESULTS. This
# script only RUNS the pre-built binary; it never compiles.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

UNITTEST="$SRC/mayhem-build/unittest"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if [ ! -x "$UNITTEST" ]; then
  echo "missing $UNITTEST — run mayhem/build.sh first" >&2
  emit_ctrf "catch2" 0 1 0; exit 2
fi

echo "=== running cxxopts Catch unit-test suite ==="
# Catch2 reports a per-test-case summary line on the last line, e.g.
#   "test cases: 42 | 41 passed | 1 failed"   (or "All tests passed (N assertions in M test cases)")
out="$("$UNITTEST" 2>&1)"; rc=$?
echo "$out"

# Parse Catch2's "test cases:" summary line for passed/failed counts.
summary_line="$(printf '%s\n' "$out" | grep -E 'test cases:' | tail -1)"
PASSED="$(printf '%s' "$summary_line" | sed -n 's/.*[|[:space:]]\([0-9][0-9]*\)[[:space:]]*passed.*/\1/p')"
FAILED="$(printf '%s' "$summary_line" | sed -n 's/.*[|[:space:]]\([0-9][0-9]*\)[[:space:]]*failed.*/\1/p')"

if [ -z "$summary_line" ]; then
  # "All tests passed (N assertions in M test cases)" — no "test cases:" line.
  M="$(printf '%s\n' "$out" | sed -n 's/.*assertions in \([0-9][0-9]*\) test case.*/\1/p' | tail -1)"
  if printf '%s\n' "$out" | grep -q 'All tests passed' && [ -n "$M" ]; then
    PASSED="$M"; FAILED=0
  fi
fi

: "${PASSED:=0}" "${FAILED:=0}"

# If we could not parse any counts, fall back to the binary's exit code.
if [ "$(( PASSED + FAILED ))" -eq 0 ]; then
  echo "could not parse Catch2 summary; using unittest exit code $rc" >&2
  [ "$rc" -eq 0 ] && { emit_ctrf "catch2" 1 0 0; exit 0; }
  emit_ctrf "catch2" 0 1 0; exit 1
fi

emit_ctrf "catch2" "$PASSED" "$FAILED" 0
