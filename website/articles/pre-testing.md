---
title: Pre-testing
---

# Pre-testing parallel trends

<div class="note" markdown="1">
Identification rests on parallel trends. That is an assumption about *untreated*
potential outcomes after treatment starts, a counterfactual quantity, and it is
not testable.
What is testable is its analogue *before* treatment: if the cohorts were already
diverging beforehand, the assumption is harder to believe.
</div>

`csdid` gives you two ways to look at that: the pre-treatment cells themselves,
and a joint test across all of them. We use both, and we would not report one of
them without the other.

## The data

Let's build the balanced sample once (the same block used elsewhere on this site)
and reuse it for the runs below.

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
are zero. The test is stored, whether or not you asked for it:

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) analytical
display "W       = " e(wald_stat)
display "p-value = " e(wald_pvalue)
display "df      = " e(wald_df)
```

<div class="important" markdown="1">
A small p-value says the pre-treatment cells are jointly distinguishable from
zero. A large one does not say that parallel trends holds. It says that this test
did not detect a violation, which with modest samples it often cannot do.
</div>

## Reading the cells

The joint test compresses everything into one number, and the event study is what
shows you where a problem actually sits (if there is one):

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
estat event
```

Negative event times are pre-treatment (that is the convention here). Look for
*pattern* rather than for stars. A gentle drift toward zero as treatment
approaches is more worrying than one isolated period: a drift suggests that the
two groups were already converging before anything happened to either of them.

<div class="tip" markdown="1">
`base_period(universal)` is the default. Under it the pre-treatment estimates
are cumulative and serially correlated, so one bad early period pushes every
later point away from zero and can look like a systematic trend. With
`base_period(varying)` each pre-treatment cell is a separate one-period
comparison, so a violation appears in the period where it happens. Thus we ask
for `varying` explicitly when pre-testing, and we recommend that you do too.
See [Base periods](base-periods.html).
</div>

## Power, and what a clean pre-test does not buy you

The pre-test can fail to reject simply because the pre-treatment standard errors
are wide. That is low power, and in the output it looks just like clean trends.
Report the standard errors, so that a reader can see whether a null result is
informative or merely imprecise:

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) analytical
estat event
```

Two designs with identical point estimates and very different standard errors tell
very different stories about the same "passed" pre-test. Only the one with the
tight standard errors is really evidence about the design.

## Conditional parallel trends

If parallel trends is only plausible after conditioning on covariates, then
condition on them, and say so in the text. The pre-test then applies to the
conditional assumption you are actually making:

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

A rejection tells you something, and it does not end the analysis. The options
worth considering, roughly in order of how much they ask of the data, are these:

- **Allow anticipation.** If the divergence sits immediately before treatment,
  it may be a response to the announcement and not a violation of parallel
  trends (see [Anticipation](anticipation.html)).
- **Change the comparison group.** A never-treated group selected differently
  from the treated cohorts may be the problem, and `notyet` uses a different one.
- **Condition on covariates** that plausibly drive the differential trend (and
  that are not themselves affected by the treatment).
- **Report a sensitivity analysis** that asks how large a violation would have to
  be to overturn the conclusion. This is what we would do whenever the design
  sits close to the line and the pre-treatment cells are noisy.

What is not defensible is searching over specifications until the pre-test passes
and then reporting only that one. We view the pre-test as one piece of evidence
on the credibility of a DiD design in a particular application. A piece of
evidence that has been selected on no longer carries the information you are
asking your readers to take from it.

```stata
capture erase "jel_balanced.dta"
```
