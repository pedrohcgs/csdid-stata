#!/usr/bin/env python3
"""Generate PY020 review-fix inheritance fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "tests/fixtures/parity/py020"
SOURCE_FILE = "csdid/test_csdid/test_review_fixes.py"
SOURCE_SHA256 = "e0206e8d37d5577d9616449dda9d1d0e74ffce4adb0f608cf36aa9f02b816711"
SOURCE_COMMIT = "555f28bc12fcafa9c099e6e5503a30a4c22fc89f"


def make_panel(
    n_units: int = 50,
    n_periods: int = 5,
    treatment_period: int = 3,
    seed: int = 42,
) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    ids = np.repeat(np.arange(1, n_units + 1), n_periods)
    years = np.tile(np.arange(1, n_periods + 1), n_units)
    groups = np.repeat(
        np.where(np.arange(1, n_units + 1) <= n_units // 2, treatment_period, 0),
        n_periods,
    )
    y = rng.normal(0, 1, len(ids))
    treated_mask = (groups > 0) & (years >= groups)
    y[treated_mask] += 2.0
    return pd.DataFrame({"id": ids, "year": years, "y": y, "group": groups})


def write_inputs() -> list[dict[str, object]]:
    (FIXTURE / "inputs").mkdir(parents=True, exist_ok=True)
    inputs: list[dict[str, object]] = []

    review = make_panel(n_units=120, n_periods=4, treatment_period=3, seed=5)
    rng = np.random.default_rng(5)
    cat = rng.choice(["a", "b", "c"], size=len(review))
    review["cat"] = cat
    review["cat_code"] = pd.Categorical(cat, categories=["a", "b", "c"]).codes + 1
    review["z"] = np.random.default_rng(1).normal(size=len(review))
    review["y"] = review["y"] + pd.Series(cat).map({"a": 0.0, "b": 0.6, "c": -0.6}).to_numpy()
    review.to_csv(FIXTURE / "inputs/review-panel.csv", index=False)
    inputs.append({"path": "inputs/review-panel.csv", "rows": int(review.shape[0]), "columns": int(review.shape[1])})

    clustered = make_panel(n_units=60, n_periods=5, treatment_period=3, seed=42)
    clustered["cluster"] = np.repeat(np.arange(1, 61) % 10, 5)
    clustered.to_csv(FIXTURE / "inputs/clustered-panel.csv", index=False)
    inputs.append({"path": "inputs/clustered-panel.csv", "rows": int(clustered.shape[0]), "columns": int(clustered.shape[1])})

    bool_outcome = make_panel(n_units=30, n_periods=4, treatment_period=3, seed=42)
    bool_outcome["y_bool"] = (bool_outcome["y"] > 0).astype(int)
    bool_outcome.to_csv(FIXTURE / "inputs/boolean-outcome.csv", index=False)
    inputs.append({"path": "inputs/boolean-outcome.csv", "rows": int(bool_outcome.shape[0]), "columns": int(bool_outcome.shape[1])})

    rows = []
    for uid in range(1, 6):
        for t in (1, 2):
            rows.append((uid, t, 0))
    for uid in range(6, 11):
        for t in (2, 3):
            rows.append((uid, t, 0))
    for uid in range(11, 21):
        for t in (1, 2, 3):
            rows.append((uid, t, 3))
    uniform_missing = pd.DataFrame(rows, columns=["id", "year", "group"])
    uniform_missing["y"] = np.random.default_rng(0).normal(size=len(uniform_missing))
    uniform_missing.to_csv(FIXTURE / "inputs/uniform-missing-periods.csv", index=False)
    inputs.append({"path": "inputs/uniform-missing-periods.csv", "rows": int(uniform_missing.shape[0]), "columns": int(uniform_missing.shape[1])})

    no_never_rows = []
    uid = 1
    for g in (2, 3, 4):
        for _ in range(15):
            for t in range(1, 5):
                no_never_rows.append((uid, t, g))
            uid += 1
    no_never = pd.DataFrame(no_never_rows, columns=["id", "year", "group"])
    no_never["y"] = np.random.default_rng(1).normal(size=len(no_never))
    no_never.to_csv(FIXTURE / "inputs/no-never.csv", index=False)
    inputs.append({"path": "inputs/no-never.csv", "rows": int(no_never.shape[0]), "columns": int(no_never.shape[1])})

    late = make_panel(n_units=30, n_periods=4, treatment_period=4, seed=42)
    extra = late[late["group"] == 0].head(12).copy()
    extra["group"] = 5
    extra["id"] = extra["id"] + 100
    late = pd.concat([late, extra], ignore_index=True)
    late.to_csv(FIXTURE / "inputs/late-cohort.csv", index=False)
    inputs.append({"path": "inputs/late-cohort.csv", "rows": int(late.shape[0]), "columns": int(late.shape[1])})

    first = make_panel(n_units=40, n_periods=4, treatment_period=2, seed=42)
    first.loc[first["id"] <= 5, "group"] = 1
    first.to_csv(FIXTURE / "inputs/first-period-treated.csv", index=False)
    inputs.append({"path": "inputs/first-period-treated.csv", "rows": int(first.shape[0]), "columns": int(first.shape[1])})

    universal_rows = []
    for uid in range(1, 201):
        g = 3 if uid <= 100 else 0
        for t in range(1, 6):
            universal_rows.append((uid, t, g, float(t)))
    universal = pd.DataFrame(universal_rows, columns=["id", "period", "g", "y"])
    universal.to_csv(FIXTURE / "inputs/universal-base.csv", index=False)
    inputs.append({"path": "inputs/universal-base.csv", "rows": int(universal.shape[0]), "columns": int(universal.shape[1])})

    universal_stochastic = make_panel(n_units=200, n_periods=5, treatment_period=3, seed=11)
    universal_stochastic = universal_stochastic.rename(columns={"year": "period", "group": "g"})
    universal_stochastic.to_csv(FIXTURE / "inputs/universal-stochastic.csv", index=False)
    inputs.append({"path": "inputs/universal-stochastic.csv", "rows": int(universal_stochastic.shape[0]), "columns": int(universal_stochastic.shape[1])})

    id_validation = make_panel(n_units=30, n_periods=4, treatment_period=3, seed=3)
    id_validation.to_csv(FIXTURE / "inputs/id-validation.csv", index=False)
    inputs.append({"path": "inputs/id-validation.csv", "rows": int(id_validation.shape[0]), "columns": int(id_validation.shape[1])})

    return inputs


def source_row(
    source_test: str,
    scenario: str,
    assertion: str,
    status: str = "mapped",
    divergence_id: str = "",
    evidence: str = "",
) -> dict[str, str]:
    return {
        "source_file": SOURCE_FILE,
        "source_sha256": SOURCE_SHA256,
        "source_test": source_test,
        "mapped_scenario": scenario,
        "assertion_family": assertion,
        "coverage_status": status,
        "divergence_id": divergence_id,
        "supporting_evidence": evidence,
    }


def write_contract(inputs: list[dict[str, object]]) -> None:
    (FIXTURE / "expected/contract").mkdir(parents=True, exist_ok=True)
    (FIXTURE / "metadata").mkdir(parents=True, exist_ok=True)

    rows = [
        source_row("TestFactorCovariates.test_factor_not_silently_dropped", "factor_not_dropped", "factor covariates materially change ATT(g,t)", evidence="F011"),
        source_row("TestFactorCovariates.test_factor_faster_mode_matches_standard[panel=True]", "factor_fast_panel", "fast request with factor covariates matches standard panel path", evidence="F011/F032/PY009"),
        source_row("TestFactorCovariates.test_factor_faster_mode_matches_standard[panel=False]", "factor_fast_rc", "fast request with factor covariates matches standard repeated-cross-section path", evidence="F011/F032/PY009"),
        source_row("TestFactorCovariates.test_mixed_factor_numeric_runs", "mixed_factor_numeric", "factor plus numeric covariates produce finite public estimates", evidence="F011"),
        source_row("TestSEScaling.test_se_scaling_formula", "clustered_bootstrap_se_reasonable", "clustered bootstrap SEs are positive and not inflated", evidence="F014/F015/PY015"),
        source_row("TestChunking.test_biters_less_than_cores", "python-mboot-helper-only", "Python multiprocessing chunk helper has no Stata command analogue", "approved-divergence", "PY020-DIV001", "F035/PY015"),
        source_row("TestChunking.test_biters_equals_one", "python-mboot-helper-only", "Python multiprocessing chunk helper has no Stata command analogue", "approved-divergence", "PY020-DIV001", "F035/PY015"),
        source_row("TestChunking.test_biters_exact_multiple_of_cores", "python-mboot-helper-only", "Python multiprocessing chunk helper has no Stata command analogue", "approved-divergence", "PY020-DIV001", "F035/PY015"),
        source_row("TestMemoryChunkedBootstrap.test_chunked_matches_shape", "python-mboot-helper-only", "Python chunked multiplier helper has no Stata command analogue", "approved-divergence", "PY020-DIV001", "F035/PY015"),
        source_row("TestMemoryChunkedBootstrap.test_chunked_statistical_properties", "python-mboot-helper-only", "Python chunked multiplier helper has no Stata command analogue", "approved-divergence", "PY020-DIV001", "F035/PY015"),
        source_row("TestAnticipation.test_asif_nevertreated_uses_anticipation", "late_cohort_anticipation", "late cohorts respect anticipation/coercion public behavior", evidence="F022/RT028/PY023"),
        source_row("TestAnticipation.test_treated_fp_uses_anticipation", "first_period_treated_drop", "first-period treated units are dropped from estimated groups", evidence="F021/PY007/RT010"),
        source_row("TestBooleanOutcome.test_bool_outcome_accepted", "boolean_outcome", "numeric 0/1 outcome is accepted as a Stata boolean analogue"),
        source_row("TestFormulaValidation.test_bad_formula_raises", "bad_formula", "missing covariate is rejected"),
        source_row("TestFormulaValidation.test_intercept_formula_still_works", "intercept_formula", "intercept-only public command succeeds"),
        source_row("TestUnbalancedPanel.test_allow_unbalanced_false_runs", "python-balance-drop-option-only", "Python allow_unbalanced_panel=False has no Stata command analogue", "approved-divergence", "PY020-DIV002", "F016/F017"),
        source_row("TestUnbalancedPanel.test_allow_unbalanced_false_balances", "python-balance-drop-option-only", "Python allow_unbalanced_panel=False balance-drop path has no Stata command analogue", "approved-divergence", "PY020-DIV002", "F016/F017"),
        source_row("TestUnbalancedPanel.test_unbalanced_switches_to_rc", "unbalanced_switches_to_rc", "unbalanced ivar() routes to repeated-cross-section computation", evidence="F016/PY007"),
        source_row("TestUnbalancedPanel.test_balanced_panel_stays_panel", "balanced_stays_panel", "balanced ivar() data stays on panel path", evidence="F016/PY007"),
        source_row("TestUnbalancedPanel.test_uniform_count_but_missing_periods_is_unbalanced", "uniform_missing_periods", "equal row counts with missing periods are still unbalanced", evidence="F016"),
        source_row("TestNevertreatedCoercion.test_last_cohort_coerced_to_control", "last_cohort_coerced", "last cohort is recoded to controls when no never-treated group exists", evidence="F020/PY007/PY008"),
        source_row("TestAnalyticalClusterSEScaling.test_analytical_se_formula_directly", "analytical_cluster_se_public", "public clustered analytical SE uses cluster-sum scaling", evidence="F015/RT007"),
        source_row("TestPostKeyAlias.test_both_post_keys_present_and_equal", "python-results-dict-alias-only", "Python results dict legacy alias has no Stata object analogue", "approved-divergence", "PY020-DIV003", "F026/RT023/PY011"),
        source_row("TestPostKeyAlias.test_summ_attgt_robust_to_alias", "python-results-dict-alias-only", "Python summary dataframe alias handling has no Stata object analogue", "approved-divergence", "PY020-DIV003", "F026/RT023/PY011"),
        source_row("TestUniversalBaseNaN.test_universal_base_cell_se_is_nan", "universal_base_nan", "universal base cell SE is missing"),
        source_row("TestUniversalBaseNaN.test_varying_base_has_no_nan_se", "varying_base_finite_se", "varying base has finite SEs"),
        source_row("TestUniversalBaseNaN.test_only_base_cell_nan_when_estimated_cells_are_degenerate", "deterministic_zero_if_r_behavior", "Python deterministic zero-IF expectation diverges from R did 2.5.1", "approved-divergence", "PY020-DIV005", "R did 2.5.1"),
        source_row("TestIdnameNumericValidation.test_string_idname_raises", "string_id_rejected", "string id variable is rejected", evidence="F030/PY024"),
        source_row("TestIdnameNumericValidation.test_numeric_idname_ok", "numeric_id_ok", "numeric id variable is accepted", evidence="F030/PY024"),
        source_row("TestIdnameNumericValidation.test_nullable_int_idname_accepted", "numeric_storage_id_ok", "Stata numeric storage classes are accepted as the nullable-int analogue", evidence="F030"),
        source_row("TestIdnameNumericValidation.test_bool_idname_rejected", "python-bool-id-dtype-only", "Python boolean id dtype has no Stata logical-type analogue", "approved-divergence", "PY020-DIV004", "F030/PY024"),
    ]
    upstream = pd.DataFrame(rows)
    upstream.to_csv(FIXTURE / "expected/contract/upstream-test-map.csv", index=False)
    (FIXTURE / "expected/contract/upstream-test-map.json").write_text(
        json.dumps(rows, indent=2),
        encoding="utf-8",
    )

    scenarios = pd.DataFrame(
        [{"scenario": row["mapped_scenario"], "coverage_status": row["coverage_status"], "expected_behavior": row["assertion_family"]} for row in rows]
    ).drop_duplicates()
    scenarios.to_csv(FIXTURE / "expected/contract/scenarios.csv", index=False)

    divergences = pd.DataFrame(
        [
            {
                "divergence_id": "PY020-DIV001",
                "source_tests": "TestChunking.*; TestMemoryChunkedBootstrap.*",
                "reason": "The Python source tests private/multiprocessing multiplier-bootstrap helper array shapes and moments. The Stata port exposes bootstrap behavior through csdid wboot() metadata and ATT(g,t) bootstrap outputs, not the Python helper API.",
                "accepted_behavior": "Public Stata bootstrap reps, seed, clustered finite-SE behavior, and validation remain covered by F035 and PY015; PY020 adds a clustered bootstrap sanity check.",
            },
            {
                "divergence_id": "PY020-DIV002",
                "source_tests": "TestUnbalancedPanel.test_allow_unbalanced_false_runs; TestUnbalancedPanel.test_allow_unbalanced_false_balances",
                "reason": "The owner-directed Stata contract does not expose Python's allow_unbalanced_panel=False balance-dropping path. Stata defaults unbalanced ivar() data to repeated-cross-section computation and soft-deprecates legacy balance modes as no-op aliases.",
                "accepted_behavior": "F016 verifies the R-compatible allow_unbalanced default; F017 records soft-deprecated legacy balance aliases.",
            },
            {
                "divergence_id": "PY020-DIV003",
                "source_tests": "TestPostKeyAlias.test_both_post_keys_present_and_equal; TestPostKeyAlias.test_summ_attgt_robust_to_alias",
                "reason": "The Python tests exercise a Python results-dictionary alias ('post '), not a public Stata command surface or saved artifact.",
                "accepted_behavior": "Stata exposes stable e() matrices, characteristics, and postestimation outputs covered by F026, RT023, and PY011.",
            },
            {
                "divergence_id": "PY020-DIV004",
                "source_tests": "TestIdnameNumericValidation.test_bool_idname_rejected",
                "reason": "Stata has numeric byte variables but no distinct pandas/R logical id dtype. A two-valued numeric id is handled by ordinary id-time uniqueness validation, not by a logical-type validator.",
                "accepted_behavior": "String ids are rejected and numeric id storage classes are accepted under F030/PY024; low-cardinality duplicate id-time errors remain covered by validation gates.",
            },
            {
                "divergence_id": "PY020-DIV005",
                "source_tests": "TestUniversalBaseNaN.test_only_base_cell_nan_when_estimated_cells_are_degenerate",
                "reason": "The Python review test expects deterministic zero-influence estimated cells to keep finite SEs, but R did 2.5.1 returns missing SEs for all deterministic zero-IF cells. The Stata port is subordinate to R did 2.5.1.",
                "accepted_behavior": "Stata follows R did 2.5.1: stochastic universal-base designs have only the inserted base-cell SE missing, while deterministic zero-IF designs have missing SEs for all zero-variance cells.",
            },
        ]
    )
    divergences.to_csv(FIXTURE / "expected/contract/approved-divergence.csv", index=False)
    (FIXTURE / "expected/contract/approved-divergence.json").write_text(
        json.dumps(divergences.to_dict(orient="records"), indent=2),
        encoding="utf-8",
    )

    manifest = {
        "matrix_id": "PY020",
        "fixture_family": "python-review-fixes",
        "normative_source": "Python csdid csdid/test_csdid/test_review_fixes.py subordinate to R did 2.5.1 public behavior",
        "source_commit": SOURCE_COMMIT,
        "decision_refs": ["D003", "D004", "D008"],
        "tolerance_ids": ["TOL002", "TOL003", "EXACT"],
        "inputs": inputs,
        "generators": [{"runtime": "Python", "command": "python3 tools/parity/generators/py020/generate.py", "path": "tools/parity/generators/py020/generate.py"}],
        "runtimes": [{"name": "Python", "version": "3", "package_versions": {"numpy": np.__version__, "pandas": pd.__version__}}],
        "rng": {"kind": "numpy.random.default_rng", "seeds": [0, 1, 3, 5, 42]},
        "expected_outputs": [
            {"path": "expected/contract/upstream-test-map.csv", "schema": "source-test-map"},
            {"path": "expected/contract/upstream-test-map.json", "schema": "source-test-map"},
            {"path": "expected/contract/scenarios.csv", "schema": "source-scenario-map"},
            {"path": "expected/contract/approved-divergence.csv", "schema": "approved-divergence"},
            {"path": "expected/contract/approved-divergence.json", "schema": "approved-divergence"},
        ],
        "comparison_plan": [
            {"actual": "Stata public command checks for mapped review-fix scenarios", "expected": "expected/contract/upstream-test-map.csv", "tolerance_id": "EXACT/TOL002/TOL003", "key_columns": ["source_test"]},
            {"actual": "Approved Python helper/object-model divergence registry", "expected": "expected/contract/approved-divergence.csv", "tolerance_id": "EXACT", "key_columns": ["divergence_id"]},
        ],
        "approved_divergence": {"status": "approved-divergence", "path": "expected/contract/approved-divergence.csv"},
        "scope_note": "PY020 maps all 31 public test_review_fixes.py tests/parameterizations. Twenty are exercised through Stata public command behavior or existing parity evidence; eleven Python helper/object-model, non-Stata-option, logical-dtype, or R-incompatible deterministic zero-IF tests are recorded as approved divergences with explicit accepted Stata behavior.",
    }
    (FIXTURE / "metadata/manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def main() -> None:
    inputs = write_inputs()
    write_contract(inputs)


if __name__ == "__main__":
    main()
