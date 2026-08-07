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
that is exactly how a reader would run them -- and executes it. Stata exits 0
even when a do-file aborts, so the log is scanned for r(NNN); rather than
trusting the exit status.

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
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# packaging/README.md is the README shipped with the package; README.md at the
# root describes this development repository and carries no Stata examples.
DOCS = ["packaging/README.md"] + sorted(
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
    the last candidate when none exists so the caller reports "no local data"
    rather than crashing -- this gate degrades to skipping, it does not block.
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
    args = ap.parse_args()

    if not shutil.which(args.stata):
        print(f"BLOCKED: {args.stata} not on PATH (set STATA_CMD)")
        return 1

    jel_csv = jel_root() / "data/county_mortality_data.csv"
    have_local = jel_csv.is_file()

    failures, blocked, passed = [], [], []
    for doc in DOCS:
        if args.only and args.only not in doc:
            continue
        md = (ROOT / doc).read_text(encoding="utf-8")
        code, skipped = blocks(md)
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
            subprocess.run([args.stata, "-b", "do", str(do)], cwd=tmp,
                           capture_output=True)
            log = Path(tmp) / "doc_example.log"
            if not log.is_file():
                failures.append((doc, "no log produced", ""))
                continue
            text = log.read_text(encoding="utf-8", errors="replace")
            err = re.search(r"^r\((\d+)\);", text, re.M)
            if err:
                tail = "\n".join(text.splitlines()[-14:])
                failures.append((doc, f"r({err.group(1)});", tail))
            else:
                passed.append((doc, len(code), skipped))

    for doc, n, skipped in passed:
        note = f", {skipped} skipped" if skipped else ""
        print(f"PASS    {doc}  ({n} block(s){note})")
    for doc, why in blocked:
        print(f"BLOCKED {doc}  -- {why}")
    for doc, why, tail in failures:
        print(f"FAIL    {doc}  -- {why}")
        if tail:
            print("\n".join("        " + ln for ln in tail.splitlines()))

    if failures or blocked:
        print(f"\n{len(passed)} passed, {len(failures)} failed, {len(blocked)} blocked")
        return 1
    print(f"\nall {len(passed)} document(s) run clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
