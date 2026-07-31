#!/usr/bin/env python3
"""Generate PY003 att_gt inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py003"
SOURCE_FILE = "csdid/test_csdid/test_att_gt.py"
SOURCE_SHA = "65d153387ad39131aa5a9f5f87abf9ae8081bf562cc26ff3bf390b953ea154fe"
SOURCE_COMMIT = "555f28bc12fcafa9c099e6e5503a30a4c22fc89f"


def build_sim_data(
    n: int = 1000,
    time_periods: int = 4,
    te: float = 1.0,
    te_e: list[float] | None = None,
    seed: int = 9142024,
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


def write_input(name: str, data: pd.DataFrame) -> dict[str, object]:
    rel = f"inputs/{name}"
    data.to_csv(FIXTURE / rel, index=False)
    return {"path": rel, "rows": int(data.shape[0]), "columns": int(data.shape[1])}


def add_map(
    rows: list[dict[str, str]],
    source_test: str,
    scenario: str,
    assertion: str,
    coverage_status: str = "mapped",
    divergence_id: str = "",
) -> None:
    rows.append({
        "source_file": SOURCE_FILE,
        "source_sha256": SOURCE_SHA,
        "source_test": source_test,
        "mapped_scenario": scenario,
        "assertion_family": assertion,
        "coverage_status": coverage_status,
        "divergence_id": divergence_id,
    })


def main() -> None:
    for path in ["inputs", "expected/contract", "metadata"]:
        (FIXTURE / path).mkdir(parents=True, exist_ok=True)

    inputs = []
    sim = build_sim_data(n=800)
    inputs.append(write_input("sim-data.csv", sim))
    inputs.append(write_input("two-period.csv", build_sim_data(n=1200, time_periods=2, te=1.0, seed=3)))
    inputs.append(write_input("dynamic.csv", build_sim_data(n=1000, time_periods=4, te=0, te_e=[1, 2, 3, 4], seed=10)))
    inputs.append(write_input("dynamic-rc.csv", build_sim_data(n=1000, time_periods=4, te=0, te_e=[1, 2, 3, 4], seed=7)))

    unequal = build_sim_data(n=1000, time_periods=8, te=0, te_e=[1, 2, 3, 4, 5, 6, 7, 8], seed=11)
    unequal = unequal[unequal["period"].isin([1, 2, 5, 7])].copy()
    unequal = unequal[unequal["g"].isin([0, 1, 2, 5, 7])].copy()
    inputs.append(write_input("unequal-periods.csv", unequal))

    anticipation = build_sim_data(n=1000, time_periods=5, te=0, te_e=[-1, 0, 1, 2, 3], seed=14)
    anticipation["g"] = anticipation["g"].map(lambda g: 0 if g == 0 else g + 1)
    anticipation = anticipation[anticipation["g"] <= 5].copy()
    inputs.append(write_input("anticipation.csv", anticipation))

    unbalanced = sim.drop(index=[1]).reset_index(drop=True)
    inputs.append(write_input("unbalanced.csv", unbalanced))

    no_never = sim[sim["g"] > 0].copy()
    inputs.append(write_input("no-never.csv", no_never))

    small = sim.copy()
    g2_ids = small.loc[small["g"] == 2, "id"].unique()
    small = small[(small["g"] != 2) | (small["id"] == g2_ids[0])].copy()
    inputs.append(write_input("small-groups.csv", small))

    rng = np.random.default_rng(11)
    fix = build_sim_data(n=800, time_periods=4, te=1.0, seed=11)
    fix["wt"] = 1.0 + 0.2 * fix["period"] + rng.uniform(0, 0.5, len(fix))
    inputs.append(write_input("fixweights.csv", fix))

    fix_const = build_sim_data(n=800, time_periods=4, te=1.0, seed=7)
    fix_const["wt"] = 1.0 + (fix_const["id"] % 5)
    inputs.append(write_input("fixweights-constant.csv", fix_const))

    fix_unbalanced = fix.drop(index=[1]).reset_index(drop=True)
    inputs.append(write_input("fixweights-unbalanced.csv", fix_unbalanced))

    nonconsec = build_sim_data(n=900, time_periods=6, te=0, te_e=[1, 2, 3, 4, 5, 6], seed=7)
    nonconsec = nonconsec[nonconsec["period"] != 3].reset_index(drop=True)
    inputs.append(write_input("nonconsecutive.csv", nonconsec))

    source_rows: list[dict[str, str]] = []
    for method in ["dr", "reg"]:
        add_map(source_rows, f"test_att_gt_dr_and_reg[{method}]", "basic-covariate-panel", "ATT(g,t) first post-treatment effect is near the simulated unit effect")
    for method in ["dr", "ipw"]:
        add_map(source_rows, f"test_att_gt_ipw[{method}]", "basic-no-covariate-panel", "DR and IPW work without covariates")
    for agg_type in ["simple", "dynamic", "group", "calendar"]:
        add_map(source_rows, f"test_two_period_case[{agg_type}]", "two-period-aggregation", "two-period aggregation is finite and near the simulated unit effect")
    for method in ["dr", "reg"]:
        add_map(source_rows, f"test_no_covariates[{method}]", "no-covariates", "no-covariate ATT(g,t) is finite and near the simulated unit effect")
    for method in ["dr", "reg"]:
        add_map(source_rows, f"test_repeated_cross_section[{method}]", "repeated-cross-section", "repeated-cross-section ATT(g,t) is finite and near the simulated unit effect")
    for method in ["dr", "ipw"]:
        add_map(source_rows, f"test_ipw_repeated_cross_sections[{method}]", "ipw-repeated-cross-section", "DR and IPW repeated-cross-section estimators are finite")

    singleton_tests = [
        ("test_rc_dynamic_effects", "rc-dynamic-effects", "dynamic event-time effect recovers the exposure-varying DGP"),
        ("test_unbalanced_panel", "allow_unbalanced", "unbalanced ivar data is routed through the R-compatible repeated-cross-section path"),
        ("test_notyettreated_rc", "notyettreated-rc", "not-yet-treated repeated-cross-section control group is finite"),
        ("test_notyettreated_no_nevertreated", "notyettreated-no-never", "not-yet-treated control works with no never-treated cohort"),
        ("test_nevertreated_coerces_no_nevertreated", "nevertreated-fallback-no-never", "nevertreated control with no never-treated cohort warns and falls back to the latest cohort"),
        ("test_aggregation_dynamic", "dynamic-aggregation", "dynamic aggregation recovers the exposure-varying DGP"),
        ("test_aggregation_balance_e", "dynamic-balance-e", "balance_e dynamic aggregation never increases the number of event-time rows"),
        ("test_unequally_spaced_groups", "unequally-spaced-groups", "dynamic aggregation supports unequally spaced time periods and cohorts"),
        ("test_first_period_treatment", "first-period-treated-warning", "first-period treated units are dropped with a warning"),
        ("test_min_max_exposures", "dynamic-min-max-window", "dynamic min_e/max_e windowing keeps the requested exposure window"),
        ("test_significance_level", "level-and-cband", "level and confidence-band metadata are coherent"),
        ("test_malformed_data_bad_idname", "bad-idname-error", "invalid id variable fails clearly"),
        ("test_sampling_weights", "unit-weight-equivalence", "unit weights match the unweighted subset result"),
        ("test_clustered_se", "clustered-se", "numeric cluster standard errors are finite and recorded"),
    ]
    for source_test, scenario, assertion in singleton_tests:
        add_map(source_rows, source_test, scenario, assertion)

    for ant in [1, 0]:
        add_map(source_rows, f"test_anticipation[anticipation={ant}]", "anticipation-dynamic", "anticipation shifts dynamic event-time effects")
    for base_period in ["varying", "universal"]:
        add_map(source_rows, f"test_varying_vs_universal_base[{base_period}]", "varying-vs-universal-base", "varying and universal base-period dynamic aggregation are finite")
    for method in ["dr", "reg"]:
        add_map(source_rows, f"test_small_groups[{method}]", "small-groups", "small treated groups warn but other cohorts remain estimable")
    for surface in ["attgt", "simple", "dynamic"]:
        add_map(source_rows, f"test_column_naming_gname[{surface}]", "reserved-column-names", "user columns named like API arguments remain usable")

    add_map(
        source_rows,
        "test_custom_est_method",
        "python-callable-estimator-only",
        "Python callable est_method has no public Stata command analogue",
        "approved-divergence",
        "PY003-DIV001",
    )

    for name in ["panel", "rcs", "unbalanced", "filtered", "time_indexing_rc", "time_indexing_panel", "time_indexing_nonconsec", "time_indexing_universal"]:
        add_map(source_rows, f"TestFasterMode.test_{name}", f"fast-mode-{name}", "requested fast path matches the standard path on public ATT(g,t) results")

    for fix_weights in ["none", "varying", "base_period", "first_period"]:
        add_map(source_rows, f"TestFixWeights.test_fix_weights_options[{fix_weights}]", "fixweights-options", "fix_weights modes produce finite ATT(g,t) estimates")
    for fix_weights in ["varying", "base_period", "first_period"]:
        add_map(source_rows, f"TestFixWeights.test_time_invariant[{fix_weights}]", "fixweights-time-invariant", "time-invariant weights match default point estimates")
    for name, scenario in [
        ("tv_weights_match", "fixweights-tv-difference"),
        ("nyt_tv_weights", "fixweights-notyettreated"),
        ("rc_tv_weights", "fixweights-rc-varying"),
        # Upstream has one TestFixWeights.test_validation containing two raises.
        # Recording them as test_validation_invalid / _rc_fixed invented names
        # upstream does not have, so neither matched and the test read as
        # unmapped. [case] is the convention the coverage gate understands for
        # splitting one upstream test into per-case rows.
        ("validation[invalid]", "fixweights-invalid"),
        ("validation[rc_fixed]", "fixweights-rc-fixed-error"),
        ("unbalanced", "fixweights-unbalanced"),
    ]:
        add_map(source_rows, f"TestFixWeights.test_{name}", scenario, "fix_weights public behavior matches the Python/R contract")

    for name in ["balanced", "notyettreated", "rc", "unbalanced", "no_covariates"]:
        add_map(source_rows, f"TestIFConsistency.test_{name}", f"if-consistency-{name}", "requested fast path preserves influence-function summaries")

    for method in ["dr", "reg", "ipw"]:
        add_map(source_rows, f"test_basic_estimation_all_methods[{method}]", "param-basic-all-methods", "all methods produce finite covariate ATT(g,t)")
        add_map(source_rows, f"test_no_covariates_all_methods[{method}]", "param-no-covariates-all-methods", "all methods produce finite no-covariate ATT(g,t)")
        add_map(source_rows, f"test_repeated_cross_section_all_methods[{method}]", "param-rc-all-methods", "all methods produce finite repeated-cross-section ATT(g,t)")
        add_map(source_rows, f"test_notyettreated_all_methods[{method}]", "param-notyettreated-all-methods", "all methods produce finite not-yet-treated ATT(g,t)")
        add_map(source_rows, f"test_anticipation_all_methods[{method}]", "param-anticipation-all-methods", "all methods produce finite dynamic anticipation aggregation")
        add_map(source_rows, f"test_column_naming_variations[{method}]", "param-column-variations", "all methods accept user column names that overlap API terms")
        for agg_type in ["simple", "dynamic", "group", "calendar"]:
            add_map(source_rows, f"test_two_period_all_methods[{method},{agg_type}]", "param-two-period-all-methods", "all methods support all aggregation types in two-period data")

    upstream_map = pd.DataFrame(source_rows)
    upstream_map.to_csv(FIXTURE / "expected/contract/upstream-test-map.csv", index=False)
    (FIXTURE / "expected/contract/upstream-test-map.json").write_text(
        json.dumps(upstream_map.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    divergence = pd.DataFrame([{
        "divergence_id": "PY003-DIV001",
        "source_tests": "test_custom_est_method",
        "reason": "The Python source accepts a callable est_method object and compares it against the built-in reg estimator. Stata commands do not expose a public callback surface that accepts user-supplied ATT and influence-function computations.",
        "accepted_behavior": "Stata verifies built-in dr/reg/ipw methods, method validation, and public fast/baseline equality through PY003, PY009, RT012, and F032. Custom user callbacks are outside the frozen public Stata command profile.",
    }])
    divergence.to_csv(FIXTURE / "expected/contract/approved-divergence.csv", index=False)
    (FIXTURE / "expected/contract/approved-divergence.json").write_text(
        json.dumps(divergence.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    scenarios = pd.DataFrame([
        {"scenario": "basic-covariate-panel", "input": "sim-data.csv", "expected_behavior": "ATT(g,t) first treated cell near one"},
        {"scenario": "two-period-aggregation", "input": "two-period.csv", "expected_behavior": "all aggte types finite and near one"},
        {"scenario": "dynamic-aggregation", "input": "dynamic.csv", "expected_behavior": "event-time effect around exposure-varying DGP"},
        {"scenario": "allow_unbalanced", "input": "unbalanced.csv", "expected_behavior": "ivar unbalanced panel reports allow_unbalanced and finite ATT"},
        {"scenario": "fixweights-options", "input": "fixweights.csv", "expected_behavior": "fix_weights modes finite or reject when unsupported for RC"},
        {"scenario": "fast-if-consistency", "input": "sim-data.csv", "expected_behavior": "requested fast equals standard and preserves IF summaries"},
    ])
    scenarios.to_csv(FIXTURE / "expected/contract/scenarios.csv", index=False)

    manifest = {
        "matrix_id": "PY003",
        "fixture_family": "python-att-gt",
        "normative_source": "Python csdid csdid/test_csdid/test_att_gt.py subordinate to R did 2.5.1 ATT(g,t) behavior",
        "source_commit": SOURCE_COMMIT,
        "decision_refs": ["D004", "D014"],
        "tolerance_ids": ["TOL002"],
        "inputs": inputs,
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py003/generate.py", "path": "tools/parity/generators/py003/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"kind": "numpy.default_rng", "seeds": [9142024, 3, 7, 10, 11, 13, 14]},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/approved-divergence.csv", "schema": "approved-divergence"},
            {"path": "expected/contract/approved-divergence.json", "schema": "approved-divergence"},
            {"path": "expected/contract/scenarios.csv", "schema": "att-gt-public-scenario-grid"},
        ],
        "comparison_plan": [
            {"actual": "Stata public ATT(g,t), aggregation, fast, IF, fix_weights, and validation checks", "expected": "source invariant map", "tolerance_id": "TOL002", "key_columns": ["source_test"]},
        ],
        "approved_divergence": {"status": "approved-divergence", "path": "expected/contract/approved-divergence.csv"},
        "scope_note": "PY003 maps 93 public Python ATT(g,t) assertions to Stata public-command gates and records the Python callable estimator surface as PY003-DIV001. The gate verifies core dr/reg/ipw estimation, repeated cross-sections, allow_unbalanced routing, not-yet-treated controls, no-never fallback, dynamic aggregation, exposure windows, anticipation, level/cband metadata, validation failures, base-period modes, small-group warnings, weights, cluster SEs, fast/baseline equality, fix_weights behavior, influence-function summaries, and user column-name variations.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
