#!/usr/bin/env bash
#
# butter/mayhem/build.sh — build neverRare/butter's parser cargo-fuzz targets for Mayhem.
#
# Butter is a WIP programming language (Rust workspace: parser, type-system, hir, cli).
# The natural fuzz surface is the PARSER: feed an arbitrary source string to the public
# combine parsers `parser::ast()` (whole program) and `parser::expr_parser()` (expression).
# We add an ADDITIVE cargo-fuzz crate under mayhem/fuzz/ and leave upstream untouched.
#
# Rust instrumentation uses RUSTFLAGS (-Zsanitizer=address), NOT clang $SANITIZER_FLAGS.
# We still honour $SANITIZER_FLAGS as the sanitizer on/off switch: an explicit empty
# --build-arg SANITIZER_FLAGS= builds with no sanitizer (natural crashes / repro).
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE. This first
# (online) build populates the cargo registry under $CARGO_HOME; the re-run resolves crates
# from that cache. Do NOT hard-code `--offline` here (it would break this first build); the
# rlenv runtime exports CARGO_NET_OFFLINE=true for the re-run.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

# DWARF < 4 contract (§6.2 item 10): Mayhem's triage can't read DWARF >= 4, and rustc/clang
# default to DWARF 5. Force DWARF 2 in rustc via llvm-args, and gdwarf-3 for any C in deps.
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=--dwarf-version=2}"

cd "$SRC"

# Sanitizer on/off switch, driven by $SANITIZER_FLAGS (base ENV default = ASan+UBSan).
# Rust has no clang-style UBSan; ASan is the OSS-Fuzz Rust path. If SANITIZER_FLAGS is
# cleared (--build-arg SANITIZER_FLAGS=), build with no sanitizer.
: "${SANITIZER_FLAGS:=}"
RUST_SAN=""
SAN_ARG="none"
if printf '%s' "$SANITIZER_FLAGS" | grep -q address; then
  RUST_SAN="-Zsanitizer=address"
  SAN_ARG="address"
fi

# When sanitizing, the Rust ASan runtime archive can carry DWARF 5 debug info; strip it so
# every linked target honours the DWARF < 4 contract.
if [ "$SAN_ARG" = address ]; then
  ASAN_RT="$(find "$RUSTUP_HOME/toolchains" -name 'librustc-nightly_rt.asan.a' 2>/dev/null | head -1)"
  if [ -n "$ASAN_RT" ] && [ -f "$ASAN_RT" ]; then
    echo "Stripping debug info from Rust ASan runtime to enforce DWARF < 4: $ASAN_RT"
    objcopy --strip-debug "$ASAN_RT" || true
  fi
fi
export CFLAGS="${CFLAGS:+$CFLAGS }-gdwarf-3"
export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }-gdwarf-3"

FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

# OSS-Fuzz Rust libFuzzer flags. --cfg fuzzing matches libfuzzer-sys.
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing ${RUST_SAN} ${RUST_DEBUG_FLAGS}"

# Discover every target from the crate's fuzz_targets/ dir (one binary per target).
FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (image nightly, sanitizer=$SAN_ARG) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" --sanitizer "$SAN_ARG" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

echo "build.sh complete:"
ls -la /mayhem/parse_program /mayhem/parse_expr
