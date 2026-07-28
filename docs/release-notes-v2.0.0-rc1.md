# csdid 2.0.0-rc1 Release Notes

Status: public release-candidate notes for collaborator testing.

## For R `did` Users

This Stata release candidate targets R `did` 2.5.1 parity. Estimator and sample
defaults are aligned to R: `method(dr)`, never-treated controls,
`baseperiod(varying)`, `anticipation(0)`, 95 percent confidence intervals,
multiplier bootstrap inference, simultaneous confidence bands, and 1000
bootstrap iterations. Analytical standard errors are available with
`analytical` or `vce(analytical)`.

Unbalanced panel data follow R semantics by default. When `ivar()` data are not
balanced, Stata uses the repeated-cross-section calculation path while
preserving the correct standard-error behavior.

## For Legacy Stata `csdid` Users

The modern interface keeps common legacy spellings as soft-deprecated aliases
where they can be mapped safely. Examples include `bal()`/`balance()`,
`long`/`long2`, `method(dripw)`, `method(stdipw)`, and older full-storage
performance spellings. New code should use the documented names in `help csdid`.

Legacy behavior is not the default oracle. If a legacy option would silently
produce non-R behavior, it warns, maps to the R-compatible behavior, or errors.

## For Developers

The required model-change gate is `docs/model-improvement-required-tests.md`.
Estimator, inference, storage, parser, aggregation, plotting, and performance
changes must pass parity and no-regression gates before review.

`e(profile)` is diagnostic and may evolve. Public stored results are listed in
`docs/stored-results-api.md`.

## Bootstrap Scope

Multiplier bootstrap support covers ATT(g,t), clustered ATT(g,t), aggregation
postprocessing, pointwise intervals, and simultaneous bands as documented in
`docs/bootstrap-scope.md`. Bootstrap timings are reported separately from
analytical estimation.

Bootstrap acceleration requires no user option. The literal unseeded default
uses an exact vectorized Mata path. Explicitly seeded ATT(g,t) bootstrap uses a
platform plugin when a certified binary is installed beside `csdid.ado`; the
full Mata implementation remains mandatory and is used automatically if the
plugin is absent or fails. The macOS RC binary is universal for Apple Silicon
and Intel. Linux and Windows binaries still require platform runtime evidence
before final release.

## Final Release Blockers

Before final `v2.0.0`, complete the platform matrix and independent review
packet. The local `2.0.0-rc1` handoff is intended for collaborator stress
testing and release review, not as an unreviewed final tag.

Final-release evidence validation is intentionally strict: empty templates,
unapproved reviews, unresolved blocking findings, and platform rows without
`release_gates_status=pass` do not unlock the final tag.
