#!/usr/bin/env python3
"""Generate PY022 tidy/summary structure inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py022"


def build_sim_data(n: int = 1000, time_periods: int = 4, te: float = 1.0, seed: int = 20260401) -> pd.DataFrame:
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
                y = y.copy()
                y[mask] += te
        frames.append(pd.DataFrame({
            "id": ids,
            "period": t,
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

    mpdta_source = ROOT / "tests/fixtures/parity/rt026/inputs/mpdta.csv"
    mpdta = pd.read_csv(mpdta_source)
    mpdta.to_csv(FIXTURE / "inputs/mpdta.csv", index=False)

    sim = build_sim_data()
    sim.to_csv(FIXTURE / "inputs/sim-tidy.csv", index=False)

    structure = pd.DataFrame([
        {"object": "MP", "input": "mpdta.csv", "method": "reg", "expected_min_rows": 1, "nobs": int(mpdta["countyreal"].nunique())},
        {"object": "aggte_simple", "input": "mpdta.csv", "method": "reg", "expected_min_rows": 1, "nobs": int(mpdta["countyreal"].nunique())},
        {"object": "aggte_dynamic", "input": "mpdta.csv", "method": "reg", "expected_min_rows": 1, "nobs": int(mpdta["countyreal"].nunique())},
        {"object": "aggte_group", "input": "mpdta.csv", "method": "reg", "expected_min_rows": 1, "nobs": int(mpdta["countyreal"].nunique())},
        {"object": "aggte_calendar", "input": "mpdta.csv", "method": "reg", "expected_min_rows": 1, "nobs": int(mpdta["countyreal"].nunique())},
        {"object": "method_dr", "input": "sim-tidy.csv", "method": "dr", "expected_min_rows": 1, "nobs": int(sim["id"].nunique())},
        {"object": "method_reg", "input": "sim-tidy.csv", "method": "reg", "expected_min_rows": 1, "nobs": int(sim["id"].nunique())},
        {"object": "method_ipw", "input": "sim-tidy.csv", "method": "ipw", "expected_min_rows": 1, "nobs": int(sim["id"].nunique())},
    ])
    structure.to_csv(FIXTURE / "expected/contract/tidy-structure.csv", index=False)

    source_tests = [
        ("test_summ_attgt_returns_dataframe", "MP", "tidy export nonempty with group/time/estimate columns"),
        ("test_mp_result_has_expected_keys", "MP", "stored ATT(g,t), IF, DIDparams-like e() metadata"),
        ("test_att_values_are_finite", "MP", "ATT(g,t) estimates finite"),
        ("test_se_values_are_positive", "MP", "SE values positive where ATT is finite"),
        ("test_aggte_has_expected_keys[simple]", "aggte_simple", "overall/effect aggregation metadata exists"),
        ("test_aggte_has_expected_keys[dynamic]", "aggte_dynamic", "overall/effect aggregation metadata exists"),
        ("test_aggte_has_expected_keys[group]", "aggte_group", "overall/effect aggregation metadata exists"),
        ("test_aggte_has_expected_keys[calendar]", "aggte_calendar", "overall/effect aggregation metadata exists"),
        ("test_aggte_dynamic_has_event_times", "aggte_dynamic", "dynamic egt values present"),
        ("test_aggte_group_has_group_ids", "aggte_group", "group egt values present"),
        ("test_aggte_calendar_has_periods", "aggte_calendar", "calendar egt values present"),
        ("test_nobs_from_didparams", "MP", "nobs metadata positive integer"),
        ("test_nobs_matches_data", "MP", "nobs equals unique id count"),
        ("test_summ_attgt_across_methods[dr]", "method_dr", "cross-method tidy export nonempty"),
        ("test_summ_attgt_across_methods[reg]", "method_reg", "cross-method tidy export nonempty"),
        ("test_summ_attgt_across_methods[ipw]", "method_ipw", "cross-method tidy export nonempty"),
    ]
    upstream_map = pd.DataFrame([
        {
            "source_file": "csdid/test_csdid/test_tidy.py",
            "source_sha256": "006ac8aeb138a660153baa5c157f61e8016ebd5cc04583c7c8aa9c29c09a9502",
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
        "matrix_id": "PY022",
        "fixture_family": "python-tidy-summary-structure",
        "normative_source": "Python csdid csdid/test_csdid/test_tidy.py subordinate to R did 2.5.1 output behavior",
        "source_commit": "555f28bc12fcafa9c099e6e5503a30a4c22fc89f",
        "decision_refs": ["D004", "D014"],
        "tolerance_ids": ["EXACT"],
        "inputs": [
            {"path": "inputs/mpdta.csv", "rows": int(mpdta.shape[0]), "columns": int(mpdta.shape[1])},
            {"path": "inputs/sim-tidy.csv", "rows": int(sim.shape[0]), "columns": int(sim.shape[1])},
        ],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py022/generate.py", "path": "tools/parity/generators/py022/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"seed": 20260401, "kind": "numpy.default_rng", "draws": "standard_normal"},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/tidy-structure.csv", "schema": "tidy-structure"},
        ],
        "comparison_plan": [
            {"actual": "Stata tidy export and e() metadata structure", "expected": "expected/contract/tidy-structure.csv", "tolerance_id": "EXACT", "key_columns": ["object"]},
        ],
        "approved_divergence": None,
        "scope_note": "PY022 maps every test in Python csdid test_tidy.py to Stata tidy export and metadata structure checks: nonempty ATT(g,t) tidy output with expected columns, finite ATT and positive SE values, aggregation result keys for all four types, event/group/calendar egt values, nobs metadata, and dr/reg/ipw cross-method tidy output.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
