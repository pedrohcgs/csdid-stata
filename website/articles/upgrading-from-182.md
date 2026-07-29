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

Two omitted-option defaults changed. They are the only two changes that alter a
number you were already getting.

| | Version 1.82 | 2.0.0 | To keep the old behaviour |
| --- | --- | --- | --- |
| comparison group | never-treated | not-yet-treated | `nevertreated` |
| base period | varying | universal | `base_period(varying)` |

Both are also departures from R `did` 2.5.1, which shares Version 1.82's two
defaults. State either option explicitly and `csdid` and R agree to machine
precision.

A third change is about inference rather than the estimand: standard errors are
now the multiplier bootstrap with simultaneous confidence bands by default,
where Version 1.82 reported pointwise analytical standard errors. Point
estimates are unaffected. `analytical` restores the old standard errors.

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
display "control group: " e(control_group)
display "base period:   " e(base_period)
estat event
```

Those three options give you Version 1.82's estimand and Version 1.82's standard
errors. Drop them and you get the 2.0.0 defaults:

```stata
use "jel_upgrade.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
display "control group: " e(control_group)
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

`bal(pair)` reproduces Version 1.82's estimand exactly, so an unbalanced-panel
result from that version can be reproduced here by asking for it.

## Deprecated commands

These still ship and still run, so nothing breaks. Each prints a notice.

| Deprecated | Use instead |
| --- | --- |
| `csdid_rif` | `estat tidy, saving(results) replace` then `use results, clear` |
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

Every old spelling is accepted and each says what to use instead, so you find
out from running your do-file rather than from reading this page.

| Old | Current |
| --- | --- |
| `allowunbalanced`, `allow_unbalanced` | `bal(none)` |
| `balanceall` | `bal(full)` |
| `balancepair` | `bal(pair)` |
| `bal(all)` | `bal(full)` |
| `bal(unbal)`, `bal(unbalanced)` | `bal(none)` |
| `long`, `long2` | `base_period(universal)` |
| `baseperiod()` | `base_period()` |
| `id()` | `ivar()` |
| `vce(cluster var)` | `cluster(var)` |
| `method(dripw)` | `method(dr)` |
| `method(stdipw)` | `method(ipw)` |
| `fixweights(base)` | `fix_weights(base_period)` |
| `asinr` | no-op; use `notyet` |

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
Stata. And it is 5× to 28× faster on every workload measured, never slower.

```stata
capture erase "jel_upgrade.dta"
```

Next: [comparison groups](comparison-groups.html).
