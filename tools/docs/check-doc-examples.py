#!/usr/bin/env python3
"""Run every Stata example in the README and the website guides.

Why this exists
---------------
`examples/*.do` are executed by tests/stata/test-release-hardening.do, but
nothing ever ran the code blocks in the package README or under website/. They were
unverified prose. A user guide whose examples do not run is worse than no guide:
the reader assumes the failure is theirs.

This extracts the ```stata blocks from each document, concatenates them in order
into one do-file per document -- guides are written to be read top to bottom, so
that is exactly how a reader would run them -- and executes it. A successful
launch must also produce a completed log with no uncaught Stata error.

A block that is illustrative rather than runnable (showing option syntax, or
output) is skipped by putting

    <!-- norun -->

on the line before it. Use that sparingly: a skipped block is an unverified one.

The guides download the JEL-DiD data from a pinned URL, which is right for a
reader but makes this gate depend on the network. When JEL_DID_REFERENCE points
at a checkout, the import line is rewritten to read that file instead, so the
gate runs offline against the same data. Without it, and without network, the
document is reported BLOCKED -- never as passed.

Exit status is 0 when every document passes, 1 otherwise.
"""

from __future__ import annotations

import argparse
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# The payload builder moves the package README to the public root and removes
# packaging/. Select by layout so a missing development package README still
# fails instead of falling back to the unrelated development root README.
README = "packaging/README.md" if (ROOT / "packaging").is_dir() else "README.md"
DOCS = [README] + sorted(
    str(p.relative_to(ROOT)) for p in (ROOT / "website").rglob("*.md")
)
BLOCK = re.compile(r"(?P<norun><!--\s*norun\s*-->\s*\n)?```stata\n(?P<code>.*?)```",
                   re.S)
JEL_URL = re.compile(
    r'"https://raw\.githubusercontent\.com/pedrohcgs/JEL-DiD/[0-9a-f]+/data/'
    r'county_mortality_data\.csv"')


def blocks(md: str) -> tuple[list[str], int]:
    """Runnable code blocks, and how many were skipped."""
    keep, skipped = [], 0
    for m in BLOCK.finditer(md):
        if m.group("norun"):
            skipped += 1
        else:
            keep.append(m.group("code"))
    return keep, skipped


def jel_root():
    """$JEL_DID_REFERENCE, then the sibling checkout, then the legacy /tmp path.

    The same order as the R generators under tools/parity/generators. Returns
    the last candidate when none exists so the caller reports BLOCKED rather
    than treating unavailable data as a successful check.
    """
    candidates = [
        Path(p).expanduser()
        for p in (
            os.environ.get("JEL_DID_REFERENCE", ""),
            Path.home() / "Documents/GitHub/JEL-DiD",
            "/tmp/jel-did-reference",
        )
        if str(p)
    ]
    return next((p for p in candidates if p.is_dir()), candidates[-1])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stata", default=os.environ.get("STATA_CMD", "stata-mp"))
    ap.add_argument("--only", help="substring: run just the documents matching it")
    ap.add_argument("--timeout", type=float, default=300,
                    help="maximum seconds per document (default: 300)")
    args = ap.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        ap.error("--timeout must be a positive finite number of seconds")

    documents = [doc for doc in DOCS if not args.only or args.only in doc]
    if not documents:
        print(f"FAIL: no documents match --only {args.only!r}")
        return 1

    if not shutil.which(args.stata):
        print(f"BLOCKED: {args.stata} not on PATH (set STATA_CMD)")
        return 1

    jel_csv = jel_root() / "data/county_mortality_data.csv"
    have_local = jel_csv.is_file()

    failures, blocked, passed, skipped_docs = [], [], [], []
    for doc in documents:
        try:
            md = (ROOT / doc).read_text(encoding="utf-8")
        except OSError as exc:
            failures.append((doc, f"cannot read document: {exc}", ""))
            continue
        code, skipped = blocks(md)
        if skipped:
            skipped_docs.append((doc, skipped))
        if not code:
            continue

        body = "\n\n".join(code)
        uses_jel = bool(JEL_URL.search(body))
        if uses_jel:
            if have_local:
                body = JEL_URL.sub(f'"{jel_csv}"', body)
            else:
                blocked.append((doc, "no JEL checkout and the example needs the network"))
                continue

        with tempfile.TemporaryDirectory() as tmp:
            do = Path(tmp) / "doc_example.do"
            do.write_text(
                f'adopath ++ "{ROOT}/src/ado"\n'
                f'adopath ++ "{ROOT}/src/mata"\n'
                "set more off\n\n" + body + "\n",
                encoding="utf-8")
            try:
                result = subprocess.run(
                    [args.stata, "-b", "do", str(do)], cwd=tmp,
                    capture_output=True, timeout=args.timeout)
            except subprocess.TimeoutExpired:
                failures.append((doc, f"Stata exceeded {args.timeout:g} seconds", ""))
                continue
            except OSError as exc:
                failures.append((doc, f"cannot launch Stata: {exc}", ""))
                continue
            if result.returncode:
                failures.append((doc, f"Stata process exited {result.returncode}", ""))
                continue
            log = Path(tmp) / "doc_example.log"
            if not log.is_file():
                failures.append((doc, "no log produced", ""))
                continue
            text = log.read_text(encoding="utf-8", errors="replace")
            err = re.search(r"^r\((\d+)\);", text, re.M)
            substantive = [line.strip() for line in text.splitlines()
                           if line.strip() and line.strip() != "."]
            complete = bool(substantive and substantive[-1] == "end of do-file")
            if err:
                tail = "\n".join(text.splitlines()[-14:])
                failures.append((doc, f"r({err.group(1)});", tail))
            elif not complete:
                tail = "\n".join(text.splitlines()[-14:])
                failures.append((doc, "incomplete Stata batch log", tail))
            else:
                passed.append((doc, len(code), skipped))

    for doc, n, skipped in passed:
        print(f"PASS    {doc}  ({n} runnable block(s))")
    for doc, skipped in skipped_docs:
        print(f"SKIP    {doc}  ({skipped} norun block(s), unverified by this gate)")
    for doc, why in blocked:
        print(f"BLOCKED {doc}  -- {why}")
    for doc, why, tail in failures:
        print(f"FAIL    {doc}  -- {why}")
        if tail:
            print("\n".join("        " + ln for ln in tail.splitlines()))

    if failures or blocked:
        print(f"\n{len(passed)} passed, {len(failures)} failed, {len(blocked)} blocked")
        return 1
    if not passed:
        print("FAIL: no runnable documentation blocks were checked")
        return 1
    print(f"\n{len(passed)} document(s) passed for their runnable blocks; "
          f"{sum(n for _, n in skipped_docs)} norun block(s) remain unverified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
