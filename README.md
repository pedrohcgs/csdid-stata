# csdid: Difference-in-Differences with Multiple Time Periods in Stata

**A Stata package.** `csdid` is a Stata command that estimates group-time
average treatment effects, ATT(g,t), and their aggregations, for
difference-in-differences designs with staggered treatment timing, following
[Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001).
It handles covariates, sampling weights, unbalanced panels and repeated cross
sections, with doubly robust, outcome-regression and inverse-probability-weighted
estimators.

It implements the same estimators as our R package
[`did`](https://github.com/bcallaway11/did), from which this implementation
derives, and the same methods are available in Python through
[`csdid`](https://github.com/d2cml-ai/csdid) (`pip install csdid`). Two
omitted-option defaults differ deliberately — this package defaults to
the not-yet-treated comparison group and a universal base period, where `did`
defaults to never-treated and varying — and both are documented in `NEWS.md`. State those
two options explicitly when comparing results. The
[implementation crosswalk](docs/r-did-crosswalk.md) explains the mapping and
behavior at boundaries, including missing cells and trimming ties.

It runs in Stata 14 or newer. The estimation engine is written in Mata and
ships precompiled for Stata 17 and later; earlier Statas read the bundled
source instead, which only makes the first `csdid` of a session take a
moment longer. Nothing else needs to be installed:

<!-- norun -->
```stata
net install csdid, from("https://raw.githubusercontent.com/pedrohcgs/csdid-stata/main") replace
```

`Stata module` |
`version 2.0.3` |
[Getting started](#getting-started) |
[Install](#install) |
[A short example](#a-short-example) |
[Unbalanced panels](#unbalanced-panels) |
[Repeated cross sections](#repeated-cross-sections) |
[Cite](#how-to-cite)

Version 2.0.3 corrects aggregation standard errors with very large or small
common sampling-weight scales, including results loaded from saved
influence-function files. See [the release notes](NEWS.md#csdid-203).

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
default. `analytical` gives analytical standard errors instead; aggregations still carry a simultaneous band (its critical value is bootstrapped, with a note) unless `pointwise` is added.

## Install

From inside Stata:

<!-- norun -->
```stata
cap ado uninstall csdid
net install csdid, from("https://raw.githubusercontent.com/pedrohcgs/csdid-stata/main") replace
```

SSC distributes csdid Version 1.81 under the same command name and the same
filenames, so remove any existing copy first — `cap ado uninstall csdid`, or
`ssc uninstall csdid` if it came from SSC. `replace` does overwrite the files,
but installing over a package Stata still tracks leaves two csdid entries
behind, and a later `ado uninstall csdid` then refuses (the name matches two
entries) or removes the wrong one.

Confirm that the installed version is 2.0.3 with:

```stata
csdid version
```

### Pinning a version for a replication package

Install from a full commit ID rather than from `main`, so the code is the same
on the day someone re-runs your do-files:

<!-- norun -->
```stata
cap ado uninstall csdid
net install csdid, from("https://raw.githubusercontent.com/pedrohcgs/csdid-stata/COMMIT") replace
```

Replace `COMMIT` with the full 40-character ID of a commit listed on the
[commits page](https://github.com/pedrohcgs/csdid-stata/commits/main);
everything else in the address is the same as for `main`, and that ID always
names the same code. A version tag listed on the
[tags page](https://github.com/pedrohcgs/csdid-stata/tags) can take the same
place, but a version number reported by `csdid version` does not by itself
mean that a download tag has been published. Record both the full installation
URL and the version reported by `csdid version` in your replication package.

### Troubleshooting

```stata
csdid version        // version, the csdid.ado that answered, and the engine in use
which csdid, all     // every copy of csdid on the adopath, in search order
csdid reset          // clear the session's engine decision and estimation cache
```

- **A csdid you did not expect is answering.** `csdid version` reports the path
  it resolved to. Stata searches the current directory and PERSONAL before
  PLUS, so a leftover `csdid.ado` in either shadows the installed one;
  `which csdid, all` lists every copy, and removing the stale one fixes it.
- **You installed or replaced csdid in a session that had already run it.**
  `csdid reset` clears the session's engine decision and estimation cache, so
  the next command decides again from the current adopath. The macOS
  bootstrap accelerator stays loaded until Stata restarts, so restart Stata to
  load a re-installed one.
- **Two csdid entries in the package list.** `ado dir` prints one numbered
  stanza per installed package; remove the older csdid stanza with
  `ado uninstall [#]`, using the number in square brackets, then reinstall as
  above.

Requires Stata 14 or newer. There are no external dependencies: the
estimation engine is Mata and ships precompiled, so the same install works
on Windows, macOS and Linux. On macOS the package also installs a small
compiled accelerator (a universal binary) that runs explicitly seeded
(`rseed()`) multiplier bootstraps. Unseeded draws, every other platform, and
a Mac where the accelerator cannot load use the Mata implementation, which
draws the same multipliers and agrees to floating-point rounding.

## A short example

The examples use the county-level mortality panel from the replication package
for *Difference-in-Differences Designs: A Practitioner's Guide*
([JEL-DiD](https://github.com/pedrohcgs/JEL-DiD)). It records deaths and
population by US county from 2009 to 2019, with the year each state expanded
Medicaid under the ACA — a staggered treatment.

The data are downloaded rather than shipped with the package, so every example
below runs from a clean Stata session. The download address points at a
fixed, dated copy of the data, so the numbers printed here stay
reproducible even if the source is later updated.

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
replace gvar = 0 if missing(gvar) | gvar > 2019

* balanced panel: counties observed in every year
bysort county_code: generate byte nyears = _N
keep if nyears == 11
```

That leaves 29,667 observations on 2,697 counties over 11 years, with cohorts
expanding in 2014, 2015, 2016 and 2019 against a large never-treated group.

```stata
* ---- estimate ATT(g,t) ------------------------------------------------------
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
```

`csdid` reports every ATT(g,t) cell and, below the table, a joint pre-test of
parallel trends on the pre-treatment cells. `e(method)`, `e(control_group)`
and `e(base_period)` record the estimator, comparison group and base period
it used.

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
estat event
csdid_plot, saving(eventdata) replace

preserve
use eventdata, clear
twoway (rcap ci_high ci_low x) (scatter estimate x), ///
    yline(0) xtitle("Years since expansion") ytitle("Effect on mortality rate")
restore
```

## Speed

The following measurements describe version 2.0.3.

Measured against **csdid Version 1.82** &mdash; the last revision of the 1.8x
line, November 2025 &mdash; on 30 October 2026, on the same machine and data, with seven timed
trials per workload after one discarded warmup, on Stata/MP 17 using 10 processors.

| Workload | Version 1.82 | 2.0.3 | |
| --- | ---: | ---: | ---: |
| ATT(g,t), outcome regression, analytical | 1.75s | 0.07s | **27x** |
| ATT(g,t), doubly robust with covariates | 2.17s | 0.12s | **17x** |
| ATT(g,t), IPW with weights | 2.08s | 0.09s | **24x** |
| ATT(g,t), clustered | 1.80s | 0.08s | **23x** |
| Bootstrap, outcome regression | 2.57s | 0.15s | **17x** |
| Bootstrap, doubly robust with covariates | 3.02s | 0.21s | **15x** |
| Bootstrap, IPW with weights | 2.91s | 0.17s | **17x** |
| Bootstrap, clustered | 2.55s | 0.10s | **26x** |
| Unbalanced panel, weighted DR | 2.02s | 0.20s | **10x** |
| Unbalanced panel, bootstrap | 2.85s | 0.28s | **10x** |
| Event study, analytical | 1.73s | 0.08s | **22x** |
| Event study, bootstrap | 3.17s | 0.27s | **12x** |
| Event study, simultaneous bands | 3.22s | 0.34s | **9x** |
| Event study, clustered + bands | 3.20s | 0.16s | **20x** |
| Large panel, weighted DR | 10.34s | 0.56s | **18x** |

Memory figures summarize the peak process RSS sampled for each trial. The
8% allowance below limits increases in memory use; reductions can be larger.

Between **9x and 27x** across these fifteen fixed-size workloads, each run
with the same options on both versions, and never slower. That is a different
measurement from the scaling comparison below, which varies the size of the
design on purpose. Peak memory is within 8% of Version 1.82 on every
workload. On the large panel above, peak memory is 190MB
against 270MB. The paired-trial memory ratio is above one
in 1 of these 15 workloads. The memory comparison uses paired
trials on the same Stata interpreter.

Those are fixed-size workloads. The gap widens with the number of periods and
cohorts, which is what drives the number of ATT(g,t) cells: **up to 305x** on
a forty-period panel in the 31 October 2026 scaling comparison, measured
separately on StataNow/MP 19.5 using 10 processors. See
[Speed against Version 1.82](https://psantanna.com/csdid/articles/speed-vs-182.html)
for that comparison, and
[How csdid compares](https://psantanna.com/csdid/articles/csdid-against-the-field.html)
for timings against the other Stata DiD commands, including Stata's own
`xthdidregress` and `hdidregress`.

The engine is Mata throughout and ships precompiled for Stata 17 and
later, so there is no per-session compilation cost there; on Stata 14-16
the bundled source loads once per session, a one-off moment on the first
call.

## Unbalanced panels

`csdid` detects an unbalanced `ivar()` panel and makes the balancing rule an
explicit, disclosed choice — `bal()` — rather than a silent one. The default,
`bal(full)`, keeps only units observed in every period. `bal(none)` keeps
every unit and estimates through the repeated-cross-section computation with
the standard-error accounting that goes with it. `bal(pair)` balances each
2×2 comparison separately, which is what Version 1.82 did. Whatever you choose (or let default), `e(panel_mode)` reports the
resolved rule, and `e(N_units)` reports how many units contributed — the
choice is never invisible.

As downloaded the JEL panel is only nearly balanced, and the
`keep if nyears == 11` step above made it exactly balanced. So this example
**creates** the unbalancedness deliberately and reproducibly, deleting a seeded
subset of county-years from that balanced sample:

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
| `wboot(reps(#) rseed(#))` | bootstrap settings; `reps()` must exceed 20 |
| `analytical` | analytical standard errors instead of the bootstrap (aggregation bands still bootstrap their critical value unless `pointwise`) |
| `pointwise` | pointwise intervals instead of simultaneous bands |
| `level(#)` | confidence level; default 95 |

`gvar()` must be 0 for never-treated units and 1 or more for treated cohorts,
and `time()` must be 1 or more: cohorts and periods share one positive
calendar-time axis. To shift an axis that starts at or below zero, add the
same constant to time and treated cohort codes, leaving never-treated codes
at zero. This preserves calendar distances and event times.

## Documentation

From inside Stata:

| Command | Contents |
| --- | --- |
| `help csdid` | syntax, options, assumptions, stored results, methods and formulas |
| `help csdid_postestimation` | what is available after estimation |
| `help csdid_estat` | `estat attgt`, `estat event`, `estat tidy`, `estat glance` |
| `help csdid_stats` | aggregation, event-time windows, balanced event samples |
| `help csdid_plot` | default plots and plot-ready data export |
| `help csdid_legacy` | utility and deprecated commands carried over from Version 1.82 |
| `help csdid_whatsnew` | what changes when you upgrade from Version 1.82 |

Upgrading from Version 1.81 or Version 1.82? The
[upgrading guide](https://psantanna.com/csdid/articles/upgrading-from-182.html)
lists every change that moves a number, what replaces each removed option,
and how to reproduce a Version 1.82 run.

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
  author = {Callaway, Brantly and Rios-Avila, Fernando and Sant'Anna, Pedro H. C.},
  title  = {csdid: Difference-in-Differences with Multiple Time Periods in Stata},
  note   = {Stata module, version 2.0.3},
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
Please include the full output of `csdid version` — it names the copy of
`csdid.ado` that answered and the engine the session used — the exact command
line, and `e(cmdline)`, `e(method)`, `e(control_group)`, `e(base_period)` and
`e(panel_mode)`. If the report concerns inference, add `e(bstrap)`,
`e(biters)`, `e(boot_seed)` and `e(bootstrap_accelerator_status)`. A small
dataset that reproduces the problem is worth more than any description of it.

## Authors

Brantly Callaway, Fernando Rios-Avila, and Pedro H. C. Sant'Anna.

The original Stata `csdid` was written by Fernando Rios-Avila; it brought these
estimators to Stata users first and defined the command surface this version
preserves.

## License

MIT. See [LICENSE](LICENSE).
