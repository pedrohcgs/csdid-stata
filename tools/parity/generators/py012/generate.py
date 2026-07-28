#!/usr/bin/env python3
"""Generate PY012 Python inference inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py012"
SOURCE_FILE = "csdid/test_csdid/test_inference.py"
SOURCE_SHA256 = "770ee9e9c76f03810c3a0dd2f9e1d78d957262696da38b806abbb538b357965f"
SOURCE_COMMIT = "555f28bc12fcafa9c099e6e5503a30a4c22fc89f"
METHODS = ["dr", "reg", "ipw"]
AGG_TYPES = ["dynamic", "group", "calendar"]


def build_sim_data(n: int = 360, time_periods: int = 4, te: float = 1.0, seed: int = 9142024) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    groups = [0] + list(range(2, time_periods + 1))
    n_per = n // len(groups)
    unit_g = np.concatenate([np.full(n_per, g, dtype=int) for g in groups])
    rem = n - len(unit_g)
    if rem > 0:
        unit_g = np.append(unit_g, np.zeros(rem, dtype=int))
    n_act = len(unit_g)
    ids = np.arange(1, n_act + 1)
    x = rng.standard_normal(n_act)
    alpha = rng.standard_normal(n_act) * 0.3
    cluster = (ids % 10) + 1

    frames = []
    for period in range(1, time_periods + 1):
        eps = rng.standard_normal(n_act)
        y = alpha + 0.3 * x + 0.1 * period + eps
        for group in groups:
            if group > 0 and period >= group:
                mask = unit_g == group
                y = y.copy()
                y[mask] += te
        frames.append(pd.DataFrame({
            "id": ids,
            "period": period,
            "G": unit_g,
            "Y": y,
            "X": x,
            "cluster": cluster,
        }))
    return pd.concat(frames, ignore_index=True)


def main() -> None:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    data = build_sim_data()
    data.to_csv(FIXTURE / "inputs/inference-data.csv", index=False)

    rows: list[dict[str, str]] = []
    for method in METHODS:
        for source_test, scenario, assertion in [
            ("TestBalancedPanelInference::test_se_positive_finite", f"balanced__{method}__attgt_se_positive", "balanced panel ATT(g,t) has positive finite SEs"),
            ("TestBalancedPanelInference::test_inffunc_shape", f"balanced__{method}__inffunc_shape", "balanced panel influence-function dimensions match ATT count and unit count"),
            ("TestBalancedPanelInference::test_aggte_simple_se_finite", f"balanced__{method}__simple_se_positive", "balanced panel simple aggregation SE is positive and finite"),
            ("TestRCSInference::test_se_positive_finite", f"rcs__{method}__attgt_se_positive", "repeated cross-section ATT(g,t) has positive finite SEs"),
            ("TestRCSInference::test_inffunc_exists", f"rcs__{method}__inffunc_exists", "repeated cross-section influence-function matrix is present"),
            ("TestRCSInference::test_aggte_simple_se_finite", f"rcs__{method}__simple_se_positive", "repeated cross-section simple aggregation SE is positive and finite"),
            ("TestInffuncDimensions::test_inffunc_cols_match_att", f"balanced__{method}__inffunc_cols", "influence-function columns match ATT(g,t) count"),
            ("TestInffuncDimensions::test_inffunc_rows_match_units", f"balanced__{method}__inffunc_rows", "influence-function rows match unique units"),
            ("test_overall_att_close_to_true", f"balanced__{method}__overall_att_true", "simple overall ATT is close to true effect 1"),
        ]:
            rows.append({
                "source_file": SOURCE_FILE,
                "source_sha256": SOURCE_SHA256,
                "source_test": f"{source_test}[em={method}]",
                "mapped_scenario": scenario,
                "assertion_family": assertion,
                "coverage_status": "mapped",
            })
        for source_test, suffix, assertion in [
            ("TestBootstrapVsAnalytical::test_bootstrap_se_close_to_analytical", "bootstrap_se_ratio", "bootstrap SE median ratio is in the same broad range as analytical SE"),
            ("TestBootstrapVsAnalytical::test_bootstrap_att_matches_analytical", "bootstrap_att_equal", "bootstrap and analytical point estimates match"),
        ]:
            rows.append({
                "source_file": SOURCE_FILE,
                "source_sha256": SOURCE_SHA256,
                "source_test": f"{source_test}[em={method}]",
                "mapped_scenario": f"balanced__{method}__{suffix}",
                "assertion_family": assertion,
                "coverage_status": "mapped",
            })
        for agg_type in AGG_TYPES:
            rows.append({
                "source_file": SOURCE_FILE,
                "source_sha256": SOURCE_SHA256,
                "source_test": f"test_aggte_se_positive[em={method},typec={agg_type}]",
                "mapped_scenario": f"balanced__{method}__aggte_{agg_type}_se_positive",
                "assertion_family": "aggregation event/group/calendar SEs are positive where ATT is finite",
                "coverage_status": "mapped",
            })
    rows.append({
        "source_file": SOURCE_FILE,
        "source_sha256": SOURCE_SHA256,
        "source_test": "test_all_methods_agree_on_att",
        "mapped_scenario": "balanced__all_methods_att_agreement",
        "assertion_family": "DR and REG ATT(g,t) point estimates agree within source tolerance",
        "coverage_status": "mapped",
    })
    upstream_map = pd.DataFrame(rows)
    upstream_map.to_csv(FIXTURE / "expected/contract/upstream-test-map.csv", index=False)
    (FIXTURE / "expected/contract/upstream-test-map.json").write_text(
        json.dumps(upstream_map.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    scenarios = pd.DataFrame([
        {
            "scenario": "python_inference",
            "methods": ";".join(METHODS),
            "agg_types": ";".join(AGG_TYPES),
            "bootstrap_reps": 49,
            "bootstrap_ratio_min": 0.3,
            "bootstrap_ratio_max": 3.0,
            "overall_att_target": 1.0,
            "overall_att_abs_tol": 0.5,
            "method_att_abs_tol": 0.3,
        }
    ])
    scenarios.to_csv(FIXTURE / "expected/contract/scenarios.csv", index=False)

    manifest = {
        "matrix_id": "PY012",
        "fixture_family": "python-inference",
        "normative_source": "Python csdid csdid/test_csdid/test_inference.py subordinate to R did 2.5.1 inference behavior",
        "source_commit": SOURCE_COMMIT,
        "decision_refs": ["D004", "D014"],
        "tolerance_ids": ["TOL002", "TOL003"],
        "inputs": [{"path": "inputs/inference-data.csv", "rows": int(data.shape[0]), "columns": int(data.shape[1])}],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py012/generate.py", "path": "tools/parity/generators/py012/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"seed": 9142024, "kind": "numpy.default_rng", "draws": "standard_normal"},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/scenarios.csv", "schema": "inference-scenario"},
        ],
        "comparison_plan": [
            {"actual": "Stata public analytical and unclustered bootstrap inference checks", "expected": "source-test-map mapped scenarios", "tolerance_id": "TOL002/TOL003", "key_columns": ["source_test"]},
        ],
        "approved_divergence": None,
        "scope_note": "PY012 maps all 43 parameterized assertions in Python test_inference.py: balanced panel and repeated-cross-section finite SE checks, influence-function dimensions, simple and event-level aggregation SEs, unclustered bootstrap-vs-analytical rough agreement, overall ATT near the true effect, and cross-method ATT agreement. Clustered bootstrap is not part of this source file; inherited Python clustered inference smoke is covered by PY002/PY004/PY005/PY015/F014/F035, and RT017 covers inherited R ATT(g,t) cluster-sum bootstrap stress.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
