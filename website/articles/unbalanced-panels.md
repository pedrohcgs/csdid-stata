---
title: Unbalanced panels
---

# Unbalanced panels

A panel is unbalanced when some units are not observed in every period (through
attrition, late entry, or simply missing records). You have three choices about
what to do. `csdid` reports the one it took:

| | |
| --- | --- |
| `bal(full)` | drop units not observed in every period, once, for all comparisons. **The default**, matching R `did`. |
| `bal(none)` | keep every unit and use the repeated-cross-section computation, with the standard-error accounting that goes with it. |
| `bal(pair)` | balance each 2×2 separately, keeping the units observed in both of its periods. This is what Version 1.82 did silently. |

<div class="important" markdown="1">
Dropping units changes the estimand, so `bal(full)` reports how many units and
how many observations it removed (both counts, printed above the table). The
report is there so that nobody has to take the change on trust.
</div>

## The data

The county mortality panel from the
[JEL-DiD](https://github.com/pedrohcgs/JEL-DiD) replication package is the
starting point here.

```stata
import delimited using ///
    "https://raw.githubusercontent.com/pedrohcgs/JEL-DiD/50f4f18/data/county_mortality_data.csv", ///
    clear varnames(1) bindquote(strict) stringcols(_all)
destring deaths population_20_64 year yaca county_code stfips unemp_rate poverty_rate, ///
    replace force
generate double mrate = 100000 * deaths / population_20_64
drop if missing(mrate) | population_20_64 <= 0
generate int gvar = yaca
replace gvar = 0 if missing(gvar) | gvar > 2016
bysort county_code: generate byte nyears = _N
keep if nyears == 11
save "jel_unbal_base.dta", replace
```

As downloaded the JEL panel is only nearly balanced, and the `keep if nyears == 11`
step above makes it exactly balanced. That leaves nothing to demonstrate on. The
block below creates some unbalancedness deliberately and reproducibly:

```stata
use "jel_unbal_base.dta", clear
set seed 424242
generate double u = runiform()
drop if u < 0.15 & year >= 2012      // delete ~15% of later county-years
save "jel_unbalanced.dta", replace
```

## The default: drop the incomplete units, and say so

```stata
use "jel_unbalanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
display "panel mode: " e(panel_mode)
display "units: "      e(N_units)
estat event
```

Read the message above the table. It names how many counties were not observed
in all eleven years and how many observations went with them, so you never have
to reconstruct that count from the data yourself. `e(panel_mode)` reports
`panel`. After the drop the panel is balanced, which is the point of the mode.

## Keeping every unit

```stata
use "jel_unbalanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) bal(none) rseed(20250101)
display "panel mode: " e(panel_mode)
display "units: "      e(N_units)
estat event
```

`e(panel_mode)` now reports `allow_unbalanced`, and `e(N_units)` is larger,
because no county was removed. `e(N_units)` is the cross-sectional unit count.
That is what the influence function and the standard errors are scaled by.
`e(N)` remains the observation count, as it does everywhere in Stata.

`unbalanced` is a supported synonym of `bal(none)`, for when that reads better
than a mode inside `bal()`. `allowunbalanced` and `allow_unbalanced` are the
longhand form of the same thing -- that is the name the setting carries in the
reference implementation, the R package -- so code written with that vocabulary
runs here unchanged. None of these spellings prints a warning or is deprecated.

All three are typed in full (no abbreviation). `unbal` is deliberately not an
option, because it reads as `bal(unbal)`, which `bal()` does not accept either.
Combining any of the three with a `bal()` that means something else is an error.
The run stops and tells you.

## Which to use

<div class="note" markdown="1">
These are *different samples answering different questions*. The choice is a
substantive one, and it belongs in the text.
</div>

`bal(full)` keeps one fixed set of units behind every reported cell, which makes
the estimand easy to state: the effect on units observed throughout. However,
that is also its cost. If attrition is related to treatment, the units it drops
are exactly the ones you would want to know about, and the report telling you
how many went is your signal to think about that.

`bal(none)` uses everything you gave it. On a balanced panel each 2×2 cell is formed by
differencing a unit over two periods; when units come and go that is not
available for everyone, so the estimator pools observations from both periods
instead (this is the repeated-cross-section computation). Two consequences are
worth knowing:

- it is *slower* than `bal(full)` by roughly 4–6× at these sizes (and roughly
  2× slower than `bal(pair)`), because each cell fits more regressions on
  more rows
- the guard on small cohorts is *stricter*, because cohort size is measured as
  observations divided by periods, which on an unbalanced panel is smaller than
  the distinct-unit count

<div class="tip" markdown="1">
If a run refuses with "the never-treated group is too small", `notyet` enlarges
the comparison group and is usually the fix. It is also the default, so you'll
only meet that refusal if you asked for `nevertreated`. See
[comparison groups](comparison-groups.html).
</div>

## `bal(pair)`

Stata `csdid` Version 1.82 balanced each 2×2 comparison separately, keeping the
units observed in both of that comparison's periods, and it said nothing about
doing so. `bal(pair)` does the same thing explicitly and on request. Every unit
stays in the sample; what varies is which units each individual comparison can
use. Thus `e(N_units)` matches `bal(none)` while the estimates do not.

```stata
use "jel_unbalanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) bal(pair) rseed(20250101)
display "panel mode: " e(panel_mode)
display "units: "      e(N_units)
estat event
```

`e(panel_mode)` reports `pair-balanced`. The mode is neither `panel` nor
`allow_unbalanced`, and the string says so. We would use it to reproduce a
result computed with Version 1.82, and we would not choose it for new work.

Next: [repeated cross sections](repeated-cross-sections.html).
