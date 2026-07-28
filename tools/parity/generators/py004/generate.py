#!/usr/bin/env python3
"""Generate PY004 cluster-analytic inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py004"
SOURCE_FILE = "csdid/test_csdid/test_cluster_analytic.py"
SOURCE_SHA256 = "5c40c7f849bf0363d27bd5fdafb23417cc7b0941c4109eb6a641d95c11c8a178"
SOURCE_COMMIT = "555f28bc12fcafa9c099e6e5503a30a4c22fc89f"


def make_clustered_shocks(seed: int, groups: int = 50) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    sizes = np.tile([1, 2, 4, 10], groups // 4 + 1)[:groups]
    n_units = int(sizes.sum())
    clusters = np.repeat(np.arange(1, groups + 1), sizes)
    alpha = rng.standard_normal(groups)[clusters - 1]
    nu = rng.standard_normal(n_units)
    periods = np.arange(1, 5)
    eta = rng.standard_normal((groups, 4)) * 1.5
    first_treat = rng.choice([2, 3, 0], size=groups, p=[0.34, 0.33, 0.33])[clusters - 1]

    rows = []
    for i in range(n_units):
        for t in periods:
            te = 1.0 if first_treat[i] != 0 and t >= first_treat[i] else 0.0
            y = alpha[i] + nu[i] + 0.3 * t + eta[clusters[i] - 1, t - 1] + te + rng.standard_normal()
            rows.append((i + 1, int(t), int(clusters[i]), int(first_treat[i]), y))

    return pd.DataFrame(rows, columns=["id", "t", "cl", "g", "y"]).sort_values(["id", "t"])


def map_row(source_test: str, scenario: str, assertion: str) -> dict[str, str]:
    return {
        "source_file": SOURCE_FILE,
        "source_sha256": SOURCE_SHA256,
        "source_test": source_test,
        "mapped_scenario": scenario,
        "assertion_family": assertion,
        "coverage_status": "mapped",
        "divergence_id": "",
    }


def main() -> None:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    seeds = [404, 505, 606, 707, 808]
    data_by_seed = {seed: make_clustered_shocks(seed) for seed in seeds}
    for seed, data in data_by_seed.items():
        data.to_csv(FIXTURE / f"inputs/clustered-shocks-{seed}.csv", index=False)

    rows = [
        map_row("test_clustered_se_differs_from_iid", "clustered_vs_iid_404", "clustered analytical SEs differ from iid analytical SEs"),
        map_row("test_clustered_se_runs_without_errors", "clustered_runs_505", "clustered analytical SEs run and at least one finite SE is positive"),
        map_row("test_analytical_cluster_se_vs_bootstrap", "panel_bootstrap_vs_analytical_505", "panel clustered bootstrap SEs broadly agree with analytical clustered SEs"),
        map_row("test_clustered_se_repeated_cross_sections", "rc_nofast_vs_fast_808", "repeated-cross-section clustered analytical SEs match requested-fast optimized path"),
        map_row("test_clustered_bootstrap_vs_analytical_rcs", "rc_bootstrap_vs_analytical_606", "repeated-cross-section clustered bootstrap SEs broadly agree with analytical clustered SEs"),
    ]
    for typec in ["simple", "group", "dynamic"]:
        rows.append(map_row("test_clustered_se_through_aggte", f"aggte_reg_{typec}_505", f"clustered analytical SE propagates through aggte type {typec}"))
    for method in ["dr", "reg", "ipw"]:
        rows.append(map_row("test_clustered_se_runs_all_methods", f"runs_{method}_606", f"clustered analytical SE runs with method {method}"))
    for method in ["dr", "reg", "ipw"]:
        for typec in ["simple", "group", "dynamic"]:
            rows.append(map_row("test_clustered_se_through_aggte_all_methods", f"aggte_{method}_{typec}_707", f"clustered analytical SE propagates through {typec} aggregation with method {method}"))

    upstream_map = pd.DataFrame(rows)
    upstream_map.to_csv(FIXTURE / "expected/contract/upstream-test-map.csv", index=False)
    (FIXTURE / "expected/contract/upstream-test-map.json").write_text(
        json.dumps(upstream_map.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    scenarios = pd.DataFrame([
        {"scenario": "clustered_vs_iid_404", "input": "clustered-shocks-404.csv", "method": "reg", "different_rtol": 0.01},
        {"scenario": "clustered_runs_505", "input": "clustered-shocks-505.csv", "method": "reg"},
        {"scenario": "panel_bootstrap_vs_analytical_505", "input": "clustered-shocks-505.csv", "method": "reg", "biters": 1499, "seed": 20250401, "bootstrap_rtol": 0.35},
        {"scenario": "rc_nofast_vs_fast_808", "input": "clustered-shocks-808.csv", "method": "reg"},
        {"scenario": "rc_bootstrap_vs_analytical_606", "input": "clustered-shocks-606.csv", "method": "reg", "biters": 1499, "seed": 20250402, "bootstrap_rtol": 0.35},
        {"scenario": "all_methods_runs_606", "input": "clustered-shocks-606.csv", "methods": "dr;reg;ipw"},
        {"scenario": "all_methods_aggte_707", "input": "clustered-shocks-707.csv", "methods": "dr;reg;ipw", "types": "simple;group;dynamic"},
    ])
    scenarios.to_csv(FIXTURE / "expected/contract/scenarios.csv", index=False)

    manifest = {
        "matrix_id": "PY004",
        "fixture_family": "python-cluster-analytic",
        "normative_source": "Python csdid csdid/test_csdid/test_cluster_analytic.py subordinate to R did 2.5.1 clustered inference behavior",
        "source_commit": SOURCE_COMMIT,
        "decision_refs": ["D004", "D013"],
        "tolerance_ids": ["TOL002", "TOL003", "EXACT"],
        "inputs": [
            {"path": f"inputs/clustered-shocks-{seed}.csv", "rows": int(data_by_seed[seed].shape[0]), "columns": int(data_by_seed[seed].shape[1])}
            for seed in seeds
        ],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py004/generate.py", "path": "tools/parity/generators/py004/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"kind": "numpy.random.default_rng", "seeds": seeds, "bootstrap_draw_parity": False},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/scenarios.csv", "schema": "cluster-analytic-scenarios"},
        ],
        "comparison_plan": [
            {"actual": "Stata clustered analytical SE run/contrast/aggregation checks", "expected": "mapped Python cluster analytic assertions", "tolerance_id": "TOL002", "key_columns": ["source_test"]},
            {"actual": "Stata clustered bootstrap-vs-analytical SE checks", "expected": "mapped Python slow bootstrap assertions", "tolerance_id": "TOL003", "key_columns": ["scenario"]},
        ],
        "approved_divergence": None,
        "scope_note": "PY004 maps all public assertions and parameterizations in Python test_cluster_analytic.py: clustered-vs-iid analytical SE differences, clustered analytical runs, simple/group/dynamic aggregation propagation, panel and repeated-cross-section bootstrap-vs-analytical broad agreement, repeated-cross-section requested-fast optimized equivalence against nofast, and all-method clustered analytical aggregation smoke.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
