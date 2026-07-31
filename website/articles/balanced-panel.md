---
title: Balanced panels
---

# Balanced panels

The standard case is a panel in which every unit is observed in every period, and
it is the case we use for most of the examples on this site. The data are the
county mortality panel from the [JEL-DiD](https://github.com/pedrohcgs/JEL-DiD)
replication package (US counties, 2009–2019, together with the year each state
expanded Medicaid under the ACA). It is a convenient example because the adoption
dates are staggered across a handful of cohorts. The never-adopted comparison
group is also large, so the individual cohort-period cells are reasonably well
estimated. That is not guaranteed in smaller panels, and it matters once you get
to the aggregations and to the bootstrap.

## Prepare

Let's build the estimation sample first. These are the same steps used on every
page of this guide.

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

That leaves **29,667 observations on 2,697 counties**, with cohorts expanding in
2014, 2015 and 2016 against a large never-adopted comparison group. States
expanding after 2016 are never treated *within this sample*, so they join the
comparison group rather than being dropped. That is a decision about the sample
and not about the estimator. If you would rather those states played no role at
all, drop them before estimating.

## Estimate

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
```

The whole estimation is one command line, and everything else on this page is
about reading its output.

Read the output in three parts:

- the **header** tells you the estimator, the comparison group, the base-period
  rule, and whether inference is bootstrap or analytical
- the **ATT(g,t) table** is one row per cohort-period cell
- the **pre-test** is a joint test that all pre-treatment cells are zero

The table of cohort-period cells is the object that everything else on this site
is built from. The aggregations you eventually report (by length of exposure, by
cohort, by calendar period, or as one overall number) are weighted averages of
its rows. Look at that table once in raw form before you aggregate anything. It
is the quickest way to see how many cells there are and how precisely each of
them is estimated.

<div class="tip" markdown="1">
Seed the bootstrap with `rseed()` if you want the run to be reproducible; an
unseeded run says so in the header (so you will not be misled by accident).
</div>

## Read the pre-test carefully

The joint pre-test printed in the header is easy to over-read. Indeed, our
impression is that it is the part of the output most often quoted out of context,
usually as evidence *in favor of* parallel trends.

<div class="important" markdown="1">
A large p-value is weak evidence, and it is not a certificate. The test has low
power in exactly the samples where parallel trends is most fragile, and it looks
only at the periods that happen to be in your sample, so it does not speak to the
post-treatment counterfactual (which is the thing you actually care about). We
recommend reading it alongside the pre-treatment cells themselves and, when the
design turns on the assumption, alongside a sensitivity analysis.
</div>

None of this makes the pre-test useless. We would worry about a design that
ignored it entirely, and we are uncomfortable reporting a design in which it
rejects sharply. What it gives you, in a particular application and on a
particular sample, is one piece of evidence on the credibility of the design.
It verifies nothing about the assumption behind it.

Next: [covariates and estimators](covariates-and-estimators.html).
