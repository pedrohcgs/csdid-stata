---
title: Upgrading from Version 1.82
---

# Upgrading from csdid Version 1.82

Throughout, **Version 1.82** means the release SSC distributes via
`ssc install csdid`, dated 2025-10-05.

The command surface is deliberately unchanged, so most do-files run as they are.
This page covers the three things that can need your attention: results that
move, commands that are deprecated, and option spellings that have been renamed.

## Results that move

<div class="important" markdown="1">
Two omitted-option defaults changed, and on unbalanced panels the balancing
default changed too (see [Unbalanced panels](#unbalanced-panels) below).
Those are the only changes that alter a number you were already getting.
</div>

| | Version 1.82 | 2.0.0 | To keep the old behaviour |
| --- | --- | --- | --- |
| comparison group | never-treated | not-yet-treated | `nevertreated` |
| base period | varying | universal | `base_period(varying)` |

Both are also departures from R `did` 2.5.1, which shares Version 1.82's two
defaults. State either option explicitly and `csdid` and R agree to machine
precision.

<div class="note" markdown="1">
A third change is about inference rather than the estimand: standard errors are
now the multiplier bootstrap with simultaneous confidence bands by default,
where Version 1.82 reported pointwise analytical standard errors. Point
estimates are unaffected. `analytical` restores the old standard errors.
</div>

To reproduce a Version 1.82 run, state all three explicitly. Load the county
mortality panel used throughout this site:

```stata
import delimited using ///
    "https://raw.githubusercontent.com/pedrohcgs/JEL-DiD/50f4f18/data/county_mortality_data.csv", ///
    clear varnames(1) bindquote(strict) stringcols(_all)
destring deaths population_20_64 year yaca county_code stfips, replace force
generate double mrate = 100000 * deaths / population_20_64
drop if missing(mrate) | population_20_64 <= 0
generate int gvar = yaca
replace gvar = 0 if missing(gvar) | gvar > 2016
bysort county_code: generate byte nyears = _N
keep if nyears == 11
save "jel_upgrade.dta", replace
```

```stata
use "jel_upgrade.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) ///
    nevertreated base_period(varying) analytical
display "comparison group: " e(control_group)
display "base period:   " e(base_period)
estat event
```

Those three options give you Version 1.82's estimand and Version 1.82's standard
errors. Drop them and you get the 2.0.0 defaults:

```stata
use "jel_upgrade.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
display "comparison group: " e(control_group)
display "base period:   " e(base_period)
estat event
```

## Unbalanced panels

Version 1.82 dropped the units missing from either period of each 2×2
comparison, silently. `csdid` 2.0.0 makes the choice explicit with `bal()` and
reports whatever it drops:

| | |
| --- | --- |
| `bal(full)` | drop units not observed in every period, once, for all comparisons. **Default**, matching R `did`. |
| `bal(none)` | keep every unit and use the repeated-cross-section computation. |
| `bal(pair)` | Version 1.82's per-comparison balancing: each 2x2 keeps the units observed in both of its periods. |

<div class="tip" markdown="1">
`bal(pair)` reproduces Version 1.82's estimand exactly, so an unbalanced-panel
result from that version can be reproduced here by asking for it.
</div>

## Deprecated commands

These still ship and still run, so nothing breaks. Each prints a notice.

| Deprecated | Use instead |
| --- | --- |
| `csdid_rif` | `estat attgt, saving(results) replace` then `use results, clear` |
| `csdid_table` | the table `csdid` prints, or `estat tidy, saving()` for the numbers |
| `dipt` | never documented; no replacement |
| `tsvmat` | never documented; no replacement |

`csgvar` is **not** deprecated. It builds the `gvar()` cohort variable from a
treatment indicator and is fully supported.

The saved-RIF workflow itself is also still supported: `csdid_stats using`
*filename* reads a saved RIF file. Only the table-building command is
deprecated.

`help csdid_legacy` documents all of this inside Stata.

## Renamed options

Every Version 1.82 spelling below is accepted and says what to use instead, so
you find out from running your do-file rather than from reading this page.

| Old (warns) | Current |
| --- | --- |
| `long`, `long2` | `base_period(universal)`, which is now the default, so usually nothing |
| `method(dripw)` | `method(dr)` |
| `method(stdipw)` | `method(ipw)` |
| `asinr` | no-op; use `notyet` |
| `never` | `nevertreated`. Not a no-op: the not-yet-treated comparison group is the default now, so this changes which units the treated are compared against |

## Spellings that are not renames

These are alternative names for current options. They are not deprecated,
nothing warns, and there is nothing to change in a do-file that uses them.

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

You may have seen these somewhere. They have never been options in any
release: they are not in Version 1.82, and 2.0.0 is the first release of the
rewrite. csdid refuses them the way it refuses any name it does not know.

| Not an option | Type instead |
| --- | --- |
| `bal(unbal)`, `bal(unbalanced)`, `bal(allow_unbalanced)` | `bal(none)`, or the `unbalanced` option |
| `balanceall`, `bal(all)` | `bal(full)` |
| `balancepair` | `bal(pair)` |
| `lean`, `performance(...)` | nothing: influence functions stay internal at every size, and `storeall` is the one switch that copies them into `e()` |

## Options that now refuse

Version 1.82 accepted these and quietly did something else. Refusing is the
change: a silently substituted setting is a result you did not ask for.

| Option | What happens now |
| --- | --- |
| `wboot(wtype(mammen))`, `gaussian`, `normal` | Errors. Only the Rademacher multiplier is supported; these used to be coerced to it |
| `wboot(reps(#))` with `#` ≤ 20 | Errors. Too few iterations to support a simultaneous band |
| `pscoretrim(#)` with `#` ≤ 0 | Errors. Omit for the default `.995`, or pass `1` for no trimming |
| `gvar()` with negative values | Errors. Use `0` for never-treated |
| `from()` | Removed. It set a lower event-time bound on the simple, group and calendar aggregations, and R fixes that bound at event time 0, so there is no equivalent. `from(0)` was the legacy default and is already what `csdid` does, so most uses were no-ops. For event-time windows use `estat event, window(# #)` |
| `dryrun` | Rejected; it was an internal option |

## What you gain

No external dependency. Version 1.82's SSC entry reads
`Requires: Stata version 14 and drdid from SSC`; 2.0.0 needs nothing beyond
Stata. And it is 5× to 28× faster on every workload measured, never slower — the
per-workload benchmark table is in the package README, and the gains by
sample size, periods, cohorts, and sampling scheme (16× to 208×) are on
[their own page](speed-vs-182.html).

```stata
capture erase "jel_upgrade.dta"
```

Back to [the guides](../index.html#guides).
