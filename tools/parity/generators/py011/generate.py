#!/usr/bin/env python3
"""Generate PY011 glance/DIDparams inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py011"


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

    data = build_sim_data()
    data.to_csv(FIXTURE / "inputs/sim-glance.csv", index=False)

    metadata = pd.DataFrame([
        {"object": "MP", "method": "dr", "nobs": 1000, "ngroup": 3, "ntime": 4, "control_group": "nevertreated", "est_method": "dr"},
        {"object": "aggte_simple", "method": "dr", "nobs": 1000, "ngroup": 3, "ntime": 4, "control_group": "nevertreated", "est_method": "dr"},
        {"object": "aggte_dynamic", "method": "dr", "nobs": 1000, "ngroup": 3, "ntime": 4, "control_group": "nevertreated", "est_method": "dr"},
        {"object": "aggte_group", "method": "dr", "nobs": 1000, "ngroup": 3, "ntime": 4, "control_group": "nevertreated", "est_method": "dr"},
        {"object": "aggte_calendar", "method": "dr", "nobs": 1000, "ngroup": 3, "ntime": 4, "control_group": "nevertreated", "est_method": "dr"},
        {"object": "fast", "method": "dr", "nobs": 1000, "ngroup": 3, "ntime": 4, "control_group": "nevertreated", "est_method": "dr"},
        {"object": "method_dr", "method": "dr", "nobs": 1000, "ngroup": 3, "ntime": 4, "control_group": "nevertreated", "est_method": "dr"},
        {"object": "method_reg", "method": "reg", "nobs": 1000, "ngroup": 3, "ntime": 4, "control_group": "nevertreated", "est_method": "reg"},
        {"object": "method_ipw", "method": "ipw", "nobs": 1000, "ngroup": 3, "ntime": 4, "control_group": "nevertreated", "est_method": "ipw"},
    ])
    metadata.to_csv(FIXTURE / "expected/contract/glance-metadata.csv", index=False)

    source_tests = [
        ("test_didparams_has_expected_keys", "MP", "DIDparams keys n/nG/nT/control_group/est_method"),
        ("test_didparams_values_are_reasonable", "MP", "positive n/nG/nT and valid control/method"),
        ("test_nobs_matches_unique_ids", "MP", "n equals unique id count"),
        ("test_ngroup_matches_treatment_groups", "MP", "nG equals treated group count"),
        ("test_ntime_matches_time_periods", "MP", "nT equals time-period count"),
        ("test_aggte_has_didparams[simple]", "aggte_simple", "DIDparams keys exist"),
        ("test_aggte_has_didparams[dynamic]", "aggte_dynamic", "DIDparams keys exist"),
        ("test_aggte_has_didparams[group]", "aggte_group", "DIDparams keys exist"),
        ("test_aggte_has_didparams[calendar]", "aggte_calendar", "DIDparams keys exist"),
        ("test_aggte_didparams_not_null[simple]", "aggte_simple", "DIDparams values nonmissing"),
        ("test_aggte_didparams_not_null[dynamic]", "aggte_dynamic", "DIDparams values nonmissing"),
        ("test_aggte_didparams_not_null[group]", "aggte_group", "DIDparams values nonmissing"),
        ("test_aggte_didparams_not_null[calendar]", "aggte_calendar", "DIDparams values nonmissing"),
        ("test_aggte_and_mp_nobs_agree", "aggte_all", "aggregation nobs equals MP nobs"),
        ("test_glance_faster_mode", "fast", "fast request returns metadata and finite ATT"),
        ("test_glance_faster_mode_agreement", "fast", "fast request agrees with standard metadata and ATT"),
        ("test_didparams_consistent_across_methods[dr]", "method_dr", "DIDparams est_method and positive counts"),
        ("test_didparams_consistent_across_methods[reg]", "method_reg", "DIDparams est_method and positive counts"),
        ("test_didparams_consistent_across_methods[ipw]", "method_ipw", "DIDparams est_method and positive counts"),
    ]
    upstream_map = pd.DataFrame([
        {
            "source_file": "csdid/test_csdid/test_glance.py",
            "source_sha256": "b750928e7c29d052194ac74ad22e928f3b153ef9d843350f422d67e40386d2ae",
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
        "matrix_id": "PY011",
        "fixture_family": "python-glance-didparams",
        "normative_source": "Python csdid csdid/test_csdid/test_glance.py subordinate to R did 2.5.1 metadata behavior",
        "source_commit": "555f28bc12fcafa9c099e6e5503a30a4c22fc89f",
        "decision_refs": ["D004", "D014"],
        "tolerance_ids": ["EXACT", "TOL002"],
        "inputs": [{"path": "inputs/sim-glance.csv", "rows": int(data.shape[0]), "columns": int(data.shape[1])}],
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py011/generate.py", "path": "tools/parity/generators/py011/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"seed": 20260401, "kind": "numpy.default_rng", "draws": "standard_normal"},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/glance-metadata.csv", "schema": "glance-metadata"},
        ],
        "comparison_plan": [
            {"actual": "Stata e() and csdid_estat glance metadata", "expected": "expected/contract/glance-metadata.csv", "tolerance_id": "EXACT", "key_columns": ["object"]},
            {"actual": "Stata fast request metadata and ATT agreement", "expected": "live Stata matrix equality", "tolerance_id": "TOL002", "key_columns": ["object"]},
        ],
        "approved_divergence": None,
        "scope_note": "PY011 maps every test in Python csdid test_glance.py to Stata e()/glance metadata checks: DIDparams keys and positive values, nobs/ngroup/ntime consistency, aggregation DIDparams for all four types, fast-request metadata and ATT agreement through the optimized path, and dr/reg/ipw method metadata.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
