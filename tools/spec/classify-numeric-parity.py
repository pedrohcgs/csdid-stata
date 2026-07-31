#!/usr/bin/env python3
"""Derive, for every feature-matrix row, whether its test actually compares
Stata output against R-computed expected values.

`current_status` used to carry two different claims at once: "we mapped what the
upstream suite tests" and "we match R numerically". A row could therefore read
`parity-verified` on the strength of a well-formed coverage spreadsheet -- RT016
did exactly that. This computes the second claim from the tests themselves so it
cannot be asserted by hand.

Classification, per row's test_file (following one level of `do` delegation,
because some rows are thin wrappers that delegate to the real test):

  measured    the test loads an R-generated expected/r/ artifact and compares
  behavioral  the test runs csdid but never compares against an R artifact
  mapping     the test never invokes csdid at all (coverage bookkeeping)
  missing     test_file does not exist

Usage:
  classify-numeric-parity.py            print the classification table
  classify-numeric-parity.py --write    write it into the numeric_parity column
"""
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MATRIX = os.path.join(ROOT, "inst", "spec", "feature-matrix.csv")

RUNS_CSDID = re.compile(r"(?m)^\s*(?:quietly |capture |noisily |qui |cap )*csdid[ _]")
LOADS_R = re.compile(r"expected/r/")
DELEGATES = re.compile(r'(?m)^\s*do\s+"[^"]*?(tests/stata/[^"]+\.do)"')


def read(path):
    full = os.path.join(ROOT, path)
    if not os.path.isfile(full):
        return None
    with open(full, encoding="utf-8", errors="replace") as fh:
        return fh.read()


RANK = {"missing": 0, "mapping": 1, "behavioral": 2, "measured": 3}
# Evidence that establishes a Stata-vs-R comparison outside a .do file. The JEL
# rows are the case that forced this: all 22 share one artifact-contract
# test_file, while the reproduction that actually compares against R runs from a
# separate harness named only in the evidence column.
R_HARNESS = re.compile(r"(?i)(reproduction|parity|oracle)")


def classify_one(path, depth=0):
    src = read(path)
    if src is None:
        return "missing"
    if LOADS_R.search(src) or (path.endswith((".py", ".R", ".sh")) and R_HARNESS.search(src)):
        return "measured"
    if RUNS_CSDID.search(src):
        return "behavioral"
    # a thin wrapper may delegate to the test that does the real work
    if depth < 2:
        best = "mapping"
        for target in DELEGATES.findall(src):
            got = classify_one(target, depth + 1)
            best = max(best, got, key=lambda k: RANK[k])
        return best
    return "mapping"


def classify(test_file, evidence=""):
    """Best evidence across the named test file and any runnable evidence path."""
    verdicts = [classify_one(test_file)]
    for item in (evidence or "").split(";"):
        item = item.strip()
        if item.endswith((".do", ".py", ".R", ".sh")):
            verdicts.append(classify_one(item))
    best = max(verdicts, key=lambda k: RANK[k])
    # a missing test_file is a defect regardless of what evidence claims
    return "missing" if verdicts[0] == "missing" else best


def main():
    with open(MATRIX, newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    fields = list(rows[0].keys())

    for r in rows:
        r["numeric_parity"] = classify(r["test_file"].strip(), r.get("evidence", ""))

    if "--write" in sys.argv:
        if "numeric_parity" not in fields:
            fields.insert(fields.index("current_status") + 1, "numeric_parity")
        with open(MATRIX, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=fields)
            w.writeheader()
            w.writerows(rows)
        print(f"wrote numeric_parity for {len(rows)} rows")
        return

    counts = {}
    for r in rows:
        counts[r["numeric_parity"]] = counts.get(r["numeric_parity"], 0) + 1
    for k in sorted(counts):
        print(f"  {counts[k]:>4}  {k}")
    print()
    print("  rows claiming parity-verified WITHOUT a measured comparison:")
    for r in rows:
        if r["current_status"].strip() == "parity-verified" and r["numeric_parity"] != "measured":
            print(f"    {r['id']:<8} {r['numeric_parity']:<11} {r['name'][:46]}")


if __name__ == "__main__":
    main()
