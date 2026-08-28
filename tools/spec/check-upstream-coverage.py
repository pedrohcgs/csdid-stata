#!/usr/bin/env python3
"""Verify that every upstream did test is accounted for by an inheritance map.

Why this exists
---------------
The inheritance record is a set of per-fixture upstream-test-map.csv files, each
naming the upstream test it mirrors and the sha256 of the file that test lived
in. Nothing forced those records to stay aligned with upstream: a test could be
added upstream, or a recorded name could drift from the real one, and every
Stata test would still pass. Two real gaps were found by hand that way -- both
unbalanced-panel inference tests were missing, and three `nobs` tests were
collapsed into one row.

So the inventory is pinned in inst/spec/upstream-did-tests.csv (source_file,
source_sha256, source_test for every test_that block upstream) and this script
checks two things:

  1. COVERAGE  -- every pinned upstream test appears in some map, matched on the
                  exact test name. Missing entries are an error.
  2. FRESHNESS -- every map's recorded source_sha256 equals the pinned sha for
                  that file, so a map cannot claim to mirror a file revision it
                  was never read against.

With --upstream PATH it additionally re-derives the inventory from a did
checkout and reports drift, which is how the pin gets refreshed when upstream
releases.

Exit status is 0 when clean, 1 otherwise.
"""

import argparse
import csv
import glob
import hashlib
import os
import re
import sys

INVENTORY = "inst/spec/upstream-did-tests.csv"
MAP_GLOBS = [
    "tests/fixtures/parity/*/expected/contract/upstream-test-map.csv",
    "tests/fixtures/jel/metadata/upstream-test-map.csv",
]
# The closing quote must be the SAME character that opened the string --
# matching either one truncates names like  aggte(type='calendar') warns ...
TEST_THAT = re.compile(r'test_that\(\s*(["\'])(.+?)\1\s*,', re.S)


def read_inventory(path):
    with open(path, newline="") as fh:
        lines = [ln for ln in fh if not ln.startswith("#")]
    return list(csv.DictReader(lines))


def scan_upstream(root):
    """Re-derive the inventory from a did checkout."""
    rows = []
    for f in sorted(glob.glob(os.path.join(root, "tests/testthat/*.R"))):
        raw = open(f, "rb").read()
        sha = hashlib.sha256(raw).hexdigest()
        name = "tests/testthat/" + os.path.basename(f)
        for m in TEST_THAT.finditer(raw.decode("utf-8", "replace")):
            rows.append({"source_file": name, "source_sha256": sha,
                         "source_test": m.group(2).strip()})
    return rows


CASE_SUFFIX = re.compile(r"\[[^\[\]]*\]$")


def base_name(test):
    """Drop a trailing [case] qualifier.

    An upstream test_that block that loops over cases is allowed to be recorded
    as one map row per case -- "all aggte types return AGGTEobj class[simple]",
    "...[dynamic]", and so on. That is a refinement of the upstream test, not a
    different test, so it counts as covering it.
    """
    return CASE_SUFFIX.sub("", test).strip()


def read_maps():
    """Every (file, test) our inheritance record claims, and the sha it used."""
    covered, shas = {}, {}
    for pattern in MAP_GLOBS:
        for p in sorted(glob.glob(pattern)):
            for r in csv.DictReader(open(p, newline="")):
                sf = r.get("source_file", "").strip()
                if not sf.endswith(".R"):
                    continue
                covered.setdefault((sf, base_name(r.get("source_test", ""))), []).append(p)
                shas.setdefault((sf, r.get("source_sha256", "").strip()), []).append(p)
    return covered, shas


PY_INVENTORY = "inst/spec/upstream-csdid-python-tests.csv"


def py_keys(test):
    """Candidate keys for a Python test name.

    The maps were written with three conventions -- bare "test_x",
    "Class.test_x", and "Class::test_x[case]" -- so matching on one spelling
    reports whole files as unmapped when every test in them is covered. Compare
    on the normalized qualified name AND on the bare method name.
    """
    t = base_name(test).replace("::", ".")
    return {t, t.rsplit(".", 1)[-1]}


def python_problems():
    """Every Python csdid test must be claimed by an inheritance map.

    This was briefly a report rather than a gate, on the view that the
    test_unit_* files covered Python internals with no Stata surface. Reading
    them individually showed otherwise -- the 0.999 overlap threshold, pscore
    trimming, min_e/max_e windows, influence-function mean-zero and the whole
    validation set are all observable in csdid. All 392 are now classified in
    some map, 8 of them as explicitly inapplicable with a stated reason, so
    anything unclaimed is a real gap and fails.
    """
    if not os.path.exists(PY_INVENTORY):
        return []
    inv = read_inventory(PY_INVENTORY)
    raw, py_shas = read_maps_ext(".py")
    # freshness, same rule as the did channel below: a map may not cite a
    # sha the pin does not know. This dictionary used to be discarded, so
    # the 392-test Python half never had its recorded source_sha256 compared
    # to the pin at all (in-house review, gates lens: three upstream files
    # were mapped against a revision the pin does not name while the gate
    # reported full coverage; corrupting every recorded sha changed nothing).
    py_pinned = {}
    for r in inv:
        py_pinned[r["source_file"]] = r["source_sha256"]
    py_problems = []
    for (sf, sha), where in sorted(py_shas.items()):
        base = os.path.basename(sf)
        pin_sha = py_pinned.get(sf, py_pinned.get(base))
        if pin_sha and sha and sha != pin_sha:
            py_problems.append(
                f"STALE SHA(py)  {sf} recorded {sha[:12]} but pin is {pin_sha[:12]} "
                f"({os.path.dirname(where[0]).split('/')[-3]})")
    covered = set()
    for f, t in raw:
        for k in py_keys(t):
            covered.add((f, k))
    miss = {}
    for r in inv:
        f = os.path.basename(r["source_file"])
        if not any((f, k) in covered for k in py_keys(r["source_test"])):
            miss[f] = miss.get(f, 0) + 1
    n = sum(miss.values())
    if not n and not py_problems:
        print(f"python csdid coverage OK ({len(inv)} tests, all mapped, shas fresh)")
        return []
    return py_problems + [f"UNCOVERED(py) {c} test(s) in {f}" for f, c in
            sorted(miss.items(), key=lambda kv: -kv[1])]


def read_maps_ext(suffix):
    covered, shas = {}, {}
    for pattern in MAP_GLOBS:
        for p in sorted(glob.glob(pattern)):
            for r in csv.DictReader(open(p, newline="")):
                sf = r.get("source_file", "").strip()
                if not sf.endswith(suffix):
                    continue
                covered.setdefault(
                    (os.path.basename(sf), base_name(r.get("source_test", ""))), []).append(p)
                shas.setdefault((sf, r.get("source_sha256", "").strip()), []).append(p)
    return covered, shas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upstream", help="path to a did checkout; also checks for drift")
    args = ap.parse_args()

    if not os.path.exists(INVENTORY):
        print(f"missing {INVENTORY}", file=sys.stderr)
        return 1
    inv = read_inventory(INVENTORY)
    covered, shas = read_maps()
    problems = []

    # 1. coverage
    missing = [r for r in inv
               if (r["source_file"], base_name(r["source_test"])) not in covered]
    for r in missing:
        problems.append(f"UNCOVERED  {r['source_file']}:: {r['source_test']}")

    # 2. freshness -- a map may not cite a sha the pin does not know
    pinned = {}
    for r in inv:
        pinned[r["source_file"]] = r["source_sha256"]
    for (sf, sha), where in sorted(shas.items()):
        if sf in pinned and sha and sha != pinned[sf]:
            problems.append(
                f"STALE SHA  {sf} recorded {sha[:12]} but pin is {pinned[sf][:12]} "
                f"({os.path.dirname(where[0]).split('/')[-3]})")

    problems.extend(python_problems())

    # 3. optional drift check against a real checkout
    if args.upstream:
        live = scan_upstream(args.upstream)
        lset = {(r["source_file"], r["source_test"]) for r in live}
        iset = {(r["source_file"], r["source_test"]) for r in inv}
        for sf, st in sorted(lset - iset):
            problems.append(f"NEW UPSTREAM  {sf}:: {st}  (refresh {INVENTORY})")
        for sf, st in sorted(iset - lset):
            problems.append(f"GONE UPSTREAM {sf}:: {st}  (refresh {INVENTORY})")

    if problems:
        for p in problems:
            print(p)
        print(f"\nFAIL: {len(problems)} problem(s); {len(inv)} pinned upstream tests")
        return 1

    print(f"upstream coverage OK ({len(inv)} pinned did tests, all mapped"
          + (", no drift vs checkout" if args.upstream else "") + ")")
    return 0


if __name__ == "__main__":
    sys.exit(main())
