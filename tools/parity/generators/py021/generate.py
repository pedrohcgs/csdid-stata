#!/usr/bin/env python3
"""Generate PY021 simulation parity fixtures.

The R oracle (expected/r/ref_sim.csv) is produced by the sibling generate.R
against the did this repo pins, NOT copied from the Python package. Run that
first; this script reads it. The input datasets are frozen in the fixture, so
neither the oracle nor the inputs depend on a checkout outside this repo.
"""

from __future__ import annotations

import json
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py021"
SOURCE_FILE = "csdid/test_csdid/test_sim_parity.py"
SOURCE_SHA256 = "16316fc012ce07f4cf158f94fb093115f1757db0ca58fe079721d0c87800955a"
# Python csdid v0.4.1. test_sim_parity.py is byte-identical at 0.3.1 and 0.4.1,
# and the simulated inputs did not change between them.
SOURCE_COMMIT = "c37d39d"


def main() -> None:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/r").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    ref_path = FIXTURE / "expected/r/ref_sim.csv"
    if not ref_path.exists():
        raise SystemExit(
            "expected/r/ref_sim.csv is missing -- run "
            "Rscript tools/parity/generators/py021/generate.R first")
    ref = pd.read_csv(ref_path)
    scenarios = (
        ref[["dataset", "control", "est"]]
        .drop_duplicates()
        .sort_values(["dataset", "control", "est"])
        .reset_index(drop=True)
    )

    copied_inputs = []
    for dataset in sorted(ref["dataset"].unique()):
        dst = FIXTURE / "inputs" / f"{dataset}.csv"
        if not dst.exists():
            raise SystemExit(f"frozen input missing: {dst}")
        data = pd.read_csv(dst)
        copied_inputs.append({"path": f"inputs/{dataset}.csv", "rows": int(data.shape[0]), "columns": int(data.shape[1])})

    scenarios.to_csv(FIXTURE / "expected/contract/scenarios.csv", index=False)

    upstream_map = scenarios.copy()
    upstream_map.insert(0, "source_file", SOURCE_FILE)
    upstream_map.insert(1, "source_sha256", SOURCE_SHA256)
    upstream_map["source_test"] = (
        "test_sim_attgt_matches_r["
        + upstream_map["dataset"]
        + "-"
        + upstream_map["control"]
        + "-"
        + upstream_map["est"]
        + "]"
    )
    upstream_map["mapped_scenario"] = (
        upstream_map["dataset"] + "/" + upstream_map["control"] + "/" + upstream_map["est"]
    )
    upstream_map["assertion_family"] = "ATT(g,t) and analytical SE match R did simulation reference"
    upstream_map["coverage_status"] = "mapped"
    upstream_map["divergence_id"] = ""
    upstream_map = upstream_map[
        [
            "source_file",
            "source_sha256",
            "source_test",
            "mapped_scenario",
            "assertion_family",
            "coverage_status",
            "divergence_id",
            "dataset",
            "control",
            "est",
        ]
    ]
    upstream_map.to_csv(FIXTURE / "expected/contract/upstream-test-map.csv", index=False)
    (FIXTURE / "expected/contract/upstream-test-map.json").write_text(
        json.dumps(upstream_map.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    manifest = {
        "matrix_id": "PY021",
        "fixture_family": "python-simulation-r-parity",
        "normative_source": "R did 2.5.1",
        "source_commit": SOURCE_COMMIT,
        "source_sha256": SOURCE_SHA256,
        "decision_refs": ["D004"],
        "tolerance_ids": ["TOL002"],
        "inputs": copied_inputs,
        "generators": [
            {
                "runtime": "R",
                "command": "Rscript tools/parity/generators/py021/generate.R",
                "path": "tools/parity/generators/py021/generate.R",
                "note": "produces expected/r/ref_sim.csv; must run before generate.py",
            },
            {
                "runtime": "Python",
                "command": "python3 tools/parity/generators/py021/generate.py",
                "path": "tools/parity/generators/py021/generate.py",
            },
        ],
        "runtimes": [
            {"name": "Python", "version": "3", "package_versions": {"pandas": pd.__version__}}
        ],
        "rng": None,
        "expected_outputs": [
            {"path": "expected/r/ref_sim.csv", "schema": "python-r-simulation-reference"},
            {"path": "expected/contract/scenarios.csv", "schema": "simulation-scenarios"},
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
        ],
        "comparison_plan": [
            {
                "actual": "Stata csdid ATT(g,t) and analytical SE",
                "expected": "expected/r/ref_sim.csv",
                "tolerance_id": "TOL002",
                "key_columns": ["dataset", "control", "est", "group", "t"],
            }
        ],
        "approved_divergence": None,
        "scope_note": "PY021 maps all 24 parameterizations of Python test_sim_parity.py: six simulated panels x {nevertreated, notyettreated} x {dr, reg}, with xformla = ~X and analytical SEs. The R oracle in expected/r/ref_sim.csv is generated by tools/parity/generators/py021/generate.R against R did 2.5.1, from the input datasets frozen in this fixture, so it is reproducible from this repo alone. It was previously copied verbatim from the Python csdid package (csdid/test_csdid/r_ref/sim), whose reference was built elsewhere against did 2.5.0; regenerating locally moved no cell by more than 1.1e-13 in ATT or 3.0e-15 in SE, confirming these paths are untouched by the 2.5.1 fixes, but the numbers are now attributable to a did version this repo verifies.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
