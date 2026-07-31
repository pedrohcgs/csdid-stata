#!/usr/bin/env python3
"""Generate PY006 compute_inffunc inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py006"
SOURCE_FILE = "csdid/test_csdid/test_compute_inffunc.py"
SOURCE_SHA256 = "52ef77c7e10318364b3a2a6df35e5452413c5e5f4808e8206f00cfbddf0bca4c"
SOURCE_COMMIT = "555f28bc12fcafa9c099e6e5503a30a4c22fc89f"


def main() -> None:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    np.random.seed(42)
    n_units = 50
    n_periods = 4
    ids = np.repeat(np.arange(1, n_units + 1), n_periods)
    years = np.tile(np.arange(2003, 2007), n_units)
    groups_unit = np.concatenate([
        np.full(20, 2004),
        np.full(15, 2006),
        np.full(15, 0),
    ])
    groups = np.repeat(groups_unit, n_periods)
    treated = (years >= groups) & (groups > 0)
    y = np.random.randn(n_units * n_periods) + 0.5 * treated
    data = pd.DataFrame({"id": ids, "year": years, "group": groups, "y": y})
    data.to_csv(FIXTURE / "inputs/sample-data.csv", index=False)

    upstream_map = pd.DataFrame([
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_point_estimates_match",
            "mapped_scenario": "compute_inffunc_false_point_estimates",
            "assertion_family": "Python internal point-estimates-only path has no public Stata analogue",
            "coverage_status": "approved-divergence",
            "divergence_id": "PY006-DIV001",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_se_is_nan_without_inffunc",
            "mapped_scenario": "compute_inffunc_false_missing_se",
            "assertion_family": "Python internal no-IF path intentionally suppresses SEs; Stata public results keep SEs",
            "coverage_status": "approved-divergence",
            "divergence_id": "PY006-DIV001",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_aggte_blocked_without_inffunc",
            "mapped_scenario": "compute_inffunc_false_blocks_aggte",
            "assertion_family": "Python internal no-IF path blocks aggregation; Stata public path keeps IFs for postestimation",
            "coverage_status": "approved-divergence",
            "divergence_id": "PY006-DIV001",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_faster_without_inffunc",
            "mapped_scenario": "compute_inffunc_false_fast_artifact_skip",
            "assertion_family": "Python internal artifact-suppression contract has no public Stata analogue",
            "coverage_status": "approved-divergence",
            "divergence_id": "PY006-DIV001",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_default_is_true",
            "mapped_scenario": "stata_default_if_backed_public_results",
            "assertion_family": "default public estimation computes influence functions, finite SEs, and postestimation",
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
            "divergence_id": "PY006-DIV001",
            "source_file": SOURCE_FILE,
            "source_tests": "test_point_estimates_match; test_se_is_nan_without_inffunc; test_aggte_blocked_without_inffunc; test_faster_without_inffunc",
            "decision_ref": "D004",
            "reason": "Python exposes an internal compute_inffunc=False construction path for point-estimates-only runs. The Stata public command surface intentionally maintains influence functions for standard errors, saved RIF artifacts, and csdid_stats/csdid_estat postestimation, and has no option to produce a no-IF object.",
            "replacement_coverage": "The PY006 gate verifies that the default Stata public command computes e(inffunc), finite SEs, and aggregation postestimation, and rejects a compute_inffunc() option as unsupported. F032/PY009 cover public fast/requested-fast equivalence.",
        }
    ])
    divergences.to_csv(FIXTURE / "expected/contract/approved-divergence.csv", index=False)
    (FIXTURE / "expected/contract/approved-divergence.json").write_text(
        json.dumps(divergences.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    manifest = {
        "matrix_id": "PY006",
        "fixture_family": "python-compute-inffunc",
        "normative_source": "Python csdid csdid/test_csdid/test_compute_inffunc.py subordinate to R did 2.5.1 public command behavior",
        "source_commit": SOURCE_COMMIT,
        "decision_refs": ["D004", "D014"],
        "tolerance_ids": ["EXACT", "TOL002"],
        "inputs": [{"path": "inputs/sample-data.csv", "rows": int(data.shape[0]), "columns": int(data.shape[1])}],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py006/generate.py", "path": "tools/parity/generators/py006/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"seed": 42, "kind": "numpy.random.seed", "draws": "randn"},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/approved-divergence.csv", "schema": "approved-divergence"},
            {"path": "expected/contract/approved-divergence.json", "schema": "approved-divergence"},
        ],
        "comparison_plan": [
            {"actual": "Stata default public IF-backed command results", "expected": "mapped default-is-true scenario", "tolerance_id": "EXACT", "key_columns": ["source_test"]},
        ],
        "approved_divergence": {
            "id": "PY006-DIV001",
            "source_tests": ["test_point_estimates_match", "test_se_is_nan_without_inffunc", "test_aggte_blocked_without_inffunc", "test_faster_without_inffunc"],
            "reason": "Python-only compute_inffunc=False point-estimates-only object path has no public Stata command analogue.",
        },
        "scope_note": "PY006 maps the default compute_inffunc=True assertion to Stata's public IF-backed command contract and records approved divergence for Python's internal compute_inffunc=False path. Stata keeps influence functions available for SEs, saved RIF artifacts, and public postestimation.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
