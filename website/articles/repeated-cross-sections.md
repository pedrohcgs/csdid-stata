---
title: Repeated cross sections
---

# Repeated cross sections

<div class="note" markdown="1">
When each observation is an independent draw, and not a unit followed over
time (repeated survey waves, pooled cross sections), say so with `rcs`, as in
`csdid y, time(year) gvar(gvar) rcs`.
</div>

Omitting `ivar()` does the same thing, and for data with no identifier that is
the natural way to write it (there is nothing to declare). We provide `rcs` for the common case where the data do carry an identifier of some
kind (a survey respondent number, a county code). You should not have to withhold
a real variable in order to describe your data correctly.

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

## A worked example

The JEL data are a panel. The block below constructs a repeated cross section
from it by keeping one randomly chosen year per county, after which every row
belongs to a different unit. Nobody would collect data this way; it is simply the
shape we need for the illustration:

```stata
set seed 20240617
generate double pick = runiform()
bysort county_code (pick): keep if _n == 1

csdid mrate, time(year) gvar(gvar) rseed(20250101)
estat event
```

We built this for illustration and would not recommend it as a design, since
throwing away 10 of every 11 observations (most of the sample) costs a great
deal of precision. We include it because the shape of the data is what matters
here, and because a genuine repeated-cross-section dataset with staggered
treatment is not part of the JEL package.

## When the data carry an identifier anyway

`county_code` still exists in the extract above, and it is a perfectly real
variable (it is still a county code) that no longer identifies a unit followed
over time. Declaring the
structure explicitly, and keeping the identifier, gives exactly the same
estimates.

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) rcs rseed(20250101)
estat event
```

`csdid` says in the header that it is not using `ivar()` as a panel identifier
(it does not fail silently),
and `e(idvar)` comes back empty while `e(panel_mode)` reads
`repeated-cross-section`. This mirrors the R `did` implementation. That
implementation validates the identifier and then replaces it with a row number
(the same convention, arrived at for the same reason).

The identifier is not wasted here. It is exactly what you pass to `cluster()`
if observations sharing it are correlated:

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) rcs ///
    cluster(stfips) rseed(20250101)
display "clusters: " e(N_clusters)
```

Because there is nothing to balance in a cross section (each row appears once),
`rcs` implies `bal(none)`. Asking for `bal(full)` alongside it is an error, not
a silent override, as is `fix_weights(base)`, which needs the same unit to
appear in more than one period. See [unbalanced panels](unbalanced-panels.html).

## What to watch

<div class="important" markdown="1">
**Cohort labels.** `gvar()` must still be well defined for every observation. In
a panel, cohort is a property of the unit (one label per unit). In repeated cross sections each row
carries its own cohort label, and that label has to be the cohort the row's unit
belongs to, which is usually a group-level variable such as the state's expansion
year.
</div>

**Unit counts.** Every row is its own cross-sectional unit. `e(N_units)` equals
the number of observations (not the number of counties), and the standard errors
are scaled accordingly.
There is no within-unit differencing to remove fixed unobserved heterogeneity, so
the identifying assumption is doing more work here than it does in a panel. Be
careful about the covariates you condition on and about the comparison group you
choose.

**Covariates.** They matter more in this setting, not less. Without differencing,
the composition changes between waves are absorbed only by the covariate model,
and we would think hard about which covariates go into it.

Next: [inference](inference.html).
