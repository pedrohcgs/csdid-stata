#!/usr/bin/env python3

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests" / "fixtures" / "parity" / "py023"
INPUTS = FIXTURE / "inputs"
CONTRACT = FIXTURE / "expected" / "contract"
META = FIXTURE / "metadata"
for path in (INPUTS, CONTRACT, META):
    path.mkdir(parents=True, exist_ok=True)


def build_sim_data(n=1000, time_periods=4, te=1.0, te_e=None, seed=9142024):
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
                e = t - g
                eff = te_e[min(e, len(te_e) - 1)] if te_e is not None else te
                y = y.copy()
                y[mask] += eff
        frames.append(pd.DataFrame({"id": ids, "period": t, "G": unit_g, "Y": y, "X": x, "cluster": cluster}))
    return pd.concat(frames, ignore_index=True)


# Frozen in this fixture rather than read from a checkout outside the repo.
_mpdta_src = INPUTS / "mpdta.csv"
if not _mpdta_src.exists():
    raise SystemExit(f"frozen input missing: {_mpdta_src}")
mpdta = pd.read_csv(_mpdta_src)

fewer_periods = build_sim_data(n=1000, time_periods=6, te=0, te_e=[1, 2, 3, 4, 5, 6], seed=56)
fewer_periods = fewer_periods[~fewer_periods["period"].isin([2, 5])].reset_index(drop=True)

zero_pretreat = build_sim_data(n=1000, time_periods=10, te=1.0, seed=126)
zero_pretreat = zero_pretreat[zero_pretreat["G"] > 0].copy()
zero_pretreat = zero_pretreat[zero_pretreat["G"] > 6].copy()
zero_pretreat = zero_pretreat[zero_pretreat["period"] > 5].copy()
zero_pretreat.loc[zero_pretreat["period"] < zero_pretreat["G"], "Y"] = 0

missing_var = build_sim_data(n=500, time_periods=3, seed=99)

np.random.seed(20250228)
n = 600
ids = np.repeat(np.arange(1, n + 1), 5)
times = np.tile(np.arange(1, 6), n)
group_vals = np.concatenate([np.full(200, 0), np.full(200, 4), np.full(200, 6)])
anticipation = pd.DataFrame({
    "id": ids,
    "time": times,
    "group": np.repeat(group_vals, 5),
    "y": np.random.randn(len(ids)),
})

inputs = {
    "mpdta": mpdta,
    "fewer_periods": fewer_periods,
    "zero_pretreat": zero_pretreat,
    "missing_var": missing_var,
    "anticipation": anticipation,
}
for name, df in inputs.items():
    df.to_csv(INPUTS / f"{name}.csv", index=False)

source_file = "csdid/test_csdid/test_user_bug_fixes.py"
source_sha = "48f8fa1d991d14a0739c359fd16477e2497c4c6f5385b2b92ec698389ec3f6fc"
rows = []


def add(source_test, scenario, assertion):
    rows.append(
        {
            "source_file": source_file,
            "source_sha256": source_sha,
            "source_test": source_test,
            "mapped_scenario": scenario,
            "assertion_family": assertion,
            "coverage_status": "mapped",
            "divergence_id": "",
        }
    )


add("test_column_named_t1_does_not_crash", "mpdta_t1_column", "mpdta not-yet-treated regression runs before and after adding a harmless t1 column")
add("test_missing_covariates", "mpdta_missing_covariate", "missing covariate row is handled by complete-case preprocessing and estimation succeeds")
add("test_fewer_periods_than_groups", "fewer_periods_main", "fewer observed periods than treatment groups gives expected ATT slice and nonmissing aggregations")
add("test_zero_pretreatment_outcomes", "zero_pretreatment", "pre-treatment ATT for group 9 at time 7 is zero under universal and varying base periods")
add("test_variables_not_in_dataset", "missing_formula_variable", "unknown covariate variable is rejected")
add("test_anticipation_window_coercion", "anticipation_window", "anticipation controls whether late cohort is coerced to controls or remains treated")
for method in ("dr", "reg", "ipw"):
    add(f"test_fewer_periods_than_groups_all_methods[{method}]", f"fewer_periods_{method}", "fewer-periods design returns finite ATT and nonmissing dynamic overall ATT")

pd.DataFrame(rows).to_csv(CONTRACT / "upstream-test-map.csv", index=False)
(CONTRACT / "upstream-test-map.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")

scenario_inputs = {
    "mpdta_t1_column": "mpdta.csv",
    "mpdta_missing_covariate": "mpdta.csv",
    "fewer_periods_main": "fewer_periods.csv",
    "zero_pretreatment": "zero_pretreat.csv",
    "missing_formula_variable": "missing_var.csv",
    "anticipation_window": "anticipation.csv",
    "fewer_periods_dr": "fewer_periods.csv",
    "fewer_periods_reg": "fewer_periods.csv",
    "fewer_periods_ipw": "fewer_periods.csv",
}
scenarios = [
    {"scenario": r["mapped_scenario"], "input": scenario_inputs[r["mapped_scenario"]], "expected_behavior": r["assertion_family"]}
    for r in rows
]
pd.DataFrame(scenarios).to_csv(CONTRACT / "scenarios.csv", index=False)

manifest = {
    "matrix_id": "PY023",
    "fixture_family": "python-user-bug-fixes",
    "normative_source": "Python csdid csdid/test_csdid/test_user_bug_fixes.py subordinate to R did 2.5.1",
    "source_commit": "555f28bc12fcafa9c099e6e5503a30a4c22fc89f",
    "source_sha256": source_sha,
    "decision_refs": ["D003", "D004"],
    "tolerance_ids": ["TOL002", "EXACT"],
    "inputs": [
        {"path": f"inputs/{name}.csv", "rows": int(df.shape[0]), "columns": int(df.shape[1])}
        for name, df in inputs.items()
    ],
    "generators": [
        {
            "runtime": "Python",
            "command": "python3 tools/parity/generators/py023/generate.py",
            "path": "tools/parity/generators/py023/generate.py",
        }
    ],
    "rng": {"kind": "numpy.random/default_rng", "seeds": [56, 99, 126, 20250228, 9142024]},
    "expected_outputs": [
        {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
        {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
        {"path": "expected/contract/scenarios.csv", "schema": "user-bug-scenarios"},
    ],
    "comparison_plan": [
        {"actual": "Stata public user-bug regression gates", "expected": "expected/contract/scenarios.csv", "tolerance_id": "TOL002", "key_columns": ["scenario"]},
        {"actual": "Mapped source tests", "expected": "expected/contract/upstream-test-map.csv", "tolerance_id": "EXACT", "key_columns": ["source_test"]},
    ],
    "approved_divergence": None,
    "scope_note": "PY023 maps all public user-bug-fix tests to Stata public behavior: harmless t1 columns, missing covariate preprocessing, fewer periods than groups with aggregations and method grid, zero pre-treatment outcomes, unknown covariate rejection, and anticipation-window treatment-group coercion.",
}
(META / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
