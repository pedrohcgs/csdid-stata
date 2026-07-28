#!/usr/bin/env python3
"""Generate PY013 Python integration inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py013"
SOURCE_FILE = "csdid/test_csdid/test_integration.py"
SOURCE_SHA256 = "dde98d8ba4d7084db5dcd2116f31855d558d8d042366ad22fbf69c40914ab4cb"
SOURCE_COMMIT = "555f28bc12fcafa9c099e6e5503a30a4c22fc89f"


def main() -> None:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    np.random.seed(42)
    n_units = 100
    n_periods = 5
    ids = np.repeat(np.arange(1, n_units + 1), n_periods)
    years = np.tile(np.arange(2003, 2008), n_units)
    groups_unit = np.concatenate([
        np.full(30, 2005),
        np.full(30, 2006),
        np.full(40, 0),
    ])
    groups = np.repeat(groups_unit, n_periods)
    treated = (years >= groups) & (groups > 0)
    y = np.random.randn(n_units * n_periods) + 0.8 * treated

    data = pd.DataFrame({"id": ids, "year": years, "group": groups, "y": y})
    data.to_csv(FIXTURE / "inputs/panel-data.csv", index=False)

    upstream_map = pd.DataFrame([
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_full_pipeline",
            "mapped_scenario": "full_public_pipeline",
            "assertion_family": "ATT rows finite, SE positive, and all public aggregations populated",
            "coverage_status": "mapped",
            "divergence_id": "",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_treatment_effect_detected",
            "mapped_scenario": "simple_positive_effect",
            "assertion_family": "simple aggregation overall ATT exceeds source threshold",
            "coverage_status": "mapped",
            "divergence_id": "",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_fast_mode_consistency",
            "mapped_scenario": "compute_inffunc_internal_path",
            "assertion_family": "Python internal compute_inffunc=False equality has no public Stata command analogue",
            "coverage_status": "approved-divergence",
            "divergence_id": "PY013-DIV001",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_all_estimation_methods",
            "mapped_scenario": "all_public_methods",
            "assertion_family": "dr, ipw, and reg commands return finite ATT estimates",
            "coverage_status": "mapped",
            "divergence_id": "",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_notyettreated_control",
            "mapped_scenario": "notyettreated_public_control",
            "assertion_family": "not-yet-treated control option returns finite ATT estimates",
            "coverage_status": "mapped",
            "divergence_id": "",
        },
    ])
    upstream_map.to_csv(FIXTURE / "expected/contract/upstream-test-map.csv", index=False)
    (FIXTURE / "expected/contract/upstream-test-map.json").write_text(
        json.dumps(upstream_map.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    divergences = pd.DataFrame([
        {
            "divergence_id": "PY013-DIV001",
            "source_file": SOURCE_FILE,
            "source_test": "test_fast_mode_consistency",
            "decision_ref": "D004",
            "reason": "The Python test compares internal ATTgt compute_inffunc=True versus compute_inffunc=False construction paths. Stata exposes no public command option that disables required influence-function construction while retaining the same postestimation contract, so the public command-surface equivalent is intentionally out of scope.",
            "replacement_coverage": "F032 and PY009 verify public fast/requested-fast equivalence. PY013 verifies the remaining public integration pipeline through ATT(g,t), aggregations, estimation methods, and not-yet-treated controls.",
        }
    ])
    divergences.to_csv(FIXTURE / "expected/contract/approved-divergence.csv", index=False)
    (FIXTURE / "expected/contract/approved-divergence.json").write_text(
        json.dumps(divergences.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    scenarios = pd.DataFrame([
        {
            "scenario": "python_integration_public_pipeline",
            "expected_att_rows": 8,
            "positive_threshold": 0.3,
            "methods": "dr;ipw;reg",
            "aggregation_types": "simple;group;dynamic;calendar",
        }
    ])
    scenarios.to_csv(FIXTURE / "expected/contract/scenarios.csv", index=False)

    manifest = {
        "matrix_id": "PY013",
        "fixture_family": "python-integration-public-pipeline",
        "normative_source": "Python csdid csdid/test_csdid/test_integration.py subordinate to R did 2.5.1 public command behavior",
        "source_commit": SOURCE_COMMIT,
        "decision_refs": ["D004", "D014"],
        "tolerance_ids": ["TOL002", "EXACT"],
        "inputs": [{"path": "inputs/panel-data.csv", "rows": int(data.shape[0]), "columns": int(data.shape[1])}],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py013/generate.py", "path": "tools/parity/generators/py013/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"seed": 42, "kind": "numpy.random.seed", "draws": "randn"},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/approved-divergence.csv", "schema": "approved-divergence"},
            {"path": "expected/contract/approved-divergence.json", "schema": "approved-divergence"},
            {"path": "expected/contract/scenarios.csv", "schema": "integration-scenario"},
        ],
        "comparison_plan": [
            {"actual": "Stata public csdid/csdid_stats pipeline", "expected": "source-test-map mapped scenarios", "tolerance_id": "EXACT", "key_columns": ["source_test"]},
            {"actual": "Stata simple aggregation overall ATT", "expected": "positive_threshold", "tolerance_id": "TOL002", "key_columns": ["scenario"]},
        ],
        "approved_divergence": {
            "id": "PY013-DIV001",
            "source_test": "test_fast_mode_consistency",
            "reason": "Python-only internal compute_inffunc=False construction path has no public Stata command analogue.",
        },
        "scope_note": "PY013 maps four of five Python integration tests to public Stata command-surface assertions and records one approved divergence for the Python-only internal compute_inffunc=False path. Public fast/requested-fast equivalence remains covered by F032 and PY009.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
