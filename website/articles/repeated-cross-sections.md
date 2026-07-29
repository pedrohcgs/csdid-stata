---
title: Repeated cross sections
---

# Repeated cross sections

When each observation is an independent draw rather than a unit followed over
time — repeated survey waves, pooled cross sections — say so with `rcs`, as in
`csdid y, time(year) gvar(gvar) rcs`.

Omitting `ivar()` does the same thing, and for data with no identifier that is
the natural way to write it. `rcs` exists for the common case where the data do
carry an identifier — a survey respondent number, a county code — and you should
not have to withhold a real variable to describe your data correctly.

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
csdid mrate, time(year) gvar(gvar) rseed(20250101)
```

## A worked example

The JEL data are a panel, so this constructs a repeated cross section from it by
keeping one randomly chosen year per county. Every row then belongs to a
different unit:

```stata
set seed 20240617
generate double pick = runiform()
bysort county_code (pick): keep if _n == 1

csdid mrate, time(year) gvar(gvar) rseed(20250101)
estat event
```

This is a construction for illustration, not a design you would choose: throwing
away 10 of every 11 observations costs precision. It is here because the shape
is what matters, and a genuine repeated-cross-section dataset with staggered
treatment is not part of the JEL package.

## When the data carry an identifier anyway

`county_code` still exists in the extract above, and it is a perfectly real
variable — it just no longer identifies a unit followed over time. Declaring the
structure explicitly, and keeping the identifier, gives the same estimates:

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) rcs rseed(20250101)
estat event
```

`csdid` says plainly that it is not using `ivar()` as a panel identifier, and
`e(idvar)` comes back empty while `e(panel_mode)` reads
`repeated-cross-section`. This mirrors the reference implementation, which
validates the identifier and then replaces it with a row number.

The identifier is not wasted. It is exactly what you pass to `cluster()` if
observations sharing it are correlated:

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) rcs ///
    cluster(stfips) rseed(20250101)
display "clusters: " e(N_clusters)
```

Because there is nothing to balance in a cross section, `rcs` implies
`bal(none)`; asking for `bal(full)` alongside it is an error
rather than a silent override, as is `fix_weights(base)`, which needs the same
unit in more than one period. See [unbalanced panels](unbalanced-panels.html).

## What to watch

**`gvar()` must still be well defined for every observation.** In a panel,
cohort is a property of the unit. In repeated cross sections each row carries
its own cohort label, and it has to be the cohort that row's unit belongs to —
usually a group-level variable such as the state's expansion year, not something
measured on the individual.

**Every row is its own cross-sectional unit.** `e(N_units)` equals the number of
observations, and standard errors are scaled accordingly. There is no
within-unit differencing to remove fixed unobserved heterogeneity, so the
identifying assumption does more work than in a panel.

**Covariates are more important, not less.** Without differencing, composition
changes between waves are absorbed only by the covariate model.

Next: [inference](inference.html).
