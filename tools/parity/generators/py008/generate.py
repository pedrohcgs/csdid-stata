#!/usr/bin/env python3
"""Generate PY008 error-handling inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py008"


def build_sim_data(n: int = 1000, time_periods: int = 4, te: float = 1.0, seed: int = 9142024) -> pd.DataFrame:
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

    base = build_sim_data()
    base.to_csv(FIXTURE / "inputs/sim-data.csv", index=False)

    no_never = base.loc[base["g"] > 0].copy()
    no_never.to_csv(FIXTURE / "inputs/no-never-treated.csv", index=False)

    treated_ids = base.loc[base["g"] > 0, "id"].drop_duplicates().to_numpy()
    control_ids = base.loc[base["g"] == 0, "id"].drop_duplicates().to_numpy()[:50]
    small_ids = np.concatenate([treated_ids[:2], control_ids])
    small = base.loc[base["id"].isin(small_ids)].copy()
    small.to_csv(FIXTURE / "inputs/small-groups.csv", index=False)

    first_period = int(base["period"].min())
    first_positive_group = int(np.sort(base.loc[base["g"] > 0, "g"].unique())[0])
    extra = base.loc[base["g"] == first_positive_group].copy()
    extra["g"] = first_period
    extra["id"] = extra["id"] + int(base["id"].max())
    first_period_treated = pd.concat([base, extra], ignore_index=True)
    first_period_treated.to_csv(FIXTURE / "inputs/first-period-treated.csv", index=False)

    missing_outcome = base.copy()
    missing_outcome.loc[missing_outcome.index[:5], "y"] = np.nan
    missing_outcome.to_csv(FIXTURE / "inputs/missing-outcome.csv", index=False)

    reversible = base.copy()
    uid = int(reversible["id"].iloc[0])
    idx = reversible.index[reversible["id"] == uid].to_numpy()
    midpoint = len(idx) // 2
    reversible.loc[idx[:midpoint], "g"] = 0
    reversible.loc[idx[midpoint:], "g"] = 2
    reversible.to_csv(FIXTURE / "inputs/treatment-reversal.csv", index=False)

    source_tests = [
        ("test_att_gt_errors_on_missing_column", "missing_column", "missing outcome variable errors"),
        ("test_att_gt_errors_on_bad_idname", "bad_idname", "missing id variable errors"),
        ("test_att_gt_coerces_no_nevertreated", "no_never_treated", "no never-treated warning and latest-cohort fallback"),
        ("test_att_gt_warns_on_small_groups", "small_groups", "small-group warning"),
        ("test_att_gt_drops_first_period_units", "first_period_treated", "first-period treated warning and drop"),
        ("test_att_gt_handles_na_in_outcome", "missing_outcome", "missing outcome rows are dropped with diagnostic"),
        ("test_aggte_handles_na_with_na_rm", "aggte_na_rm", "na_rm aggregation proceeds after missing ATT injection"),
        ("test_fix_weights_validation[bad_value]", "fix_weights_bad_value", "bad fix_weights() value rejected"),
        ("test_fix_weights_validation[rc_first_period]", "fix_weights_requires_panel", "first_period fixed weights require panel id"),
        ("test_faster_mode_missing_column", "faster_mode_missing_column", "fast request still validates missing gvar"),
        ("test_invalid_est_method", "invalid_est_method", "unknown method rejected"),
        ("test_treatment_reversals", "treatment_reversal", "time-varying cohort within id rejected"),
    ]
    upstream_map = pd.DataFrame([
        {
            "source_file": "csdid/test_csdid/test_error_handling.py",
            "source_sha256": "fa1824e14730746a442ca24fd234aa9aafa50e0fd53d7540a5f6ca98f4951d73",
            "source_test": test,
            "mapped_scenario": scenario,
            "assertion_family": assertion,
            "coverage_status": "mapped",
        }
        for test, scenario, assertion in source_tests
    ])
    upstream_map.to_csv(FIXTURE / "expected/contract/upstream-test-map.csv", index=False)
    (FIXTURE / "expected/contract/upstream-test-map.json").write_text(
        json.dumps(upstream_map.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    manifest = {
        "matrix_id": "PY008",
        "fixture_family": "python-error-handling",
        "normative_source": "Python csdid csdid/test_csdid/test_error_handling.py subordinate to R did 2.5.1 validation behavior",
        "source_commit": "555f28bc12fcafa9c099e6e5503a30a4c22fc89f",
        "decision_refs": ["D004", "D010", "D014", "D015"],
        "tolerance_ids": ["EXACT"],
        "inputs": [
            {"path": "inputs/sim-data.csv", "rows": int(base.shape[0]), "columns": int(base.shape[1])},
            {"path": "inputs/no-never-treated.csv", "rows": int(no_never.shape[0]), "columns": int(no_never.shape[1])},
            {"path": "inputs/small-groups.csv", "rows": int(small.shape[0]), "columns": int(small.shape[1])},
            {"path": "inputs/first-period-treated.csv", "rows": int(first_period_treated.shape[0]), "columns": int(first_period_treated.shape[1])},
            {"path": "inputs/missing-outcome.csv", "rows": int(missing_outcome.shape[0]), "columns": int(missing_outcome.shape[1])},
            {"path": "inputs/treatment-reversal.csv", "rows": int(reversible.shape[0]), "columns": int(reversible.shape[1])},
        ],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py008/generate.py", "path": "tools/parity/generators/py008/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"seed": 9142024, "kind": "numpy.default_rng", "draws": "standard_normal"},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
        ],
        "comparison_plan": [
            {"actual": "Stata captured validation diagnostics and successful fallback checks", "expected": "source-test-map mapped scenarios", "tolerance_id": "EXACT", "key_columns": ["source_test"]},
        ],
        "approved_divergence": None,
        "scope_note": "PY008 maps every test in Python csdid test_error_handling.py to Stata diagnostics or successful fallback checks: missing variables, no-never-treated fallback, small-group and first-period-treated warnings, missing-row diagnostics, na_rm aggregation, fix_weights validation, fast-request validation, invalid method validation, and irreversible treatment timing.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
