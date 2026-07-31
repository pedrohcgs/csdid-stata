#!/usr/bin/env python3
"""Generate PY024 validation inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py024"


def sample_data() -> pd.DataFrame:
    np.random.seed(42)
    n_units = 50
    n_periods = 4
    ids = np.repeat(np.arange(1, n_units + 1), n_periods)
    years = np.tile(np.arange(2003, 2003 + n_periods), n_units)
    groups_unit = np.concatenate([
        np.full(20, 2004),
        np.full(15, 2006),
        np.full(15, 0),
    ])
    groups = np.repeat(groups_unit, n_periods)
    y = np.random.randn(n_units * n_periods) + 0.5 * (years >= groups) * (groups > 0)
    return pd.DataFrame({"id": ids, "year": years, "group": groups, "y": y})


def main() -> None:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    base = sample_data()
    base.to_csv(FIXTURE / "inputs/sample.csv", index=False)

    neg_weight = base.copy()
    neg_weight["wt"] = 1.0
    neg_weight.loc[0, "wt"] = -1.0
    neg_weight.to_csv(FIXTURE / "inputs/negative-weight.csv", index=False)

    duplicate = pd.concat([base, base.iloc[[0]]], ignore_index=True)
    duplicate.to_csv(FIXTURE / "inputs/duplicate.csv", index=False)

    valid = pd.DataFrame([{"scenario": "valid_data", "nobs": int(base["id"].nunique()), "min_att_rows": 1}])
    valid.to_csv(FIXTURE / "expected/contract/valid-scenarios.csv", index=False)

    source_tests = [
        ("test_missing_yname", "missing_yname", "mapped", "missing outcome variable errors"),
        ("test_missing_tname", "missing_tname", "mapped", "missing time variable errors"),
        ("test_missing_idname", "missing_idname", "mapped", "missing id variable errors"),
        ("test_missing_gname", "missing_gname", "mapped", "missing group variable errors"),
        ("test_missing_weights_name", "missing_weights_name", "mapped", "missing iweight variable errors"),
        ("test_missing_clustervar", "missing_clustervar", "mapped", "missing cluster variable errors"),
        ("test_reserved_column_w", "reserved_column_w", "approved-divergence", "Stata permits user variables named w; no Python internal w conflict exists in this command surface"),
        ("test_reserved_column_rowid", "reserved_column_rowid", "approved-divergence", "Stata permits user variables named rowid; no Python internal rowid conflict exists in this command surface"),
        ("test_non_numeric_outcome", "non_numeric_outcome", "mapped", "string outcome rejected"),
        ("test_non_numeric_tname", "non_numeric_tname", "mapped", "string time rejected"),
        ("test_non_numeric_gname", "non_numeric_gname", "mapped", "string group rejected"),
        ("test_negative_gname_rejected", "negative_gname", "mapped", "negative group values rejected"),
        ("test_duplicate_id_time", "duplicate_id_time", "mapped", "duplicate id-time rejected"),
        ("test_alp_too_low", "level_too_high", "mapped", "Stata level equivalent rejects invalid confidence level"),
        ("test_alp_too_high", "level_too_low", "mapped", "Stata level equivalent rejects invalid confidence level"),
        ("test_biters_negative", "biters_negative", "mapped", "negative bootstrap iterations rejected"),
        ("test_biters_zero", "biters_zero", "mapped", "zero bootstrap iterations rejected"),
        ("test_negative_anticipation", "negative_anticipation", "mapped", "negative anticipation rejected"),
        ("test_invalid_control_group", "invalid_control_group", "mapped", "unsupported control_group() option rejected"),
        ("test_negative_weights", "negative_weights", "mapped", "negative weights rejected"),
        ("test_valid_data_no_error", "valid_data_no_error", "mapped", "valid initialization analogue succeeds"),
        ("test_valid_data_with_fit", "valid_data_with_fit", "mapped", "valid fit produces ATT(g,t) results"),
    ]
    upstream_map = pd.DataFrame([
        {
            "source_file": "csdid/test_csdid/test_validation.py",
            "source_sha256": "90f92c37e1123518cb4d9c3aaa9389ec6f92889b53a569fa11553cc21609b969",
            "source_test": test,
            "mapped_scenario": scenario,
            "assertion_family": assertion,
            "coverage_status": status,
        }
        for test, scenario, status, assertion in source_tests
    ])
    upstream_map.to_csv(FIXTURE / "expected/contract/upstream-test-map.csv", index=False)
    (FIXTURE / "expected/contract/upstream-test-map.json").write_text(
        json.dumps(upstream_map.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    manifest = {
        "matrix_id": "PY024",
        "fixture_family": "python-validation",
        "normative_source": "Python csdid csdid/test_csdid/test_validation.py subordinate to R did 2.5.1 validation behavior",
        "source_commit": "555f28bc12fcafa9c099e6e5503a30a4c22fc89f",
        "decision_refs": ["D004", "D010", "D014"],
        "tolerance_ids": ["EXACT"],
        "inputs": [
            {"path": "inputs/sample.csv", "rows": int(base.shape[0]), "columns": int(base.shape[1])},
            {"path": "inputs/negative-weight.csv", "rows": int(neg_weight.shape[0]), "columns": int(neg_weight.shape[1])},
            {"path": "inputs/duplicate.csv", "rows": int(duplicate.shape[0]), "columns": int(duplicate.shape[1])},
        ],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py024/generate.py", "path": "tools/parity/generators/py024/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"seed": 42, "kind": "numpy.random.seed", "draws": "randn"},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/valid-scenarios.csv", "schema": "validation-valid-scenarios"},
        ],
        "comparison_plan": [
            {"actual": "Stata captured validation return codes and messages", "expected": "source-test-map mapped scenarios", "tolerance_id": "EXACT", "key_columns": ["source_test"]},
        ],
        "approved_divergence": {
            "status": "approved-divergence",
            "reason": "Python-only reserved internal column names w and rowid do not map to Stata's command surface; Stata allows user variables with those names unless they conflict with explicit option variables. All other source validation tests are mapped to Stata diagnostics."
        },
        "scope_note": "PY024 maps 20 validation tests to Stata diagnostics and valid-run checks. Two Python internal reserved-name tests are approved divergences because Stata has no hidden w/rowid data-column reservation in this command surface."
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
