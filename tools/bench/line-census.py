#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# line-census.py -- code / comment / blank census of the engine and the ado
# layer at any revision.
#
# The three counts are disjoint and sum to the file's total lines, so the
# arithmetic in a stage report can be checked against `wc -l'.
#
#   COMMENT  a line whose content is entirely comment: `//' or `/* */' in
#            Mata, plus a leading `*' in ado. A trailing comment on a code
#            line counts as CODE -- the line carries a statement.
#   BLANK    empty or whitespace only.
#   CODE     everything else.
#
# Usage:
#   python3 tools/bench/line-census.py src/mata/csdid.mata src/ado/*.ado
#   python3 tools/bench/line-census.py --rev <sha> src/mata/csdid.mata
# ---------------------------------------------------------------------------

import argparse
import subprocess
import sys


def census(text, ado=False):
    code = comment = blank = 0
    in_block = False
    for raw in text.split("\n"):
        s = raw.strip()
        if not in_block and not s:
            blank += 1
            continue
        # walk the line, tracking block state, collecting non-comment text
        out = []
        i = 0
        line = raw
        started_in_block = in_block
        while i < len(line):
            if in_block:
                j = line.find("*/", i)
                if j < 0:
                    i = len(line)
                else:
                    in_block = False
                    i = j + 2
                continue
            if line.startswith("/*", i):
                in_block = True
                i += 2
                continue
            if line.startswith("//", i):
                break
            out.append(line[i])
            i += 1
        rest = "".join(out).strip()
        if ado and rest.startswith("*"):
            rest = ""
        if rest:
            code += 1
        elif started_in_block or "//" in line or "/*" in line or (ado and s.startswith("*")):
            comment += 1
        elif not s:
            blank += 1
        else:
            comment += 1
    return code, comment, blank


def read(path, rev=None):
    if rev:
        try:
            return subprocess.check_output(
                ["git", "show", "%s:%s" % (rev, path)], text=True,
                stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            return None
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--rev")
    ap.add_argument("--label", default="")
    ap.add_argument("--tsv", action="store_true")
    args = ap.parse_args()

    tot = [0, 0, 0]
    rows = []
    for path in args.files:
        text = read(path, args.rev)
        if text is None:
            rows.append((path, 0, 0, 0, 0))
            continue
        if text.endswith("\n"):
            text = text[:-1]
        c, m, b = census(text, ado=path.endswith(".ado") or path.endswith(".do"))
        rows.append((path, c, m, b, c + m + b))
        tot[0] += c
        tot[1] += m
        tot[2] += b

    lab = args.label or (args.rev or "worktree")
    if args.tsv:
        for p, c, m, b, t in rows:
            print("%s\t%s\t%d\t%d\t%d\t%d" % (lab, p, c, m, b, t))
        print("%s\tTOTAL\t%d\t%d\t%d\t%d"
              % (lab, tot[0], tot[1], tot[2], sum(tot)))
    else:
        print("%-14s %-32s %7s %8s %6s %7s"
              % ("rev", "file", "code", "comment", "blank", "total"))
        for p, c, m, b, t in rows:
            print("%-14s %-32s %7d %8d %6d %7d" % (lab, p, c, m, b, t))
        print("%-14s %-32s %7d %8d %6d %7d"
              % (lab, "TOTAL", tot[0], tot[1], tot[2], sum(tot)))


if __name__ == "__main__":
    sys.exit(main())
