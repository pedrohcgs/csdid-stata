#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# clone-scan.py -- duplicate-block detector for the Mata engine and the ado
# layer.
#
# Two passes over the same normalized text:
#
#   EXACT   comments stripped, whitespace collapsed, blank lines dropped.
#           Two blocks are the same clone when their normalized text is
#           byte-identical.
#   SHAPE   the same, then every identifier that is not a Mata/Stata keyword
#           or a call target is replaced by a placeholder and every numeric
#           literal by `#'. Catches the family of near-identical routines that
#           differ only in the names they read and write -- which is what an
#           exact detector is blind to and what the profiling banks are.
#
# A clone class is reported when its members are pairwise non-overlapping and
# the block is at least MINLEN normalized lines long. Blocks are grown to
# maximal length before reporting, so a 40-line duplicate is one row and not
# twenty-six overlapping 15-line rows.
#
# Usage:
#   python3 tools/bench/clone-scan.py --min 15 --occ 2  src/mata/csdid.mata
#   python3 tools/bench/clone-scan.py --min 8  --occ 3  src/ado/*.ado
# ---------------------------------------------------------------------------

import argparse
import hashlib
import re
import sys
from collections import defaultdict

# --- parameters ------------------------------------------------------------

KEYWORDS = {
    # Mata declarations and control flow
    "void", "real", "string", "complex", "pointer", "numeric", "transmorphic",
    "scalar", "vector", "rowvector", "colvector", "matrix", "class", "struct",
    "function", "if", "else", "for", "while", "do", "break", "continue",
    "return", "external", "static", "public", "private", "protected", "final",
    "virtual", "version", "mata", "end", "extern", "new", "this",
    # Stata ado control flow
    "program", "syntax", "local", "global", "tempname", "tempvar", "tempfile",
    "quietly", "noisily", "capture", "display", "exit", "foreach", "forvalues",
    "in", "of", "using", "by", "sort", "gen", "generate", "replace", "drop",
    "keep", "assert", "confirm", "args", "define", "end",
}

IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NUMLIT = re.compile(r"\b\d+\.?\d*([eE][-+]?\d+)?\b")
WS = re.compile(r"\s+")


# --- normalization ---------------------------------------------------------

def strip_comments(lines, ado=False):
    """Return (text, srcline) pairs with comments removed, blanks dropped."""
    out = []
    in_block = False
    for n, raw in enumerate(lines, start=1):
        s = raw
        buf = []
        i = 0
        while i < len(s):
            if in_block:
                j = s.find("*/", i)
                if j < 0:
                    i = len(s)
                else:
                    in_block = False
                    i = j + 2
                continue
            if s.startswith("/*", i):
                in_block = True
                i += 2
                continue
            if s.startswith("//", i):
                break
            buf.append(s[i])
            i += 1
        t = "".join(buf)
        if ado:
            # a leading * is a whole-line comment in ado
            if t.lstrip().startswith("*"):
                t = ""
        t = WS.sub(" ", t).strip()
        if t:
            out.append((t, n))
    return out


def shape(text):
    """Identifier-blind form: names -> placeholders, numbers -> #."""
    t = NUMLIT.sub("#", text)

    seen = {}

    def sub(m):
        w = m.group(0)
        if w in KEYWORDS:
            return w
        if w not in seen:
            seen[w] = "v%d" % len(seen)
        return seen[w]

    return IDENT.sub(sub, t)


# --- clone detection -------------------------------------------------------

def find_clones(units, minlen, minocc):
    """units: list of (key, srcfile, srcline). Returns maximal clone classes."""
    n = len(units)
    keys = [u[0] for u in units]

    # hash every window of length minlen
    buckets = defaultdict(list)
    for i in range(n - minlen + 1):
        h = hashlib.blake2b(
            "\n".join(keys[i:i + minlen]).encode(), digest_size=16
        ).hexdigest()
        buckets[h].append(i)

    classes = []
    consumed = set()
    for h, starts in buckets.items():
        if len(starts) < minocc:
            continue
        # grow every member of the class together while all still agree
        length = minlen
        while True:
            nxt = length + 1
            if starts[-1] + nxt > n:
                break
            vals = {tuple(keys[s:s + nxt]) for s in starts}
            if len(vals) != 1:
                break
            length = nxt
        # drop overlapping members (keep greedily left to right)
        kept = []
        last_end = -1
        for s in sorted(starts):
            if s > last_end:
                kept.append(s)
                last_end = s + length - 1
        if len(kept) < minocc:
            continue
        # skip if fully inside an already-reported class
        covered = bool(consumed) and all(
            any(s >= cs and s + length <= cs + cl for cs, cl in consumed)
            for s in kept
        )
        if covered:
            continue
        classes.append((length, kept))
        for s in kept:
            consumed.add((s, length))

    # drop classes whose every member sits inside a longer class's member
    classes.sort(key=lambda c: -c[0])
    final = []
    taken = []
    for length, starts in classes:
        if all(
            any(s >= ts and s + length <= ts + tl for ts in tstarts)
            for s in starts
            for tl, tstarts in [(length, starts)]
        ) and False:
            pass
        inside = 0
        for s in starts:
            for tl, tstarts in taken:
                if any(ts <= s and s + length <= ts + tl for ts in tstarts):
                    inside += 1
                    break
        if inside == len(starts):
            continue
        final.append((length, starts))
        taken.append((length, starts))
    return final


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--min", type=int, default=15)
    ap.add_argument("--occ", type=int, default=2)
    ap.add_argument("--mode", choices=["exact", "shape", "both"],
                    default="both")
    args = ap.parse_args()

    units_exact = []
    units_shape = []
    for path in args.files:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
        ado = path.endswith(".ado") or path.endswith(".do")
        for text, srcline in strip_comments(lines, ado=ado):
            units_exact.append((text, path, srcline))
            units_shape.append((shape(text), path, srcline))

    modes = ["exact", "shape"] if args.mode == "both" else [args.mode]
    for mode in modes:
        units = units_exact if mode == "exact" else units_shape
        classes = find_clones(units, args.min, args.occ)
        classes.sort(key=lambda c: (-c[0] * len(c[1]), -c[0]))
        print("=== MODE %s  min=%d occ>=%d  classes=%d ==="
              % (mode, args.min, args.occ, len(classes)))
        for length, starts in classes:
            locs = []
            for s in starts:
                _, f, l0 = units[s]
                _, _, l1 = units[s + length - 1]
                locs.append("%s:%d-%d" % (f.split("/")[-1], l0, l1))
            print("CLONE len=%d occ=%d  %s" % (length, len(starts),
                                               "  ".join(locs)))
            head = units[starts[0]][0]
            print("       first: %s" % head[:96])
        print()


if __name__ == "__main__":
    sys.exit(main())
