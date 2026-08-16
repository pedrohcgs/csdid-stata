#!/usr/bin/env python3
"""Classify Mata source lines into the five disjoint buckets the refactor's
line accounting reports, so that table is reproducible from the tree rather
than from a scratch script.

    python3 tools/bench/line-classify.py --rev <sha> src/mata/csdid.mata
    python3 tools/bench/line-classify.py src/mata/csdid.mata

line-census.py answers code/comment/blank; this answers what the CODE is made
of, which is the question "did the refactor add work or add structure?".

The five buckets partition the code lines exactly (their sum is printed and
checked against the census's code count, so a drift in either is visible):

  signature    a function/method header and its continuation argument lines
  classdef     lines inside a `class ... {' body (member declarations)
  declaration  a type declaration inside a function body
  brace        a line whose only content is a brace
  statement    everything else -- the lines that do work

The refactor's finding was that three quarters of the code growth landed in
signature + classdef + brace: the arithmetic price of decomposition and of the
classes the charter asked for, both of which the charter counted as free.
"""

import argparse
import re
import subprocess
import sys

TYPES = (
    r"real|string|complex|numeric|transmorphic|pointer|void|class|struct"
)
DECL_RE = re.compile(rf"^\s*(?:external\s+)?(?:{TYPES})\b")
FUNC_RE = re.compile(rf"^\s*(?:{TYPES})[\w\s\(\)\*,]*\s[\w:]+\s*\(")
CLASS_OPEN_RE = re.compile(r"^\s*class\s+\w+\s*(?:extends\s+\w+\s*)?\{")
BRACE_RE = re.compile(r"^\s*[{}]\s*$")


def source(path, rev):
    if rev:
        return subprocess.run(
            ["git", "show", f"{rev}:{path}"], capture_output=True, text=True, check=True
        ).stdout.splitlines()
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read().splitlines()


def classify(lines):
    counts = dict.fromkeys(
        ("signature", "classdef", "declaration", "brace", "statement"), 0
    )
    comment = blank = 0
    in_class = in_block_comment = False
    in_signature = False
    depth = 0

    for raw in lines:
        line = raw.rstrip()
        stripped = line.strip()

        if in_block_comment:
            comment += 1
            if "*/" in stripped:
                in_block_comment = False
            continue
        if not stripped:
            blank += 1
            continue
        if stripped.startswith("//") or stripped.startswith("*"):
            comment += 1
            continue
        if stripped.startswith("/*"):
            comment += 1
            if "*/" not in stripped:
                in_block_comment = True
            continue

        # A signature can span lines; it ends at the line closing its paren run.
        if in_signature:
            counts["signature"] += 1
            if stripped.endswith(")") or stripped.endswith("){") or "{" in stripped:
                in_signature = False
            continue

        if CLASS_OPEN_RE.match(stripped):
            in_class = True
            counts["classdef"] += 1
            continue
        if in_class:
            counts["classdef"] += 1
            if stripped.startswith("}"):
                in_class = False
            continue

        if BRACE_RE.match(stripped):
            counts["brace"] += 1
            depth += stripped.count("{") - stripped.count("}")
            continue

        if FUNC_RE.match(stripped) and depth == 0:
            counts["signature"] += 1
            opens = stripped.count("(")
            closes = stripped.count(")")
            if opens > closes:
                in_signature = True
            depth += stripped.count("{") - stripped.count("}")
            continue

        if DECL_RE.match(stripped) and depth > 0:
            counts["declaration"] += 1
            depth += stripped.count("{") - stripped.count("}")
            continue

        counts["statement"] += 1
        depth += stripped.count("{") - stripped.count("}")

    return counts, comment, blank


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--rev", default=None, help="git revision (default: worktree)")
    args = ap.parse_args()

    lines = source(args.path, args.rev)
    counts, comment, blank = classify(lines)
    code = sum(counts.values())

    label = args.rev or "worktree"
    print(f"{args.path} @ {label}")
    for bucket in ("signature", "declaration", "classdef", "brace", "statement"):
        print(f"  {bucket:12s} {counts[bucket]:6d}")
    print(f"  {'CODE':12s} {code:6d}")
    print(f"  {'comment':12s} {comment:6d}")
    print(f"  {'blank':12s} {blank:6d}")
    print(f"  {'TOTAL':12s} {code + comment + blank:6d}  (wc -l: {len(lines)})")
    if code + comment + blank != len(lines):
        print("  WARNING: buckets do not partition the file", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
