---
title: Inference
---

# Inference

<div class="note" markdown="1">
`csdid` bootstraps by default: 1,000 multiplier-bootstrap iterations with
Rademacher multipliers, reported with **simultaneous** confidence bands.
</div>

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
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
```

## Simultaneous versus pointwise

<div class="important" markdown="1">
This matters more than it looks. A pointwise 95% interval is correct for **one**
cell considered alone. Read a table or a plot of fifteen cells and ask "is
anything significant?", and pointwise intervals will mislead you — roughly one
in twenty will exclude zero by chance.
</div>

Simultaneous bands cover the whole family at once, so you can scan the table.
They are wider, and that width is the honest price of looking at everything.

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) pointwise    // one at a time
```

`e(cband)` and `e(pointwise)` record which was used; `e(crit_val)` is the
critical value actually applied.

## Analytical standard errors

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) analytical
```

<div class="tip" markdown="1">
Faster, and pointwise only. Useful while iterating; report the bootstrap.
</div>

## Reproducibility

An unseeded bootstrap moves by a few percent between otherwise identical runs,
and the results header says so. Seed it:

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) wboot(reps(1000) rseed(20250101))
```

`reps()` must exceed 20. A handful of draws cannot support a standard error, and
the empirical quantile behind a simultaneous critical value cannot be resolved
at all — so `csdid` refuses rather than returning a number that looks like a
standard error and is not.

## Clustering

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) cluster(stfips)
```

The influence function is clustered on `stfips`, which must be numeric and
nested within units. Treatment here is assigned by *state*, so clustering at the
state level is the defensible choice even though the unit is a county.
Clustering applies to analytical and bootstrap inference alike.

## The parallel-trends pre-test

When pre-treatment cells exist, `csdid` reports a joint Wald test that all of
them are zero, built from the analytical influence-function covariance — so it
does not depend on whether the bootstrap ran.

Treat a large p-value as weak evidence rather than a certificate: the test has
low power in exactly the samples where parallel trends is most fragile, and it
sees only the periods in your sample. It cannot speak to the post-treatment
counterfactual at all, which is the assumption you actually need.
