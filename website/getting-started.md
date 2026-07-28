---
title: Getting started
---

# Getting started

## The estimand

The building block is the **group-time average treatment effect** ATT(g,t): the
average effect, in period *t*, on the cohort first treated in period *g*.

A staggered design produces one of these for every cohort and every period. That
is more numbers than anyone reads directly, which is the point: `csdid`
estimates them all, and then you aggregate them into the summary that answers
your question. What it never does is average them for you with weights you did
not choose.

## The three choices

**The comparison group.** Never-treated units (the default), or not-yet-treated
units with `notyet`. Not-yet-treated gives you more comparisons when few units
are never treated, at the cost of assuming those units' untreated paths are
comparable.

**The 2×2 estimator.** `method(dr)` (default) is doubly robust: consistent if
*either* the outcome model or the propensity score is right. `method(reg)` is
outcome regression, `method(ipw)` is inverse probability weighting.

**The aggregation.** `estat event` (by time since treatment), `estat group` (by
cohort), `estat calendar` (by period), `estat simple` (one number).

## Your first estimate

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

csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
estat event
```

`bindquote(strict)` is not optional here: the file has quoted fields containing
newlines, and without it Stata splits them into extra observations. Several
columns carry `"NA"`, hence the `destring ... , force`.

## Two rules about the axis

`gvar()` is `0` for never-treated units and the first treated period otherwise;
`time()` is 1 or more. Cohorts and periods share one positive calendar-time
axis, and `0` is reserved for "never treated", so a zero or negative cohort code
has no consistent reading. If your data start at or below zero, shift both by
the same amount — a monotone relabelling of the periods leaves every estimate
unchanged.

Next: [balanced panels](articles/balanced-panel.html).
