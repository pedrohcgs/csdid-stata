#!/usr/bin/env python3
"""Generate PY015 clustered multiplier-bootstrap inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py015"
SOURCE_FILE = "csdid/test_csdid/test_mboot_cluster.py"
SOURCE_SHA256 = "1cfd3d4ecf4bf5b62b81a3b0096964664628398ad8d68b9c8183efb3f020d07c"
SOURCE_COMMIT = "555f28bc12fcafa9c099e6e5503a30a4c22fc89f"


def make_clustered(seed: int, balanced: bool, groups: int = 40) -> pd.DataFrame:
    """Mirror the upstream Python _make_clustered helper."""

    rng = np.random.default_rng(seed)
    sizes = np.full(groups, 4) if balanced else np.tile([1, 2, 3, 8], groups // 4 + 1)[:groups]
    n_units = int(sizes.sum())
    clusters = np.repeat(np.arange(1, groups + 1), sizes)
    a = rng.standard_normal(groups)[clusters - 1]
    nu = rng.standard_normal(n_units)
    first_treat = np.where(rng.random(n_units) < 0.5, 2, 0)

    rows = []
    for i in range(n_units):
        for t in [1, 2, 3]:
            te = 1.0 if first_treat[i] == 2 and t >= 2 else 0.0
            y = a[i] + nu[i] + 0.5 * t + te + rng.standard_normal()
            rows.append((i + 1, t, int(clusters[i]), int(first_treat[i]), y))

    return pd.DataFrame(rows, columns=["id", "t", "cl", "g", "y"]).sort_values(["id", "t"])


def main() -> None:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    unbalanced = make_clustered(101, balanced=False)
    balanced = make_clustered(202, balanced=True)
    invalid = make_clustered(303, balanced=False)
    invalid["cl2"] = invalid["cl"]

    unbalanced.to_csv(FIXTURE / "inputs/clustered-unbalanced.csv", index=False)
    balanced.to_csv(FIXTURE / "inputs/clustered-balanced.csv", index=False)
    invalid.to_csv(FIXTURE / "inputs/clustered-invalid.csv", index=False)

    upstream_map = pd.DataFrame([
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_clustered_mboot_unbalanced_runs",
            "mapped_scenario": "clustered_mboot_unbalanced",
            "assertion_family": "clustered multiplier bootstrap produces at least one finite positive SE with unbalanced clusters",
            "coverage_status": "mapped",
            "divergence_id": "",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_clustered_mboot_balanced_runs",
            "mapped_scenario": "clustered_mboot_balanced",
            "assertion_family": "clustered multiplier bootstrap produces at least one finite positive SE with balanced clusters",
            "coverage_status": "mapped",
            "divergence_id": "",
        },
        {
            "source_file": SOURCE_FILE,
            "source_sha256": SOURCE_SHA256,
            "source_test": "test_clustering_validation_rejects_multiple_clustervars",
            "mapped_scenario": "reject_multiple_bootstrap_cluster_variables",
            "assertion_family": "public bootstrap cluster declaration rejects multiple cluster variables",
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
            "scenario": "clustered_mboot_unbalanced",
            "input": "clustered-unbalanced.csv",
            "seed": 101,
            "balanced_clusters": False,
            "n_clusters": int(unbalanced["cl"].nunique()),
            "biters": 399,
            "stata_seed": 20251501,
        },
        {
            "scenario": "clustered_mboot_balanced",
            "input": "clustered-balanced.csv",
            "seed": 202,
            "balanced_clusters": True,
            "n_clusters": int(balanced["cl"].nunique()),
            "biters": 399,
            "stata_seed": 20251502,
        },
        {
            "scenario": "reject_multiple_bootstrap_cluster_variables",
            "input": "clustered-invalid.csv",
            "seed": 303,
            "balanced_clusters": False,
            "n_clusters": int(invalid["cl"].nunique()),
            "biters": 17,
            "stata_seed": 20251503,
        },
    ])
    scenarios.to_csv(FIXTURE / "expected/contract/scenarios.csv", index=False)

    manifest = {
        "matrix_id": "PY015",
        "fixture_family": "python-clustered-multiplier-bootstrap",
        "normative_source": "Python csdid csdid/test_csdid/test_mboot_cluster.py subordinate to R did 2.5.1 clustered multiplier-bootstrap behavior",
        "source_commit": SOURCE_COMMIT,
        "decision_refs": ["D004", "D013"],
        "tolerance_ids": ["TOL003", "EXACT"],
        "inputs": [
            {"path": "inputs/clustered-unbalanced.csv", "rows": int(unbalanced.shape[0]), "columns": int(unbalanced.shape[1])},
            {"path": "inputs/clustered-balanced.csv", "rows": int(balanced.shape[0]), "columns": int(balanced.shape[1])},
            {"path": "inputs/clustered-invalid.csv", "rows": int(invalid.shape[0]), "columns": int(invalid.shape[1])},
        ],
        "generators": [
            {"runtime": "Python", "command": "python3 tools/parity/generators/py015/generate.py", "path": "tools/parity/generators/py015/generate.py"},
        ],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"kind": "numpy.random.default_rng", "seeds": [101, 202, 303], "bootstrap_draw_parity": False},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/scenarios.csv", "schema": "clustered-bootstrap-scenarios"},
        ],
        "comparison_plan": [
            {"actual": "Stata clustered wboot finite-SE behavior", "expected": "mapped Python run assertions", "tolerance_id": "TOL003", "key_columns": ["scenario"]},
            {"actual": "Stata multiple bootstrap cluster validation", "expected": "mapped Python exception assertion", "tolerance_id": "EXACT", "key_columns": ["source_test"]},
        ],
        "approved_divergence": None,
        "scope_note": "PY015 maps all three Python test_mboot_cluster.py assertions: clustered multiplier bootstrap runs with finite positive SEs for unbalanced and balanced cluster designs, and multiple/list-valued bootstrap cluster declarations are rejected. F035 guards exact seeded BMisc/R rademacher multiplier-stream parity; PY015 remains an inherited Python cluster-bootstrap smoke fixture rather than a raw-draw export fixture.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
