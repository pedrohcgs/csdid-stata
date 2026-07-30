# Legacy Stata Migration Guide

Status: migration contract for conformance profile v1.

This guide covers migration from legacy Stata `csdid` Version 1.82 at commit
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

New Stata estimator and sample defaults match R `did` 2.5.1, including for
unbalanced panels: when `ivar()` is supplied and the panel is actually
unbalanced, the default `bal(full)` drops the units not observed in every
period, once, and reports what it removed -- the same sample R takes. It does
not reproduce legacy Stata's silent pair-balanced unit dropping, which is now
available only on request as `bal(pair)`. See the fuller statement of the three
`bal()` settings below.

### Breaking change: how group size is measured

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

Omitting `ivar()` is repeated cross sections, matching R `panel = FALSE`; the
`rcs` option says the same thing explicitly and lets you keep `ivar()` when the
data carry an identifier anyway.

Two omitted-option defaults deliberately differ from both R `did` 2.5.1 and
Stata `csdid` Version 1.82, and they are the only two that can move a number:

| | csdid 2.0.0 | R `did` and Version 1.82 | To reproduce those |
| --- | --- | --- | --- |
| comparison group | not-yet-treated | never-treated | `nevertreated` |
| base period | universal | varying | `base_period(varying)` |

State either option explicitly and csdid and R agree to machine precision. Both
are recorded as documented divergences.

The remaining defaults follow R: the method is `dr`, the confidence level is 95,
and omitted inference is the multiplier bootstrap with simultaneous confidence
bands over 1000 iterations. Use `analytical` or `vce(analytical)` only when
analytical standard errors are deliberately needed.

An unbalanced `ivar()` panel is balanced by dropping the units not observed in
every period -- `bal(full)`, matching R -- and csdid reports how many units and
observations that removed. `bal(none)` keeps every unit and uses the
repeated-cross-section computation. `bal(pair)` balances each 2x2 separately,
which is what Version 1.82 did silently -- use it to reproduce a result from
that version.

## Legacy Option Mapping

| Legacy surface | v1 behavior |
| --- | --- |
| `method(dripw)` | Accepted with warning; canonical method is `dr`. |
| `method(stdipw)` | Accepted with warning; canonical method is `ipw`. |
| `asinr` | Accepted with warning as a no-op; R-compatible not-yet controls are governed by `notyet`. |
| `wboot(wtype(rademacher))` | Accepted as the R-compatible multiplier path. |
| `wboot(wbtype(mammen))`, `wboot(wtype(gaussian))`, `wboot(wtype(normal))` | Unsupported in this R-parity port and now fail loudly rather than being silently coerced to rademacher. |
| `wboot reps(#) seed(#)`, `wboot reps(#) rseed(#)` | Accepted as Stata-style shorthand for `wboot(reps(#) seed(#))` and `wboot(reps(#) rseed(#))`; top-level `reps()`, `biters()`, `seed()`, and `rseed()` are also accepted with default bootstrap inference. |
| `allowunbalanced`, `allow_unbalanced` | Accepted as a deprecated spelling of `bal(none)`, which keeps every unit and uses the repeated-cross-section computation. It is not the default: an unbalanced `ivar()` panel is balanced with `bal(full)` unless you ask otherwise. |
| `storeall`, `store_all` | Preferred full stored-result opt-in for users who need large matrices in `e()`. `store_all` remains as the R-parity spelling. |
| `bal(full)`, `balance(full)`, `bal(unbal)` | `bal(full)` is the default and drops units not observed in every period; `balance()` is an accepted spelling of `bal()`; `bal(unbal)` is a deprecated spelling of `bal(none)`. None of them restores legacy per-comparison unit dropping -- that is `bal(pair)`. |
| `long`, `long2` | Accepted with a strong deprecation warning; when `baseperiod()` is omitted they use `baseperiod(universal)` to preserve legacy/JEL event-study layout. |
| `id(idvar)` | Accepted as a Stata-style alias for `ivar(idvar)`; conflicting `id()` and `ivar()` values are rejected. |
| `notyettreated`, `nevertreated` | Accepted as readable control-group aliases; `notyettreated` maps to `notyet`, and `nevertreated` selects never-treated controls, which is R's default and not csdid's. |
| `vce(cluster clustvar)` | Accepted as Stata-style syntax for `cluster(clustvar)`; conflicting `vce(cluster ...)` and `cluster()` values are rejected. |
| `dryrun` | Rejected as an internal legacy option. |
| `agg(event)` | Accepted as an immediate wrapper over verified dynamic aggregation, with legacy `r(table)` and posted coefficient matrices. Other immediate `agg()` types still use `csdid_stats`. |
| `csdid_stats event`, `csdid_stats, type(event)` | Accepted as aliases for dynamic aggregation. |
| `estat dynamic`, `estat simple`, `estat group`, `estat calendar` | Accepted as conventional postestimation aggregation replay forms backed by `csdid_stats`. |
| graph styling options | Cosmetic only; parity is checked on plot data before graph rendering. |

Every retained legacy alias must be opt-in, emit a deprecation or compatibility
warning, record canonical behavior in stored results when applicable, and avoid
changing R-parity defaults.

## What To Compare

Use the test suite under `tests/` as the migration map. It pins, among
other things:

- the old default divergences, proving that rejected legacy defaults cannot
  silently govern current behavior;
- the retained legacy warning text and the canonical behavior each alias maps
  to;
- the three `bal()` settings for unbalanced panels;
- the soft-deprecated balancing aliases and the strongly deprecated legacy
  `long` / `long2` options;
- the bootstrap option-surface mapping;
- the immediate `agg(event)` wrapper;
- the Stata-style aliases, bootstrap shorthand, postestimation aggregation
  aliases, and default user-workflow diagnostics;
- plot-data parity and the JEL-DiD empirical replication.

Do not compare new Stata output to legacy Stata as the statistical oracle.
Legacy Stata can explain migration hazards, but R `did` 2.5.1 controls the
target behavior.
