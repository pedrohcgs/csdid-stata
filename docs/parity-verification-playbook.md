# Parity Verification Playbook

Status: frozen for conformance profile v1.

## North Star

Build a Stata `csdid` package that faithfully reproduces R `did` 2.5.1 for
Callaway-Sant'Anna multi-period DiD workflows. R is the statistical oracle.
Python contributes deeper tests. Current Stata contributes legacy migration
evidence only. JEL-DiD is the empirical release gate. The pinned Stata
engineering repositories guide implementation quality but never override R
parity.

## Source Hierarchy

| Rank | Source | Binding role |
| --- | --- | --- |
| 1 | R `did` 2.5.1 at `9aba07d054a798558ac9b551887f5cb592d8db10` | estimator behavior, defaults, samples, inference, aggregation, plotting data, validation |
| 2 | Python `csdid` at `555f28bc12fcafa9c099e6e5503a30a4c22fc89f` | deeper tests and regression cases, subordinate to R |
| 3 | Existing Stata `csdid` at `fdbae25521a941314af8d84ec0c93fb0596daa8e` | compatibility inventory and legacy fixtures only |
| 4 | JEL-DiD at `50f4f183783d2344f85bc4f39bcbcc1b7eba6466` | empirical release acceptance |
| 5 | Algebraic and simulation invariants | sanity checks where no software oracle exists |
| 6 | Pinned Stata engineering references | ado/Mata architecture, testing, performance, packaging, dependency policy |

When references disagree, isolate the smallest fixture, export R output first,
record the disagreement in `docs/behavior-decisions.md`, and test the chosen
behavior. R wins unless an approved divergence is recorded before
implementation.

## Status Vocabulary

| Status | Meaning | Mandatory-row terminal status |
| --- | --- | --- |
| `contract-frozen` | Scope, source, fixture, tolerance, and evidence path are frozen before implementation | No |
| `parity-verified` | Compared against the governing source and passed | Yes |
| `approved-divergence` | Intentionally different from a reference with a decision record and regression test | Yes |
| `implemented-only` | Implemented and tested without external oracle | No |
| `unsupported-by-design` | Rejected with a clear user-facing error | Only for preapproved nonmandatory legacy rows |
| `soft-deprecated-alias` | Accepted with warning and mapped to canonical behavior | Only for preapproved nonmandatory legacy rows |
| `blocked` | Incomplete or unresolved | No |

## Evidence Layout

Implementation must write generated and committed evidence under these paths:

- F, RT, and PY rows: `tests/fixtures/parity/{matrix_id_lowercase}/`
- JEL rows: `tests/fixtures/jel/{matrix_id_lowercase}/`
- per-fixture inputs: `{fixture}/inputs/*`
- per-fixture source outputs: `{fixture}/expected/r/*`,
  `{fixture}/expected/python/*`, `{fixture}/expected/legacy-stata/*`, and
  `{fixture}/expected/new-stata/*`
- per-fixture manifest: `{fixture}/metadata/manifest.json`
- `tools/parity/generators/{matrix_id_lowercase}/*`
- `reports/parity-summary.md`
- `reports/jel-replication-summary.md`
- `reports/engineering-audit.md`

Default tests consume committed deterministic artifacts. Regeneration jobs may
require R, Python, licensed Stata, or internet access, but those jobs are always
opt-in.

Fixture schemas are frozen in `inst/spec/fixture-schemas.md`. Reference locks
are frozen in `tools/parity/reference-lock/`. R/Python source test hashes are
frozen in `tools/parity/source-test-inventory.csv`.

## R Parity Workflow

Use the pinned R checkout and record its commit, R version, package versions,
and generator hashes in `tools/parity/reference-lock/`.

For every fixture and inherited R test:

1. Generate canonical input data in a neutral format readable by R, Python, and
   Stata.
2. Run R `did` 2.5.1 first.
3. Export ATT(g,t), standard errors, confidence intervals, critical values,
   influence-function summaries, aggregation weights, sample masks, diagnostics,
   plot data, and errors/warnings where applicable.
4. Compare new Stata against the exported R artifacts under
   `docs/tolerance-registry-v1.md`.
5. Store the exact generator command and hashes in the fixture manifest.

Every R file in `tests/testthat/` is mapped by RT001-RT030 in
`inst/spec/feature-matrix.csv`.

R generation must set and record RNG seed and `RNGkind()` for any stochastic
fixture. `tools/parity/reference-lock/r-did-lock.json` is the
pre-implementation source lock; fixture manifests extend it with run-specific
versions and hashes.

## Python Deeper-Test Workflow

Use Python `csdid` only after R behavior is clear. Python output is used to
discover deeper fixtures, validate stress cases, and inherit regressions around
unbalanced panels, inference, parametric combinations, JEL replication, and user
bug fixes. Python cannot override R. Python files are mapped by PY001-PY024 in
`inst/spec/feature-matrix.csv`.

## Legacy Stata Workflow

Run the current Stata package only as legacy evidence:

- inventory existing command and postestimation surfaces;
- generate legacy outputs for retained compatibility modes;
- test that R-parity defaults differ from legacy behavior where the contract
  says they must differ;
- test soft-deprecation warnings.

Current Stata output is never the estimator oracle when it disagrees with R.

## JEL-DiD Workflow

JEL-DiD is a release gate. Its original committed and pinned empirical
artifacts are acceptance targets even though the JEL `renv.lock` uses R `did`
2.3.0. Package-wide estimator parity still targets R `did` 2.5.1. If a JEL
artifact depends on behavior that differs between the JEL dependency context
and R `did` 2.5.1, the implementation must add an empirical compatibility
decision and keep R-parity defaults unchanged.

The R and Stata pipelines must be run in isolated environments for full
regenerated JEL parity. In the current default gate, every table/figure is
mapped by JEL001-JEL018 and audited through committed script/artifact hashes
plus full-reproduction evidence registries under `tests/fixtures/jel/`.

For each artifact:

1. Record the R script and Stata do-file that produce it.
2. Run R with the JEL `renv.lock` context and preserve table/plot-data
   artifacts.
3. Run Stata with a local ado path that places the new `csdid` before any SSC
   installation.
4. Compare numeric table contents cell-by-cell.
5. Compare figure data before comparing rendered PDFs.
6. Approve rendered graph differences only when plot-data parity already
   passed and the difference is cosmetic.

## Unbalanced-Panel Workflow

F016 is an early blocking fixture. It must prove:

- balanced panel data stay on the panel path;
- unbalanced panel data use the repeated-cross-section path by default;
- all R-consistent observations are retained;
- standard errors match R;
- sample masks and row counts match R;
- current Stata pair-balanced and full-balanced behaviors are opt-in
  compatibility modes or soft-deprecated aliases if retained, or explicit
  `unsupported-by-design` errors if removed;
- retained compatibility modes warn and all removed modes are tested.

## Stata Engineering Workflow

The implementation must follow `docs/stata-engineering-references.md`:

- ado wrappers own syntax, validation, sample marking, messages, `ereturn`, and
  postestimation dispatch;
- Mata kernels own group/time indexing, 2x2 construction, influence-function
  storage, covariance/bootstrap accumulation, and aggregation weights;
- optional fast paths for `gtools` or `ftools` require base-Stata/Mata fallback
  and fast-path/fallback parity tests;
- `reghdfe` is not a required runtime dependency for v1;
- default tests must not install packages from the network.

## Integration Controls

Default tests run offline against committed artifacts. Heavier checks use:

- `CSDID_RUN_R_PARITY=1`
- `CSDID_RUN_PYTHON_PARITY=1`
- `CSDID_RUN_LEGACY_STATA_PARITY=1`
- `CSDID_RUN_JEL_REPLICATION=1`
- `CSDID_RUN_BENCHMARKS=1`

## Completion Gates

Gate 1: Spec completeness. All R tests, Python deeper tests, current Stata
options, JEL artifacts, tolerances, and engineering requirements are mapped.

Gate 2: Estimator parity. ATT(g,t), methods, controls, base periods,
anticipation, weights, missingness, and panel/RC modes pass.

Gate 3: Inference parity. Analytical SEs, bootstrap, clustering, simultaneous
bands, p-values, and influence-function dimensions pass.

Gate 4: Aggregation and plotting. Simple, group, calendar, dynamic, plot-data,
stored results, and postestimation workflows pass.

Gate 5: Empirical replication. All JEL tables and figure data pass.

Gate 6: Release hygiene. Clean install, isolated ado path, help files, no data
or global-state leaks, benchmark budgets, provenance, and engineering audit
pass.

## Final Report Requirements

The implementation final report must record reference commits, checksums,
package versions, Stata version, feature-matrix summary, R/Python/JEL parity
tables, legacy compatibility status, tolerance exceptions, approved
divergences, benchmark results, engineering audit, license/source-use
statement, and regeneration commands.
