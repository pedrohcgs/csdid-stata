# Worldwide Release Governance

Status: final-release operating policy for the world-facing Stata `csdid`
replacement.

The package is public statistical infrastructure. Final release decisions must
be made as if a numerical mistake will be cited, replicated, and taught.

## Release Principles

- R `did` 2.5.1 remains the statistical oracle.
- Speed never overrides parity.
- Legacy Stata behavior is compatibility behavior, not the default.
- The public API must be simpler than the internal parser.
- Failed commands must not leave plausible stale or half-valid results.
- Support requests about estimates, standard errors, aggregation, plotting, or
  stored results must produce a fixture or an explicit non-bug disposition.

## Director-Level Release Bar

Final `v2.0.0` requires:

- completed final evidence inventory under `reports/final-release/`;
- independent Stata/Mata implementation review;
- independent econometrics/user-surface review;
- macOS, Windows, and Linux platform rows with release gates passing;
- full smoke, full JEL reproduction, adversarial differential testing,
  release failure-mode testing, and performance gates;
- isolated install verification from the release bundle;
- public help and examples that run from a clean install;
- a release-owner decision that explicitly approves release.

## Stata/Mata Engineering Bar

Maintainability requirements:

- parser complexity must remain reviewable, with any post-release
  decomposition tracked before final tag when reviewers require it;
- new aliases require a documented reason, a canonical normalized spelling, and
  explicit tests;
- new fast paths require an R parity fixture and a performance budget;
- performance-sensitive releases require the pinned legacy-to-candidate time
  and process-RSS confidence-bound gate;
- large matrices stay out of `e()` by default unless `storeall` is requested;
- Mata cache changes require repeated-run, `mata clear`, and failed-estimation
  lifecycle tests.

## Support Bar

Every user-facing numerical issue must include:

- exact Stata command and full log;
- `csdid version` and `which csdid`;
- Stata version, edition, and operating system;
- R `did` 2.5.1 comparison when the issue concerns parity;
- small reproducible data or a fixture generator;
- classification as P0/P1/P2 using `docs/support-runbook.md`.

P0 issues block release, or trigger an immediate patch release if discovered
after release.

## Change-Control Rule

After final release candidate approval, changes are allowed only if they are:

- documentation-only;
- test-only;
- release-evidence additions; or
- code fixes for a signed release blocker.

Any estimator, inference, aggregation, plotting, parser, or stored-result change
must rerun the full model-improvement gate in
`docs/model-improvement-required-tests.md`.
