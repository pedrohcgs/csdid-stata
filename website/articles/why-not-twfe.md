---
title: Why not two-way fixed effects
---

# Why not two-way fixed effects

The reflex for staggered adoption is a two-way fixed effects regression, with unit
effects, period effects, and a treatment dummy. When treatment timing is staggered
and effects differ across cohorts or over time, the coefficient on that dummy is
not the average treatment effect on the treated; it is a weighted average of many
2×2 comparisons, and some of those weights are negative. Our aim on this page is
to show you what that weighting does to a real dataset, and what we suggest
reporting in its place.

<div class="note" markdown="1">
The reason is that TWFE uses **already-treated units as comparison units**. A cohort
treated in 2014 becomes a comparison group for one treated in 2016, so that if the
2014 cohort's effect is still growing, that growth is subtracted from the 2016
cohort's estimate.
</div>

## The data

Let's use the county mortality panel that runs through the rest of this site.
These are the replication data behind the review article listed at the end of the
page.

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

The regression returns a single coefficient. It is easy to report, and easy to
read as though it were the average effect of the policy on the counties that
adopted it (and, in a design with a single adoption date, that reading would be
right).

## The same data, without the negative weights

```stata
use "jel_twfe.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) cluster(stfips) analytical
estat simple
```

`estat simple` is the closest analogue to the TWFE coefficient (it also reports a
single overall effect), so it is the natural thing to compare with the regression
above. That is one command and one line of output.

<div class="important" markdown="1">
If the two are close, TWFE was not badly contaminated here, which is useful to
know, though it is a fact about this dataset (and this outcome) rather than a
general license. If they
differ, the difference is the contamination, and no amount of clustering or extra
fixed effects will remove it, because it comes from *which comparisons* the
estimator makes and not from how the standard errors are computed (clustering, in
particular, changes the standard error and leaves the point estimate alone).
</div>

## Where the single number came from

The point of ATT(g,t) is that the single number was hiding structure. You can
look at that structure directly, one cohort and one period at a time (and we would
look before reporting any average of it).

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

`estat event` shows how the effect evolves with time since treatment, period by
period. `estat group` shows whether the 2014, 2015 and 2016 expanders responded
differently. A TWFE coefficient averages all of that into one number, using
weights that you did not choose and cannot inspect. Note that if the event study
is flat and the cohorts agree, the average is a fair summary of what happened. If
they disagree (as they often do in practice), then reporting only the average is
reporting an artifact of the weighting, not a feature of the policy.

## What to report

<div class="tip" markdown="1">
We recommend reporting the disaggregated estimates alongside an aggregation you
can name: `estat event` for dynamics, `estat group` for cohort heterogeneity,
`estat calendar` for calendar-time effects, and `estat simple` for one overall
number. Each of these has explicit, non-negative weights (you can print them), and
each of them says which average it is taking. See [Aggregations](aggregations.html).
</div>

Nothing here says that fixed effects are wrong in general, and we are not asking
you to abandon them. With a single treatment date and homogeneous effects, TWFE
and Callaway–Sant'Anna coincide. The problem we have been describing is a specific
one (staggered timing together with effects that vary across cohorts or over
time), and outside those conditions it does not arise.

## Further reading

Full citations are on the [References](../references.html) page.

**Reviews**, for the wider literature: Baker, Callaway, Cunningham,
Goodman-Bacon and Sant'Anna (2026) in the *Journal of Economic
Literature*, whose replication data this site uses throughout, and Roth,
Sant'Anna, Bilinski and Poe (2023) in the *Journal of Econometrics*.

**On the estimator:** Callaway and Sant'Anna (2021).

**On what TWFE actually estimates under staggered timing:** Goodman-Bacon (2021)
decomposes the estimand into 2×2 comparisons and shows where the negative weights
come from; de Chaisemartin and D'Haultfœuille (2020) characterize those weights;
and Sun and Abraham (2021) show how event-study coefficients contaminate each
other across cohorts.

```stata
capture erase "jel_twfe.dta"
```
