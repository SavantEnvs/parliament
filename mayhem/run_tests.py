#!/opt/toolchains/python/venv/bin/python3
"""run_tests.py — RUN parliament's own pytest suite and print a parseable summary.

Invoked via the /mayhem/parliament-tests ELF launcher (NOT directly), so the verify-repo sabotage
oracle can neuter the launcher and prove the test oracle is behavioral.

It runs the real suites — tests/unit/*.py (the suite upstream's tests/scripts/unit_tests.sh runs)
plus parliament/community_auditors/tests/*.py (upstream's COMMUNITY_TESTS, nose-style; see the
assert_equal shim below) — all known-answer cases
asserting that analyze_policy_string(<policy>).finding_ids / findings / expand_action() results
EXACTLY equal expected values. It writes a JUnit XML, parses the counts, and prints one line:

    RUNTESTS tests=<n> passed=<p> failed=<f> skipped=<s>

Exit 0 iff failed == 0. mayhem/test.sh parses that line into a CTRF report.
"""
from __future__ import annotations

import os
import sys
import tempfile
import xml.etree.ElementTree as ET

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO_ROOT)

import builtins  # noqa: E402

import pytest  # noqa: E402

SUITES = ["tests/unit", "parliament/community_auditors/tests"]


# nose compatibility shim. parliament/community_auditors/tests/*.py were written for nose and call
# `assert_equal(a, b)` without importing it (nose injected it); under pytest every one of those 6
# known-answer tests dies with NameError on upstream itself (verified on the pristine checkout).
# nose's assert_equal is unittest.TestCase.assertEqual, i.e. `assert a == b` — provide exactly that
# so the community-auditor assertions run instead of being lost.
def _assert_equal(a, b, msg=None):
    assert a == b, (msg if msg is not None else f"{a!r} != {b!r}")


builtins.assert_equal = _assert_equal

# Known-broken on PRISTINE upstream HEAD, independent of this integration (verified by running the
# suite on the unmodified checkout). Deselected so the oracle reflects upstream's real passing
# suite; the remaining known-answer cases keep it behavioral.
DESELECT: list[str] = [
    # The bundled iam_definition.json makes expand_action("iAm:li*sTuS*rs") return iam:ListUsers
    # twice, so this de-dup assertion (expects exactly 1) fails on upstream itself.
    "tests/unit/test_action_expansion.py::TestActionExpansion::test_expand_action_with_casing",
]


def main() -> int:
    os.chdir(REPO_ROOT)
    fd, xml_path = tempfile.mkstemp(prefix="parliament-junit-", suffix=".xml",
                                    dir=os.environ.get("TMPDIR", "/tmp"))
    os.close(fd)
    args = ["-q", "-p", "no:cacheprovider", "--rootdir", REPO_ROOT, "--junitxml", xml_path] + SUITES
    for nodeid in DESELECT:
        args += ["--deselect", nodeid]
    pytest.main(args)

    root = ET.parse(xml_path).getroot()
    os.unlink(xml_path)
    suites = root.findall("testsuite") or ([root] if root.tag == "testsuite" else [])
    if not suites:
        print("RUNTESTS tests=0 passed=0 failed=1 skipped=0")
        return 1

    tests = failed = skipped = 0
    for s in suites:
        tests += int(s.get("tests", 0))
        failed += int(s.get("failures", 0)) + int(s.get("errors", 0))
        skipped += int(s.get("skipped", 0))
    passed = tests - failed - skipped

    print(f"RUNTESTS tests={tests} passed={passed} failed={failed} skipped={skipped}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # import/setup failure is a hard failure, not a vacuous pass
        import traceback

        traceback.print_exc()
        print(f"RUNTESTS tests=1 passed=0 failed=1 skipped=0 (harness error: {exc})")
        sys.exit(1)
