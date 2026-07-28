#!/usr/bin/env python3
"""Generate PY025: inheritance record for the Python csdid unit-test suite.

Python csdid 0.4.x added six test_unit_* files -- 106 tests covering the
DRDID 2x2 estimators, the multiplier bootstrap, preprocessing/validation, the
shared ATT(g,t) helpers, the aggregations, and compute_att_gt. They were
initially left out of the inheritance record on the grounds that they test
Python internals with no Stata surface.

That was too sweeping. Read individually, most of them assert behaviour a Stata
user can observe: the 0.999 overlap threshold, pscore trimming, rejection of
negative weights and duplicate (id, time) rows, min_e/max_e/balance_e windows,
faster-mode equivalence, influence-function mean-zero. csdid either has that
behaviour or should. Only eight are genuinely inapplicable, and each says why.

Every one of the 106 is classified here. A test that appears upstream and is not
in CLASSIFICATION raises, so the record cannot silently fall behind again.
"""

from __future__ import annotations

import csv
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py025"
INVENTORY = ROOT / "inst/spec/upstream-csdid-python-tests.csv"
UNIT_FILES = {
    "test_unit_aggte.py", "test_unit_attgt_shared.py", "test_unit_compute_attgt.py",
    "test_unit_drdid.py", "test_unit_mboot.py", "test_unit_preprocess.py",
}

M = "mapped"
D = "approved-divergence"

# test name -> (where the behaviour is asserted in this repo, assertion family, status)
CLASSIFICATION: dict[str, tuple[str, str, str]] = {
    # ---- aggregations ------------------------------------------------------
    "test_simple_overall_matches_weighted_average": ("test-aggte-comprehensive.do simple", "aggregation-value-vs-r", M),
    "test_group_per_group_and_overall": ("test-aggte-comprehensive.do group", "aggregation-value-vs-r", M),
    "test_dynamic_event_times_and_overall": ("test-aggte-comprehensive.do dynamic", "aggregation-value-vs-r", M),
    "test_calendar_per_time_and_overall": ("test-aggte-comprehensive.do calendar", "aggregation-value-vs-r", M),
    "test_dynamic_max_e_window": ("test-f025.do window() upper bound", "event-window-bounds", M),
    "test_dynamic_min_e_window": ("test-f025.do window() lower bound", "event-window-bounds", M),
    "test_dynamic_balance_e_bounds_event_times": ("test-f017.do balanced event sample", "event-window-bounds", M),
    "test_invalid_type_raises": ("test-f036.do csdid_stats type() refusal", "option-refusal", M),
    "test_all_types_have_positive_overall_se": ("test-inference.do aggregation SEs", "aggregation-value-vs-r", M),
    "test_cband_crit_val_exceeds_pointwise": ("test-f025.do e(crit_val) vs e(point_crit_val)", "uniform-band-critical-value", M),
    "test_get_se_analytic_formula": ("py019 ref_aggte.csv SE vs R", "aggregation-value-vs-r", M),
    "test_get_agg_inf_func_weighted_combination": ("py019 ref_aggte.csv SE vs R", "aggregation-influence-function", M),
    "test_get_agg_inf_func_adds_weight_if": ("py019 ref_aggte.csv SE vs R (estimated-weight term)", "aggregation-influence-function", M),
    # The aggregated influence function is not exported by csdid_stats, so this
    # cannot be asserted directly. It is covered indirectly and tightly: the
    # aggregated SE is computed from that influence function and matches R to
    # <1e-9 in py019, which a wrong weight term would move.
    "test_wif_mean_zero_columns": ("py019 ref_aggte.csv SE vs R (aggregated IF not exported)", "aggregation-influence-function", M),

    # ---- shared ATT(g,t) helpers ------------------------------------------
    "test_lpi_basic": ("test_unit_inheritance.do varying base period", "base-period-selection", M),
    "test_lpi_no_pretreatment_returns_none": ("test_unit_inheritance.do no pre-treatment cell", "base-period-selection", M),
    "test_lpi_anticipation_shifts": ("test-f009.do anticipation shifts the base period", "base-period-selection", M),
    "test_plan_cell_pre_period_estimate": ("rt031 varying base period", "base-period-selection", M),
    "test_plan_cell_post_period_uses_last_pretreatment": ("rt031 varying base period", "base-period-selection", M),
    "test_plan_cell_universal_base_zero": ("rt031 universal base period", "base-period-selection", M),
    "test_plan_cell_universal_no_pretreatment_breaks": ("test_unit_inheritance.do no pre-treatment cell", "base-period-selection", M),
    "test_plan_cell_post_no_pretreatment_breaks": ("test_unit_inheritance.do no pre-treatment cell", "base-period-selection", M),
    "test_select_estimators_dr": ("test-att_gt.do method(dr)", "estimator-dispatch", M),
    "test_select_estimators_ipw": ("test-att_gt.do method(ipw)", "estimator-dispatch", M),
    "test_select_estimators_reg": ("test-att_gt.do method(reg)", "estimator-dispatch", M),
    "test_select_estimators_callable": (
        "n/a -- csdid takes no callable estimator; method() is dr, reg or ipw and "
        "anything else is rejected (rc 198)", "estimator-dispatch", D),
    "test_rcond_full_rank_passes": ("test-f011.do full-rank design", "singular-design-guard", M),
    "test_rcond_collinear_fails": ("test-f011.do collinear design warns and skips the cell", "singular-design-guard", M),
    "test_rcond_no_control_fails": ("test_percell_failure.do cell with no controls", "singular-design-guard", M),
    "test_overlap_balanced_ok": ("test-overlap-guard-cache.do balanced design", "overlap-guard", M),
    "test_overlap_all_treated_violates": ("test-f040.do overlap violation warning", "overlap-guard", M),
    "test_overlap_threshold_is_0999": ("test-f040.do 0.999 propensity threshold", "overlap-guard", M),
    "test_overlap_empty_no_violation": ("test-overlap-guard-cache.do empty cell", "overlap-guard", M),
    "test_design_singular_panel_full_rank": ("test-f011.do panel full rank", "singular-design-guard", M),
    "test_design_singular_panel_control_singular": ("test-f011.do singular control design", "singular-design-guard", M),
    "test_design_singular_ipw_checks_ps_fullsample": ("test_percell_failure.do ipw full-sample propensity", "singular-design-guard", M),
    "test_design_singular_rc_full_rank": ("test-f011.do repeated cross-section full rank", "singular-design-guard", M),
    "test_design_singular_rc_tiny_treated_post_fails": ("test_percell_failure.do tiny treated-post cell", "singular-design-guard", M),

    # ---- compute_att_gt ----------------------------------------------------
    "test_faster_equals_standard": ("test-f032.do fast and standard paths agree", "fast-path-equivalence", M),
    "test_faster_equals_standard_fix_weights_varying": ("py019 ref_fixweights.csv varying, both paths", "fast-path-equivalence", M),
    "test_constant_te_recovered_and_post_flag": ("rt031 recovers the true effect of 3", "attgt-value-vs-r", M),
    "test_inffunc_overall_mean_zero": ("test_unit_inheritance.do e(inffunc) columns mean-zero", "influence-function-mean-zero", M),

    # ---- DRDID 2x2 estimators ---------------------------------------------
    "test_drdid_panel_att_closed_form": ("py019 ref_attgt.csv panel dr ATT vs R", "attgt-value-vs-r", M),
    "test_ipw_panel_att_closed_form": ("py019 ref_attgt.csv panel ipw ATT vs R", "attgt-value-vs-r", M),
    "test_drdid_rc_att_closed_form": ("py019 sim/ref_gaps.csv rc ATT vs R", "attgt-value-vs-r", M),
    "test_ipw_rc_att_closed_form": ("py019 sim/ref_gaps.csv rc ipw ATT vs R", "attgt-value-vs-r", M),
    "test_drdid_panel_if_closed_form": ("rt008 e(inffunc) element-wise vs R", "influence-function-vs-r", M),
    "test_ipw_panel_if_closed_form": ("rt008 e(inffunc) element-wise vs R", "influence-function-vs-r", M),
    "test_drdid_rc_if_closed_form": ("py006 e(inffunc) element-wise vs R", "influence-function-vs-r", M),
    "test_ipw_rc_if_closed_form": ("py006 e(inffunc) element-wise vs R", "influence-function-vs-r", M),
    "test_drdid_panel_if_fd_with_covariates": ("rt008 e(inffunc) with covariates vs R", "influence-function-vs-r", M),
    "test_panel_if_mean_zero": ("test_unit_inheritance.do e(inffunc) columns mean-zero, panel", "influence-function-mean-zero", M),
    "test_rc_if_mean_zero": ("test_unit_inheritance.do e(inffunc) columns mean-zero, rc", "influence-function-mean-zero", M),
    "test_panel_dr_equals_ipw_intercept_only": ("test_unit_inheritance.do dr equals ipw with no covariates, panel", "estimator-equivalence", M),
    "test_rc_dr_equals_ipw_intercept_only": ("test_unit_inheritance.do dr equals ipw with no covariates, rc", "estimator-equivalence", M),
    "test_panel_weight_scale_invariance": ("test_unit_inheritance.do rescaling iweights leaves ATT unchanged", "weight-scale-invariance", M),
    "test_panel_weighted_att_matches_closed_form": ("py019 ref_fixweights.csv weighted ATT vs R", "attgt-value-vs-r", M),
    "test_panel_negative_weight_raises": ("test-robustness-guards.do negative weights rejected", "option-refusal", M),
    "test_rc_negative_weight_raises": ("test-robustness-guards.do negative weights rejected", "option-refusal", M),
    "test_trim_pscore_clamp_upper": ("test-f051.do propensity clamped at the trim bound", "pscore-trimming", M),
    "test_trim_pscore_controls_threshold": ("test-f033.do pscoretrim() threshold", "pscore-trimming", M),
    "test_trim_pscore_treated_never_trimmed": ("test-f051.do treated units never trimmed", "pscore-trimming", M),
    "test_trim_pscore_mixed_only_controls_affected": ("test-f051.do only controls affected", "pscore-trimming", M),
    "test_panel_trim_default_is_active": ("test-f033.do default pscoretrim(.995)", "pscore-trimming", M),
    "test_rc_trim_default_is_active": ("test-f033.do default pscoretrim(.995)", "pscore-trimming", M),
    "test_default_weights_path_succeeds_all_estimators": ("test-att_gt.do unweighted dr/reg/ipw", "estimator-dispatch", M),

    # ---- multiplier bootstrap ---------------------------------------------
    "test_mb_n1_abs_equals_a_exactly": ("test-f015.do Mallows multiplier draw", "multiplier-draw", M),
    "test_mb_n2_lattice_values": ("test-f015.do Mallows multiplier draw", "multiplier-draw", M),
    "test_mb_rademacher_variance": ("test-f015.do multiplier variance", "multiplier-draw", M),
    "test_mb_division_by_n": ("test-f015.do bootstrap scaling", "bootstrap-scaling", M),
    "test_mb_serial_reproducible_under_global_seed": ("test-f015.do rseed() reproducibility", "bootstrap-reproducibility", M),
    "test_mb_seed_path_independent_of_global": ("test-f015.do rseed() independent of set seed", "bootstrap-reproducibility", M),
    "test_run_multiplier_bootstrap_shape_and_scaling": ("test-bootstrap-plugin.do draw shape", "bootstrap-scaling", M),
    "test_mboot_se_positive_and_crit_exceeds_pointwise": ("test-f025.do e(crit_val) vs e(point_crit_val)", "uniform-band-critical-value", M),
    "test_mboot_se_scales_with_if_magnitude": ("test-bootstrap-plugin.do SE scaling", "bootstrap-scaling", M),
    "test_mboot_degenerate_column_gives_nan_se": ("test_percell_failure.do degenerate cell SE missing", "degenerate-cell", M),
    "test_mboot_all_degenerate_returns_nan": ("test_percell_failure.do all cells degenerate", "degenerate-cell", M),
    "test_mboot_clustered_se_uses_cluster_sums": ("test-inference.do clustered SE vs R", "clustered-inference", M),
    "test_mboot_clustervar_equal_idname_collapses_to_none": ("test-cluster-analytic.do cluster() equal to ivar()", "clustered-inference", M),
    "test_mboot_missing_clustervar_warns_and_falls_back": ("test-aggte-clustervars-override.do fallback warning", "clustered-inference", M),
    "test_mboot_time_varying_cluster_raises": ("test-error-handling.do time-varying cluster rejected", "option-refusal", M),
    "test_mboot_multiple_clustervars_rejected": ("test-error-handling.do cluster() takes one variable", "option-refusal", M),
    "test_parallel_path_row_count_equals_biters": (
        "n/a -- csdid has no parallel bootstrap; there is no cores() option "
        "(rc 198) and the multiplier loop is serial in Mata", "parallel-bootstrap", D),
    "test_parallel_path_reproducible_under_seed": (
        "n/a -- csdid has no parallel bootstrap; rseed() reproducibility is "
        "covered for the serial path by test-f015.do", "parallel-bootstrap", D),
    "test_parallel_path_correct_variance_not_collapsed": (
        "n/a -- csdid has no parallel bootstrap", "parallel-bootstrap", D),
    "test_serial_vs_parallel_branch_selection": (
        "n/a -- csdid has no parallel branch to select", "parallel-bootstrap", D),

    # ---- preprocessing and validation -------------------------------------
    "test_validate_normal_returns_none_clustervar": ("test-inference.do unclustered run", "clustered-inference", M),
    "test_validate_unwraps_single_clustervar": ("test-inference.do cluster(cluster)", "clustered-inference", M),
    "test_validate_rejects_multiple_clustervars": ("test-error-handling.do cluster() takes one variable", "option-refusal", M),
    "test_validate_rejects_time_varying_cluster": ("test-error-handling.do time-varying cluster rejected", "option-refusal", M),
    "test_validate_rejects_negative_gname": ("test-f022.do negative gvar() rejected", "option-refusal", M),
    "test_validate_rejects_negative_weights": ("test-robustness-guards.do negative weights rejected", "option-refusal", M),
    "test_validate_rejects_nonpositive_mean_weights": ("test-robustness-guards.do zero-mean weights rejected", "option-refusal", M),
    "test_validate_accepts_positive_weights": ("test-robustness-guards.do positive weights accepted", "option-refusal", M),
    "test_validate_rejects_invalid_control_group": ("test-error-handling.do control group refusal", "option-refusal", M),
    "test_validate_rejects_negative_anticipation": ("test-f026.do anticipation() must be non-negative", "option-refusal", M),
    "test_validate_rejects_duplicate_id_time": ("test-f024.do duplicate (id, time) rejected", "option-refusal", M),
    "test_validate_rejects_reversible_treatment": ("test-error-handling.do reversible treatment rejected", "option-refusal", M),
    "test_validate_panel_requires_idname": ("test_unit_inheritance.do panel path requires ivar()", "option-refusal", M),
    "test_validate_rejects_nonnumeric_time": ("test_unit_inheritance.do string time() rejected", "option-refusal", M),
    "test_time_varying_weights_warning": ("test-f012.do time-varying weights message", "diagnostic-message", M),
    "test_constant_weights_no_tv_warning": ("test-f012.do no message when weights are constant", "diagnostic-message", M),
    "test_anticipation_text_in_dropped_first_period_warning": ("test-f026.do anticipation wording in the dropped-period message", "diagnostic-message", M),
    "test_strictly_numeric_int_true": (
        "n/a -- Python helper that type-introspects a pandas column. Stata "
        "variables are numeric or string by construction; the user-visible "
        "consequence is covered by the string time() refusal", "internal-helper", D),
    "test_strictly_numeric_bool_false": (
        "n/a -- Python helper; Stata has no boolean column type", "internal-helper", D),
    "test_strictly_numeric_string_false": (
        "n/a -- Python helper; the user-visible consequence is the string "
        "time() refusal", "internal-helper", D),
}


def main() -> None:
    for sub in ("expected/contract", "metadata"):
        (FIXTURE / sub).mkdir(parents=True, exist_ok=True)

    with open(INVENTORY, newline="") as fh:
        inv = list(csv.DictReader(ln for ln in fh if not ln.startswith("#")))
    unit = [r for r in inv if os.path.basename(r["source_file"]) in UNIT_FILES]

    unknown = [r["source_test"] for r in unit if r["source_test"] not in CLASSIFICATION]
    if unknown:
        raise SystemExit(
            "unclassified upstream unit tests (add them to CLASSIFICATION):\n  "
            + "\n  ".join(sorted(unknown)))

    rows = []
    for r in sorted(unit, key=lambda x: (x["source_file"], x["source_test"])):
        scenario, family, status = CLASSIFICATION[r["source_test"]]
        rows.append({
            "source_file": r["source_file"],
            "source_sha256": r["source_sha256"],
            "source_test": r["source_test"],
            "mapped_scenario": scenario,
            "assertion_family": family,
            "coverage_status": status,
            "divergence_id": "PY025-DIV001" if status == D else "",
        })

    contract = FIXTURE / "expected/contract"
    fields = list(rows[0].keys())
    with open(contract / "upstream-test-map.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    (contract / "upstream-test-map.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")

    div = [{
        "divergence_id": "PY025-DIV001",
        "summary": "Python-internal assertions with no csdid surface",
        "rationale": (
            "Eight of the 106 unit tests assert something csdid cannot express. "
            "Four target the parallel multiplier bootstrap: csdid has no cores() "
            "option (rc 198) and runs the multiplier loop serially in Mata, so "
            "there is no parallel branch to select, seed or compare. Three target "
            "a Python type-introspection helper over pandas columns; Stata "
            "variables are numeric or string by construction and the user-visible "
            "consequence -- rejecting a string time() -- is asserted directly. "
            "One targets a callable est_method, which csdid does not accept: "
            "method() is dr, reg or ipw and anything else is rejected (rc 198)."),
        "owner_decision": "recorded as inapplicable rather than left unmapped",
    }]
    with open(contract / "approved-divergence.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(div[0].keys()))
        w.writeheader()
        w.writerows(div)
    (contract / "approved-divergence.json").write_text(json.dumps(div, indent=2), encoding="utf-8")

    n_map = sum(1 for r in rows if r["coverage_status"] == M)
    n_div = len(rows) - n_map
    manifest = {
        "fixture_family": "python-unit-test-inheritance",
        "normative_source": "R did 2.5.1",
        "generators": [{
            "runtime": "Python",
            "command": "python3 tools/parity/generators/py025/generate.py",
            "path": "tools/parity/generators/py025/generate.py",
        }],
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/approved-divergence.csv", "schema": "approved-divergence"},
            {"path": "expected/contract/approved-divergence.json", "schema": "approved-divergence"},
        ],
        "comparison_plan": [{
            "actual": "Stata csdid behaviour asserted by the test named in mapped_scenario",
            "expected": "the corresponding Python csdid unit test",
            "key_columns": ["source_file", "source_test"],
        }],
        "scope_note": (
            f"PY025 classifies all {len(rows)} tests in the six Python csdid test_unit_* files. "
            f"{n_map} are mapped to a Stata assertion, named per row in mapped_scenario; "
            f"{n_div} are recorded as inapplicable under PY025-DIV001. These were initially "
            "excluded wholesale as 'Python internals with no Stata surface', which was wrong: "
            "most assert behaviour a csdid user can observe. The generator raises on any "
            "upstream unit test missing from its classification table, so the record cannot "
            "silently fall behind."),
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"PY025: {len(rows)} rows ({n_map} mapped, {n_div} inapplicable)")


if __name__ == "__main__":
    main()
