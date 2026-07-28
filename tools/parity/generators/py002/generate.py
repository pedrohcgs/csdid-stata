#!/usr/bin/env python3
"""Generate PY002 analytical clustered-SE inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py002"
SOURCE_FILE = "csdid/test_csdid/test_analytical_cluster_se.py"
SOURCE_SHA256 = "ecc53965a392860c01430282bb766dca041a86329b7d3ffcbbb3493c8fa8fb29"
SOURCE_COMMIT = "555f28bc12fcafa9c099e6e5503a30a4c22fc89f"


def make_clustered_data() -> pd.DataFrame:
    np.random.seed(42)
    n_clusters = 10
    units_per_cluster = 5
    n_units = n_clusters * units_per_cluster
    n_periods = 4

    cluster_id = np.repeat(np.arange(1, n_clusters + 1), units_per_cluster)
    groups_cluster = np.concatenate([
        np.full(3, 2005),
        np.full(3, 2006),
        np.full(4, 0),
    ])
    groups_unit = np.repeat(groups_cluster, units_per_cluster)

    ids = np.repeat(np.arange(1, n_units + 1), n_periods)
    years = np.tile(np.arange(2003, 2007), n_units)
    groups = np.repeat(groups_unit, n_periods)
    clusters = np.repeat(cluster_id, n_periods)

    cluster_effect = np.random.randn(n_clusters)
    y = np.random.randn(n_units * n_periods)
    y += np.repeat(np.repeat(cluster_effect, units_per_cluster), n_periods)
    treated = (years >= groups) & (groups > 0)
    y[treated] += 0.5

    return pd.DataFrame({
        "id": ids,
        "year": years,
        "group": groups,
        "y": y,
        "cluster": clusters,
    })


def main() -> None:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    data = make_clustered_data()
    data.to_csv(FIXTURE / "inputs/clustered-data.csv", index=False)

    upstream_map = pd.DataFrame([
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_analytical_clustered_se_runs",
            "mapped_scenario": "analytical_clustered_se_runs",
            "assertion_family": "analytical clustered SEs run without bootstrap and finite SEs are positive",
            "coverage_status": "mapped",
            "divergence_id": "",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_analytical_clustered_se_matches_bootstrap",
            "mapped_scenario": "analytical_clustered_se_matches_bootstrap",
            "assertion_family": "clustered analytical SEs and clustered bootstrap SEs broadly agree",
            "coverage_status": "mapped",
            "divergence_id": "",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_aggte_with_analytical_clustered_se",
            "mapped_scenario": "aggte_simple_with_analytical_clustered_se",
            "assertion_family": "simple aggregation works and returns positive clustered analytical SE",
            "coverage_status": "mapped",
            "divergence_id": "",
        },
    ])
    upstream_map.to_csv(FIXTURE / "expected/contract/upstream-test-map.csv", index=False)
    (FIXTURE / "expected/contract/upstream-test-map.json").write_text(
        json.dumps(upstream_map.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    scenarios = pd.DataFrame([
        {
            "scenario": "analytical_clustered_se",
            "input": "clustered-data.csv",
            "n_clusters": int(data["cluster"].nunique()),
            "bootstrap_biters": 1499,
            "bootstrap_seed": 20250202,
            "bootstrap_rtol": 0.30,
        }
    ])
    scenarios.to_csv(FIXTURE / "expected/contract/scenarios.csv", index=False)

    manifest = {
        "matrix_id": "PY002",
        "fixture_family": "python-analytical-cluster-se",
        "normative_source": "Python csdid csdid/test_csdid/test_analytical_cluster_se.py subordinate to R did 2.5.1 clustered inference behavior",
        "source_commit": SOURCE_COMMIT,
        "decision_refs": ["D004", "D013"],
        "tolerance_ids": ["TOL002", "TOL003", "EXACT"],
        "inputs": [{"path": "inputs/clustered-data.csv", "rows": int(data.shape[0]), "columns": int(data.shape[1])}],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py002/generate.py", "path": "tools/parity/generators/py002/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"seed": 42, "kind": "numpy.random.seed", "bootstrap_draw_parity": False},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/scenarios.csv", "schema": "analytical-cluster-se-scenario"},
        ],
        "comparison_plan": [
            {"actual": "Stata analytical clustered SE finite-positive checks", "expected": "mapped Python run assertion", "tolerance_id": "TOL002", "key_columns": ["source_test"]},
            {"actual": "Stata clustered bootstrap-vs-analytical SE agreement", "expected": "mapped Python bootstrap comparison", "tolerance_id": "TOL003", "key_columns": ["scenario"]},
            {"actual": "Stata simple aggregation clustered SE", "expected": "mapped Python aggte assertion", "tolerance_id": "TOL002", "key_columns": ["source_test"]},
        ],
        "approved_divergence": None,
        "scope_note": "PY002 maps all three Python analytical clustered-SE assertions: clustered analytical ATT(g,t) SEs run and are positive, clustered bootstrap SEs broadly agree with analytical clustered SEs under the recorded stochastic tolerance, and simple aggregation returns a positive analytical clustered SE.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
