#!/usr/bin/env python3
"""Generate PY001 aggregation-comprehensive inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py001"
SOURCE_FILE = "csdid/test_csdid/test_aggte_comprehensive.py"
SOURCE_SHA256 = "0b8e87470662850acd90d96c449dfb1f51f7bd48393ad0864aa082ad693701df"
SOURCE_COMMIT = "555f28bc12fcafa9c099e6e5503a30a4c22fc89f"

BASE_TESTS = [
    ("test_simple_valid_overall_att", "simple-valid-overall-att", "simple overall ATT is finite and near one"),
    ("test_simple_valid_se", "simple-valid-se", "simple overall SE is positive and finite"),
    ("test_simple_no_egt", "simple-no-egt", "simple aggregation has no event/group/calendar egt component"),
    ("test_dynamic_returns_event_times", "dynamic-event-times", "dynamic aggregation has pre and post event times"),
    ("test_dynamic_event_times_sorted", "dynamic-sorted", "dynamic event times are sorted"),
    ("test_dynamic_overall_att", "dynamic-overall-att", "dynamic overall ATT is finite and near one"),
    ("test_dynamic_min_e_filters", "dynamic-min-e", "dynamic min_e filters event times"),
    ("test_dynamic_max_e_filters", "dynamic-max-e", "dynamic max_e filters event times"),
    ("test_dynamic_min_max_together", "dynamic-min-max", "dynamic min_e/max_e jointly filter event times"),
    ("test_dynamic_balance_e", "dynamic-balance-e", "dynamic balance_e does not increase event-count"),
    ("test_dynamic_positive_se", "dynamic-positive-se", "dynamic SEs are positive where ATT is nonmissing"),
    ("test_group_returns_per_group", "group-per-group", "group aggregation returns treatment-group rows"),
    ("test_group_overall_att", "group-overall-att", "group overall ATT is finite and near one"),
    ("test_group_positive_se", "group-positive-se", "group SEs are positive where ATT is nonmissing"),
    ("test_calendar_returns_periods", "calendar-periods", "calendar aggregation returns period rows"),
    ("test_calendar_overall_att", "calendar-overall-att", "calendar overall ATT is finite and near one"),
    ("test_calendar_positive_se", "calendar-positive-se", "calendar SEs are positive where ATT is nonmissing"),
    ("test_calendar_post_treatment_only", "calendar-post-treatment-only", "calendar rows are post-treatment periods"),
    ("test_na_rm_drops_na_and_proceeds", "na-rm-drops-na", "na_rm drops injected missing ATT and returns finite overall ATT"),
    ("test_preserves_overridden_settings", "preserves-overridden-settings", "aggregation preserves analytical/level settings through public metadata"),
]

TYPES = ["simple", "dynamic", "group", "calendar"]
METHODS = ["dr", "reg", "ipw"]
CROSS_METHOD_TESTS = [
    ("test_simple_valid_across_methods", "simple-across-methods", "simple aggregation valid across methods"),
    ("test_dynamic_valid_across_methods", "dynamic-across-methods", "dynamic aggregation valid across methods"),
    ("test_group_valid_across_methods", "group-across-methods", "group aggregation valid across methods"),
    ("test_calendar_valid_across_methods", "calendar-across-methods", "calendar aggregation valid across methods"),
    ("test_balance_e_across_methods", "balance-e-across-methods", "balance_e filters across methods"),
    ("test_na_rm_across_methods", "na-rm-across-methods", "na_rm works across methods"),
]


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
    frames = []
    for t in range(1, time_periods + 1):
        eps = rng.standard_normal(n_act)
        y = alpha + 0.3 * x + 0.1 * t + eps
        for g in groups:
            if g > 0 and t >= g:
                mask = unit_g == g
                y = y.copy()
                y[mask] += te
        frames.append(pd.DataFrame({"id": ids, "period": t, "g": unit_g, "y": y, "x": x}))
    return pd.concat(frames, ignore_index=True)


def row(source_test: str, scenario: str, assertion: str) -> dict[str, str]:
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

    data = build_sim_data()
    data.to_csv(FIXTURE / "inputs/aggte-data.csv", index=False)

    rows: list[dict[str, str]] = []
    scenarios: list[dict[str, str]] = []
    for test, scenario, assertion in BASE_TESTS:
        rows.append(row(test, scenario, assertion))
        scenarios.append({"scenario": scenario, "family": "base", "expected_behavior": assertion})
    for typec in TYPES:
        rows.append(row(f"test_all_types_return_dict[{typec}]", f"return-dict-{typec}", f"{typec} returns public aggregation result matrix"))
        rows.append(row(f"test_all_types_have_didparams[{typec}]", f"didparams-{typec}", f"{typec} exposes public aggregation metadata"))
        scenarios.append({"scenario": f"return-dict-{typec}", "family": "type-structure", "expected_behavior": f"{typec} returns e(aggte)"})
        scenarios.append({"scenario": f"didparams-{typec}", "family": "type-metadata", "expected_behavior": f"{typec} exposes e() metadata"})
    for method in METHODS:
        for test, stem, assertion in CROSS_METHOD_TESTS:
            scenario = f"{stem}-{method}"
            rows.append(row(f"{test}[{method}]", scenario, assertion))
            scenarios.append({"scenario": scenario, "family": "cross-method", "expected_behavior": assertion})

    pd.DataFrame(rows).to_csv(FIXTURE / "expected/contract/upstream-test-map.csv", index=False)
    (FIXTURE / "expected/contract/upstream-test-map.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")
    pd.DataFrame(scenarios).drop_duplicates().to_csv(FIXTURE / "expected/contract/scenarios.csv", index=False)

    manifest = {
        "matrix_id": "PY001",
        "fixture_family": "python-aggte-comprehensive",
        "normative_source": "Python csdid csdid/test_csdid/test_aggte_comprehensive.py subordinate to R did 2.5.1 aggregation behavior",
        "source_commit": SOURCE_COMMIT,
        "source_sha256": SOURCE_SHA256,
        "decision_refs": ["D004"],
        "tolerance_ids": ["TOL002", "EXACT"],
        "inputs": [{"path": "inputs/aggte-data.csv", "rows": int(data.shape[0]), "columns": int(data.shape[1])}],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py001/generate.py", "path": "tools/parity/generators/py001/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"kind": "numpy.random.default_rng", "seed": 9142024},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/scenarios.csv", "schema": "source-scenario-map"},
        ],
        "comparison_plan": [
            {"actual": "Stata csdid_stats public aggregation behavior", "expected": "expected/contract/upstream-test-map.csv", "tolerance_id": "TOL002/EXACT", "key_columns": ["source_test"]},
        ],
        "approved_divergence": None,
        "scope_note": "PY001 maps all 46 public parameterizations in Python test_aggte_comprehensive.py to Stata csdid_stats behavior: simple/dynamic/group/calendar validity, windows, balance_e, na_rm, metadata, and dr/reg/ipw cross-method aggregation checks.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
