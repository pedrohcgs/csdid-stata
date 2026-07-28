---
title: Trimming and overlap
---

# Trimming and overlap

With covariates, `method(dr)` and `method(ipw)` weight comparison units by a
propensity score — the estimated probability of belonging to the treated cohort.
A unit with a score near 1 gets an enormous weight, and a handful of such units
can dominate the estimate and inflate its variance.

That is an **overlap** problem: the data contain treated units with no
comparable controls. `csdid` guards against it in two ways, both visible.

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
save "jel_overlap.dta", replace
```

## The overlap warning

Every `dr` and `ipw` cell is checked. If the fitted propensity scores get too
close to 1, `csdid` warns for that cohort–period cell and keeps going, so you
learn which comparison is fragile rather than silently averaging it in:

```stata
use "jel_overlap.dta", clear
csdid mrate unemp_rate poverty_rate, ivar(county_code) time(year) gvar(gvar) ///
    method(dr) analytical
estat event
```

No warning here means overlap held in every cell for these covariates. Add
enough covariates and it will not: the more you condition on, the easier it is
to predict cohort membership perfectly.

## Trimming

`pscoretrim()` caps how extreme a propensity score may get. The default is
`.995`:

```stata
use "jel_overlap.dta", clear
csdid mrate unemp_rate poverty_rate, ivar(county_code) time(year) gvar(gvar) ///
    method(dr) analytical
display "trim: " e(pscoretrim)
estat simple
```

Tighten it to see how sensitive the estimate is to the most extreme weights:

```stata
use "jel_overlap.dta", clear
csdid mrate unemp_rate poverty_rate, ivar(county_code) time(year) gvar(gvar) ///
    method(dr) pscoretrim(0.95) analytical
display "trim: " e(pscoretrim)
estat simple
```

Turn it off with `pscoretrim(1)`, which permits any score:

```stata
use "jel_overlap.dta", clear
csdid mrate unemp_rate poverty_rate, ivar(county_code) time(year) gvar(gvar) ///
    method(dr) pscoretrim(1) analytical
estat simple
```

A value of zero or below is refused — it would trim away every observation:

```stata
use "jel_overlap.dta", clear
capture noisily csdid mrate unemp_rate, ivar(county_code) time(year) gvar(gvar) ///
    method(dr) pscoretrim(0) analytical
display "return code: " _rc
```

## Reading the sensitivity

If the estimate moves a lot between `pscoretrim(1)` and a tighter bound, a small
number of extreme-weight units are driving the result. That is worth reporting,
not hiding: it tells the reader the estimate rests on units with few
counterparts.

Trimming changes the estimand slightly — it reweights toward the region of
common support. That is usually preferable to an estimate dominated by units
that have no real comparison, but it is a choice, so state the value you used.

## Avoiding the problem

Overlap is easier to keep than to repair.

- **Condition on fewer things.** Every covariate makes cohort membership easier
  to predict. Include what parallel trends plausibly needs, not everything
  available.
- **Prefer `method(reg)` when overlap is genuinely poor.** Outcome regression
  does not weight by a propensity score, so it does not blow up on extreme
  scores — at the cost of relying on the outcome model being right.
- **Use `notyet`.** A larger comparison pool makes extreme scores less likely.
  See [Comparison groups](comparison-groups.html).

`method(dr)`, the default, is doubly robust: it is consistent if *either* the
outcome model or the propensity model is correct. That is why it is the default,
and it is the reason overlap matters less here than for plain `ipw` — but
"doubly robust" is not "immune to no overlap". See
[Covariates and estimators](covariates-and-estimators.html).

```stata
capture erase "jel_overlap.dta"
```
