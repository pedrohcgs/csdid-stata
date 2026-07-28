#!/usr/bin/env python3
"""Generate PY016 not-yet-treated inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py016"


def main() -> None:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    np.random.seed(123)
    n_per_group = 30
    n_periods = 5
    groups_unit = np.concatenate([
        np.full(n_per_group, 2005),
        np.full(n_per_group, 2006),
        np.full(n_per_group, 2007),
    ])
    n_units = len(groups_unit)
    ids = np.repeat(np.arange(1, n_units + 1), n_periods)
    years = np.tile(np.arange(2003, 2003 + n_periods), n_units)
    groups = np.repeat(groups_unit, n_periods)
    y = np.random.randn(n_units * n_periods)
    treated = (years >= groups) & (groups > 0)
    y[treated] += 1.0
    data = pd.DataFrame({"id": ids, "year": years, "group": groups, "y": y})
    data.to_csv(FIXTURE / "inputs/notyettreated.csv", index=False)

    source_tests = [
        ("test_no_crash_notyettreated_no_nevertreated", "notyet_no_crash", "notyettreated with no never-treated group fits and returns ATT rows"),
        ("test_last_cohort_retained_in_data", "last_cohort_retained", "latest cohort remains in processed comparison data"),
        ("test_last_cohort_not_in_glist", "last_cohort_not_estimated", "latest cohort is not an estimated group under notyettreated"),
        ("test_estimates_not_nan", "notyet_finite_att", "notyettreated ATT estimates are not all missing"),
        ("test_nevertreated_coerces_without_control", "nevertreated_coerce", "nevertreated with no never-treated group warns and coerces latest cohort"),
        ("test_positive_treatment_effect_detected", "positive_post_att", "post-treatment ATT average is positive"),
    ]
    upstream_map = pd.DataFrame([
        {
            "source_file": "csdid/test_csdid/test_notyettreated.py",
            "source_sha256": "5bec2a6cc01f1a4bc23a828ce0ef7544375647eb7258b319096e0635a4c2be4a",
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

    scenarios = pd.DataFrame([
        {
            "scenario": "notyettreated_no_never",
            "latest_cohort": 2007,
            "expected_min_att_rows": 1,
            "positive_threshold": 0.3,
        }
    ])
    scenarios.to_csv(FIXTURE / "expected/contract/scenarios.csv", index=False)

    manifest = {
        "matrix_id": "PY016",
        "fixture_family": "python-notyettreated-no-never",
        "normative_source": "Python csdid csdid/test_csdid/test_notyettreated.py subordinate to R did 2.5.1 no-never-treated behavior",
        "source_commit": "555f28bc12fcafa9c099e6e5503a30a4c22fc89f",
        "decision_refs": ["D004", "D014"],
        "tolerance_ids": ["TOL002", "EXACT"],
        "inputs": [{"path": "inputs/notyettreated.csv", "rows": int(data.shape[0]), "columns": int(data.shape[1])}],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py016/generate.py", "path": "tools/parity/generators/py016/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"seed": 123, "kind": "numpy.random.seed", "draws": "randn"},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/scenarios.csv", "schema": "notyettreated-scenario"},
        ],
        "comparison_plan": [
            {"actual": "Stata notyettreated/no-never diagnostics and ATT metadata", "expected": "source-test-map mapped scenarios", "tolerance_id": "EXACT", "key_columns": ["source_test"]},
        ],
        "approved_divergence": None,
        "scope_note": "PY016 maps all tests in Python csdid test_notyettreated.py: notyettreated with no never-treated group does not crash, the latest cohort is retained as comparison data but excluded from estimated groups, ATT estimates are finite, nevertreated fallback warns/coerces, and post-treatment ATT averages remain positive.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
