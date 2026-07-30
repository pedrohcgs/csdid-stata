---
title: Balanced panels
---

# Balanced panels

The standard case: every unit observed in every period. We use the county
mortality panel from the [JEL-DiD](https://github.com/pedrohcgs/JEL-DiD)
replication package — US counties, 2009–2019, with the year each state expanded
Medicaid under the ACA.

## Prepare

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
comparison group rather than being dropped.

## Estimate

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
```

Read the output in three parts:

- the **header** tells you the estimator, the comparison group, the base-period
  rule, and whether inference is bootstrap or analytical
- the **ATT(g,t) table** is one row per cohort-period cell
- the **pre-test** is a joint test that all pre-treatment cells are zero

<div class="tip" markdown="1">
Seed the bootstrap with `rseed()` if you want the run to be reproducible; an
unseeded run says so in the header.
</div>

## Read the pre-test carefully

<div class="important" markdown="1">
A large p-value is weak evidence, not a certificate. The test has low power in
exactly the samples where parallel trends is most fragile, and it looks only at
the periods in your sample. Read it alongside the pre-treatment cells
themselves, and — when the design turns on the assumption — a sensitivity
analysis.
</div>

Next: [covariates and estimators](covariates-and-estimators.html).
