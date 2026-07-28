#!/usr/bin/env python3
"""Generate PY010 plotting inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py010"


def build_sim_data(n: int = 300, time_periods: int = 4, te: float = 1.0, seed: int = 20260401) -> pd.DataFrame:
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
        frames.append(pd.DataFrame({
            "id": ids,
            "period": t,
            "g": unit_g,
            "y": y,
            "x": x,
        }))
    return pd.concat(frames, ignore_index=True)


def main() -> None:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    data = build_sim_data()
    data.to_csv(FIXTURE / "inputs/sim-ggdid.csv", index=False)

    mapped = [
        ("test_plot_attgt_returns_figure", "attgt_plot_data", "matplotlib Figure creation mapped to Stata plot-data file creation"),
        ("test_plot_attgt_with_single_group", "attgt_single_group_plot_data", "group argument mapped to Stata group() plot-data filter"),
        ("test_plot_aggte_dynamic", "aggte_dynamic_plot_data", "dynamic Axes creation mapped to dynamic plot-data export"),
        ("test_plot_aggte_group", "aggte_group_plot_data", "group Axes creation mapped to group plot-data export"),
        ("test_plot_aggte_calendar", "aggte_calendar_plot_data", "calendar Axes creation mapped to calendar plot-data export"),
    ]
    divergent = [
        ("test_plot_attgt_with_custom_labels", "PY010-DIV001", "matplotlib label/title rendering options have no Stata plot-data analogue"),
        ("test_plot_attgt_invalid_group_raises", "PY010-DIV002", "Python raises for invalid groups, while R did warns and the Stata port follows the R-like warning/all-groups behavior"),
        ("test_plot_aggte_custom_labels", "PY010-DIV001", "matplotlib label/theme rendering options have no Stata plot-data analogue"),
        ("test_plot_aggte_no_theming", "PY010-DIV001", "matplotlib theming toggle has no Stata plot-data analogue"),
        ("test_plot_aggte_no_ref_line", "PY010-DIV001", "matplotlib reference-line toggle has no Stata plot-data analogue"),
    ]
    for typec in ["dynamic", "group", "calendar"]:
        for theming in [True, False]:
            divergent.append((
                f"test_plot_aggte_all_types_theming[{typec}-{theming}]",
                "PY010-DIV001",
                "matplotlib theming parameterization has no Stata plot-data analogue",
            ))

    rows = [
        {
            "source_file": "csdid/test_csdid/test_ggdid.py",
            "source_sha256": "75cc08b6418c85f2b4c73d05fa3affc239e9ee2e463165c932e899b6236f4376",
            "source_test": test,
            "mapped_scenario": scenario,
            "assertion_family": assertion,
            "coverage_status": "mapped",
            "divergence_id": "",
        }
        for test, scenario, assertion in mapped
    ]
    rows.extend([
        {
            "source_file": "csdid/test_csdid/test_ggdid.py",
            "source_sha256": "75cc08b6418c85f2b4c73d05fa3affc239e9ee2e463165c932e899b6236f4376",
            "source_test": test,
            "mapped_scenario": "python-rendered-graph-api",
            "assertion_family": assertion,
            "coverage_status": "approved-divergence",
            "divergence_id": divergence_id,
        }
        for test, divergence_id, assertion in divergent
    ])
    upstream_map = pd.DataFrame(rows)
    upstream_map.to_csv(FIXTURE / "expected/contract/upstream-test-map.csv", index=False)
    (FIXTURE / "expected/contract/upstream-test-map.json").write_text(
        json.dumps(upstream_map.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    divergence = pd.DataFrame([
        {
            "divergence_id": "PY010-DIV001",
            "source_tests": "; ".join([test for test, div_id, _ in divergent if div_id == "PY010-DIV001"]),
            "reason": "Python plotting tests exercise matplotlib label, theme, and reference-line controls. The Stata port currently freezes numerical plot-data export and rejects graph styling options.",
            "accepted_behavior": "Stata csdid_plot saves ATT(g,t) and aggregation plot data; unsupported styling options fail with a diagnostic.",
        },
        {
            "divergence_id": "PY010-DIV002",
            "source_tests": "test_plot_attgt_invalid_group_raises",
            "reason": "Python raises for invalid plot groups, but R did test-ggdid.R treats invalid groups as a warning path. The Python package is subordinate to R for parity decisions.",
            "accepted_behavior": "Stata follows the R-like behavior: it emits an informational diagnostic and reports all available groups.",
        },
    ])
    divergence.to_csv(FIXTURE / "expected/contract/approved-divergence.csv", index=False)
    (FIXTURE / "expected/contract/approved-divergence.json").write_text(
        json.dumps(divergence.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    scenarios = pd.DataFrame([
        {"scenario": "attgt_plot_data", "expected_rc": 0, "min_rows": 1},
        {"scenario": "attgt_single_group_plot_data", "expected_rc": 0, "min_rows": 1},
        {"scenario": "attgt_invalid_group_r_like_warning", "expected_rc": 0, "min_rows": 1},
        {"scenario": "aggte_dynamic_plot_data", "expected_rc": 0, "min_rows": 1},
        {"scenario": "aggte_group_plot_data", "expected_rc": 0, "min_rows": 1},
        {"scenario": "aggte_calendar_plot_data", "expected_rc": 0, "min_rows": 1},
        {"scenario": "unsupported_style_option", "expected_rc": 198, "min_rows": 0},
    ])
    scenarios.to_csv(FIXTURE / "expected/contract/plot-scenarios.csv", index=False)

    manifest = {
        "matrix_id": "PY010",
        "fixture_family": "python-plotting-public-surface",
        "normative_source": "Python csdid csdid/test_csdid/test_ggdid.py subordinate to R did 2.5.1 plotting behavior",
        "source_commit": "555f28bc12fcafa9c099e6e5503a30a4c22fc89f",
        "decision_refs": ["D004", "D015"],
        "tolerance_ids": ["TOL005", "EXACT"],
        "inputs": [{"path": "inputs/sim-ggdid.csv", "rows": int(data.shape[0]), "columns": int(data.shape[1])}],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py010/generate.py", "path": "tools/parity/generators/py010/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"seed": 20260401, "kind": "numpy.default_rng", "draws": "standard_normal"},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/approved-divergence.csv", "schema": "approved-divergence"},
            {"path": "expected/contract/approved-divergence.json", "schema": "approved-divergence"},
            {"path": "expected/contract/plot-scenarios.csv", "schema": "plot-scenario-contract"},
        ],
        "comparison_plan": [
            {"actual": "Stata csdid_plot ATT(g,t) and aggregation plot-data files", "expected": "expected/contract/plot-scenarios.csv", "tolerance_id": "EXACT", "key_columns": ["scenario"]},
            {"actual": "Stata diagnostics for invalid group and unsupported style options", "expected": "expected/contract/approved-divergence.csv", "tolerance_id": "EXACT", "key_columns": ["divergence_id"]},
        ],
        "approved_divergence": {
            "status": "approved-divergence",
            "path": "expected/contract/approved-divergence.csv",
            "reason": "Python matplotlib styling and invalid-group behavior do not override the R did plotting contract.",
        },
        "scope_note": "PY010 maps Python plotting object-creation tests to Stata csdid_plot plot-data export for ATT(g,t), single-group filtering, and dynamic/group/calendar aggregation. Approved divergence records Python/matplotlib styling options and the Python invalid-group raising behavior, because the Stata port follows R did plot-data and invalid-group warning semantics.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
