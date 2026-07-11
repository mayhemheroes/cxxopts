#!/usr/bin/env bash
#
# cxxopts/mayhem/build.sh — build jarro2783/cxxopts' OSS-Fuzz harness as a sanitized libFuzzer
# target (+ a standalone reproducer), AND cxxopts' own Catch unit-test suite for mayhem/test.sh.
#
# cxxopts is a HEADER-ONLY command-line option parser (single header include/cxxopts.hpp).
# The fuzzed surface is the parser itself, driven by the upstream harness test/fuzz.cpp:
#   cxxopts_fuzz — wraps the input bytes in a FuzzedDataProvider and uses them to (1) build a random
#                  cxxopts::Options spec (a random program/usage string + 0..1024 options of random
#                  int/string/vector<string>/float/double types with random short/long names),
#                  (2) optionally toggle allow_unrecognised_options() and a trailing positional, then
#                  (3) synthesize a random argv (1..1024 tokens of random bytes) and call
#                  options.parse(argc, argv). It is the cxxopts PARSE path that is fuzzed — the input
#                  is NOT a literal argv string but raw bytes the FDP slices into the spec + argv.
#                  The harness swallows exceptions (catch(...)), so only memory-safety / UB bugs in
#                  the header-only parser (caught by ASan/UBSan) are reported.
#
# Build contract comes from the org base ENV (CC/CXX/SANITIZER_FLAGS/LIB_FUZZING_ENGINE/SRC/
# STANDALONE_FUZZ_MAIN/OUT). Because cxxopts is header-only, the whole parser lives in cxxopts.hpp
# and is compiled (and thus sanitizer-instrumented) directly into the harness — there is no separate
# library object to instrument.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) for SANITIZER_FLAGS so an explicit empty --build-arg builds with NO sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${OUT:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE STANDALONE_FUZZ_MAIN MAYHEM_JOBS OUT

cd "$SRC"

HARNESS="$SRC/test/fuzz.cpp"   # the upstream OSS-Fuzz harness (BUILD.bazel: cxxopts_fuzz_test)
INC="-Iinclude"
CXXSTD="-std=c++17"

BUILD="$SRC/mayhem-build"
mkdir -p "$BUILD"

# ── 1) libFuzzer target -> $OUT/cxxopts_fuzz ───────────────────────────────────────────────────
#    Header-only: the parser is compiled (+ instrumented) straight into the harness TU.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $CXXSTD $INC \
    "$HARNESS" $LIB_FUZZING_ENGINE \
    -o "$OUT/cxxopts_fuzz"

# ── 2) standalone reproducer (no libFuzzer runtime) -> $OUT/cxxopts_fuzz-standalone ─────────────
#    $STANDALONE_FUZZ_MAIN is the base-provided run-once driver (C). Compile it with $CC, then link
#    it with the C++ harness via $CXX so libc++/libstdc++ is pulled in.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$BUILD/standalone_main.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $CXXSTD $INC \
    "$HARNESS" "$BUILD/standalone_main.o" \
    -o "$OUT/cxxopts_fuzz-standalone"

echo "built cxxopts_fuzz (+ standalone)"

# ── 3) Build cxxopts' OWN Catch unit-test suite with NORMAL flags (clean, separate tree) so
#       test.sh only RUNS it. This mirrors the OSS-Fuzz run_tests.sh:
#         $CXX -std=c++17 -o unittest -Iinclude -Itest test/main.cpp test/options.cpp
#       test/main.cpp pulls in Catch's main (CATCH_CONFIG_MAIN); test/options.cpp is the suite. ──
env -u CFLAGS -u CXXFLAGS -u SANITIZER_FLAGS \
  $CXX $CXXSTD -Iinclude -Itest \
    "$SRC/test/main.cpp" "$SRC/test/options.cpp" \
    -o "$BUILD/unittest"
echo "built cxxopts Catch unit-test suite -> mayhem-build/unittest"

echo "build.sh complete:"
ls -la "$OUT/cxxopts_fuzz" "$OUT/cxxopts_fuzz-standalone" "$BUILD/unittest" 2>&1 || true
