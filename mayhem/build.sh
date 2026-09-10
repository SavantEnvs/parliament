#!/usr/bin/env bash
#
# parliament/mayhem/build.sh — build the ELF launcher shims for the Atheris fuzz harness, the test
# runner and the CLI known-answer probe. parliament (duo-labs/parliament) is a PURE-PYTHON package
# (an AWS IAM policy linter): there is no native code to compile or sanitize. The Atheris harness
# (mayhem/fuzz_policy.py) is a `.py`, but Mayhem requires the target `cmd:` to be an ELF, so we
# compile a tiny C shim per Python entry point that exec()s the pinned /opt/toolchains/python
# interpreter on that script (see mayhem/launcher.c).
#
# The Python toolchain (atheris, pytest, parliament's runtime deps) was baked into
# /opt/toolchains/python by the Dockerfile — that step needs the network and root, which this
# script (re-run OFFLINE as the non-root `mayhem` user at the PATCH tier) must NOT require.
# parliament itself is imported from the source tree (/mayhem/parliament) by every entry point, so
# nothing is pip-installed here either. This script only compiles the shims and sanity-checks the
# harness imports, so it is idempotent and air-gapped (clang + the baked venv, no network).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

SRC="${SRC:-/mayhem}"
cd "$SRC"

: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"

# $DEBUG_FLAGS threads DWARF < 4 debug info onto the shims (SPEC §6.2 item 10): clang-19's plain
# `-g` emits DWARF-5, which Mayhem's triage can't read, so force DWARF-3 explicitly.
: "${DEBUG_FLAGS:=-g -gdwarf-3}"

# The pinned interpreter (SPEC §6.2 item 8: fixed, $HOME-independent). Fail loudly if it is missing —
# a shim exec()ing a python3 without atheris would fail in a confusing way at fuzz time instead.
PY_INTERP="${VIRTUAL_ENV:-/opt/toolchains/python/venv}/bin/python3"
[ -x "$PY_INTERP" ] || { echo "FATAL: pinned Python interpreter $PY_INTERP missing (Dockerfile toolchain step)" >&2; exit 1; }

# The base exports $SANITIZER_FLAGS (ASan+UBSan, halting) for projects with compiled code; parliament
# has none, and the shims are pure exec() wrappers (instrumenting them would only add ASan noise on
# the wrapper itself, never on the fuzzed Python — the shim's process image is replaced by the
# interpreter before any fuzzing happens). The real fuzzed code runs under Atheris/libFuzzer at
# runtime. Referenced here for parity / so an override is visible.
echo "SANITIZER_FLAGS=${SANITIZER_FLAGS:-<unset>} (pure-Python project; not applied to the exec shims)"
echo "DEBUG_FLAGS=$DEBUG_FLAGS"
echo "PY_INTERP=$PY_INTERP ($("$PY_INTERP" --version))"

build_launcher() {
  local out="$1" script="$2"
  echo "--- compiling launcher /mayhem/$out -> $PY_INTERP $script ---"
  [ -x "$script" ] || { echo "FATAL: $script missing or not executable" >&2; exit 1; }
  # Dynamically linked (default) so the verify-repo sabotage oracle's LD_PRELOAD can reach it.
  "$CC" $DEBUG_FLAGS -O1 -DPY_INTERP="\"$PY_INTERP\"" -DPY_SCRIPT="\"$script\"" -o "/mayhem/$out" mayhem/launcher.c
  chmod +x "/mayhem/$out"
  # Regression guard: a statically linked shim would silently defeat the sabotage oracle.
  readelf -l "/mayhem/$out" | grep -q 'Requesting program interpreter' \
    || { echo "FATAL: /mayhem/$out is not dynamically linked" >&2; exit 1; }
}

# Fuzz target: the Atheris harness (analyze_policy_string over the fuzzer's bytes as policy text).
build_launcher fuzz-policy        /mayhem/mayhem/fuzz_policy.py
# Test oracle runner: runs the real pytest suite (driven by mayhem/test.sh through this ELF so the
# sabotage check can neuter it).
build_launcher parliament-tests   /mayhem/mayhem/run_tests.py
# CLI known-answer probe: upstream's `parliament` console_script, from the source tree.
build_launcher parliament-cli     /mayhem/mayhem/cli_entry.py

# Harness import check (the Python analogue of "does it compile"): the pinned interpreter must see
# atheris + parliament's runtime deps, and the SOURCE-TREE parliament must import (a PATCH that
# breaks the package fails here, like a compile error would). No network involved.
echo "--- import check ---"
"$PY_INTERP" - <<'PY'
import sys
sys.path.insert(0, "/mayhem")
import atheris, jsoncfg, yaml, pkg_resources  # noqa: F401  (toolchain)
import parliament                             # noqa: F401  (the fuzzed package, from the source tree)
from parliament import analyze_policy_string  # noqa: F401
assert parliament.__file__.startswith("/mayhem/parliament/"), parliament.__file__
print("import check ok:", parliament.__file__, "version", parliament.__version__)
PY

echo "build.sh complete:"
ls -la /mayhem/fuzz-policy /mayhem/parliament-tests /mayhem/parliament-cli
