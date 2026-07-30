# csdid: Difference-in-Differences with Multiple Time Periods in Stata

**A Stata package.** `csdid` is a Stata command that estimates group-time
average treatment effects, ATT(g,t), and their aggregations, for
difference-in-differences designs with staggered treatment timing, following
[Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001).
It handles covariates, sampling weights, unbalanced panels and repeated cross
sections, with doubly robust, outcome-regression and inverse-probability-weighted
estimators.

It follows the same estimators and defaults as our R package
[`did`](https://github.com/bcallaway11/did), from which this implementation
derives. The same methods are also available in Python through
[`csdid`](https://github.com/DrSquare/csdid) (`pip install csdid`), so results
are comparable across all three.

It runs in Stata 14 or newer. The estimation engine is written in Mata and
ships precompiled, so there is nothing else to install:

<!-- norun -->
```stata
net install csdid, from("https://raw.githubusercontent.com/pedrohcgs/csdid-stata/main") replace
```

`Stata module` |
`version 2.0.0` |
[Getting started](#getting-started) |
[Install](#install) |
[A short example](#a-short-example) |
[Unbalanced panels](#unbalanced-panels) |
[Repeated cross sections](#repeated-cross-sections) |
[Cite](#how-to-cite)

## Getting started

The building block is the **group-time average treatment effect** ATT(g,t): the
average effect in period *t* on the cohort first treated in period *g*. A
staggered design produces one for every cohort and period, which is more numbers
than anyone reads directly, so `csdid` estimates them all and then aggregates
them into the summary you want.

Three choices matter:

- **the comparison group** — not-yet-treated units (the default), or only
  never-treated units with `nevertreated`
- **the 2×2 estimator** — doubly robust `method(dr)` (the default),
  outcome regression `method(reg)`, or inverse probability weighting
  `method(ipw)`
- **the aggregation** — `estat event` for an event study, or `estat group`,
  `estat calendar`, `estat simple`

Inference is a multiplier bootstrap with simultaneous confidence bands by
default. `analytical` gives pointwise analytical standard errors instead.

## Install

From inside Stata:

<!-- norun -->
```stata
net install csdid, from("https://raw.githubusercontent.com/pedrohcgs/csdid-stata/main") replace
```

`replace` also upgrades an existing installation. Confirm what you are running
with:

```stata
csdid version
```

Requires Stata 14 or newer. There are no external dependencies: the
estimation engine is Mata and ships precompiled, so the same install works
on Windows, macOS and Linux. On macOS the package also installs a small
compiled accelerator (a universal binary) that speeds up the multiplier
bootstrap; everywhere else — and on macOS if the accelerator cannot load —
the bootstrap runs through the Mata implementation with identical results.

## A short example

The examples use the county-level mortality panel from the replication package
for *Difference-in-Differences Designs: A Practitioner's Guide*
([JEL-DiD](https://github.com/pedrohcgs/JEL-DiD)). It records deaths and
population by US county from 2009 to 2019, with the year each state expanded
Medicaid under the ACA — a staggered treatment.

The data are downloaded rather than shipped with the package, so every example
below runs from a clean Stata session. The URL is pinned to a commit, so the
numbers printed here stay reproducible even if the upstream branch moves.

```stata
* ---- load and prepare -------------------------------------------------------
* bindquote(strict) matters: the file has quoted fields containing newlines,
* and without it Stata splits them into extra observations.
import delimited using ///
    "https://raw.githubusercontent.com/pedrohcgs/JEL-DiD/50f4f18/data/county_mortality_data.csv", ///
    clear varnames(1) bindquote(strict) stringcols(_all)

* several columns carry "NA"; force turns those into Stata missing
destring deaths population_20_64 year yaca county_code stfips unemp_rate poverty_rate, ///
    replace force

* mortality per 100,000 among adults aged 20-64
generate double mrate = 100000 * deaths / population_20_64
drop if missing(mrate) | population_20_64 <= 0

* Treatment timing. gvar() is 0 for never-treated units and the first treated
* period otherwise. States expanding after this panel ends are never treated
* *within this sample*, so they join the never-treated comparison group.
generate int gvar = yaca
replace gvar = 0 if missing(gvar) | gvar > 2016

* balanced panel: counties observed in every year
bysort county_code: generate byte nyears = _N
keep if nyears == 11
```

That leaves 29,667 observations on 2,697 counties over 11 years, with cohorts
expanding in 2014, 2015 and 2016 against a large never-treated group.

```stata
* ---- estimate ATT(g,t) ------------------------------------------------------
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
```

`csdid` reports every ATT(g,t) cell, the estimator and comparison group it used,
and a joint pre-test of parallel trends on the pre-treatment cells.

```stata
* ---- aggregate --------------------------------------------------------------
estat event          // effects by time since treatment
estat group          // one effect per cohort
estat calendar       // one effect per calendar year
estat simple         // a single overall summary
```

Covariates are listed after the outcome. They enter the outcome regression, the
propensity score, or both, depending on `method()`:

```stata
csdid mrate unemp_rate poverty_rate, ivar(county_code) time(year) gvar(gvar) ///
    rseed(20250101)
estat event
```

To plot, export the plot-ready data and draw it yourself, so the styling stays
under your control:

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
csdid_plot, saving(eventdata) replace

preserve
use eventdata, clear
twoway (rcap ci_high ci_low x) (scatter estimate x), ///
    yline(0) xtitle("Years since expansion") ytitle("Effect on mortality rate")
restore
```

## Speed

Measured against **csdid Version 1.82** — the version SSC distributes today — on the
same machine, same data, seven trials per workload with the first discarded.

| Workload | Version 1.82 | 2.0.0 | |
| --- | ---: | ---: | ---: |
| ATT(g,t), outcome regression, analytical | 7.27s | 0.27s | **27x** |
| ATT(g,t), doubly robust with covariates | 8.30s | 0.42s | **20x** |
| ATT(g,t), IPW with weights | 7.72s | 0.31s | **25x** |
| ATT(g,t), clustered | 6.81s | 0.25s | **28x** |
| Bootstrap, outcome regression | 9.40s | 0.42s | **22x** |
| Bootstrap, doubly robust with covariates | 10.76s | 0.61s | **18x** |
| Bootstrap, clustered | 11.94s | 0.42s | **28x** |
| Unbalanced panel, weighted DR | 9.41s | 1.44s | **6.5x** |
| Unbalanced panel, bootstrap | 13.42s | 1.60s | **8.4x** |
| Event study, analytical | 7.95s | 1.54s | **5.2x** |
| Event study, bootstrap | 13.89s | 2.63s | **5.3x** |
| Event study, simultaneous bands | 14.08s | 2.80s | **5.0x** |
| Event study, clustered + bands | 12.64s | 2.57s | **4.9x** |
| Large panel, weighted DR | 28.88s | 2.07s | **13.9x** |

Between **5x and 28x**, and never slower. Peak memory is lower on every
workload. The engine is Mata throughout and ships precompiled, so there is no
per-session compilation cost either.

## Unbalanced panels

`csdid` detects an unbalanced `ivar()` panel and makes the balancing rule an
explicit, disclosed choice — `bal()` — rather than a silent one. The default,
`bal(full)`, keeps only units observed in every period. `bal(none)` keeps
every unit and estimates through the repeated-cross-section computation with
the standard-error accounting that goes with it. `bal(pair)` balances each
2×2 comparison separately, which is what Version 1.82 did without telling
you. Whatever you choose (or let default), `e(panel_mode)` reports the
resolved rule, and `e(N_units)` reports how many units contributed — the
choice is never invisible.

The JEL panel is nearly balanced, so this example **creates** the
unbalancedness deliberately and reproducibly, deleting a seeded subset of
county-years from the balanced sample above:

```stata
set seed 424242
generate double u = runiform()
drop if u < 0.15 & year >= 2012      // delete ~15% of later county-years

csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
display "panel mode: " e(panel_mode) ", units: " e(N_units)

csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101) bal(none)
display "panel mode: " e(panel_mode) ", units: " e(N_units)
estat event
```

The first run reports `panel` — the unbalanced units were dropped up front
and the count says how many survived. The second reports `allow_unbalanced`
with every county contributing. The two answer slightly different questions,
and the point of `bal()` is that you pick which one you asked.

## Repeated cross sections

When each observation is an independent draw rather than a unit followed over
time, omit `ivar()`.

The JEL data are a panel, so this example constructs a repeated cross section
from it by keeping one randomly chosen year per county, making every row a
different unit:

```stata
set seed 20240617
generate double pick = runiform()
bysort county_code (pick): keep if _n == 1

csdid mrate, time(year) gvar(gvar) rseed(20250101)
estat event
```

There is no `ivar()` here. `e(panel_mode)` reports the repeated-cross-section
path.

## Common options

| Option | |
| --- | --- |
| `method(dr\|reg\|ipw)` | 2×2 estimator; default `dr` |
| `nevertreated` | compare against never-treated units only; the default uses all not-yet-treated |
| `base_period(varying\|universal)` | pre-treatment base period; default `universal` |
| `bal(full\|none\|pair)` | balancing rule for unbalanced `ivar()` panels; default `full` |
| `rcs` | force the repeated-cross-section interpretation |
| `anticipation(#)` | periods of anticipated treatment effect |
| `[iw=varname]` | sampling weights |
| `cluster(varname)` | cluster the influence function above the unit level |
| `wboot(reps(#) rseed(#))` | bootstrap controls; `reps()` must exceed 20 |
| `analytical` | analytical pointwise standard errors instead of the bootstrap |
| `pointwise` | pointwise intervals instead of simultaneous bands |
| `level(#)` | confidence level; default 95 |

`gvar()` must be 0 for never-treated units and 1 or more for treated cohorts,
and `time()` must be 1 or more: cohorts and periods share one positive
calendar-time axis. A monotone relabelling of the periods leaves every estimate
unchanged, so shifting an axis that starts at or below 0 costs nothing.

## Documentation

From inside Stata:

| Command | Contents |
| --- | --- |
| `help csdid` | syntax, options, assumptions, stored results, methods and formulas |
| `help csdid_postestimation` | what is available after estimation |
| `help csdid_estat` | `estat attgt`, `estat event`, `estat tidy`, `estat glance` |
| `help csdid_stats` | aggregation, event-time windows, balanced event samples |
| `help csdid_plot` | plot-ready data export |

## How to cite

Please cite **both** the method and the software.

For the method:

> Callaway, Brantly, and Pedro H. C. Sant'Anna. 2021. "Difference-in-Differences
> with Multiple Time Periods." *Journal of Econometrics* 225 (2): 200-230.
> https://doi.org/10.1016/j.jeconom.2020.12.001

```bibtex
@article{CallawaySantAnna2021,
  author  = {Callaway, Brantly and Sant'Anna, Pedro H. C.},
  title   = {Difference-in-Differences with Multiple Time Periods},
  journal = {Journal of Econometrics},
  volume  = {225},
  number  = {2},
  pages   = {200--230},
  year    = {2021},
  doi     = {10.1016/j.jeconom.2020.12.001}
}
```

If you use the doubly robust estimator (`method(dr)`, the default), also cite:

> Sant'Anna, Pedro H. C., and Jun Zhao. 2020. "Doubly Robust
> Difference-in-Differences Estimators." *Journal of Econometrics* 219 (1):
> 101-122. https://doi.org/10.1016/j.jeconom.2020.06.003

For the software, cite the version you actually ran (report it with
`csdid version`):

```bibtex
@misc{csdidStata,
  title  = {csdid: Difference-in-Differences with Multiple Time Periods in Stata},
  note   = {Stata module, version 2.0.0},
  year   = {2026},
  url    = {https://github.com/pedrohcgs/csdid-stata}
}
```

## Further reading

Two reviews that place these estimators in context:

> Baker, Andrew, Brantly Callaway, Scott Cunningham, Andrew Goodman-Bacon, and
> Pedro H. C. Sant'Anna. 2026. "Difference-in-Differences Designs: A
> Practitioner's Guide." *Journal of Economic Literature* 64 (2): 498-557.
> https://doi.org/10.1257/jel.20251650

The examples above use the replication data from that article.

> Roth, Jonathan, Pedro H. C. Sant'Anna, Alyssa Bilinski, and John Poe. 2023.
> "What's trending in difference-in-differences? A synthesis of the recent
> econometrics literature." *Journal of Econometrics* 235 (2): 2218-2244.
> https://doi.org/10.1016/j.jeconom.2023.03.008

## Reporting bugs

Open an issue at
[github.com/pedrohcgs/csdid-stata/issues](https://github.com/pedrohcgs/csdid-stata/issues).
Please include the output of `csdid version`, the exact command line, and
`e(cmdline)`, `e(method)`, `e(control_group)`, `e(base_period)` and
`e(panel_mode)`. If the report concerns inference, add `e(bstrap)`,
`e(biters)` and `e(boot_seed)`. A small dataset that reproduces the problem is
worth more than any description of it.

## Authors

Fernando Rios-Avila, Pedro H. C. Sant'Anna, and Brantly Callaway.

The original Stata `csdid` was written by Fernando Rios-Avila; it brought these
estimators to Stata users first and defined the command surface this version
preserves.

## License

MIT. See [LICENSE](LICENSE).
