# Collaborator Testing Protocol

Status: required protocol for `csdid` Stata `2.0.0-rc1` external review.

Date: 2026-07-09

This protocol is for collaborator stress testing before the final public
`v2.0.0` release. The release candidate is intended to replace the legacy
Stata `csdid` structure, but final tagging still requires platform and
independent-review evidence.

## Minimum Review

Each collaborator should run these checks from the extracted handoff bundle:

```stata
do install.do
csdid version
do validation-tests/install-and-smoke.do
```

Shell users can run the same bundled smoke test with:

```bash
bash validation-tests/run-install-smoke.sh
```

Then run all public examples:

```stata
do examples/01_balanced_panel.do
do examples/02_unbalanced_weighted_clustered.do
do examples/03_repeated_cross_section.do
do examples/04_postestimation_exports.do
do examples/05_legacy_migration.do
do examples/06_mpdta_workflow.do
```

## Required Stress Areas

Reviewers should test at least one real or realistic workflow in each area:

- balanced panel, no covariates;
- covariate `method(dr)`;
- weighted `method(ipw)`;
- unbalanced `ivar()` panel, using default R-compatible repeated-cross-section
  semantics;
- repeated cross-section data without `ivar()`;
- clustered inference;
- default bootstrap, cband, and 1000-repetition behavior;
- `csdid_stats` simple, group, calendar, and event/dynamic aggregation;
- `estat event`, `estat simple`, `estat group`, `estat calendar`, `estat tidy`,
  and `estat glance`;
- `csdid_plot, saving()` plot-data export;
- legacy migration aliases that matter for old code, especially
  `bal()`/`balance()`, `long`/`long2`, `method(dripw)`, and `method(stdipw)`.

## R Parity Checks

For any numerical discrepancy, compare against R `did` 2.5.1. Report:

- the Stata command and Stata version;
- the matching R `att_gt()` or `aggte()` call;
- dataset dimensions and whether data are panel or repeated cross-section;
- whether covariates, weights, clusters, bootstrap, cband, and unbalanced
  panels were used;
- the maximum absolute ATT difference and maximum standard-error difference;
- the complete Stata log and R output.

Numerical differences from R `did` 2.5.1 are release blockers unless already
listed as approved divergences in the frozen contract.

## Performance Checks

Report performance regressions only with enough context to reproduce them:

- operating system, CPU, memory, Stata version and edition;
- dataset rows, number of groups, number of periods, and number of ATT(g,t)
  cells;
- method, covariates, weights, cluster, bootstrap reps, and cband status;
- command runtime from Stata;
- `e(bootstrap_accelerator)`, `e(bootstrap_accelerator_status)`, and
  `e(bootstrap_accelerator_file)` for seeded bootstrap reports;
- `e(agg_boot_accelerator)` and `e(agg_boot_accel_status)` for seeded
  aggregation bootstrap reports;
- whether the run used defaults, `storeall`, or `performance(lean)`.

The current release evidence requires F049 non-bootstrap rows and the literal
omitted-option default bootstrap/cband row to pass `<=1.8x` R. Expanded seeded
bootstrap rows retain a cross-platform hard gate of `<=3x` R and a `<=2x`
stretch gate. Reported memory evidence must come from the process-RSS gate,
not Stata's `c(memory)` setting.

The development repository also requires the pinned seven-trial
legacy-to-candidate gate. All frozen workloads must be faster and use less
peak RSS at both the paired median and bootstrap 95% upper bound. Collaborators
do not need the internal legacy checkout to run the lean handoff smoke test;
the complete certification evidence is bundled under `validation/`.

## Sign-Off Standard

Final `v2.0.0` cannot be tagged from collaborator enthusiasm alone. Before
final release, the release evidence must include:

- macOS, Windows, and Linux platform rows with `release_gates_status=pass`;
- independent Stata/Mata implementation sign-off;
- independent econometrics/user-surface sign-off;
- release-owner decision approving final release;
- disposition of every blocking finding.
