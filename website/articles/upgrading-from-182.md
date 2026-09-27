---
title: Upgrading from Version 1.82
---

# Upgrading from csdid Version 1.82

Throughout this page, *Version 1.82* means the last revision of the 1.8x line
(November 2025), the version this page and the
[speed comparison](speed-vs-182.html) were measured against.
`ssc install csdid` installs Version 1.81, dated 2025-10-05; the two places
where it differs from Version 1.82 are [listed below](#version-181).

The command surface is deliberately unchanged, so most do-files run exactly as
they are. Four things can need your attention: results that move,
postestimation forms that are gone, commands that are deprecated, and option
spellings that have been renamed.

## Results that move

<div class="important" markdown="1">
Five defaults changed. The comparison group and the base period can change
point estimates; so can trimming, where it binds, and balancing, on an
unbalanced panel (see [Unbalanced panels](#unbalanced-panels) below).
Inference changes standard errors and intervals, never point estimates.
</div>

| | Version 1.82 | 2.0.0 | To keep the old behavior |
| --- | --- | --- | --- |
| comparison group | never-treated | not-yet-treated | `nevertreated` |
| base period | varying | universal | `base_period(varying)` |
| inference | analytical, pointwise | multiplier bootstrap, simultaneous bands | `analytical` |
| propensity-score trimming | none | comparison observations at .995 or above, without a message | `pscoretrim(1)` |
| unbalanced panels | each 2×2 balanced separately | balanced once, `bal(full)` | `bal(pair)` |

The first two rows are also the two defaults on which 2.0.0 departs from
R `did` 2.5.1, which shares Version 1.82's comparison group and base period;
the other three follow R. Set both options explicitly when comparing
implementations, alongside the same sample, estimator, weights, and inference
settings.

<div class="note" markdown="1">
Inference leaves the estimand alone: standard errors are now the multiplier
bootstrap with simultaneous confidence bands by default, where Version 1.82
reported pointwise analytical standard errors. `analytical` restores analytical
standard errors; add `pointwise` to request fully analytical pointwise
intervals for aggregations too. Otherwise their simultaneous critical value is
still bootstrapped.
</div>

To reproduce a Version 1.82 run, state the options explicitly (none of them
is implied by the others). Let's load
the county mortality panel used throughout this site:

```stata
import delimited using ///
    "https://raw.githubusercontent.com/pedrohcgs/JEL-DiD/50f4f18/data/county_mortality_data.csv", ///
    clear varnames(1) bindquote(strict) stringcols(_all)
destring deaths population_20_64 year yaca county_code stfips, replace force
generate double mrate = 100000 * deaths / population_20_64
drop if missing(mrate) | population_20_64 <= 0
generate int gvar = yaca
replace gvar = 0 if missing(gvar) | gvar > 2019
bysort county_code: generate byte nyears = _N
keep if nyears == 11
save "jel_upgrade.dta", replace
```

```stata
use "jel_upgrade.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) ///
    nevertreated base_period(varying) analytical pscoretrim(1)
display "comparison group: " e(control_group)
display "base period:   " e(base_period)
estat event
```

Those options, with `bal(pair)` added on an unbalanced panel, give you
Version 1.82's estimates and standard errors, with the exceptions listed in
the next section. Drop them and you get the 2.0.0
defaults instead:

```stata
use "jel_upgrade.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
display "comparison group: " e(control_group)
display "base period:   " e(base_period)
estat event
```

## Changes that options do not undo

These move numbers in a Version 1.82 do-file, and no option brings the old
number back.

- **`notyet` pre-treatment cells follow Version 1.82's `asinr` rule.** In a
  pre-treatment cell with a varying base period, Version 1.82's `notyet`
  compared cohort *g* only with cohorts treated after *g*; `asinr` compared it
  with every cohort not yet treated at *t*. Version 2.0.0's `notyet` keeps a
  comparison unit when it is untreated in both periods of the comparison,
  which is the `asinr` rule, so under `notyet base_period(varying)` the
  pre-treatment cells, pre-period event-study coefficients and the pre-test
  differ from Version 1.82's plain `notyet`. Post-treatment cells do not.
- **`long` reports pre-treatment cells with the opposite sign.**
  Version 1.82's `long` and `long2` gave the same pre-treatment cells with
  opposite signs, and 2.0.0 gives `long2`'s for both. After `long`, every
  pre-treatment ATT(g,t) changes sign, and each pre-period event-study
  coefficient changes sign and moves one event time earlier: Version 1.82's
  `Tm1` is 2.0.0's `Tm2` with the sign reversed, and 2.0.0's `Tm1` is the
  reference row, fixed at 0.
- **The bootstrap draws Rademacher multipliers.** Version 1.82's `wboot` drew
  Mammen multipliers unless `wbtype(rademacher)` was given; 2.0.0 draws only
  Rademacher multipliers, so bootstrap standard errors and bands change as
  any change of draws changes them.
- **The overall standard error of `estat group`.** The cohort effects, their
  standard errors and the overall effect are Version 1.82's; the overall
  effect's standard error is not (0.0119 against 0.0118 on the package's
  `mpdta` example with `lpop` as covariate, and a wider gap under sampling
  weights). The event-study, calendar and simple aggregations report
  Version 1.82's standard errors.
- **Time-varying iweights move the aggregations on a balanced panel.** The
  cohort shares behind the simple, calendar and event-study aggregations, and
  behind the overall effect of `estat group`, count each unit at its iweight
  in the first period; Version 1.82 counted it at its mean iweight over its
  periods. Where a unit's iweight varies over time, those estimates and their
  standard errors differ from Version 1.82's, including the ones the previous
  item lists as unchanged. The two rules agree when each unit's iweight is
  constant, and on an unbalanced panel under `bal(pair)`, which also uses the
  mean. The ATT(g,t), their standard errors and the per-cohort effects of
  `estat group` do not move.

One further change moves no number but can stop a `nevertreated` run that
Version 1.82 estimated. Version 1.82 had no size check on the never-treated
group; 2.0.0 refuses a never-treated comparison group smaller than
`#covariates + 5` (measured as rows divided by periods), on balanced panels
too. `notyet`, the default, does not depend on the never-treated group.

### Version 1.81 {#version-181}

`ssc install csdid` installs Version 1.81, which differs from Version 1.82 in
two places. Its `method(ipw)` weighted without normalizing the weights;
Version 1.82 and 2.0.0 normalize them (Version 1.81's `method(stdipw)`), so
`method(ipw)` estimates change and 2.0.0 has no unnormalized version. And
aggregation standard errors on repeated cross sections differ slightly from
Version 1.81's. Everything else on this page applies to Version 1.81 as well.

## Unbalanced panels

Version 1.82 balanced each 2×2 comparison separately, dropping the units
missing from either of its periods: it said the panel was unbalanced, but not
which or how many units each comparison dropped. `csdid` 2.0.0 makes the
choice explicit with `bal()` and reports whatever it drops (units and
observations both):

| | |
| --- | --- |
| `bal(full)` | drop units not observed in every period, once, for all comparisons. **Default**, matching R `did`. |
| `bal(none)` | keep every unit and use the repeated-cross-section computation. |
| `bal(pair)` | Version 1.82's per-comparison balancing: each 2x2 keeps the units observed in both of its periods. |

<div class="tip" markdown="1">
`bal(pair)` reproduces Version 1.82's estimand exactly, so an unbalanced-panel
result from that version can be reproduced here by asking for it.
</div>

## Postestimation forms that are gone

Each of these ran in Version 1.82 and stops a do-file in 2.0.0.

| Version 1.82 | 2.0.0 |
| --- | --- |
| `estat pretrend` | `csdid` prints the pre-test below the ATT(g,t) table and stores it in `e(wald_stat)`, `e(wald_df)` and `e(wald_pvalue)`. `window()` has no equivalent |
| `estat cevent` | No equivalent. `estat event, window(# #)` reports the effects inside an event-time window |
| `estat all` | Run `estat simple`, `estat group`, `estat calendar` and `estat event` |
| `estore()`, `esave()` | `estat` *type*`, post`, then `estimates store` or `estimates save` |
| `estat event, balance(#)` | `csdid_stats event, balance(#)` |
| `csdid ..., agg(simple\|group\|calendar\|attgt)` | `csdid`, then `estat` *type*. `agg(event)` still works |
| `csdid, version` | `csdid version` |
| `csdid_stats attgt`, `csdid_stats cevent` | `estat attgt`; `cevent` has no equivalent |
| `csdid_stats` with no type | Aggregates by group, where Version 1.82 redisplayed the active results. Name the type |
| `csdid_stats ..., wboot` | Bootstrap inference is chosen when `csdid` runs; aggregation from a saved RIF file is analytical |
| `csdid_stats ..., save` | `storeall` keeps the aggregation's influence functions in `e(agg_inffunc)` |
| `csdid_stats ..., post` | `estat` *type*`, post` |
| A RIF file written by Version 1.82 | `csdid_stats using` reads files written by 2.0.0's `saverif()`; run `csdid` again with `saverif()`. `csdid_stats` aggregates a file only through `using`, not after `use` |

Coefficient names and stored results have a new layout, documented in
`help csdid`: ATT(g,t) cells are named like `g2004___2005_2003` (Version 1.82:
`g2004:t_2003_2005`); the overall effect of `estat group` and `estat calendar`
is `Overall` (Version 1.82: `GAverage`, `CAverage`); `estat event` reports no
`Pre_avg`; and `e(b)`, `e(V)`, `e(attgt)` and `e(N_clusters)` take the place of
Version 1.82's `e(b_attgt)`, `e(V_attgt)`, `e(gtt)` and `e(N_clust)`.

## Deprecated commands

These still ship and still run, and each of them now prints a notice (a
notice, not an error) saying what to use instead.

| Deprecated | Use instead |
| --- | --- |
| `csdid_rif` | `estat attgt, saving(results) replace` then `use results, clear` |
| `csdid_table` | the table `csdid` prints, or `estat tidy, saving()` for the numbers |
| `dipt` | never documented; no replacement |
| `tsvmat` | never documented; no replacement |

`csgvar` is *not* deprecated, since it builds the `gvar()` cohort variable from a
treatment indicator and is fully supported.

The saved-RIF workflow itself is also still supported: `csdid_stats using`
*filename* aggregates a file written by `saverif()`, and only the
table-building command around it is deprecated. `csdid_rif` reads RIF files
written by Version 1.82 and refuses those written by 2.0.0.

`help csdid_legacy` documents all of this inside Stata (offline), so you don't have to
keep this page open beside you.

## Renamed options

Every Version 1.82 spelling below is accepted and says what to use instead, so you
find out by running your do-file. Nothing on the list will stop a do-file from
running, but `long` changes the sign of its pre-treatment cells (see above).

| Old (warns) | Current |
| --- | --- |
| `long`, `long2` | `base_period(universal)`, which is now the default. Both give Version 1.82's `long2` cells, so `long` reverses the sign of its Version 1.82 pre-treatment cells |
| `method(dripw)` | `method(dr)` |
| `method(stdipw)` | `method(ipw)` |
| `asinr` | no-op; use `notyet` |
| `never` | `nevertreated`. Not a no-op: the not-yet-treated comparison group is the default now, so this changes which units the treated are compared against |

## Spellings that are not renames

These are alternative names for current options, so they are not deprecated,
nothing warns, and there is nothing at all to change in a do-file that uses
them.

| Spelling | Same as |
| --- | --- |
| `baseperiod()` | `base_period()` |
| `id()` | `ivar()` |
| `vce(cluster var)` | `cluster(var)` |
| `fixweights(base)` | `fix_weights(base_period)` |
| `balance()` | `bal()`, the same option unabbreviated |
| `unbalanced` | `bal(none)`. Typed in full -- `unbal` is not an option |
| `allowunbalanced`, `allow_unbalanced` | `bal(none)` as well; the R-style longhand, also typed in full |

## Spellings that were never options

You may have seen these somewhere, but they have never been options in any
release. They are not in Version 1.82, and 2.0.0 is the first release of the
rewrite. csdid refuses them the way it refuses any other name it does not know.

| Not an option | Type instead |
| --- | --- |
| `bal(unbal)`, `bal(unbalanced)`, `bal(allow_unbalanced)` | `bal(none)`, or the `unbalanced` option |
| `balanceall`, `bal(all)` | `bal(full)` |
| `balancepair` | `bal(pair)` |
| `lean`, `performance(...)` | nothing: influence functions stay internal at every size, and `storeall` is the one switch that copies them into `e()` |

## Options that now refuse

Each of these ran under Version 1.82 and stops a do-file in 2.0.0. We would
rather stop a run than return a number we cannot vouch for, or one from a
method this version does not offer.

| Option | What happens now |
| --- | --- |
| `method(drimp)` | Errors. The improved doubly robust estimator is not offered; `method(dr)` is Version 1.82's `method(dripw)` |
| `wboot(wbtype(mammen))` | Errors. Only the Rademacher multiplier is supported |
| `wboot(reps(#))` with `#` ≤ 20 | Errors. Too few iterations to support a simultaneous band |
| `pscoretrim(#)` with `#` ≤ 0 | Errors. Omit for the default `.995`, or pass `1` for no trimming |
| `gvar()` with negative values | Errors. Use `0` for never-treated |
| `from()` | Removed. It set a lower event-time bound on the simple, group and calendar aggregations, and R fixes that bound at event time 0, so there is no equivalent. `from(0)` was the legacy default and is already what `csdid` does, so most uses were no-ops. For event-time windows use `estat event, window(# #)` |
| `dryrun` | Rejected; it was an internal option |

## What you gain

There is no external dependency (no drdid, and nothing else). The SSC entry
for Version 1.81 reads `Requires: Stata version 14 and drdid from SSC`, and
Version 1.82 needs `drdid` too, while 2.0.0 needs nothing beyond Stata
itself. It is also faster: between 10x and 35x, and never slower, on the
fixed-size workloads in the package README, and from 10x to 308x as the
design's size, periods, cohorts and sampling scheme vary, on
[their own page](speed-vs-182.html).

Back to [the guides](../index.html#guides).
