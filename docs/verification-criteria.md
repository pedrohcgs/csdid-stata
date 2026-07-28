# Verification Criteria

Status: frozen for conformance profile v1.

This document is the readable catalogue for the binding feature matrix in
`inst/spec/feature-matrix.csv`. The matrix contains 128 frozen rows:

- F001-F051: fixture families and release gates.
- RT001-RT030: inherited R `did` `tests/testthat` files.
- PY001-PY024: inherited Python `csdid` deeper test files.
- JEL001-JEL018: JEL-DiD empirical scripts, tables, and figures.
- ENG001-ENG005: Stata engineering-reference requirements.

All mandatory rows start implementation with status `contract-frozen` and may
finish only as `parity-verified` or `approved-divergence`.

Canonical fixture paths and file schemas are defined in
`inst/spec/fixture-schemas.md`. R/Python source-test hashes are defined in
`tools/parity/source-test-inventory.csv`.

## Fixture Families

| ID | Name | Criterion | Stata test | Tolerance |
| --- | --- | --- | --- | --- |
| F001 | Static 2x2 ATT | Minimal `att_gt` point estimate, SE, CI, row counts, diagnostics | `tests/stata/test-f001.do` | TOL001 |
| F002 | Balanced staggered panel | Multi-group ATT(g,t), pre-treatment effects, ordering | `tests/stata/test-f002.do` | TOL001 |
| F003 | Simple aggregation | `aggte(type = "simple")` estimates, weights, inference | `tests/stata/test-f003.do` | TOL001 |
| F004 | Group aggregation | group effects, weights, ordering, inference | `tests/stata/test-f004.do` | TOL001 |
| F005 | Calendar aggregation | calendar effects, weights, ordering, inference | `tests/stata/test-f005.do` | TOL001 |
| F006 | Dynamic aggregation | event-time labels, base periods, bands, overall effect | `tests/stata/test-f006.do` | TOL001 |
| F007 | Base periods | varying and universal base-period semantics | `tests/stata/test-f007.do` | TOL001 |
| F008 | Control groups | never-treated and not-yet-treated controls | `tests/stata/test-f008.do` | TOL001 |
| F009 | Anticipation | shifted treatment timing and excluded periods | `tests/stata/test-f009.do` | TOL001 |
| F010 | Estimation methods | `dr`, `reg`, `ipw`, aliases, invalid methods | `tests/stata/test-f010.do` | TOL001 |
| F011 | Covariates | formula, factor, and covariate timing semantics | `tests/stata/test-f011.do` | TOL001 |
| F012 | Weights and fix_weights | weights, time-varying weights, scaling invariance | `tests/stata/test-f012.do` | TOL001 |
| F013 | Analytical standard errors | non-bootstrap SE and influence-function dimensions | `tests/stata/test-f013.do` | TOL002 |
| F014 | Bootstrap and simultaneous bands | multiplier bootstrap, critical values, bands | `tests/stata/test-f014.do` | TOL003 |
| F015 | Clustered inference | cluster validation, SEs, errors | `tests/stata/test-f015.do` | TOL002 |
| F016 | `allow_unbalanced` panels | R default repeated-cross-section path and SEs | `tests/stata/test-f016.do` | TOL002 |
| F017 | Balance alias compatibility | soft-deprecated legacy balancing aliases map to `allowunbalanced` without unit dropping | `tests/stata/test-f017.do` | TOL001 |
| F018 | True repeated cross sections | `panel = FALSE` behavior and id handling | `tests/stata/test-f018.do` | TOL002 |
| F019 | Missingness and subset | exact sample construction and masks | `tests/stata/test-f019.do` | EXACT |
| F020 | No never-treated units | automatic/explicit not-yet-treated behavior | `tests/stata/test-f020.do` | TOL001 |
| F021 | Always and first-period treated | exclusion and first-period treatment diagnostics | `tests/stata/test-f021.do` | EXACT |
| F022 | Treatment timing encodings | zero, missing, invalid, inconsistent `gvar` values | `tests/stata/test-f022.do` | EXACT |
| F023 | Irregular time gaps | nonconsecutive time handling and errors | `tests/stata/test-f023.do` | EXACT |
| F024 | Duplicate unit-time rows | duplicate policy and diagnostics | `tests/stata/test-f024.do` | EXACT |
| F025 | Aggregation window options | `balance_e`, `min_e`, `max_e`, `na.rm` | `tests/stata/test-f025.do` | TOL001 |
| F026 | Stored results | `ereturn`, matrices, scalars, macros, ordering | `tests/stata/test-f026.do` | EXACT |
| F027 | Exportable tables | tidy/glance analogues and table schema | `tests/stata/test-f027.do` | EXACT |
| F028 | Plot data and csdid_plot | plot data, labels, CIs, save behavior | `tests/stata/test-f028.do` | TOL005 |
| F029 | Error and warning surface | invalid option combinations and messages | `tests/stata/test-f029.do` | EXACT |
| F030 | Data types | ids, controls, names, string/numeric support | `tests/stata/test-f030.do` | EXACT |
| F031 | Mutation and temp safety | no unintended data or state mutation | `tests/stata/test-f031.do` | EXACT |
| F032 | Optimized path equivalence | fast path equals baseline, including default `fast(auto)` surface compatibility | `tests/stata/test-f032.do`; `tests/stata/test-f032-fast-auto-surface.do` | TOL002 |
| F033 | DRDID boundary | delegated or native 2x2 estimator boundary | `tests/stata/test-f033.do` | TOL001 |
| F034 | RIF and saved artifacts | RIF storage and postestimation artifacts | `tests/stata/test-f034.do` | TOL002 |
| F035 | Wild bootstrap options | Stata bootstrap syntax and shorthand mapped to R parity or legacy | `tests/stata/test-f035.do` | TOL003 |
| F036 | Option inventory | every current Stata option and release alias classified | `tests/stata/test-f036.do` | EXACT |
| F037 | Parametric combination grid | Python deeper combination tests | `tests/stata/test-f037.do` | TOL001 |
| F038 | User regression tests | Python and R user bug-fix regressions | `tests/stata/test-f038.do` | TOL001 |
| F039 | Inference tests | Python deeper inference coverage | `tests/stata/test-f039.do` | TOL002 |
| F040 | Python JEL tests | Python JEL regression coverage | `tests/stata/test-f040.do` | TOL004 |
| F041 | JEL Table 7 | 2x2 CS-DiD with covariates | `tests/stata/test-f041.do` | TOL004 |
| F042 | JEL 2xT event study | 2xT event-study outputs | `tests/stata/test-f042.do` | TOL004 |
| F043 | JEL GxT analysis | group-time analysis outputs | `tests/stata/test-f043.do` | TOL004 |
| F044 | JEL figures and tables | all JEL artifacts as an integration gate | `tests/stata/test-f044.do` | TOL004 |
| F045 | Legacy default divergences | old defaults behind explicit options | `tests/stata/test-f045.do` | TOL001 |
| F046 | Legacy deprecation warnings | warning and migration text | `tests/stata/test-f046.do` | EXACT |
| F047 | Randomized differential testing | seeded small-panel differential tests | `tests/stata/test-f047.do` | TOL002 |
| F048 | Monte Carlo sanity | known DGP bias and coverage checks | `tests/stata/test-f048.do` | TOL008 |
| F049 | Performance pathology | scale and memory budgets | `tests/stata/test-f049.do` | TOL007 |
| LEGACY-AB | Previous-release regression | seven isolated trials; paired time and process-RSS medians plus 95% upper bounds must remain below pinned legacy | `tests/run-legacy-candidate-ab.sh` | TOL007 |
| F050 | Clean install and portability | install, isolated ado/help path, direct public-command help, no hidden network use | `tests/stata/test-f050.do` | EXACT |
| F051 | Release defaults and UX | omitted defaults, Stata-facing aliases, default-safe postestimation, plot-data diagnostics | `tests/stata/test-f051.do` | TOL001/EXACT |

## R Test Inheritance Map

| ID | R source | Stata test | Tolerance |
| --- | --- | --- | --- |
| RT001 | `tests/testthat/test-aggte-clustervars-override.R` | `tests/stata/r/test-aggte-clustervars-override.do` | EXACT |
| RT002 | `tests/testthat/test-aggte-comprehensive.R` | `tests/stata/r/test-aggte-comprehensive.do` | TOL002 |
| RT003 | `tests/testthat/test-aggte-edge-coverage.R` | `tests/stata/r/test-aggte-edge-coverage.do` | TOL002 |
| RT004 | `tests/testthat/test-always-treated-invariance.R` | `tests/stata/r/test-always-treated-invariance.do` | TOL002 |
| RT005 | `tests/testthat/test-att_gt.R` | `tests/stata/r/test-att_gt.do` | TOL002 |
| RT006 | `tests/testthat/test-audit-fixes.R` | `tests/stata/r/test-audit-fixes.do` | TOL002 |
| RT007 | `tests/testthat/test-cluster-analytic.R` | `tests/stata/r/test-cluster-analytic.do` | TOL002 |
| RT008 | `tests/testthat/test-compute-inffunc.R` | `tests/stata/r/test-compute-inffunc.do` | TOL002 |
| RT009 | `tests/testthat/test-conditional-did-pretest.R` | `tests/stata/r/test-conditional-did-pretest.do` | TOL002 |
| RT010 | `tests/testthat/test-edge-cases.R` | `tests/stata/r/test-edge-cases.do` | TOL002 |
| RT011 | `tests/testthat/test-error-handling.R` | `tests/stata/r/test-error-handling.do` | EXACT |
| RT012 | `tests/testthat/test-faster-mode-consistency.R` | `tests/stata/r/test-faster-mode-consistency.do` | TOL002 |
| RT013 | `tests/testthat/test-ggdid.R` | `tests/stata/r/test-ggdid.do` | TOL005 |
| RT014 | `tests/testthat/test-glance.R` | `tests/stata/r/test-glance.do` | EXACT |
| RT015 | `tests/testthat/test-inference.R` | `tests/stata/r/test-inference.do` | TOL002 |
| RT016 | `tests/testthat/test-jel_replication.R` | `tests/stata/r/test-jel_replication.do` | TOL004 |
| RT017 | `tests/testthat/test-mboot-cluster.R` | `tests/stata/r/test-mboot-cluster.do` | TOL003 |
| RT018 | `tests/testthat/test-mboot-postprocess.R` | `tests/stata/r/test-mboot-postprocess.do` | TOL003 |
| RT019 | `tests/testthat/test-modelmatrix-hoist.R` | `tests/stata/r/test-modelmatrix-hoist.do` | TOL002 |
| RT020 | `tests/testthat/test-mutation-safety.R` | `tests/stata/r/test-mutation-safety.do` | EXACT |
| RT021 | `tests/testthat/test-output-methods-coverage.R` | `tests/stata/r/test-output-methods-coverage.do` | EXACT |
| RT022 | `tests/testthat/test-overlap-guard-cache.R` | `tests/stata/r/test-overlap-guard-cache.do` | EXACT |
| RT023 | `tests/testthat/test-pretest-vectorization.R` | `tests/stata/r/test-pretest-vectorization.do` | TOL002 |
| RT024 | `tests/testthat/test-robustness-guards.R` | `tests/stata/r/test-robustness-guards.do` | EXACT |
| RT025 | `tests/testthat/test-slowpath-precompute.R` | `tests/stata/r/test-slowpath-precompute.do` | TOL002 |
| RT026 | `tests/testthat/test-tidy.R` | `tests/stata/r/test-tidy.do` | EXACT |
| RT027 | `tests/testthat/test-unbalanced-faster-cluster-se.R` | `tests/stata/r/test-unbalanced-faster-cluster-se.do` | TOL002 |
| RT028 | `tests/testthat/test-user_bug_fixes.R` | `tests/stata/r/test-user_bug_fixes.do` | TOL002 |
| RT029 | `tests/testthat/att_gt_point_estimate_tests.R` | `tests/stata/r/att_gt_point_estimate_tests.do` | TOL002 |
| RT030 | `tests/testthat/att_gt_point_estimate_tests.Rmd` | `tests/stata/r/att_gt_point_estimate_tests_rmd.do` | TOL002 |

## Python Deeper-Test Map

| ID | Python source | Stata test | Tolerance |
| --- | --- | --- | --- |
| PY001 | `csdid/test_csdid/test_aggte_comprehensive.py` | `tests/stata/python/test_aggte_comprehensive.do` | TOL002 |
| PY002 | `csdid/test_csdid/test_analytical_cluster_se.py` | `tests/stata/python/test_analytical_cluster_se.do` | TOL002 |
| PY003 | `csdid/test_csdid/test_att_gt.py` | `tests/stata/python/test_att_gt.do` | TOL002 |
| PY004 | `csdid/test_csdid/test_cluster_analytic.py` | `tests/stata/python/test_cluster_analytic.do` | TOL002 |
| PY005 | `csdid/test_csdid/test_clustered.py` | `tests/stata/python/test_clustered.do` | TOL002 |
| PY006 | `csdid/test_csdid/test_compute_inffunc.py` | `tests/stata/python/test_compute_inffunc.do` | TOL002 |
| PY007 | `csdid/test_csdid/test_edge_cases.py` | `tests/stata/python/test_edge_cases.do` | TOL002 |
| PY008 | `csdid/test_csdid/test_error_handling.py` | `tests/stata/python/test_error_handling.do` | EXACT |
| PY009 | `csdid/test_csdid/test_faster_mode_consistency.py` | `tests/stata/python/test_faster_mode_consistency.do` | TOL002 |
| PY010 | `csdid/test_csdid/test_ggdid.py` | `tests/stata/python/test_ggdid.do` | TOL005 |
| PY011 | `csdid/test_csdid/test_glance.py` | `tests/stata/python/test_glance.do` | EXACT |
| PY012 | `csdid/test_csdid/test_inference.py` | `tests/stata/python/test_inference.do` | TOL002 |
| PY013 | `csdid/test_csdid/test_integration.py` | `tests/stata/python/test_integration.do` | TOL002 |
| PY014 | `csdid/test_csdid/test_jel_replication.py` | `tests/stata/python/test_jel_replication.do` | TOL004 |
| PY015 | `csdid/test_csdid/test_mboot_cluster.py` | `tests/stata/python/test_mboot_cluster.do` | TOL003 |
| PY016 | `csdid/test_csdid/test_notyettreated.py` | `tests/stata/python/test_notyettreated.do` | TOL002 |
| PY017 | `csdid/test_csdid/test_parametric_combinations.py` | `tests/stata/python/test_parametric_combinations.do` | TOL002 |
| PY018 | `csdid/test_csdid/test_percell_failure.py` | `tests/stata/python/test_percell_failure.do` | EXACT |
| PY019 | `csdid/test_csdid/test_r_parity.py` | `tests/stata/python/test_r_parity.do` | TOL002 |
| PY020 | `csdid/test_csdid/test_review_fixes.py` | `tests/stata/python/test_review_fixes.do` | TOL002 |
| PY021 | `csdid/test_csdid/test_sim_parity.py` | `tests/stata/python/test_sim_parity.do` | TOL002 |
| PY022 | `csdid/test_csdid/test_tidy.py` | `tests/stata/python/test_tidy.do` | EXACT |
| PY023 | `csdid/test_csdid/test_user_bug_fixes.py` | `tests/stata/python/test_user_bug_fixes.do` | TOL002 |
| PY024 | `csdid/test_csdid/test_validation.py` | `tests/stata/python/test_validation.do` | EXACT |

Python files `csdid/test_csdid/conftest.py` and `test/test_vs_r.py` are
supporting evidence. Their behaviors must be absorbed into fixture manifests
and PY019 rather than separate mandatory rows.

## JEL Acceptance Map

| ID | JEL source | Stata acceptance test | Tolerance |
| --- | --- | --- | --- |
| JEL001 | `scripts/R/00_master_did_jel.R` | `tests/stata/jel/test-artifact-contract.do` | TOL004 |
| JEL002 | `scripts/Stata/00_stata_master_did_jel.do` | `tests/stata/jel/test-artifact-contract.do` | TOL004 |
| JEL003 | `tables/table1_R.tex`, `tables/table1_stata.tex` | `tests/stata/jel/test-artifact-contract.do` | TOL004 |
| JEL004 | `tables/table2_R.tex`, `tables/table2_stata.tex` | `tests/stata/jel/test-artifact-contract.do` | TOL004 |
| JEL005 | `tables/table3_R.tex`, `tables/table3_stata.tex` | `tests/stata/jel/test-artifact-contract.do` | TOL004 |
| JEL006 | `tables/table4_R.tex`, `tables/table4_stata.tex` | `tests/stata/jel/test-artifact-contract.do` | TOL004 |
| JEL007 | `tables/table5_R.tex`, `tables/table5_stata.tex` | `tests/stata/jel/test-artifact-contract.do` | TOL004 |
| JEL008 | `tables/table6_R.tex`, `tables/table6_stata.tex` | `tests/stata/jel/test-artifact-contract.do` | TOL004 |
| JEL009 | `tables/table7_R.tex`, `tables/table7_stata.tex` | `tests/stata/jel/test-artifact-contract.do` | TOL004 |
| JEL010 | `figures/figure1_R.pdf`, `figures/figure1_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` | TOL006 |
| JEL011 | `figures/figure2_R.pdf`, `figures/figure2_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` | TOL006 |
| JEL012 | `figures/figure3_R.pdf`, `figures/figure3_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` | TOL006 |
| JEL013 | `figures/figure4_R.pdf`, `figures/figure4_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` | TOL006 |
| JEL014 | `figures/figure5_R.pdf`, `figures/figure5_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` | TOL006 |
| JEL015 | `figures/figure6_R.pdf`, `figures/figure6_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` | TOL006 |
| JEL016 | `figures/figure7_R.pdf`, `figures/figure7_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` | TOL006 |
| JEL017 | `figures/figure8_R.pdf`, `figures/figure8_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` | TOL006 |
| JEL018 | `figures/figure9_R.pdf`, `figures/figure9_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` | TOL006 |

## Engineering Gates

| ID | Requirement | Evidence | Tolerance |
| --- | --- | --- | --- |
| ENG001 | Pinned engineering inventory | `docs/stata-engineering-references.md` | EXACT |
| ENG002 | Ado/Mata architecture | `docs/stata-engineering-references.md` | EXACT |
| ENG003 | Dependency policy | `docs/stata-engineering-references.md` | EXACT |
| ENG004 | Performance style | `docs/stata-engineering-references.md` and benchmarks | TOL007 |
| ENG005 | Release engineering audit | `reports/engineering-audit.md` | EXACT |

## Acceptance Rules

Numeric comparisons use `docs/tolerance-registry-v1.md`. Names, masks,
diagnostics, statuses, option defaults, row ordering, warning classes, and error
classes use EXACT. Rendered graph comparison is never a substitute for plot-data
comparison. Legacy compatibility modes cannot change R-parity defaults.
