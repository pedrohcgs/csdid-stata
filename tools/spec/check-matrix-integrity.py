#!/usr/bin/env python3
"""Referential and evidential integrity for inst/spec/feature-matrix.csv.

The matrix is the conformance ledger, and until now nothing checked that what it
claims is backed by anything that exists. Two concrete failures motivated this:

  * RT016 read `parity-verified` while its test asserted only that two coverage
    spreadsheets had the expected number of rows. `current_status` was carrying
    two different claims -- "we mapped what the upstream suite tests" and "we
    match R numerically" -- so the weaker one could masquerade as the stronger.
  * All 22 JEL rows named manifests and contract CSVs as their evidence but
    never named tools/jel/run-full-reproduction.py, the harness that actually
    compares the R and Stata artifacts. The evidence chain did not reach the
    thing that establishes the claim.

Checks, all mechanical:

  1. numeric_parity matches what tools/spec/classify-numeric-parity.py derives
     from the tests themselves, so the column cannot rot.
  2. Every test_file exists.
  3. Every artifact_path exists.
  4. Every stata_gate referenced by a scenario-coverage map resolves to a real
     matrix row, so a coverage map cannot point at a gate that is not there.
  5. No row claims parity-verified on mapping-only evidence. Rows in `contract`
     and `release` scope are exempt: their claim is structural (architecture,
     dependency policy, installability), not numeric.

Exit 0 on success; print every violation and exit 1 otherwise.
"""
import csv
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from importlib.machinery import SourceFileLoader

classifier = SourceFileLoader(
    "classify_numeric_parity", os.path.join(HERE, "classify-numeric-parity.py")
).load_module()

MATRIX = os.path.join(ROOT, "inst", "spec", "feature-matrix.csv")
STRUCTURAL_SCOPES = {"contract", "release"}


def main():
    with open(MATRIX, newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))

    problems = []

    if "numeric_parity" not in rows[0]:
        print("feature matrix is missing the numeric_parity column", file=sys.stderr)
        return 1

    ids = {r["id"].strip() for r in rows}

    for r in rows:
        rid = r["id"].strip()
        scope = r["scope"].strip()
        status = r["current_status"].strip()
        declared = r["numeric_parity"].strip()

        # 1. the column must match what the tests actually do
        derived = classifier.classify(r["test_file"].strip(), r.get("evidence", ""))
        if declared != derived:
            problems.append(
                f"{rid}: numeric_parity is '{declared}' but the tests say '{derived}'. "
                f"Re-run tools/spec/classify-numeric-parity.py --write."
            )

        # 2/3. declared artifacts must exist
        tf = r["test_file"].strip()
        if tf and not os.path.exists(os.path.join(ROOT, tf)):
            problems.append(f"{rid}: test_file does not exist: {tf}")
        ap = r["artifact_path"].strip()
        if ap and not os.path.exists(os.path.join(ROOT, ap)):
            problems.append(f"{rid}: artifact_path does not exist: {ap}")

        # 5. a numeric claim needs more than a coverage map behind it
        if status == "parity-verified" and derived == "mapping" and scope not in STRUCTURAL_SCOPES:
            problems.append(
                f"{rid}: claims parity-verified but its evidence never runs csdid "
                f"(numeric_parity=mapping, scope={scope}). Either point evidence at the "
                f"harness that establishes it, or use a status the evidence supports."
            )

    # 4. coverage maps must reference gates that exist
    for path in sorted(glob.glob(os.path.join(ROOT, "tests", "fixtures", "parity", "*", "expected", "contract", "scenario-coverage.csv"))):
        rel = os.path.relpath(path, ROOT)
        with open(path, newline="", encoding="utf-8") as fh:
            for i, row in enumerate(csv.DictReader(fh), start=2):
                gate = (row.get("stata_gate") or "").strip()
                if gate and gate not in ids:
                    problems.append(f"{rel}:{i}: references unknown gate '{gate}'")

    if problems:
        print("feature-matrix integrity check FAILED:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    counts = {}
    for r in rows:
        counts[r["numeric_parity"]] = counts.get(r["numeric_parity"], 0) + 1
    summary = ", ".join(f"{v} {k}" for k, v in sorted(counts.items()))
    print(f"feature-matrix integrity OK ({len(rows)} rows: {summary})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
