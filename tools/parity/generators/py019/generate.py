#!/usr/bin/env python3
"""Generate PY019 Python-vs-R parity inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py019"
SOURCE_FILE = "csdid/test_csdid/test_r_parity.py"
SOURCE_SHA256 = "59eda1cbb9b794dc8bfdd3b15d3695ab2fa9d05e67174feee11e6b026f7f95bd"
# Python csdid v0.4.1.
SOURCE_COMMIT = "c37d39d"
# The Wald pre-test scenarios are inherited from a second upstream file.
PRETEST_FILE = "csdid/test_csdid/test_pretest.py"
PRETEST_SHA256 = "7631743afb620bbc00f4e8983792910f581391ce35d7fc30a0888a5ff94e0941"


SCENARIOS = ["mpdta_nev_dr", "mpdta_nyt_dr", "mpdta_nev_reg_cov", "mpdta_nev_ipw", "sim_nev_dr"]
AGG_TYPES = ["group", "dynamic", "calendar"]
FIXWEIGHT_TAGS = ["none", "base_period", "first_period", "varying"]
FACTOR_MODES = ["standard", "fast"]
GAP_SCENARIOS = ["rc", "universal", "anticipation1", "weighted", "clustered"]


def source_row(source_test: str, scenario: str, assertion: str) -> dict[str, str]:
    return {
        "source_file": SOURCE_FILE,
        "source_sha256": SOURCE_SHA256,
        "source_test": source_test,
        "mapped_scenario": scenario,
        "assertion_family": assertion,
        "coverage_status": "mapped",
        "divergence_id": "",
    }


def pretest_row(source_test: str, scenario: str, assertion: str) -> dict[str, str]:
    return {
        "source_file": PRETEST_FILE,
        "source_sha256": PRETEST_SHA256,
        "source_test": source_test,
        "mapped_scenario": scenario,
        "assertion_family": assertion,
        "coverage_status": "mapped",
        "divergence_id": "",
    }


PRETEST_ROWS = [
    ("test_pretest_matches_R",
     "5 scenarios vs expected/r/ref_pretest.csv", "wald-stat-and-pvalue-vs-r"),
    ("test_pretest_finite_when_pre_cells_exist",
     "mpdta_nev_dr", "wald-stat-and-pvalue-vs-r"),
    ("test_pretest_none_when_no_pre_cells",
     "no pre-treatment cells", "wald-absent"),
    ("test_pretest_suppressed_under_clustered_bootstrap",
     "clustered bootstrap", "wald-absent"),
    ("test_pretest_computed_under_clustered_analytic",
     "clustered analytical", "wald-stat-and-pvalue-vs-r"),
    ("test_pretest_absent_without_inffunc",
     "no influence function", "wald-absent"),
]


def main() -> None:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/r").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/r/sim").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    # Frozen in this fixture; no longer copied from a checkout outside the repo.
    input_files = [
        "mpdta.csv", "sim_data.csv", "mpdta_tvw.csv",
        "factor_cov.csv", "mpdta_extra.csv",
    ]
    # Generated locally by the sibling generate.R against the pinned did, not
    # copied from the Python package. See that script for why.
    ref_files = [
        "ref_attgt.csv", "ref_aggte.csv", "ref_pretest.csv", "ref_fixweights.csv",
        "sim/ref_factor.csv", "sim/ref_gaps.csv",
    ]

    inputs = []
    for name in input_files:
        dst = FIXTURE / "inputs" / name
        if not dst.exists():
            raise SystemExit(f"frozen input missing: {dst}")
        d = pd.read_csv(dst)
        inputs.append({"path": f"inputs/{name}", "rows": int(d.shape[0]), "columns": int(d.shape[1])})

    expected_outputs = []
    for name in ref_files:
        dst = FIXTURE / "expected/r" / name
        if not dst.exists():
            raise SystemExit(
                f"{dst} is missing -- run "
                "Rscript tools/parity/generators/py019/generate.R first")
        expected_outputs.append({"path": f"expected/r/{name}", "schema": "r-reference"})

    rows: list[dict[str, str]] = []
    scenarios: list[dict[str, str]] = []

    for scn in SCENARIOS:
        rows.append(source_row(f"test_attgt_matches_r[{scn}]", scn, "ATT(g,t) point estimates and analytical SEs match R did references"))
        scenarios.append({"scenario": scn, "family": "attgt", "expected_behavior": "ATT(g,t) and SE match R reference"})

    for scn in SCENARIOS:
        rows.append(source_row(f"test_aggte_overall_matches_r[{scn}]", scn, "simple/group/dynamic/calendar overall ATT and SE match R did references"))
        scenarios.append({"scenario": scn, "family": "aggte-overall", "expected_behavior": "overall aggregation ATT and SE match R reference"})

    for scn in SCENARIOS:
        for aggtype in AGG_TYPES:
            scenario = f"{scn}/{aggtype}"
            rows.append(source_row(f"test_aggte_egt_matches_r[{scn}-{aggtype}]", scenario, "group/dynamic/calendar event-level ATT and SE match R did references"))
            scenarios.append({"scenario": scenario, "family": "aggte-egt", "expected_behavior": "event/group/calendar aggregation rows match R reference"})

    for tag in FIXWEIGHT_TAGS:
        rows.append(source_row(f"test_fix_weights_matches_r[{tag}]", tag, "time-varying weight ATT(g,t) matches R did references"))
        scenarios.append({"scenario": tag, "family": "fix-weights", "expected_behavior": "ATT(g,t) under fix_weights mode matches R reference"})

    for mode in FACTOR_MODES:
        rows.append(source_row(f"test_factor_covariate_matches_r[{mode}]", mode, "factor covariate ATT(g,t) and SE match R did references"))
        scenarios.append({"scenario": mode, "family": "factor-covariate", "expected_behavior": "factor-covariate ATT(g,t) and SE match R reference"})

    for scn in GAP_SCENARIOS:
        rows.append(source_row(f"test_gap_scenarios_match_r[{scn}]", scn, "repeated cross-section, universal base, anticipation, weighted, and clustered gaps match R did references"))
        scenarios.append({"scenario": scn, "family": "gap-scenarios", "expected_behavior": "gap-scenario ATT(g,t) and SE match R reference"})

    for t, scn, fam in PRETEST_ROWS:
        rows.append(pretest_row(t, scn, fam))

    upstream = pd.DataFrame(rows)
    upstream.to_csv(FIXTURE / "expected/contract/upstream-test-map.csv", index=False)
    (FIXTURE / "expected/contract/upstream-test-map.json").write_text(
        json.dumps(rows, indent=2), encoding="utf-8"
    )
    pd.DataFrame(scenarios).drop_duplicates().to_csv(
        FIXTURE / "expected/contract/scenarios.csv", index=False
    )

    expected_outputs.extend([
        {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
        {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
        {"path": "expected/contract/scenarios.csv", "schema": "source-scenario-map"},
    ])

    manifest = {
        "matrix_id": "PY019",
        "fixture_family": "python-r-parity",
        "normative_source": "R did 2.5.1",
        "source_commit": SOURCE_COMMIT,
        "source_sha256": SOURCE_SHA256,
        "decision_refs": ["D004"],
        "tolerance_ids": ["TOL002", "TOL004"],
        "inputs": inputs,
        "generators": [
            {
                "runtime": "R",
                "command": "Rscript tools/parity/generators/py019/generate.R",
                "path": "tools/parity/generators/py019/generate.R",
                "note": "produces the five expected/r references; must run before generate.py",
            },
            {
                "runtime": "Python",
                "command": "python3 tools/parity/generators/py019/generate.py",
                "path": "tools/parity/generators/py019/generate.py",
            }
        ],
        "runtimes": [
            {"name": "Python", "version": "3", "package_versions": {"pandas": pd.__version__}}
        ],
        "rng": None,
        "expected_outputs": expected_outputs,
        "comparison_plan": [
            {
                "actual": "Stata csdid ATT(g,t), analytical SEs, and aggregation output",
                "expected": "expected/r/*.csv",
                "tolerance_id": "TOL002/TOL004",
                "key_columns": ["scenario", "group", "t", "type", "egt"],
            }
        ],
        "approved_divergence": None,
        "scope_note": "PY019 maps all 36 public parameterizations in Python test_r_parity.py: ATT(g,t), overall and event-level aggregations, time-varying fix_weights modes, factor-covariate parity, and repeated-cross-section/universal-base/anticipation/weighted/clustered gap scenarios.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
