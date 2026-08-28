#!/usr/bin/env python3
"""Generate PY005 clustered bootstrap behavior fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py005"
SOURCE_FILE = "csdid/test_csdid/test_clustered.py"
SOURCE_SHA256 = "0290932d54694d4010912249202cd7521df35836c6c1a388e891ff4a71816cfd"
SOURCE_COMMIT = "c37d39d5d0c28c345f2950db734d7a0f5e02aceb"


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
        "unit_cluster": ids,
    })


def make_time_varying_cluster_data() -> pd.DataFrame:
    np.random.seed(42)
    n_units = 20
    n_periods = 4
    ids = np.repeat(np.arange(1, n_units + 1), n_periods)
    years = np.tile(np.arange(2003, 2007), n_units)
    groups_unit = np.concatenate([np.full(10, 2005), np.full(10, 0)])
    groups = np.repeat(groups_unit, n_periods)
    y = np.random.randn(n_units * n_periods)
    tv_cluster = (ids * 10 + years) % 5
    return pd.DataFrame({
        "id": ids,
        "year": years,
        "group": groups,
        "y": y,
        "tv_cluster": tv_cluster,
    })


def main() -> None:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    clustered = make_clustered_data()
    tv = make_time_varying_cluster_data()
    clustered.to_csv(FIXTURE / "inputs/clustered-data.csv", index=False)
    tv.to_csv(FIXTURE / "inputs/time-varying-cluster.csv", index=False)

    upstream_map = pd.DataFrame([
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_clustered_bootstrap_runs",
            "mapped_scenario": "clustered_bootstrap_runs",
            "assertion_family": "clustered multiplier bootstrap runs and finite valid SEs are positive",
            "coverage_status": "mapped",
            "divergence_id": "",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_clustered_se_differs_from_unclustered",
            "mapped_scenario": "clustered_se_differs_from_unclustered",
            "assertion_family": "clustered bootstrap SEs differ from unclustered bootstrap SEs",
            "coverage_status": "mapped",
            "divergence_id": "",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_clustered_se_differs_in_magnitude",
            "mapped_scenario": "clustered_se_differs_in_magnitude",
            "assertion_family": "clustered bootstrap SEs are positive and not identical to unclustered SEs",
            "coverage_status": "mapped",
            "divergence_id": "",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_unit_level_cluster_similar_to_no_cluster",
            "mapped_scenario": "unit_level_cluster_similar_to_no_cluster",
            "assertion_family": "unit-level clustering gives bootstrap SEs close to no-cluster bootstrap SEs",
            "coverage_status": "mapped",
            "divergence_id": "",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_time_varying_cluster_rejected",
            "mapped_scenario": "time_varying_cluster_rejected",
            "assertion_family": "time-varying cluster variables are rejected",
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
            "scenario": "clustered_bootstrap_runs",
            "input": "clustered-data.csv",
            "biters": 200,
            "seed": 20250501,
            "n_clusters": int(clustered["cluster"].nunique()),
        },
        {
            "scenario": "clustered_vs_unclustered",
            "input": "clustered-data.csv",
            "biters": 500,
            "seed": 20250502,
            "different_rtol": 0.10,
        },
        {
            "scenario": "unit_cluster_vs_unclustered",
            "input": "clustered-data.csv",
            "biters": 500,
            "seed": 20250503,
            "similar_rtol": 0.30,
        },
        {
            "scenario": "time_varying_cluster_rejected",
            "input": "time-varying-cluster.csv",
            "biters": 50,
            "seed": 20250504,
        },
    ])
    scenarios.to_csv(FIXTURE / "expected/contract/scenarios.csv", index=False)

    manifest = {
        "matrix_id": "PY005",
        "fixture_family": "python-clustered-bootstrap-behavior",
        "normative_source": "Python csdid csdid/test_csdid/test_clustered.py subordinate to R did 2.5.1 clustered multiplier-bootstrap behavior",
        "source_commit": SOURCE_COMMIT,
        "decision_refs": ["D004", "D013"],
        "tolerance_ids": ["TOL003", "EXACT"],
        "inputs": [
            {"path": "inputs/clustered-data.csv", "rows": int(clustered.shape[0]), "columns": int(clustered.shape[1])},
            {"path": "inputs/time-varying-cluster.csv", "rows": int(tv.shape[0]), "columns": int(tv.shape[1])},
        ],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py005/generate.py", "path": "tools/parity/generators/py005/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"seed": 42, "kind": "numpy.random.seed", "bootstrap_draw_parity": False},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/scenarios.csv", "schema": "clustered-bootstrap-scenarios"},
        ],
        "comparison_plan": [
            {"actual": "Stata clustered bootstrap finite-SE behavior", "expected": "mapped Python clustered run assertion", "tolerance_id": "TOL003", "key_columns": ["source_test"]},
            {"actual": "Stata clustered/no-cluster bootstrap SE contrasts", "expected": "mapped Python contrast assertions", "tolerance_id": "TOL003", "key_columns": ["scenario"]},
            {"actual": "Stata time-varying cluster rejection", "expected": "mapped Python validation assertion", "tolerance_id": "EXACT", "key_columns": ["source_test"]},
        ],
        "approved_divergence": None,
        "scope_note": "PY005 maps all five Python test_clustered.py assertions: clustered multiplier bootstrap runs with positive valid SEs, clustered and unclustered bootstrap SEs differ, unit-level clustering is close to no-cluster bootstrap, and time-varying cluster variables are rejected.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
