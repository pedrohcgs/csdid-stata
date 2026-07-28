---
title: Working with results
---

# Working with results

Everything `csdid` computes is available programmatically: as tidy data for
tables, as matrices for your own calculations, and as plot-ready data so the
graph stays yours.

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
save "jel_results.dta", replace
```

## A run to work with

```stata
use "jel_results.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) cluster(stfips) rseed(20250101)
```

## Tidy output

`estat tidy` writes one row per estimate with the columns a table or a plot
needs — estimate, standard error, test statistic, p-value, confidence bounds.
`saving()` is required: these commands hand you a dataset rather than printing,
which is what makes them scriptable.

```stata
estat tidy, saving("attgt_table.dta") replace
preserve
use "attgt_table.dta", clear
describe
list in 1/5
restore
capture erase "attgt_table.dta"
```

`estat glance` is the one-line summary of the fit, and also takes `saving()`:

```stata
estat glance, saving("glance.dta") replace
preserve
use "glance.dta", clear
list
restore
capture erase "glance.dta"
```

## Stored results

The full set is in `e()`:

```stata
use "jel_results.dta", clear
quietly csdid mrate, ivar(county_code) time(year) gvar(gvar) cluster(stfips) analytical
display "cells        : " e(N_attgt)
display "units        : " e(N_units)
display "cohorts      : " e(N_groups)
display "periods      : " e(N_time)
display "method       : " e(method)
display "control group: " e(control_group)
display "base period  : " e(base_period)
display "panel mode   : " e(panel_mode)
display "clusters     : " e(N_clusters)
display "pre-test W   : " e(wald_stat) "  p = " e(wald_pvalue)
```

`e(attgt)` is the estimate matrix — cohort, period, and then the estimate and
its standard error:

```stata
matrix A = e(attgt)
matrix list A
```

## Influence functions

`e(inffunc)` holds the influence function, one column per ATT(g,t) cell and one
row per unit. It is what standard errors, uniform bands and clustered inference
are built from, and it is exported so you can do your own:

```stata
use "jel_results.dta", clear
quietly csdid mrate, ivar(county_code) time(year) gvar(gvar) analytical
matrix IF = e(inffunc)
display "influence function: " rowsof(IF) " units x " colsof(IF) " cells"
mata: printf("columns are mean-zero to %g\n", max(abs(mean(st_matrix("IF")))))
```

Each column is mean-zero by construction. With it you can compute standard
errors for aggregations `csdid` does not provide, or feed a sensitivity
analysis.

## Plot-ready data

`csdid_plot` exports what a graph needs rather than drawing one, so styling
stays under your control:

```stata
use "jel_results.dta", clear
quietly csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
csdid_plot, saving("eventdata.dta") replace

preserve
use "eventdata.dta", clear
list in 1/5
twoway (rcap ci_high ci_low x) (scatter estimate x), ///
    yline(0) xtitle("Years since expansion") ///
    ytitle("Effect on mortality per 100,000") ///
    title("Event study") name(es, replace)
restore
capture erase "eventdata.dta"
```

The exported columns are `x` (the value on the horizontal axis), `estimate`,
the bounds `ci_low` and `ci_high`, plus `group`, `time`, `event_time`,
`series` (Pre/Post), `x_label` and `significant`. Note the estimate column is
`estimate`, not `att` — `csdid_plot` renames it on export. Because the bounds come from the same
run as the estimates, a simultaneous band stays simultaneous — building the
interval yourself from a standard error would silently turn it into a pointwise
one. See [Inference](inference.html).

## Replaying without re-estimating

Aggregations are computed from the stored influence function, so asking for a
different one does not re-estimate anything:

```stata
use "jel_results.dta", clear
quietly csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
estat event
estat group
estat calendar
estat simple
```

```stata
capture erase "jel_results.dta"
```
