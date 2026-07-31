#!/usr/bin/env python3

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests" / "fixtures" / "parity" / "py007"
INPUTS = FIXTURE / "inputs"
CONTRACT = FIXTURE / "expected" / "contract"
META = FIXTURE / "metadata"
for path in (INPUTS, CONTRACT, META):
    path.mkdir(parents=True, exist_ok=True)


def make_single_group(seed=20260401):
    np.random.seed(seed)
    n_ids, n_periods = 200, 5
    ids = np.repeat(np.arange(1, n_ids + 1), n_periods)
    periods = np.tile(np.arange(1, n_periods + 1), n_ids)
    groups = np.repeat(np.concatenate([np.full(50, 4), np.full(150, 0)]), n_periods)
    y = np.random.randn(n_ids * n_periods)
    df = pd.DataFrame({"id": ids, "period": periods, "G": groups, "Y": y})
    df.loc[(df["G"] == 4) & (df["period"] >= 4), "Y"] += 1
    return df


def make_no_never(seed=20260401):
    np.random.seed(seed)
    n_ids, n_periods = 200, 6
    ids = np.repeat(np.arange(1, n_ids + 1), n_periods)
    periods = np.tile(np.arange(1, n_periods + 1), n_ids)
    groups = np.repeat(np.concatenate([np.full(100, 3), np.full(100, 5)]), n_periods)
    y = np.random.randn(n_ids * n_periods)
    return pd.DataFrame({"id": ids, "period": periods, "G": groups, "Y": y})


def make_two_period(seed=20260401):
    np.random.seed(seed)
    n_ids = 200
    ids = np.repeat(np.arange(1, n_ids + 1), 2)
    periods = np.tile([1, 2], n_ids)
    groups = np.repeat(np.concatenate([np.full(50, 2), np.full(150, 0)]), 2)
    y = np.random.randn(n_ids * 2)
    df = pd.DataFrame({"id": ids, "period": periods, "G": groups, "Y": y})
    df.loc[(df["G"] == 2) & (df["period"] == 2), "Y"] += 1
    return df


def make_nonconsecutive_time(seed=20260401):
    np.random.seed(seed)
    n_ids = 200
    time_periods = [2000, 2003, 2007, 2010]
    ids = np.repeat(np.arange(1, n_ids + 1), len(time_periods))
    periods = np.tile(time_periods, n_ids)
    groups = np.repeat(np.concatenate([np.full(50, 2007), np.full(150, 0)]), len(time_periods))
    y = np.random.randn(n_ids * len(time_periods))
    df = pd.DataFrame({"id": ids, "period": periods, "G": groups, "Y": y})
    df.loc[(df["G"] == 2007) & (df["period"] >= 2007), "Y"] += 1
    return df


def make_nonconsecutive_group(seed=20260401):
    np.random.seed(seed)
    n_ids, n_periods = 200, 5
    ids = np.repeat(np.arange(1, n_ids + 1), n_periods)
    periods = np.tile(np.arange(1, n_periods + 1), n_ids)
    groups = np.repeat(
        np.concatenate([np.full(50, 3), np.full(50, 5), np.full(100, 0)]),
        n_periods,
    )
    y = np.random.randn(n_ids * n_periods)
    return pd.DataFrame({"id": ids, "period": periods, "G": groups, "Y": y})


def make_single_post(seed=20260401):
    np.random.seed(seed)
    n_ids, n_periods = 200, 3
    ids = np.repeat(np.arange(1, n_ids + 1), n_periods)
    periods = np.tile(np.arange(1, n_periods + 1), n_ids)
    groups = np.repeat(np.concatenate([np.full(50, 3), np.full(150, 0)]), n_periods)
    y = np.random.randn(n_ids * n_periods)
    df = pd.DataFrame({"id": ids, "period": periods, "G": groups, "Y": y})
    df.loc[(df["G"] == 3) & (df["period"] == 3), "Y"] += 1
    return df


# Read the copy frozen in this fixture, not a checkout outside the repo, so
# regeneration is reproducible here and the inputs cannot shift under us if the
# upstream package changes its bundled data. The frozen file is the verbatim
# round-trip of that source.
sim_source = INPUTS / "sim_data.csv"
if not sim_source.exists():
    raise SystemExit(f"frozen input missing: {sim_source}")
sim_data = pd.read_csv(sim_source)
first_per = int(sim_data["period"].min())
first_group = np.sort(sim_data.loc[sim_data["G"] > 0, "G"].unique())[0]
extra = sim_data.loc[sim_data["G"] == first_group].copy()
extra["G"] = first_per
extra["id"] = extra["id"] + sim_data["id"].max()
first_period = pd.concat([sim_data, extra], ignore_index=True)
unbalanced = sim_data.drop([0, 4, 9]).reset_index(drop=True)

inputs = {
    "single_group": make_single_group(),
    "no_never": make_no_never(),
    "two_period": make_two_period(),
    "nonconsecutive_time": make_nonconsecutive_time(),
    "nonconsecutive_group": make_nonconsecutive_group(),
    "single_post": make_single_post(),
    "sim_data": sim_data,
    "first_period": first_period,
    "unbalanced": unbalanced,
}
for name, df in inputs.items():
    df.to_csv(INPUTS / f"{name}.csv", index=False)

source_file = "csdid/test_csdid/test_edge_cases.py"
source_sha = "c8ca36c53ceb2a42599e9cd4a55ad97d870ae76ebb4d0d512f8259d4be8b173f"
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


for method in ("dr", "reg", "ipw"):
    add(f"test_single_treated_group_produces_valid_att_gt[{method}]", f"single_treated_{method}", "finite ATT(g,t) with a single treated group")
for agg_type in ("simple", "dynamic", "group", "calendar"):
    add(f"test_single_treated_group_aggte_types[{agg_type}]", f"single_treated_agg_{agg_type}", "nonmissing aggregation overall ATT")
for method in ("dr", "reg", "ipw"):
    add(f"test_two_period_data_with_universal_base_period[{method}]", f"two_period_universal_{method}", "finite two-period universal-base ATT(g,t)")
add("test_no_nevertreated_works_with_notyettreated", "no_never_notyet", "not-yet-treated run with no never-treated group succeeds")
add("test_no_nevertreated_coerces_with_nevertreated", "no_never_default_warning", "default nevertreated branch warns/coerces and returns finite ATT(g,t)")
add("test_groups_treated_in_first_period_are_dropped", "first_period_warning", "first-period-treated units warn and are dropped")
for method in ("dr", "reg", "ipw"):
    add(f"test_non_consecutive_time_periods[{method}]", f"nonconsecutive_time_{method}", "nonconsecutive time values run and dynamic aggregation exists")
for method in ("dr", "reg", "ipw"):
    add(f"test_non_consecutive_group_values[{method}]", f"nonconsecutive_group_{method}", "nonconsecutive group values estimate multiple groups")
add("test_allow_unbalanced_panel_with_balanced_data", "balanced_allow_default", "balanced panel public default returns finite ATT(g,t)")
add("test_allow_unbalanced_panel_with_truly_unbalanced_data", "unbalanced_allow_default", "unbalanced ivar public default routes to repeated cross sections and returns finite ATT(g,t)")
for method in ("dr", "reg", "ipw"):
    add(f"test_single_post_treatment_period[{method}]", f"single_post_{method}", "finite post-treatment ATT(g,t) with one post-treatment period")
for method in ("dr", "reg", "ipw"):
    add(f"test_unbalanced_data_rcs_works[{method}]", f"unbalanced_rcs_{method}", "repeated-cross-section unbalanced data returns finite ATT(g,t)")

pd.DataFrame(rows).to_csv(CONTRACT / "upstream-test-map.csv", index=False)
(CONTRACT / "upstream-test-map.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")

scenarios = [
    {"scenario": r["mapped_scenario"], "input": "", "expected_behavior": r["assertion_family"]}
    for r in rows
]
input_by_prefix = {
    "single_treated": "single_group.csv",
    "single_treated_agg": "single_group.csv",
    "two_period": "two_period.csv",
    "no_never": "no_never.csv",
    "first_period": "first_period.csv",
    "nonconsecutive_time": "nonconsecutive_time.csv",
    "nonconsecutive_group": "nonconsecutive_group.csv",
    "balanced_allow": "sim_data.csv",
    "unbalanced_allow": "unbalanced.csv",
    "single_post": "single_post.csv",
    "unbalanced_rcs": "unbalanced.csv",
}
for scenario in scenarios:
    for prefix, input_name in input_by_prefix.items():
        if scenario["scenario"].startswith(prefix):
            scenario["input"] = input_name
            break
pd.DataFrame(scenarios).to_csv(CONTRACT / "scenarios.csv", index=False)

manifest = {
    "matrix_id": "PY007",
    "fixture_family": "python-edge-cases",
    "normative_source": "Python csdid csdid/test_csdid/test_edge_cases.py subordinate to R did 2.5.1",
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
            "command": "python3 tools/parity/generators/py007/generate.py",
            "path": "tools/parity/generators/py007/generate.py",
        }
    ],
    "rng": {"kind": "numpy.random", "seed": 20260401},
    "expected_outputs": [
        {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
        {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
        {"path": "expected/contract/scenarios.csv", "schema": "edge-case-scenarios"},
    ],
    "comparison_plan": [
        {
            "actual": "Stata public edge-case method grid",
            "expected": "expected/contract/scenarios.csv",
            "tolerance_id": "TOL002",
            "key_columns": ["scenario"],
        },
        {
            "actual": "Mapped source tests",
            "expected": "expected/contract/upstream-test-map.csv",
            "tolerance_id": "EXACT",
            "key_columns": ["source_test"],
        },
    ],
    "approved_divergence": None,
    "scope_note": "PY007 maps all Python edge-case parameterizations to Stata public behavior: method-grid finite ATT checks, aggregation checks, no-never warning/coercion, first-period-treated dropping, nonconsecutive time/group values, balanced/unbalanced public defaults, single-post-treatment cells, and repeated-cross-section unbalanced data.",
}
(META / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
