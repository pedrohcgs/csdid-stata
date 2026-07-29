#!/usr/bin/env python3
"""Validate the frozen csdid Stata porting contract."""

from __future__ import annotations

import csv
import json
from pathlib import Path
import sys
import argparse


ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    print(f"contract validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--phase",
        choices=("contract", "implementation"),
        default="implementation",
        help="contract requires all mandatory rows to be contract-frozen; implementation also accepts terminal progress statuses",
    )
    args = parser.parse_args()

    matrix_path = ROOT / "inst/spec/feature-matrix.csv"
    rows = list(csv.DictReader(matrix_path.open(newline="")))
    expected_columns = [
        "id",
        "category",
        "name",
        "mandatory",
        "scope",
        "normative_source",
        "criteria_ref",
        "description",
        "fixture_id",
        "test_file",
        "artifact_path",
        "tolerance_id",
        "decision_refs",
        "allowed_terminal_statuses",
        "current_status",
        "numeric_parity",
        "evidence",
        "notes",
    ]
    if rows and list(rows[0].keys()) != expected_columns:
        fail("feature matrix columns do not match the frozen schema")
    # 129 -> 132: F052 (rcs), F053 (saving() on every estat subcommand) and
    # F054 (bal(pair)) were added deliberately. The count is frozen so rows
    # cannot appear or vanish unnoticed; update it in the same commit that
    # adds the row.
    if len(rows) != 132:
        fail(f"expected 132 feature-matrix rows, found {len(rows)}")
    for row in rows:
        allowed = set(row["allowed_terminal_statuses"].split("|"))
        allowed.add("contract-frozen")
        if row["current_status"] not in allowed:
            fail(f"{row['id']} has invalid status {row['current_status']}")
        if (
            args.phase == "contract"
            and row["mandatory"] == "true"
            and row["current_status"] != "contract-frozen"
        ):
            fail(f"{row['id']} mandatory row is not contract-frozen")
        rid = row["id"].lower()
        if row["id"].startswith(("F", "RT", "PY")):
            want = f"tests/fixtures/parity/{rid}"
            if row["artifact_path"] != want:
                fail(f"{row['id']} artifact_path is {row['artifact_path']}, expected {want}")
        if row["id"].startswith("JEL"):
            want = f"tests/fixtures/jel/{rid}"
            if row["artifact_path"] != want:
                fail(f"{row['id']} artifact_path is {row['artifact_path']}, expected {want}")

    source_inventory = list(
        csv.DictReader((ROOT / "tools/parity/source-test-inventory.csv").open(newline=""))
    )
    if len(source_inventory) != 57:
        fail(f"expected 57 source-test inventory rows, found {len(source_inventory)}")

    for lock in (ROOT / "tools/parity/reference-lock").glob("*.json"):
        with lock.open() as fh:
            json.load(fh)

    required = [
        "docs/parity-verification-playbook.md",
        "docs/conformance-profile-v1.md",
        "docs/verification-criteria.md",
        "docs/behavior-decisions.md",
        "docs/tolerance-registry-v1.md",
        "docs/stata-engineering-references.md",
        "docs/jel-replication-inventory.md",
        "docs/legacy-stata-compatibility.md",
        "docs/legacy-migration-guide.md",
        "inst/spec/fixture-schemas.md",
        "inst/spec/bench-budgets.yml",
        "reports/oracle-review.md",
        "reports/jel-replication-summary.md",
        "reports/engineering-audit.md",
        "PROVENANCE.md",
    ]
    for rel in required:
        if not (ROOT / rel).exists():
            fail(f"missing required contract artifact {rel}")

    print("contract validation ok")


if __name__ == "__main__":
    main()
