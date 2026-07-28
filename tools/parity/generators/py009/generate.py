#!/usr/bin/env python3
"""Generate PY009 faster-mode consistency inheritance fixtures."""

from __future__ import annotations

import json
from itertools import product
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py009"


def build_sim_data(
    n: int = 1000,
    time_periods: int = 4,
    te: float = 1.0,
    te_e: list[float] | None = None,
    seed: int = 42,
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
    for period in range(1, time_periods + 1):
        eps = rng.standard_normal(n_act)
        y = alpha + 0.3 * x + 0.1 * period + eps
        for group in groups:
            if group > 0 and period >= group:
                mask = unit_g == group
                exposure = period - group
                effect = te_e[min(exposure, len(te_e) - 1)] if te_e is not None else te
                y = y.copy()
                y[mask] += effect
        frames.append(pd.DataFrame({
            "id": ids,
            "period": period,
            "g": unit_g,
            "y": y,
            "x": x,
            "cluster": cluster,
        }))
    return pd.concat(frames, ignore_index=True)


def main() -> None:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    data = build_sim_data(n=1000, time_periods=4, te=0.0, te_e=[1, 2, 3, 4], seed=42)
    data.to_csv(FIXTURE / "inputs/sim-fast.csv", index=False)

    scenario_rows = []
    source_rows = []
    for panel, control_group, est_method, base_period in product(
        [True, False],
        ["nevertreated", "notyettreated"],
        ["dr", "reg", "ipw"],
        ["varying", "universal"],
    ):
        scenario = f"panel_{str(panel).lower()}__{control_group}__{est_method}__{base_period}"
        scenario_rows.append({
            "scenario": scenario,
            "panel": "panel" if panel else "repeated-cross-section",
            "control_group": control_group,
            "est_method": est_method,
            "base_period": base_period,
            "has_covariates": 1,
            "expected_fast_requested": 1,
            "expected_fast_used": 1,
        })
        source_rows.append({
            "source_file": "csdid/test_csdid/test_faster_mode_consistency.py",
            "source_sha256": "0a96e5e21e880cbbc703b8ff77bee8b207debc2a5ff9865b86e37ee45c123028",
            "source_test": (
                "test_faster_mode_equals_standard"
                f"[panel={panel},control_group={control_group},est_method={est_method},base_period={base_period}]"
            ),
            "mapped_scenario": scenario,
            "assertion_family": "requested-fast ATT and finite SE equal standard path",
            "coverage_status": "mapped",
        })

    scenarios = pd.DataFrame(scenario_rows)
    scenarios.to_csv(FIXTURE / "expected/contract/scenarios.csv", index=False)

    upstream_map = pd.DataFrame(source_rows)
    upstream_map.to_csv(FIXTURE / "expected/contract/upstream-test-map.csv", index=False)
    (FIXTURE / "expected/contract/upstream-test-map.json").write_text(
        json.dumps(upstream_map.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    manifest = {
        "matrix_id": "PY009",
        "fixture_family": "python-faster-mode-consistency",
        "normative_source": "Python csdid csdid/test_csdid/test_faster_mode_consistency.py subordinate to R did 2.5.1 fast/standard equivalence behavior",
        "source_commit": "555f28bc12fcafa9c099e6e5503a30a4c22fc89f",
        "decision_refs": ["D004", "D014"],
        "tolerance_ids": ["TOL002"],
        "inputs": [{"path": "inputs/sim-fast.csv", "rows": int(data.shape[0]), "columns": int(data.shape[1])}],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py009/generate.py", "path": "tools/parity/generators/py009/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"seed": 42, "kind": "numpy.default_rng", "draws": "standard_normal"},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/scenarios.csv", "schema": "faster-mode-scenario-grid"},
        ],
        "comparison_plan": [
            {"actual": "Stata standard path and requested-fast path ATT(g,t)", "expected": "live Stata equality", "tolerance_id": "TOL002", "key_columns": ["scenario", "group", "time"]},
        ],
        "approved_divergence": None,
        "scope_note": "PY009 maps all 24 Python fast-mode consistency parameterizations. Stata verifies explicit nofast baseline equality against the requested-fast optimized path (fast_requested=1, fast_used=1) across covariate panel/repeated-cross-section, nevertreated/notyettreated, dr/reg/ipw, and varying/universal base-period surfaces.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
