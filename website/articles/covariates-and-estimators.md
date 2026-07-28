---
title: Covariates and estimators
---

# Covariates and estimators

List covariates after the outcome. Where they enter depends on `method()`.

## The data

Every guide on this site is self-contained: run this first and the rest of the
page follows. It is the county mortality panel from the
[JEL-DiD](https://github.com/pedrohcgs/JEL-DiD) replication package.

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

## Which estimator

| | uses covariates in | consistent if |
| --- | --- | --- |
| `method(dr)` *(default)* | outcome regression **and** propensity score | **either** model is correct |
| `method(reg)` | outcome regression | the outcome model is correct |
| `method(ipw)` | propensity score | the propensity model is correct |

`dr` is the default because it gives you two chances to be right, and is
locally efficient when both models are. Prefer it unless you have a specific
reason not to.

## Conditional parallel trends

With no covariates, the identifying assumption is unconditional parallel
trends. With covariates it is weaker in one direction and stronger in another:
it permits trends to differ across observably different units, but it requires
your covariate model to capture how. Adding covariates is not free.

## Overlap

Doubly robust and IPW estimators need comparison units at every covariate value
the treated units take. When the estimated propensity approaches 1, weights
explode. `csdid` guards this two ways: it refuses a cell whose fitted
propensity reaches 0.999, and it trims comparison observations at
`pscoretrim()`, default `.995`.

```stata
csdid mrate unemp_rate, ivar(county_code) time(year) gvar(gvar) pscoretrim(.99)
csdid mrate unemp_rate, ivar(county_code) time(year) gvar(gvar) pscoretrim(1)   // no trimming
```

If trimming binds often, that is information: the overlap assumption is in
doubt, and no estimator repairs it.

Next: [aggregations](aggregations.html).
