---
title: Why not two-way fixed effects
---

# Why not two-way fixed effects

The reflex for staggered adoption is a two-way fixed effects regression: unit
effects, period effects, and a treatment dummy. With staggered timing and
effects that differ across cohorts or over time, its coefficient is not the
average treatment effect on the treated. It is a weighted average of many
2×2 comparisons, and some of those weights are negative.

<div class="note" markdown="1">
The reason is that TWFE uses **already-treated units as comparison units**. A cohort
treated in 2014 becomes a comparison group for one treated in 2016, so if the
2014 cohort's effect is still growing, that growth is subtracted from the 2016
cohort's estimate.
</div>

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
save "jel_twfe.dta", replace
```

## The TWFE regression

```stata
use "jel_twfe.dta", clear
xtset county_code year
generate byte treated = (gvar > 0 & year >= gvar)
xtreg mrate treated i.year, fe vce(cluster stfips)
```

One number, and it looks like an answer.

## The same data, without the negative weights

```stata
use "jel_twfe.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) cluster(stfips) analytical
estat simple
```

`estat simple` is the closest analogue to the TWFE coefficient: a single overall
effect. Compare it with the regression above.

<div class="important" markdown="1">
If the two are close, TWFE was not badly contaminated here — which is worth
knowing, but it is a fact about this dataset, not a general licence. If they
differ, the difference is the contamination, and no amount of clustering or
extra fixed effects removes it: it comes from *which comparisons* the estimator
makes, not from how the standard errors are computed.
</div>

## Where the single number came from

The point of ATT(g,t) is that the one number was hiding structure. Look at it:

```stata
use "jel_twfe.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) cluster(stfips) rseed(20250101)
estat event
```

```stata
use "jel_twfe.dta", clear
quietly csdid mrate, ivar(county_code) time(year) gvar(gvar) cluster(stfips) rseed(20250101)
estat group
```

`estat event` shows how the effect evolves with time since treatment;
`estat group` shows whether the 2014, 2015 and 2016 expanders responded
differently. A TWFE coefficient averages all of that — with weights you did not
choose and cannot see — into one number. If the event study is flat and the
cohorts agree, the average is a fair summary. If they do not, reporting only the
average is reporting an artefact of the weighting.

## What to report

<div class="tip" markdown="1">
Report the disaggregated estimates and an aggregation you can name. `estat
event` for dynamics, `estat group` for cohort heterogeneity, `estat calendar`
for calendar-time effects, `estat simple` for one overall number. Each has
explicit, non-negative weights, and each says which average it is taking. See
[Aggregations](aggregations.html).
</div>

Nothing here says fixed effects are wrong in general. With a single treatment
date and homogeneous effects, TWFE and Callaway–Sant'Anna coincide. The problem
is specific: staggered timing plus heterogeneous effects.

## Further reading

Full citations are on the [References](../references.html) page.

**Reviews**, for the landscape rather than one estimator: Baker, Callaway,
Cunningham, Goodman-Bacon and Sant'Anna (2026) in the *Journal of Economic
Literature*, whose replication data this site uses throughout; and Roth,
Sant'Anna, Bilinski and Poe (2023) in the *Journal of Econometrics*.

**On the estimator:** Callaway and Sant'Anna (2021).

**On what TWFE actually estimates under staggered timing:** Goodman-Bacon (2021)
decomposes the estimand into 2×2 comparisons and shows where negative weights
come from; de Chaisemartin and D'Haultfœuille (2020) characterise those weights;
Sun and Abraham (2021) show how event-study coefficients contaminate each other
across cohorts.

```stata
capture erase "jel_twfe.dta"
```
