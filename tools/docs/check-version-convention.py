#!/usr/bin/env python3
"""Enforce the "Version 1.82" naming convention in prose.

The legacy Stata release is always written "Version 1.82", never a bare
"1.82". Written bare it reads as a decimal number rather than a release, and
alongside "2.0.0" it invites the reader to compare two things that are not on
the same scale. Prose fixed by hand drifts back, so this gate holds it.

Two kinds of occurrence are legitimate and are allowed:

  * a literal quotation of the shipped ado header ("version: 1.82"), because
    rewording it would misquote the source being reported;
  * a path or filename that contains the version.

Run: python3 tools/docs/check-version-convention.py
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

# Everything a reader of the package or the site can reach.
SEARCH = [
    ("*.md", ["README.md", "NEWS.md", "PROVENANCE.md"]),
]
SEARCH_DIRS = ["docs", "website", "reports", "packaging", "src"]
SUFFIXES = {".md", ".sthlp", ".do", ".ado", ".mata", ".txt"}

BARE = re.compile(r"(?<![\w.])1\.82(?![\w.])")

# Quotations of the legacy ado header. These report a literal string.
ALLOWED_SUBSTRINGS = (
    "ado header reports version 1.82",
    "ado header reports `version: 1.82`",
    # The sentence that states this very rule has to show the form it forbids.
    "never a bare `1.82`",
)


def candidates():
    seen = set()
    for name in ("README.md", "NEWS.md", "PROVENANCE.md"):
        p = ROOT / name
        if p.is_file():
            seen.add(p)
    for d in SEARCH_DIRS:
        base = ROOT / d
        if not base.is_dir():
            continue
        for p in base.rglob("*"):
            if p.is_file() and p.suffix in SUFFIXES:
                seen.add(p)
    return sorted(seen)


def main() -> int:
    violations = []
    for path in candidates():
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            if not BARE.search(line):
                continue
            if any(a in line for a in ALLOWED_SUBSTRINGS):
                continue
            # "Version 1.82" is the required form; a line may also carry an
            # allowed literal alongside a correct mention, so strip the good
            # ones before deciding.
            stripped = line.replace("Version 1.82", "")
            if not BARE.search(stripped):
                continue
            violations.append((path.relative_to(ROOT), lineno, line.strip()))

    if violations:
        print("bare '1.82' found; write 'Version 1.82' in prose:", file=sys.stderr)
        for rel, lineno, line in violations:
            print(f"  {rel}:{lineno}: {line[:110]}", file=sys.stderr)
        print(
            f"\n{len(violations)} violation(s). If a line quotes the legacy ado header "
            "verbatim, add it to ALLOWED_SUBSTRINGS in this script rather than "
            "rewording the quotation.",
            file=sys.stderr,
        )
        return 1

    print(f"version-naming convention OK ({len(candidates())} files scanned)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
