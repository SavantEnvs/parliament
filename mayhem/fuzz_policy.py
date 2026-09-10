#!/opt/toolchains/python/venv/bin/python3
"""fuzz_policy.py — Atheris (libFuzzer) harness for parliament, the AWS IAM policy linter.

Target `fuzz-policy` (launched through the /mayhem/fuzz-policy ELF shim, see launcher.c). Ported
from the legacy mayhemheroes/parliament harness, which drove analyze_policy_string() over the
fuzzer's bytes and found 10 defects (uncaught exceptions on malformed policy structures).

Input mapping: the raw fuzzer bytes ARE the policy text (UTF-8, undecodable bytes replaced), so the
starter seeds are literal IAM policy JSON documents and every byte mutation is a text mutation the
JSON/policy parser actually sees. (The legacy harness went through FuzzedDataProvider's
ConsumeUnicodeNoSurrogates, whose first byte selects an ASCII/UTF-16/UTF-32 decoding — a seed
starting with '{' decoded as UTF-32 garbage, so seeds never reached the parser.)

Surface: analyze_policy_string() on the default (core) audit path — exactly what the legacy harness
fuzzed — then the Finding/Policy accessors the CLI uses. The community auditors are deliberately
NOT enabled here: measured on this checkout, any policy with a bare "Action": "*" costs 6-9 s per
input under the community auditors (privilege-escalation/permissions checks expand and re-scan all
~15k IAM actions) versus <=0.02 s on the core path, and the fuzzer produces "*" trivially, so
enabling them would stall the campaign on slow units. They are still graded by the oracle
(mayhem/test.sh: the pytest suite + the --include-community-auditors CLI probe), and their own
exceptions are swallowed into an EXCEPTION finding by upstream anyway, so they add no crash surface.

No file I/O: bytes come only from the fuzzer; nothing is read or written on disk.
"""
import os
import sys

# Import parliament from the SOURCE TREE (<repo>/parliament), never an installed copy, so the code
# under fuzz is exactly the checked-out (or PATCH-tier patched) revision. This file lives at
# <repo>/mayhem/fuzz_policy.py, so the repo root is one directory up.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO_ROOT)

import atheris  # noqa: E402

with atheris.instrument_imports(include=["parliament", "jsoncfg"]):
    from parliament import analyze_policy_string


def TestOneInput(data: bytes) -> None:
    # errors="replace" keeps the str well-formed, so any exception below is parliament's own, never
    # the decoder's.
    policy_str = data.decode("utf-8", errors="replace")
    policy = analyze_policy_string(policy_str)
    for finding in policy.findings:
        repr(finding)
    policy.finding_ids
    policy.is_valid


def main() -> None:
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()


if __name__ == "__main__":
    main()
