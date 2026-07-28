# Public API Freeze For v2

Status: release-candidate API policy for `2.0.0-rc1`; required before final
`v2.0.0`. The default-inference item below remains release-blocking until the
release owner and econometrics reviewer either switch Stata to R's bootstrap
default or record an explicit approved divergence.

## Frozen Command Surface

The public command surface consists of:

- `csdid`
- `csdid_estat`
- `csdid_stats`
- `csdid_plot`
- `estat attgt`
- `estat event`
- `estat dynamic`
- `estat simple`
- `estat group`
- `estat calendar`
- `estat tidy`
- `estat glance`

## Frozen Estimator And Sample Defaults

The estimator and sample defaults must match R `did` 2.5.1:

- `method(dr)`
- never-treated controls
- `baseperiod(varying)`
- `anticipation(0)`
- `level(95)`
- optimized computation and automatic storage resolution
- unbalanced `ivar()` data use the R-compatible repeated-cross-section path

## Omitted-Inference Default

R `did` 2.5.1 defaults to multiplier bootstrap inference with simultaneous
confidence bands and 1000 iterations. This Stata release candidate now uses the
same omitted-inference default. Analytical inference is opt-in through
`analytical` or `vce(analytical)`.

## Frozen User-Facing Names

Preferred Stata-facing names:

- `id()` as an alias for `ivar()`
- `baseperiod(varying|universal)`
- bare `varying` and `universal`
- `notyettreated`
- `nevertreated`
- `allowunbalanced`
- `vce(cluster clustvar)`
- `storeall`
- `wboot reps(#) seed(#)`
- `wboot reps(#) rseed(#)`

R-parity names such as `ivar()`, `notyet`, `cluster()`, and `store_all` remain
accepted.

## Soft-Deprecated Compatibility Names

These remain accepted for migration support, with warnings where appropriate:

- `bal()` and `balance()`
- `long` and `long2`
- `method(dripw)`
- `method(stdipw)`
- `performance(full)`
- `performance(materialized)`

They must never change R-matching defaults.

## Stored Results

Stable stored results are governed by `docs/stored-results-api.md`.
`e(profile)` is diagnostic. It may evolve with internal optimization work.

## Warning And Error Policy

- Continuing compatibility diagnostics use normal warning text.
- True invalid user input exits nonzero and uses error styling.
- Deprecated aliases must state the preferred replacement.
- Unsupported legacy options must fail loudly; they must not silently switch
  to non-R behavior.

## Change Control

No public API change may enter final `v2.0.0` without:

- feature-matrix update;
- behavior-decision update;
- help-file update;
- parity or approved-divergence evidence;
- release-owner approval.
