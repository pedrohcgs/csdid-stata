#!/usr/bin/env python3
"""Generate PY017 parametric-combination inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py017"
SOURCE_FILE = "csdid/test_csdid/test_parametric_combinations.py"
SOURCE_SHA256 = "ce505335fe16f7ed98196daffa628b25852474b0fd1fe948167c32f8e2502936"
SOURCE_COMMIT = "555f28bc12fcafa9c099e6e5503a30a4c22fc89f"


EST_METHODS = ["dr", "reg", "ipw"]
CONTROL_GROUPS = ["nevertreated", "notyettreated"]
BASE_PERIODS = ["varying", "universal"]
AGGTE_TYPES = ["simple", "dynamic", "group", "calendar"]


def build_sim_data(
    n: int = 1000,
    time_periods: int = 4,
    te: float = 1.0,
    te_e: list[float] | None = None,
    seed: int = 9142024,
) -> pd.DataFrame:
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
    for t in range(1, time_periods + 1):
        eps = rng.standard_normal(n_act)
        y = alpha + 0.3 * x + 0.1 * t + eps
        for g in groups:
            if g > 0 and t >= g:
                mask = unit_g == g
                exposure = t - g
                eff = te_e[min(exposure, len(te_e) - 1)] if te_e is not None else te
                y = y.copy()
                y[mask] += eff
        frames.append(pd.DataFrame({"id": ids, "period": t, "g": unit_g, "y": y, "x": x, "cluster": cluster}))
    return pd.concat(frames, ignore_index=True)


def source_row(source_test: str, scenario: str, assertion: str) -> dict[str, str]:
    return {
        "source_file": SOURCE_FILE,
        "source_sha256": SOURCE_SHA256,
        "source_test": source_test,
        "mapped_scenario": scenario,
        "assertion_family": assertion,
        "coverage_status": "mapped",
    }


def add(rows: list[dict[str, str]], scenarios: list[dict[str, str]], source_test: str, scenario: str, assertion: str, family: str) -> None:
    rows.append(source_row(source_test, scenario, assertion))
    scenarios.append({"scenario": scenario, "family": family, "expected_behavior": assertion})


def main() -> None:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    panel = build_sim_data(n=1000, time_periods=4, te=1.0, seed=9142024)
    dynamic = build_sim_data(n=2000, time_periods=4, te=0.0, te_e=[1, 2, 3, 4], seed=10)
    anticipation = build_sim_data(n=1000, time_periods=6, te=1.0, seed=42)
    panel.to_csv(FIXTURE / "inputs/panel-data.csv", index=False)
    dynamic.to_csv(FIXTURE / "inputs/dynamic-data.csv", index=False)
    anticipation.to_csv(FIXTURE / "inputs/anticipation-data.csv", index=False)

    rows: list[dict[str, str]] = []
    scenarios: list[dict[str, str]] = []

    for em in EST_METHODS:
        for cg in CONTROL_GROUPS:
            for bp in BASE_PERIODS:
                param = f"{em}-{cg}-{bp}"
                scenario = f"combo_a__{em}__{cg}__{bp}"
                add(rows, scenarios, f"TestComboA.test_att_gt_valid[{param}]", scenario, "ATT(g,t) has at least one nonmissing estimate", "combo_a")
                add(rows, scenarios, f"TestComboA.test_se_positive_finite[{param}]", scenario, "at least one positive finite ATT(g,t) standard error", "combo_a")
                add(rows, scenarios, f"TestComboA.test_aggte_simple[{param}]", scenario, "simple aggregation has nonmissing overall ATT", "combo_a")

    for em in EST_METHODS:
        for panel_flag in [True, False]:
            param = f"{em}-panel{panel_flag}"
            suffix = "panel_true" if panel_flag else "panel_false"
            scenario = f"combo_b__{em}__{suffix}"
            add(rows, scenarios, f"TestComboB.test_produces_results[{param}]", scenario, "panel flag variant has at least one nonmissing ATT(g,t)", "combo_b")
            add(rows, scenarios, f"TestComboB.test_aggte_dynamic[{param}]", scenario, "dynamic aggregation has nonmissing overall ATT", "combo_b")

    for ant in [0, 1, 2]:
        for em in EST_METHODS:
            param = f"ant{ant}-{em}"
            scenario = f"combo_c__ant{ant}__{em}"
            add(rows, scenarios, f"TestComboC.test_produces_results[{param}]", scenario, "anticipation variant has at least one nonmissing ATT(g,t)", "combo_c")
            add(rows, scenarios, f"TestComboC.test_se_finite[{param}]", scenario, "anticipation variant has at least one positive finite SE", "combo_c")

    for bstrap in [True, False]:
        for em in EST_METHODS:
            param = f"bstrap{bstrap}-{em}"
            suffix = "bstrap_true" if bstrap else "bstrap_false"
            scenario = f"combo_d__{suffix}__{em}"
            add(rows, scenarios, f"TestComboD.test_se_finite[{param}]", scenario, "bootstrap flag variant has at least one positive finite SE", "combo_d")
            add(rows, scenarios, f"TestComboD.test_att_reasonable[{param}]", scenario, "bootstrap flag variant has finite nonmissing ATT(g,t)", "combo_d")

    for em in EST_METHODS:
        for cg in CONTROL_GROUPS:
            for bp in BASE_PERIODS:
                for panel_flag in [True, False]:
                    param = f"{em}-{cg}-{bp}-panel{panel_flag}"
                    suffix = "panel_true" if panel_flag else "panel_false"
                    scenario = f"combo_e__{em}__{cg}__{bp}__{suffix}"
                    add(rows, scenarios, f"test_full_integration[{param}]", scenario, "fit plus simple aggregation has nonmissing overall ATT", "combo_e")

    for typec in AGGTE_TYPES:
        for em in EST_METHODS:
            param = f"{typec}-{em}"
            scenario = f"combo_f__{typec}__{em}"
            add(rows, scenarios, f"test_aggte_type_by_method[{param}]", scenario, "aggregation type by method has nonmissing overall ATT and positive SE", "combo_f")

    for em in EST_METHODS:
        add(rows, scenarios, f"test_rcs_dynamic_effects_by_method[{em}]", f"combo_g__dynamic_rc__{em}", "repeated-cross-section dynamic post-treatment effects include a positive effect", "combo_g")
        add(rows, scenarios, f"test_rcs_vs_panel_both_work[{em}]", f"combo_g__rc_vs_panel__{em}", "panel and repeated-cross-section variants both have nonmissing ATT(g,t)", "combo_g")

    upstream = pd.DataFrame(rows)
    upstream.to_csv(FIXTURE / "expected/contract/upstream-test-map.csv", index=False)
    (FIXTURE / "expected/contract/upstream-test-map.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")
    scenario_df = pd.DataFrame(scenarios).drop_duplicates()
    scenario_df.to_csv(FIXTURE / "expected/contract/scenarios.csv", index=False)

    manifest = {
        "matrix_id": "PY017",
        "fixture_family": "python-parametric-combinations",
        "normative_source": "Python csdid csdid/test_csdid/test_parametric_combinations.py subordinate to R did 2.5.1 public behavior",
        "source_commit": SOURCE_COMMIT,
        "decision_refs": ["D004"],
        "tolerance_ids": ["TOL002", "TOL003", "EXACT"],
        "inputs": [
            {"path": "inputs/panel-data.csv", "rows": int(panel.shape[0]), "columns": int(panel.shape[1])},
            {"path": "inputs/dynamic-data.csv", "rows": int(dynamic.shape[0]), "columns": int(dynamic.shape[1])},
            {"path": "inputs/anticipation-data.csv", "rows": int(anticipation.shape[0]), "columns": int(anticipation.shape[1])},
        ],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py017/generate.py", "path": "tools/parity/generators/py017/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"kind": "numpy.random.default_rng", "seeds": [9142024, 10, 42]},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/scenarios.csv", "schema": "source-scenario-map"},
        ],
        "comparison_plan": [
            {"actual": "Stata public command checks for mapped parametric combination scenarios", "expected": "expected/contract/upstream-test-map.csv", "tolerance_id": "EXACT/TOL002/TOL003", "key_columns": ["source_test"]},
        ],
        "approved_divergence": None,
        "scope_note": "PY017 maps all 120 test_parametric_combinations.py parameterized assertions to Stata public command behavior: method/control/base-period grids, panel and repeated-cross-section paths, anticipation 0/1/2, bootstrap and non-bootstrap finite SE/ATT checks, full simple-aggregation integration, all aggregation types by method, and repeated-cross-section dynamic-effect checks.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
