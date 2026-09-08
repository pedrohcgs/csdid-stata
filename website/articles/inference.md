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
replace gvar = 0 if missing(gvar) | gvar > 2019
bysort county_code: generate byte nyears = _N
keep if nyears == 11
```

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
```

That run computes inference for the ATT(g,t) cells and the pre-test. The
examples below rerun the model to illustrate alternative inference settings;
postestimation aggregations reuse its influence functions and compute their
own standard errors and bands.

## Simultaneous versus pointwise

<div class="important" markdown="1">
A pointwise 95% interval targets coverage for one pre-specified cell. When
a cell's true effect is zero, a corresponding nominal 5% test can still
reject by chance. Scanning many cells increases the chance of at least one
false rejection; the increase depends on their dependence.
</div>

Simultaneous bands target coverage of the whole family at once. They are
usually wider because they account for looking across multiple cells.
Read the family of effects and the reported critical value together.

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) pointwise    // one at a time
```

`e(cband)` and `e(pointwise)` record which of the two was used. `e(crit_val)` is
the critical value actually applied (a saved run remembers both).

One row is always pointwise, whichever band you choose: an aggregation's overall
summary effect — `Post_avg` on an event study, `Overall` by cohort or period,
`ATT` for the simple average. A simultaneous band answers whether a set of
effects all lie inside their intervals at once, and a single summary number is
not a set, so it is reported at the normal quantile (`e(point_crit_val)`). One
`estat event` table can therefore show both kinds of interval, and it says so
underneath. Read the per-column `crit` row of `r(table)` after `estat event`
when reconstructing its intervals. `e(agg_cband)` describes the aggregation
effects; `e(cband)` describes the original ATT(g,t) band request.

## Analytical standard errors

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) analytical
```

<div class="tip" markdown="1">
These are faster, noticeably so on large panels. The standard errors are
analytical; an aggregation of an analytical fit still carries a simultaneous
band -- its critical value is bootstrapped, and `csdid_stats` says so in a
note -- unless you add `pointwise`. We use `analytical pointwise` while
iterating on a specification and the bootstrap for reported inference. The
point estimates stay the same; the standard errors and confidence bands can
change.
</div>

## Reproducibility

An unseeded bootstrap can change standard errors and confidence bands between
otherwise identical runs. The results header warns you. Seed it:

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) wboot(reps(1000) rseed(20250101))
```

`reps()` must exceed 20. Very small bootstrap samples can give unstable standard
errors and tail quantiles, so `csdid` refuses those requests. For reproducible
bootstrap results, specify `rseed()` and record the seed and number of draws
with published tables.

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

When pre-treatment cells exist, `csdid` reports a joint Wald test that the estimable pre-treatment
effects are zero. It is unavailable when those effects or their covariance
cannot support the test; the output explains why. The test is built from the analytical
influence-function covariance, so it does not depend on whether the bootstrap
ran.

For what a large p-value is and is not worth, see
[Pre-testing](pre-testing.html).
