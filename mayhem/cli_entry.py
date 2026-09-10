#!/opt/toolchains/python/venv/bin/python3
"""cli_entry.py — run parliament's real command-line tool from the SOURCE TREE.

Invoked through the /mayhem/parliament-cli ELF launcher (see launcher.c) by mayhem/test.sh's
known-answer probes: `parliament-cli --files <policy.json> [--minimal|--json] ...` is exactly
upstream's `parliament` console_script (parliament.cli:cli), resolved against <repo>/parliament
rather than an installed copy so the oracle grades the checked-out (or patched) code.
"""
import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO_ROOT)

from parliament.cli import cli  # noqa: E402

if __name__ == "__main__":
    cli()
