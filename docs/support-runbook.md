# Support Runbook

Status: support-facing release-candidate runbook.

This runbook is for maintainers and collaborators triaging user reports after
the modern Stata `csdid` release.

## First Response Checklist

Ask for:

- `csdid version`
- `which csdid`
- Stata version and edition
- operating system
- exact command
- full Stata log
- whether the same design was run in R `did` 2.5.1
- data dimensions, number of groups, number of periods, and treatment cohorts
- whether the data are panel or repeated cross section
- whether weights, covariates, clustering, or bootstrap were used
- for bootstrap performance reports, the values of
  `e(bootstrap_accelerator)`, `e(bootstrap_accelerator_status)`,
  `e(bootstrap_accelerator_file)`, and `e(bootstrap_accelerator_rc)`

Direct users to the structured issue forms:

- numerical discrepancy: `.github/ISSUE_TEMPLATE/numerical-discrepancy.yml`
- supported command failure: `.github/ISSUE_TEMPLATE/bug-report.yml`
- performance regression: `.github/ISSUE_TEMPLATE/performance-regression.yml`

## Common Topics

Unbalanced panels:

- Modern Stata `csdid` follows R-compatible behavior by default.
- Actually unbalanced `ivar()` data use the repeated-cross-section computation
  path while preserving the correct standard-error behavior.
- `bal()` and `balance()` are migration aliases and do not restore legacy
  unit-dropping defaults.

Weights:

- `iweight`s are supported.
- Time-varying panel weights follow the frozen `fixweights()` policy.
- Extreme weights should be stress tested against R before publication.

Covariates:

- Covariates are supported for `dr`, `ipw`, and `reg`.
- Near-collinear covariates and separation-like propensity-score designs should
  be treated as numerical edge cases and compared against R.

Clustering:

- `cluster(var)` and `vce(cluster var)` are accepted public spellings.
- Multiple non-id cluster declarations must be rejected unless explicitly
  supported by the frozen contract.

Bootstrap:

- Bootstrap support is described in `docs/bootstrap-scope.md`.
- Users should set a seed and report repetitions for publication workflows.

Postestimation:

- Use `estat event`, `estat simple`, `estat group`, `estat calendar`, or
  `csdid_stats` after estimation.
- Use `csdid_plot, saving(filename) replace` to export plot-ready data.

## Triage Severity

P0:

- Any default Stata result differs from R `did` 2.5.1 outside tolerance.
- Any release build produces silent non-R legacy behavior.
- Any crash corrupts data in memory or leaves invalid postestimation state.

P1:

- Supported option combination fails.
- Stored result contract breaks.
- Help or migration guidance is materially wrong.
- Performance regression violates F049 or opt-in budgets.

P2:

- Confusing warning text.
- Missing example.
- Nonblocking documentation gap.

## Reproduction Rule

Every bug report that affects estimates, standard errors, aggregation, plotting
data, or stored results must get a fixture or a model-improvement gate before
being closed.

## Numerical Discrepancy Protocol

1. Reproduce the Stata result from a clean install and record `csdid version`
   plus `which csdid`.
2. Reproduce the same design in R `did` 2.5.1.
3. Compare ATT(g,t), analytical standard errors, aggregation results, and
   plot-data exports against the frozen tolerance registry.
4. If the report involves bootstrap, first compare point estimates and
   analytical influence-function paths, then compare bootstrap behavior under
   the documented bootstrap scope.
5. Reproduce a compiled-path report with the Mata fallback. A plugin failure is
   never a reason to bypass parity checks; preserve the original log and plugin
   checksum before replacing a binary.
6. If the discrepancy is real, create or extend a fixture before fixing code.
7. If the discrepancy is an approved divergence or unsupported legacy behavior,
   link the relevant contract row and improve diagnostics or documentation if
   the user confusion is reasonable.

No numerical discrepancy should be closed only with an explanation in an issue
thread. It must leave behind an executable regression guard or a documented
contract decision.
