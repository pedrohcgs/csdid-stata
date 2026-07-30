---
title: Getting started
---

# Getting started

## The estimand

<div class="note" markdown="1">
The building block is the **group-time average treatment effect** ATT(g,t): the
average effect, in period *t*, on the cohort first treated in period *g*.
</div>

A staggered design produces one of these for every cohort and every period,
which is more numbers than anyone reads directly. `csdid` estimates all of them
and leaves the aggregation to you. The cells themselves stay available for
inspection after estimation.

## The three choices

**The comparison group.** Not-yet-treated units are the default, and
`nevertreated` restricts the comparison to units that are never treated.
Not-yet-treated gives you more comparisons and does not require a never-treated
group to exist. The cost is an extra assumption: later-treated cohorts' untreated
paths have to be comparable over the periods they spend in the comparison group.
We would check that against the pre-treatment cells before leaning on it.

**The 2×2 estimator.** `method(dr)` (default) is doubly robust: consistent if
*either* the outcome model or the propensity score is right. `method(reg)` is
outcome regression, and `method(ipw)` is inverse probability weighting. We
recommend keeping the default unless you have a reason to trust one of the two
models over the other.

**The aggregation.** `estat event` (by time since treatment), `estat group` (by
cohort), `estat calendar` (by period), `estat simple` (one number).

## Your first estimate

Let's run one from the raw file to the event study, on county mortality data.

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
columns carry `"NA"`, hence the `destring ... , force`. The last two lines are
the whole estimation.

## Two rules about the axis

<div class="important" markdown="1">
`gvar()` is `0` for never-treated units and the first treated period otherwise;
`time()` is 1 or more. Cohorts and periods share one positive calendar-time
axis, and `0` is reserved for "never treated". A zero or negative cohort code
has no consistent reading. If your data start at or below zero, shift both by
the same amount. A monotone relabeling of the periods leaves every estimate
unchanged.
</div>

Next: [balanced panels](articles/balanced-panel.html).
