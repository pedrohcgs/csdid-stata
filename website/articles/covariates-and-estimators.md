---
title: Covariates and estimators
---

# Covariates and estimators

You list covariates after the outcome (the same place you would list them in a
regression). Where they enter the estimator depends on `method()`. We say a
little below about which method to choose, and rather more about what
conditioning on covariates costs you.

## The data

The county mortality panel from the
[JEL-DiD](https://github.com/pedrohcgs/JEL-DiD) replication package (US counties
over eleven years) is what the runs below use.

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
```

```stata
csdid mrate unemp_rate poverty_rate, ivar(county_code) time(year) gvar(gvar) ///
    rseed(20250101)
```

The two covariates (a county unemployment rate and a poverty rate) enter each
cohort-period comparison separately rather than once for the sample as a whole.
That is what allows a covariate to matter a great deal for one cohort and hardly
at all for another. It is also why adding covariates costs more computing time
than you might expect from the length of the command line.

## Which estimator

| | uses covariates in | consistent if |
| --- | --- | --- |
| `method(dr)` *(default)* | outcome regression **and** propensity score | **either** model is correct |
| `method(reg)` | outcome regression | the outcome model is correct |
| `method(ipw)` | propensity score | the propensity model is correct |

The three rows differ only in where the covariates are used. The last column is
what matters in practice. Two of the three estimators are consistent only when
the single model they rely on is correctly specified. The doubly robust
estimator is consistent when either of its two models is correct, and you do not
have to know in advance which one it will be.

<div class="tip" markdown="1">
`dr` is the default because it gives you two chances to be right, and because it
is locally efficient when both models are correct. We keep the default unless
there is a specific reason not to, and we would want that reason written down in
the paper. It should be a reason about the design, not about the estimates it
produced.
</div>

## Conditional parallel trends

<div class="important" markdown="1">
With no covariates, the identifying assumption is unconditional parallel trends
(across all units, treated and comparison alike).
With covariates it becomes weaker in one direction and stronger in another, in
that it permits trends to differ across observably different units but requires
your covariate model to capture how they differ (a linear index in the covariates
you happened to collect is a real restriction, not a formality). Adding covariates
is not free. A badly specified covariate model can do more damage to the estimates
than leaving those covariates out of the specification would have done.
</div>

## Overlap

<div class="note" markdown="1">
Doubly robust and IPW estimators need comparison units at every covariate value
the treated units take. When the estimated propensity score approaches 1, the
weights explode (a handful of observations end up carrying the whole cell). `csdid` guards against this in two ways: it refuses a cell whose
fitted propensity reaches 0.999, and it trims comparison observations at
`pscoretrim()`, whose default is `.995`.
</div>

```stata
csdid mrate unemp_rate, ivar(county_code) time(year) gvar(gvar) pscoretrim(.99)
csdid mrate unemp_rate, ivar(county_code) time(year) gvar(gvar) pscoretrim(1)   // no trimming
```

The first line tightens the threshold and the second turns trimming off altogether
(as its comment says). Running both is a cheap diagnostic. If the estimates
move a lot between the two runs, then a small number of comparison observations
carrying extreme weights were doing much of the work. That is worth knowing
before you report either number.

If trimming binds often, that is itself information. It says the overlap
assumption is in doubt in this sample. No estimator repairs a design in which the
treated and comparison units simply do not look alike. Trimming hides that
problem; it does not solve it. Thus we treat trimming as a diagnostic first and a
remedy second, and we would read a binding threshold as a question about the
design (which covariates, which comparison group) rather than as a setting to be
tuned until the estimates behave.

Next: [aggregations](aggregations.html).
