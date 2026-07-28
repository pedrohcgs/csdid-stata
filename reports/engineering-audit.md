# Engineering Audit

Status: parity-verified for conformance profile v1. Latest local full-JEL
R `did` 2.5.1 oracle parity passes; public `v2.0.0` still requires external
platform rows, independent signoffs, release-owner approval, and final
evidence inventory.

Date: 2026-06-24.

## Verification Summary

- Contract validation passes with `python3 tools/validate-contract.py`.
- Engineering meta tests pass with `for f in tests/meta/*.sh; do bash "$f" ||
  exit 1; done`.
- Default smoke coverage is exercised by `tests/run-smoke.sh`.
- JEL smoke coverage is exercised by `tests/run-jel-smoke.sh`.
- Full JEL reproduction runs through
  `CSDID_RUN_JEL_FULL=1 tests/run-jel-full-reproduction.sh` and now returns
  `pass` against regenerated R `did` 2.5.1. Figure 3/8/9 label audits and the
  Table 7 display audit have zero failures; historical R artifact drift is
  recorded separately as release evidence context with
  `historical_artifact_status=needs-review`.
- Clean install and isolated ado-path behavior are covered by F050.
- Release defaults, postestimation handoff, plot-data UX, and diagnostics are
  covered by F051.
- Default small, medium, and aggregation benchmark budgets are covered by F049.

## Architecture Audit

- Public ado entry points are present under `src/ado/`: `csdid`,
  `csdid_estat`, `csdid_stats`, and `csdid_plot`.
- The main numerical kernel is isolated under `src/mata/csdid.mata`.
- Help files are present under `src/help/`.
- The implementation follows the frozen ado/Mata split in
  `docs/stata-engineering-references.md`: ado wrappers own syntax, validation,
  stored results, and user-facing behavior; Mata kernels own group/time
  indexing, influence functions, aggregation, and bootstrap work.

## Dependency Audit

- Default tests run offline against committed fixtures.
- No default runtime or smoke-test path installs SSC/network packages.
- `gtools` and `ftools` remain optional-fast-path candidates only.
- `reghdfe` is not a required v1 runtime dependency.
- `honestdid` and other JEL dependencies remain test/JEL-only.
- Full JEL replication isolates ado paths and installs non-`csdid`
  dependencies only inside the opt-in wrapper.

## Performance Audit

- F049 covers `small_smoke`, `medium_panel`, `medium_panel_fast_lean`,
  `medium_panel_performance_auto`, `medium_panel_covariate_dr`,
  `medium_panel_weighted_ipw`, `medium_panel_clustered_reg`,
  `medium_panel_bootstrap_reg`, `medium_unbalanced_cov_weight_dr`, and
  all simple/group/calendar/dynamic aggregation plus supported `csdid_plot`
  plot-data export budgets. The default large-job gate now runs
  `fast(auto)` with the `performance(auto)` storage resolver, which uses
  cache-backed storage above the frozen large-job threshold while small jobs
  keep full `e(inffunc)`/`e(unit_group)` compatibility. The
  option-surface rows require `e(fast_used)=1` for covariate, weighted,
  clustered, bootstrap-smoke, allow_unbalanced, aggregation, and plot-data
  workflows, with `e(compute_path)` identifying `fast-balanced-panel`,
  `fast-repeated-cross-section`, or `fast-allow-unbalanced`. The paired
  R-relative F049 gate records Stata/R ratios for every F049 benchmark and
  enforces the frozen ratio budget of <=1.8x R for non-bootstrap rows plus a
  hard <=3x R budget for expanded seeded bootstrap/cband rows. The literal
  omitted-option default has its own binding <=1.8x R gate. The 2026-07-09
  passing run records Stata/R ratios of 0.18x for the 50,000-row balanced panel,
  0.17x for explicit fast-lean and performance-auto, 1.22x for covariate DR,
  1.26x for weighted IPW, 0.75x for clustered REG, 1.73x for the literal
  unseeded DR/bootstrap/cband default, 1.76x for seeded pointwise REG
  bootstrap, 1.72x for seeded cband REG, 1.56x for covariate DR bootstrap,
  1.73x for weighted IPW bootstrap, 1.26x for clustered REG bootstrap, 1.14x
  for unbalanced covariate/weighted DR bootstrap, 1.28x for non-bootstrap
  unbalanced covariate/weighted DR, <=1.28x for all non-bootstrap aggregation
  rows, 1.68x for dynamic aggregation bootstrap, and <=0.07x for supported
  plot-data exports. The
  optimized kernels now cover sorted balanced-panel reshaping, vectorized
  sorted-layout detection before fallback row scans, Mata-native panel validation and weight-variation
  warnings, hoisted covariate nuisance work, conditional balanced-panel
  blocks, cached row-to-unit and cluster mappings, cache-only large
  cluster-vector storage, compressed row-map allow_unbalanced extraction, scalarized
  influence-function adjustment products, intercept-only weighted IPW special
  cases, compressed cluster sums, skipped quiet display work, cached DR
  nuisance layouts, vectorized IF assignment, exact vectorized unseeded cband
  draws, one-sort bootstrap scales, and an optional compiled BMisc-compatible
  multiplier kernel. The plugin stages ATT(g,t) IFs through temporary numeric
  variables and consumes aggregate IF matrices directly, advances the seeded
  625-word RNG state exactly, and fails closed to the full Mata implementation.
  `e(profile)`, `e(bootstrap_profile)`, and
  `e(agg_bootstrap_profile)` record phase seconds, calls, and work counts.
- `CSDID_RUN_OPTIN_PERF=1 tests/run-optin-performance.sh` passed the generated
  scale budgets on this machine: the full omitted-option `large_panel` workload
  finished in 3.664s for 500,000 rows, and seeded `bootstrap_medium` finished
  in 0.268s for 25,000 rows and 999 pointwise bootstrap reps. The same command
  now runs paired R/Stata F049 and process-level RSS gates. Peak RSS was 368.938
  MB for default cband, 225.844 MB for seeded balanced bootstrap, 225.047 MB for
  unbalanced weighted DR bootstrap, 155.562 MB for aggregation bootstrap, and
  263.516 MB for `large_panel`. These measured peaks replace `c(memory)` as
  release memory evidence. `jel_replication` remains opt-in by contract in
  `inst/spec/bench-budgets.yml`.
- `tests/run-legacy-candidate-ab.sh` passes all 15 frozen old-vs-new rows
  against the pinned public Stata commit. Seven isolated alternating trials
  require both paired time and RSS medians and their bootstrap 95% upper bounds
  to remain below legacy. The worst bounds are 0.442013 for time and 0.996870
  for RSS.
- JEL-scale runtime evidence is recorded in
  `reports/jel-full-reproduction-result.md` and the corresponding logs under
  `build/jel-full-reproduction/logs` when the full gate is run.

## Release Hygiene

- Isolated install passes through F050.
- Release-facing defaults and user workflow diagnostics pass through F051.
- Migration guidance is recorded in `docs/legacy-migration-guide.md`.
- Release checklist is recorded in `docs/release-checklist.md`.
- Conformance-profile release notes are recorded in `NEWS.md`.
- License and clean-room source boundaries are recorded in `PROVENANCE.md`.

This is a conformance-profile v1 engineering signoff. It is not a Git tag by
itself; tagging still requires rerunning the checklist on the target release
machine and recording any environment-specific skips.
