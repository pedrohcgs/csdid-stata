---
title: Pre-testing
---

# Pre-testing parallel trends

Identification rests on parallel trends, which is an assumption about
*untreated* potential outcomes after treatment starts. It is not testable. What
is testable is its analogue *before* treatment: if the cohorts were already
diverging beforehand, the assumption is harder to believe.

`csdid` gives you two ways to look at that — the pre-treatment cells themselves,
and a joint test across all of them.

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

## The joint pre-test

Every run reports a Wald test of the hypothesis that all pre-treatment ATT(g,t)
are zero, and stores it:

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) analytical
display "W       = " e(wald_stat)
display "p-value = " e(wald_pvalue)
display "df      = " e(wald_df)
```

A small p-value says the pre-treatment cells are jointly distinguishable from
zero. A large one does not say parallel trends holds — it says this test did not
detect a violation, which with modest samples it often cannot.

## Reading the cells, not just the test

The joint test compresses everything into one number. The event study shows
where any problem is:

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
estat event
```

Negative event times are pre-treatment. Look for **pattern**, not stars: a
gentle drift toward zero as treatment approaches is more worrying than one
isolated period, because it suggests the groups were already converging.

`base_period(universal)` is the default, and under it the pre-treatment
estimates are cumulative and serially correlated — one bad early period pushes
every later point away from zero, which can look like a systematic trend when it
is a single deviation. With `base_period(varying)` each pre-treatment cell is a
separate one-period comparison, so a violation appears in the period where it
happens. **For pre-testing, ask for `varying` explicitly.** See
[Base periods](base-periods.html).

## Power, and what a clean pre-test does not buy you

The pre-test can fail to reject simply because the pre-treatment standard errors
are wide. Report them, so a reader can see whether a null result is informative
or merely imprecise:

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) analytical
estat event
```

Two designs with identical point estimates and very different standard errors
tell very different stories about the same "passed" pre-test.

## Conditional parallel trends

If parallel trends is only plausible after conditioning on covariates, condition
on them — the pre-test then applies to the conditional assumption you are
actually making:

```stata
use "jel_balanced.dta", clear
csdid mrate unemp_rate poverty_rate, ivar(county_code) time(year) gvar(gvar) ///
    method(dr) analytical
display "W       = " e(wald_stat)
display "p-value = " e(wald_pvalue)
estat event
```

See [Covariates and estimators](covariates-and-estimators.html) for what each
estimator assumes.

## If the pre-test fails

A rejection is information, not a dead end. Options worth considering, roughly
in order of how much they ask of the data:

- **Allow anticipation.** If the divergence sits immediately before treatment,
  it may be response rather than violation — see [Anticipation](anticipation.html).
- **Change the comparison group.** A never-treated group selected differently
  from the treated cohorts may be the problem; `notyet` uses a different one.
- **Condition on covariates** that plausibly drive the differential trend.
- **Report a sensitivity analysis** that asks how large a violation would have to
  be to overturn the conclusion, rather than asserting the assumption holds.

What is not defensible is searching over specifications until the pre-test
passes and reporting only that one.

```stata
capture erase "jel_balanced.dta"
```
