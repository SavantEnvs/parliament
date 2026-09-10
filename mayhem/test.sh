#!/usr/bin/env bash
#
# parliament/mayhem/test.sh — RUN parliament's behavioral oracle and emit a CTRF summary.
# exit 0 iff no test failed.
#
# Two layers, both driven through ELF launchers under /mayhem (built by mayhem/build.sh) so the
# verify-repo anti-reward-hack check — which LD_PRELOADs a constructor that _exit(0)s every
# NON-system executable (system python under /usr/bin is spared; /mayhem/* is not) — neuters them
# and this script then FAILS (no summary line / empty CLI output), proving the oracle is behavioral:
#
#  1. Upstream's own pytest suite via /mayhem/parliament-tests (exec()s mayhem/run_tests.py):
#     tests/unit/*.py + parliament/community_auditors/tests/*.py — known-answer cases asserting that
#     analyze_policy_string(<policy>).finding_ids / findings / expand_action() EXACTLY equal the
#     expected values. Parsed from its `RUNTESTS tests=N passed=P failed=F skipped=S` line.
#  2. CLI known-answer probes via /mayhem/parliament-cli (exec()s mayhem/cli_entry.py = upstream's
#     `parliament` console_script): fixed IAM policy documents under mayhem/kat/ -> the EXACT finding
#     id set (--minimal), the exact default-format finding line and the exact --json record, each
#     compared byte-for-byte against mayhem/kat/*.expected (finding ids/titles/severity/detail lifted
#     from upstream's unit-test assertions and README; line/column locations from the fixture) plus
#     the documented exit status (1 = findings, 0 = none).
#     Probes are unconditional: a missing launcher, fixture or expected file is a FAILURE.
#
# This script only RUNS things (build.sh compiled the launchers); it never compiles or installs.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

SRC="${SRC:-/mayhem}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
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

PASSED=0; FAILED=0; SKIPPED=0
ok()  { PASSED=$((PASSED + 1)); echo "PASS $1"; }
bad() { FAILED=$((FAILED + 1)); echo "FAIL $1" >&2; }

TESTS_BIN=/mayhem/parliament-tests
CLI_BIN=/mayhem/parliament-cli
KAT=mayhem/kat
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/parliament-test.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

# ---- 1. upstream pytest suite, through the neuterable launcher -------------------------------
echo "=== 1. pytest (parliament known-answer suite) via $TESTS_BIN ==="
if [ ! -x "$TESTS_BIN" ]; then
  bad "pytest: launcher $TESTS_BIN missing — run mayhem/build.sh first"
else
  out="$("$TESTS_BIN" 2>&1)"; rc=$?
  printf '%s\n' "$out" | tail -n 25
  line="$(printf '%s\n' "$out" | sed -n 's/^RUNTESTS //p' | head -1)"
  if [ -z "$line" ]; then
    # No summary line: the suite did not run (neutered launcher, import error, crash). Never pass vacuously.
    bad "pytest: no RUNTESTS summary line from $TESTS_BIN (rc=$rc) — the suite did not run"
  else
    # line looks like: tests=N passed=P failed=F skipped=S
    T=$(printf '%s' "$line" | sed -n 's/.*tests=\([0-9][0-9]*\).*/\1/p')
    P=$(printf '%s' "$line" | sed -n 's/.*passed=\([0-9][0-9]*\).*/\1/p')
    F=$(printf '%s' "$line" | sed -n 's/.*failed=\([0-9][0-9]*\).*/\1/p')
    S=$(printf '%s' "$line" | sed -n 's/.*skipped=\([0-9][0-9]*\).*/\1/p')
    : "${T:=0}" "${P:=0}" "${F:=0}" "${S:=0}"
    if [ "$T" -eq 0 ]; then
      bad "pytest: runner reported 0 tests collected"
    else
      PASSED=$((PASSED + P)); FAILED=$((FAILED + F)); SKIPPED=$((SKIPPED + S))
      echo "pytest: tests=$T passed=$P failed=$F skipped=$S (rc=$rc)"
    fi
  fi
fi

# ---- 2. CLI known-answer probes, through the neuterable launcher -----------------------------
echo "=== 2. CLI known-answer probes via $CLI_BIN ==="
# kat <name> <expected-file> <expected-rc> <cli args...>
#   stdout, as a sorted SET of lines (sort -u — the same set semantics as upstream's own assertions on
#   Policy.finding_ids; --minimal prints one id per finding and an issue can be reported several
#   times with different detail), must equal the expected file exactly, and the exit status must be
#   the documented one (1 when there are findings, 0 when there are none).
kat() {
  local name="$1" exp="$2" want_rc="$3"; shift 3
  if [ ! -x "$CLI_BIN" ]; then bad "kat $name: launcher $CLI_BIN missing — run mayhem/build.sh first"; return; fi
  if [ ! -f "$exp" ]; then bad "kat $name: expected-output file $exp missing"; return; fi
  local rc
  "$CLI_BIN" "$@" >"$TMPD/actual.raw" 2>"$TMPD/stderr"; rc=$?
  LC_ALL=C sort -u "$TMPD/actual.raw" >"$TMPD/actual"
  LC_ALL=C sort -u "$exp" >"$TMPD/expected"
  if cmp -s "$TMPD/actual" "$TMPD/expected" && [ "$rc" = "$want_rc" ]; then
    ok "kat $name (rc=$rc, $(wc -l <"$TMPD/expected" | tr -d ' ') line(s) matched)"
  else
    bad "kat $name: rc=$rc (want $want_rc); output diff (expected vs actual):"
    diff "$TMPD/expected" "$TMPD/actual" | sed 's/^/        /' >&2
    sed 's/^/        stderr: /' "$TMPD/stderr" | tail -5 >&2
  fi
}
for f in readme_getobject multi_one_bad privesc community_wildcards mfa condition_bad_type fn_sub good_simple; do
  [ -f "$KAT/$f.json" ] || bad "kat: fixture $KAT/$f.json missing"
done
# README example (s3:GetObject on a bucket ARN): finding id, README's exact default-format line, exact --json record
kat readme-minimal     "$KAT/readme_getobject.minimal.expected" 1 --files "$KAT/readme_getobject.json" --minimal
kat readme-default     "$KAT/readme_getobject.default.expected" 1 --files "$KAT/readme_getobject.json"
kat readme-json        "$KAT/readme_getobject.json.expected"    1 --files "$KAT/readme_getobject.json" --json
# tests/unit/test_formatting.py::test_analyze_policy_string_multiple_statements_one_bad
kat multi-one-bad      "$KAT/multi_one_bad.minimal.expected"    1 --files "$KAT/multi_one_bad.json" --minimal
# tests/unit/test_patterns.py::test_resource_policy_privilege_escalation
kat privesc            "$KAT/privesc.minimal.expected"          1 --files "$KAT/privesc.json" --minimal
# tests/unit/test_community_auditors.py (community auditors off / on)
kat community-off      "$KAT/community_wildcards.minimal.expected"           1 --files "$KAT/community_wildcards.json" --minimal
kat community-on       "$KAT/community_wildcards.community.minimal.expected" 1 --files "$KAT/community_wildcards.json" --minimal --include-community-auditors
# tests/unit/test_patterns.py::test_bad_mfa_condition
kat mfa                "$KAT/mfa.minimal.expected"              1 --files "$KAT/mfa.json" --minimal
# tests/unit/test_formatting.py::test_condition_action_specific_bad_type
kat condition-bad-type "$KAT/condition_bad_type.minimal.expected" 1 --files "$KAT/condition_bad_type.json" --minimal
# tests/unit/test_resources.py::test_resource_with_sub
kat fn-sub             "$KAT/fn_sub.minimal.expected"           1 --files "$KAT/fn_sub.json" --minimal
# tests/unit/test_formatting.py::test_analyze_policy_string_not_json (via --string)
kat not-json-string    "$KAT/not_json.string.minimal.expected"  1 --string 'not json' --minimal
# tests/unit/test_formatting.py::test_analyze_policy_string_correct_simple: no findings, exit 0
kat good-simple        "$KAT/good_simple.minimal.expected"      0 --files "$KAT/good_simple.json" --minimal

echo "=== summary: passed=$PASSED failed=$FAILED skipped=$SKIPPED ==="
emit_ctrf "pytest+parliament-cli-kat" "$PASSED" "$FAILED" "$SKIPPED"
