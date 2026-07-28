---
title: Comparison groups
---

# Comparison groups: never-treated or not-yet-treated

Every ATT(g,t) compares cohort *g* against units that are untreated at time *t*.
Which units those are is your choice, and it is one of the few choices that can
change both what you estimate and whether you can estimate it at all.

- **Never-treated** (the default) uses only units never treated in the sample.
- **`notyet`** uses every unit not yet treated at *t*, which includes cohorts
  treated later.

## The data

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
save "jel_balanced.dta", replace
```

## Never-treated: the default

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
estat event
```

`e(control_group)` records what was used:

```stata
display "control group: " e(control_group)
```

## Not-yet-treated

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) notyet rseed(20250101)
estat event
display "control group: " e(control_group)
```

The two runs usually give similar answers when the never-treated group is large
and comparable, as it is here. They diverge when it is not.

## When you have no never-treated units

This is where the choice stops being cosmetic. Drop every never-treated county
and ask for the default:

```stata
use "jel_balanced.dta", clear
keep if gvar > 0
capture noisily csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
display "return code: " _rc
```

`csdid` refuses. There is no never-treated group to compare against, and it will
not quietly substitute one. `notyet` is the estimator for this design:

```stata
use "jel_balanced.dta", clear
keep if gvar > 0
csdid mrate, ivar(county_code) time(year) gvar(gvar) notyet rseed(20250101)
estat event
```

The last-treated cohort now serves as the comparison group for the earlier ones.
It gets no ATT of its own — there is nothing left to compare it against — so it
is absent from the results table while still contributing as a control.

## Which to use

Prefer **never-treated** when you have a large never-treated group you are
willing to defend as comparable. It uses one fixed comparison group, so the
identifying assumption is easy to state and to argue about.

Prefer **`notyet`** when the never-treated group is small, absent, or selected
in a way that makes it a poor comparison. It uses more data and often gives
tighter standard errors, at the cost of assuming parallel trends against
later-treated cohorts too — including over periods where those cohorts may
already be anticipating treatment. If anticipation is a concern, see
[Anticipation](anticipation.html).

A small never-treated group is refused rather than used: `csdid` stops when it
is smaller than `#covariates + 5`. That guard changes whether the command runs,
never an estimate.

```stata
capture erase "jel_balanced.dta"
```
