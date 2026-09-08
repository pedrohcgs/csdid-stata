---
title: csdid
---
<div class="hero" markdown="1">

# `csdid`

<p class="tagline" markdown="span">**A Stata package for difference-in-differences with multiple periods.**</p>
<p class="meta-line">version 2.0.0</p>

</div>

`csdid` estimates difference-in-differences effects when units begin treatment
at different times. It supports balanced and unbalanced panels, repeated cross
sections, covariates, and sampling weights.

Following [Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001),
it estimates an average treatment effect for each treatment cohort and period,
then combines those effects into event studies, cohort averages, calendar-time
averages, or one overall summary. Effects may differ across cohorts and over
time. Inference uses a multiplier bootstrap with simultaneous confidence bands
by default; analytical and clustered inference are also available.

## How to install

Version 2.0.0 installs from GitHub. It replaces an earlier `csdid` under the
same command name, so uninstall first and then install:

<!-- norun -->

```stata
cap ado uninstall csdid
net install csdid, from("https://raw.githubusercontent.com/pedrohcgs/csdid-stata/main") replace
```

If your current copy came from SSC, `ssc uninstall csdid` is the first line
instead. Uninstalling first is what keeps Stata tracking one `csdid` rather
than two. Run `csdid version` afterwards to confirm what you are running.

SSC currently distributes csdid **Version 1.82**, the previous generation of
the package. If that is what you want, it is one line:

<!-- norun -->

```stata
ssc install csdid, replace
```

## What it is built for

The package is for researchers who want to estimate and report staggered
adoption designs in Stata. Choose doubly robust estimation (the default),
outcome regression, or inverse probability weighting. Each aggregation has
explicit weights, so its interpretation follows the question being asked.

Sample choices matter. The default `bal(full)` retains units observed in every
period; `bal(none)` uses the available observations. If missingness changes
which units remain, the population represented by an estimate may change.
The [unbalanced-panel guide](articles/unbalanced-panels.html) explains these
choices.

Other DiD commands can target different causal parameters. Our
[comparison guide](articles/csdid-against-the-field.html) shows when estimates
coincide, when they differ, and how the comparison depends on the design.

## Speed

Version 2.0.0 takes advantage of the shared structure across cohort-period
comparisons. In the published comparisons with Version 1.82, the speedup ranges
from 10x to 308x as the design's size, periods, and cohorts vary. See
[Speed against Version 1.82](articles/speed-vs-182.html) for the timings,
machine, matched settings, and runnable code. The
[comparison with other commands](articles/csdid-against-the-field.html)
reports both runtime and differences in what each command estimates.

## Also in R and Python

The same estimators, from the same team, are available as [`did` for R](https://bcallaway11.github.io/did/) and [`csdid` for Python](https://d2cml-ai.github.io/csdid/index.html) (`pip install csdid`).

When comparing implementations, set the same sample, comparison group, base
period, estimator, and inference options explicitly. This Stata package
defaults to not-yet-treated controls and a universal base period; the R
package defaults to never-treated controls and a varying base period.

If you find any discrepancy, please raise an [issue](https://github.com/pedrohcgs/csdid-stata/issues), and we will address it. But also make sure you are using the same options!

## How to use

<!-- norun -->

```stata
csdid y x1 x2, ivar(id) time(year) gvar(gvar)   // every ATT(g,t), doubly robust
estat event                                     // the event study, uniform bands
estat group                                     // one effect per group/cohort
```

The syntax is as simple as described above. Covariates go right after the outcome, and the default estimation method is a doubly robust DiD estimator; you set `method(reg)` or `method(ipw)` options to use regression-adjusted or (normalized/Hajek-based) IPW DiD estimators. The default comparison group is not-yet-treated units (if you use the `nevertreated` option, the comparison group becomes the never-treated units). The default inference procedure is based on a multiplier bootstrap procedure paired with simultaneous bands, so we address head-on the issues of multiple hypothesis tests; if you want analytical standard errors, use the `analytical` option (add `pointwise` for pointwise intervals; otherwise the aggregation's simultaneous band is still bootstrapped, with a note). For panel data, inference accounts for repeated observations of each unit.
Use `cluster(state)`, for example, when dependence extends across units within
states. In repeated cross sections each observation is a separate unit unless
you specify clustering.

## Guides

{: #guides}
We have prepared some user guides to help you use and understand our commands. Beyond actually reading [Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001), you can find all our [guides here](guides.html). A few that stand out include:


|                                                                 |                                                                                                                           |
| ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| [Getting started](getting-started.html)                         | A discussion about the three choices you need to make and how to use them in an example                                   |
| [Why not two-way fixed effects](articles/why-not-twfe.html)     | What a TWFE coefficient actually averages once treatment timing is staggered, and why that is rarely what you are after   |
| [How csdid compares](articles/csdid-against-the-field.html)     | We compare csdid with other packages, in different settings. This can clarify some differences that sometimes get ignored |
| [Upgrading from Version 1.82](articles/upgrading-from-182.html) | What changes in 2.0, which defaults moved, and what each old option is called now                                         |
| [Comparison groups](articles/comparison-groups.html)            | Whether to compare against not-yet-treated or never-treated units, and what to do when there are no never-treated units   |

## Help Files

From inside Stata, you can get help for all our commands: `help csdid`, `help csdid_postestimation`, `help csdid_estat`, `help csdid_stats`, `help csdid_plot`.

## Citing csdid

We ask that you cite *both* the method and the software when you use our `csdid` command: for the method, [Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001); for the software, cite the version you ran, which `csdid version` reports for you.

```bibtex
@misc{CRS2026_csdidStata,
  author = {Callaway, Brantly and Rios-Avila, Fernando and Sant'Anna, Pedro H. C.},
  title  = {csdid: Difference-in-Differences with Multiple Time Periods in Stata},
  note   = {Stata module, version 2.0.0},
  year   = {2026},
  url    = {https://github.com/pedrohcgs/csdid-stata}
}
```
