---
title: Working with results
---

# Working with results

<div class="note" markdown="1">
Everything `csdid` computes is available programmatically, as tidy data for
tables, as matrices for your own calculations, and as plot-ready data (so that
the graph stays yours).
</div>

## The data

Build and save the sample once. Each section starts from that sample and
illustrates a results workflow, including the inference and storage options it
requires.

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
save "jel_results.dta", replace
```

## A run to work with

```stata
use "jel_results.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) cluster(stfips) rseed(20250101)
```

## Results as a dataset

Add `saving()` to any `estat` subcommand and it writes what it computed to a
dataset instead of only printing it. `saving()` is the same option that
`margins`, `simulate` and `graph` take, so there is no separate export command to
learn. We use it for anything that has to end up in a paper, on the grounds that
a dataset is easier to check, and easier to re-run, than a log file.

`estat attgt, saving()` gives one row per ATT(g,t) cell. Each row carries the
estimate, its standard error, the test statistic, the p-value, and both the
reported and the pointwise confidence limits (everything the printed table shows,
and a little more besides):

```stata
estat attgt, saving("attgt_cells.dta") replace
preserve
use "attgt_cells.dta", clear
describe
list in 1/5
restore
```

Every aggregation exports itself in the same way. The file then holds that
aggregation rather than the underlying cells:

```stata
estat event, saving("eventstudy.dta") replace
preserve
use "eventstudy.dta", clear
list in 1/5
restore
```

```stata
estat simple, saving("overall.dta") replace
preserve
use "overall.dta", clear
list
restore
```

Because `saving()` sits on the subcommand, the options that shape a result go
there too. The file then matches the table you have just read, so that
`estat event, window(-3 3) saving(w.dta)` saves the windowed event study and not
the full one.

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
display "comparison group: " e(control_group)
display "base period  : " e(base_period)
display "panel mode   : " e(panel_mode)
display "clusters     : " e(N_clusters)
display "pre-test W   : " e(wald_stat) "  p = " e(wald_pvalue)
```

`e(attgt)` has ten columns: `group`, `time`, `event_time`, `att`, `se`,
`n_treat_t`, `n_treat_pre`, `n_control_t`, `n_control_pre`, and `base_time`.
Use column names when extracting results. `base_time` identifies the period
used for each comparison, including on gapped calendars or with anticipation:

```stata
matrix A = e(attgt)
matrix list A
```

## Influence functions

The influence function has one column per ATT(g,t) cell and one row per unit.
The standard errors, the uniform bands and the clustered inference are all built
from it. It stays internal by default because it is a large object, so you ask
for it with `storeall` when you want to do your own inference:

```stata
use "jel_results.dta", clear
quietly csdid mrate, ivar(county_code) time(year) gvar(gvar) analytical storeall
matrix IF = e(inffunc)
display "influence function: " rowsof(IF) " units x " colsof(IF) " cells"
mata: printf("columns are mean-zero to %g\n", max(abs(mean(st_matrix("IF")))))
```

<div class="tip" markdown="1">
For a version that survives the session, and that feeds `csdid_stats using` for
later aggregation, write it to a dataset instead with `saverif()`.
</div>

Each column is mean-zero by construction, which is what the printed maximum
above confirms. Note that the option changes what is stored and leaves what is
estimated alone, so the numbers you report are the same either way. With the
influence function in hand you can compute standard errors for aggregations
that `csdid`
does not provide, or feed a sensitivity analysis of your own (we do exactly this
when a referee asks for a weighting we have not implemented).

## Plot-ready data

`csdid_plot` draws the current results. Add `saving()` to export the plot
data for a graph of your own design. First run `estat event` to select the
event study; directly after `csdid`, the plot shows ATT(g,t) by cohort and
calendar period.

```stata
use "jel_results.dta", clear
quietly csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
estat event
csdid_plot, saving("eventdata.dta") replace

preserve
use "eventdata.dta", clear
list in 1/5
twoway (rcap ci_high ci_low x) (scatter estimate x), ///
    yline(0) xtitle("Years since expansion") ///
    ytitle("Effect on mortality per 100,000") ///
    title("Event study") name(es, replace)
restore
```

The exported columns are `x` (the value on the horizontal axis), `estimate`,
the bounds `ci_low` and `ci_high`, plus `group`, `time`, `event_time`,
`series` (Pre/Post), `x_label`, `plot_type`, and `significant`.

<div class="important" markdown="1">
Note that the estimate column is `estimate` rather than `att`, since
`csdid_plot` renames it on export. Because the bounds come from the same run as
the estimates, a simultaneous band stays simultaneous. Build the interval
yourself out of a standard error and it silently becomes a pointwise one.
See [Inference](inference.html).
</div>

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

The ATT(g,t) estimates and their influence functions are reused. Each
aggregation runs its own multiplier bootstrap when required for its standard
errors or simultaneous band. Seeded aggregations continue the stored random
stream, so reproducing a table requires the same estimation and the same
sequence of aggregation commands.
