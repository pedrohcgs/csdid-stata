---
title: Inference
---

# Inference

<div class="note" markdown="1">
`csdid` bootstraps by default: 1,000 multiplier-bootstrap iterations with
Rademacher multipliers, reported with *simultaneous* confidence bands (both the
number of iterations and the type of band can be changed).
</div>

## The data

The runs below use the county mortality panel from the
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

That single run carries the whole inference apparatus with it (the bootstrap
draws, the critical value, the pre-test). Nothing else on this page needs a fresh
estimation of the model.

## Simultaneous versus pointwise

<div class="important" markdown="1">
This matters more than it looks. A pointwise 95% interval is correct for *one*
cell considered alone. Read a table or a plot of fifteen cells, ask whether
anything in it is significant, and pointwise intervals will mislead you.
Roughly one in twenty cells will exclude zero by chance.
</div>

Simultaneous bands cover the whole family at once, so you can scan the table
without doing any adjustment in your head. However, they are wider. That extra
width is what it costs to look at the whole table when you did not pick one cell
in advance.

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) pointwise    // one at a time
```

`e(cband)` and `e(pointwise)` record which of the two was used. `e(crit_val)` is
the critical value actually applied (a saved run remembers both).

## Analytical standard errors

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) analytical
```

<div class="tip" markdown="1">
These are faster, noticeably so on large panels, and pointwise only. We use them
while iterating on a specification -- the estimates do not change, only the
standard errors -- and we report the bootstrap.
</div>

## Reproducibility

An unseeded bootstrap moves by a few percent between otherwise identical runs.
The results header warns you. Seed it:

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) wboot(reps(1000) rseed(20250101))
```

`reps()` must exceed 20. A handful of draws cannot support a standard error, and
the empirical quantile behind a simultaneous critical value cannot be resolved at
all, so `csdid` refuses the request. We seed every run on this site for that
reason, and we would seed the runs behind a published table as well.

## Clustering

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) cluster(stfips)
```

The influence function is clustered on `stfips`. That variable must be numeric and
nested within units (a county sits inside exactly one state). Treatment here is
assigned by *state*, so clustering at the state level is the defensible choice
even though the unit of observation is a county. The clustering applies to
analytical and bootstrap inference alike. Note that clustering is a statement
about which observations share shocks. The design settles it. We would not pick a
cluster variable by looking at the standard errors it produced.

## The parallel-trends pre-test

When pre-treatment cells exist, `csdid` reports a joint Wald test that all of
them are zero, automatically, on every run. The test is built from the analytical
influence-function covariance, so it does not depend on whether the bootstrap
ran.

For what a large p-value is and is not worth, see
[Pre-testing](pre-testing.html).
