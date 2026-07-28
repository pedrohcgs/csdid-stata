# Legacy Stata Migration Guide

Status: migration contract for conformance profile v1.

This guide covers migration from legacy Stata `csdid` 1.82 at commit
`fdbae25521a941314af8d84ec0c93fb0596daa8e` to the clean-room Stata port.
Legacy Stata is compatibility evidence only. R `did` 2.5.1 at commit
`9aba07d054a798558ac9b551887f5cb592d8db10` is the estimator oracle unless a
frozen behavior decision records a narrower divergence.

## Source Hierarchy

1. R `did` 2.5.1 controls estimator behavior, defaults, samples, inference,
   aggregation, and plot-data parity.
2. Python `csdid` contributes deeper tests where those tests are compatible
   with R `did` 2.5.1.
3. Legacy Stata `csdid` contributes migration evidence only.
4. JEL-DiD is a release-blocking empirical replication suite; it does not
   override the package-wide R `did` 2.5.1 default contract.

## Defaults

New Stata estimator and sample defaults match R `did` 2.5.1, with the
owner-directed D003 unbalanced-panel rule: when `ivar()` is supplied and the
panel is actually unbalanced, the port uses the repeated-cross-section
computation path while preserving standard-error accounting. It does not
reproduce legacy Stata's silent pair-balanced unit dropping.

### Breaking change: how group size is measured (F-014)

`csdid` refuses to run when the never-treated group is too small to be a
credible control, and warns about any small group. The size threshold is
`#covariates + 5`, as in R.

**What changed:** group size is now measured the way R measures it — *rows
divided by the number of periods*, i.e. the average number of units per period
— rather than the number of distinct units. Verified against R `did` 2.5.1
`pre_process_did`, which computes `gcnt / length(tlist)`.

The two measures are **identical on balanced panels**. They differ only on
**unbalanced** panels, where rows-per-period is strictly smaller, so the guard
now fires in some cases where earlier builds estimated. Concretely, a
never-treated group of 5 distinct units observed in only 19 of 20
possible unit-periods averages 4.75 units per period and is now refused,
exactly as R refuses it.

**If this affects you,** the refusal message names the fix, and it is the same
one R recommends:

```stata
csdid y, ivar(id) time(t) gvar(g) notyet
```

`notyet` uses not-yet-treated units as controls, which does not depend on the
never-treated group being large. Alternatively, supply more never-treated units
or fewer covariates (the threshold scales with the covariate count).

**Why this is the right default:** without it, `csdid` silently returned
estimates from samples the reference implementation considers too small to
trust, and the divergence was invisible to the user. The guard changes *whether
the command runs*; it never changes an estimate, a standard error, or a
critical value.

Note also that the refusal is raised whether or not output is suppressed.
R's `stop()` is not conditional on verbosity, so `quietly csdid ...` refuses
too rather than silently proceeding.

Omitting `ivar()` is repeated cross sections, matching R `panel = FALSE`.
The default control group is never-treated where available, the default base
period is varying, the default method is `dr`, the default confidence level is
95, and omitted inference follows R `did` 2.5.1: multiplier bootstrap with
simultaneous confidence bands and 1000 iterations. Use `analytical` or
`vce(analytical)` only when analytical standard errors are deliberately needed.

## Legacy Option Mapping

| Legacy surface | v1 behavior | Evidence |
| --- | --- | --- |
| `method(dripw)` | Accepted with warning; canonical method is `dr`. | F010, F045, F046 |
| `method(stdipw)` | Accepted with warning; canonical method is `ipw`. | F010, F045, F046 |
| `asinr` | Accepted with warning as a no-op; R-compatible not-yet controls are governed by `notyet`. | F017, F045, F046 |
| `wboot(wtype(rademacher))` | Accepted as the R-compatible multiplier path. | F035, F046 |
| `wboot(wbtype(mammen))`, `wboot(wtype(gaussian))`, `wboot(wtype(normal))` | Unsupported in this R-parity port and now fail loudly rather than being silently coerced to rademacher. | F035, F046 |
| `wboot reps(#) seed(#)`, `wboot reps(#) rseed(#)` | Accepted as Stata-style shorthand for `wboot(reps(#) seed(#))` and `wboot(reps(#) rseed(#))`; top-level `reps()`, `biters()`, `seed()`, and `rseed()` are also accepted with default bootstrap inference. | F035, F051 |
| `allowunbalanced`, `allow_unbalanced` | Accepted for readability; this is already the default for actually unbalanced `ivar()` data. `allow_unbalanced` remains as the R-parity spelling. | F016, F017, F045, F051 |
| `storeall`, `store_all` | Preferred full stored-result opt-in for users who need large matrices in `e()`. `store_all` remains as the R-parity spelling. | F049, F051 |
| `bal(full)`, `balance(full)`, `bal(unbal)` | Soft-deprecated warning aliases for `allowunbalanced`; they do not restore legacy unit dropping. | F016, F017, F045 |
| `long`, `long2` | Accepted with a strong deprecation warning; when `baseperiod()` is omitted they use `baseperiod(universal)` to preserve legacy/JEL event-study layout. | F017, F036, F045, JEL |
| `id(idvar)` | Accepted as a Stata-style alias for `ivar(idvar)`; conflicting `id()` and `ivar()` values are rejected. | F036, F051 |
| `notyettreated`, `nevertreated` | Accepted as readable control-group aliases; `notyettreated` maps to `notyet`, and `nevertreated` records the R default control group. | F008, F036, F051 |
| `vce(cluster clustvar)` | Accepted as Stata-style syntax for `cluster(clustvar)`; conflicting `vce(cluster ...)` and `cluster()` values are rejected. | F015, F036, F051 |
| `dryrun` | Rejected as an internal legacy option. | F036, F045 |
| `agg(event)` | Accepted as an immediate wrapper over verified dynamic aggregation, with legacy `r(table)` and posted coefficient matrices. Other immediate `agg()` types still use `csdid_stats`. | F003-F006, F025, F036 |
| `csdid_stats event`, `csdid_stats, type(event)` | Accepted as aliases for dynamic aggregation. | F006, F025, F051 |
| `estat dynamic`, `estat simple`, `estat group`, `estat calendar` | Accepted as conventional postestimation aggregation replay forms backed by `csdid_stats`. | F003-F006, F027, F051 |
| graph styling options | Cosmetic only; parity is checked on plot data before graph rendering. | F028, F040-F044 |

Every retained legacy alias must be opt-in, emit a deprecation or compatibility
warning, record canonical behavior in stored results when applicable, and avoid
changing R-parity defaults.

## What To Compare

Use the fixture matrix as the migration map:

- F045 compares old default divergences and proves that rejected legacy defaults
  cannot silently govern v1 behavior.
- F046 freezes retained legacy warning text and canonical behavior.
- F016 proves the owner-directed unbalanced-panel default.
- F017 proves soft-deprecated balancing aliases and strongly deprecated legacy
  long options.
- F035 proves the current bootstrap option-surface mapping.
- F036 proves the immediate `agg(event)` wrapper used by JEL-DiD.
- F051 proves release-facing Stata-style aliases, bootstrap shorthand,
  postestimation aggregation aliases, and default user-workflow diagnostics.
- F040-F044 and JEL001-JEL018 govern JEL-DiD empirical replication.

Do not compare new Stata output to legacy Stata as the statistical oracle.
Legacy Stata can explain migration hazards, but R `did` 2.5.1 controls the
target behavior.

## Release Limitations

This guide does not claim full release parity by itself. Rows that remain
`contract-frozen` in `inst/spec/feature-matrix.csv` are still incomplete. The
hardening goal remains blocked until all mandatory R, Python, JEL,
documentation, benchmark, and engineering gates reach an allowed terminal
status.
