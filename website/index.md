---
title: csdid
---
<div class="hero" markdown="1">

# `csdid`

<p class="tagline" markdown="span">**A Stata package for difference-in-differences with multiple periods.**</p>
<!-- <p class="meta-line">version 2.0 </p> -->

</div>

Welcome to the `csdid` Stata page! This is your one-stop shop for Difference-in-Differences (DiD) estimates under staggered (and block) designs. We cover a large family of settings, including balanced panel, unbalanced panel, and repeated cross-section data. All our procedures work with or without covariates. For inference, we enable analytical and bootstrap-based cluster-robust procedures. We also support simultaneous/uniform inference procedures suitable for making inference about the entire event-study path and addressing multiple-testing concerns.

The engine of `csdid` is [Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001). All our procedures embrace treatment effect heterogeneity across covariate subgroups, groups/cohorts, and time periods. We also discuss how we can aggregate group-time average treatment effects, ATT(g,t), into more aggregated summary measures such as event studies (and other functionals).

<!-- We also highlight that we accommodate different estimation procedures when covariates are available and used to strengthen the plausibility of the parallel trends assumption. More specifically, we implement regression-adjusted, inverse probability weighted (IPW), and doubly robust (augmented IPW) estimators for ATT(g,t)'s and their aggregations. Our default method is a doubly-robust DiD procedure that is more resilient against model misspecifications than the other alternatives. -->

## How to install

To install the latest version of `csdid`

<!-- norun -->

```stata
net install csdid, from("https://raw.githubusercontent.com/pedrohcgs/csdid-stata/main") replace
```

You can also install it using the ssc command (this version is not yet these)

<!-- norun -->

```stata
ssc install csdid, replace
```

## What it is built for

Our `csdid` DiD package is tailored to researchers who are comfortable with Stata and want an easy-to-use, fast, and reliable implementation of the staggered DiD methods in [Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001). All the procedures we implement first estimate the building block ATT(g,t)'s and then aggregate them using well-understood and explicitly defined weights. We built the package to **make the methods accessible** to a broader audience, without requiring them to worry about technical implementation details.

One important aspect of `csdid` is that all our causal target parameters are well-defined with explicit weights as discussed in [Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001), and that these causal parameters do not vary with the type of sampling process you have (e.g., the causal target parameter does not depend on whether the data is a balanced or unbalanced panel).

We caveat that one should be careful when comparing `csdid` estimates with DiD estimates from other packages, as they do not always target the same causal parameters. We discuss this in more detail [here](articles/csdid-against-the-field.html).

## Speed

This version of `csdid` is substantially faster than versions 1.XX (including version 1.81 and the `csdid2` variant). It can sometimes be 300x faster than Version 1.82, for example. We have documented these speed gains [here](articles/speed-vs-182.html). Our understanding is that, so far, we are the fastest implementation of staggered DiD in Stata. That is, we have a strong package, with a lot of options and strong statistical guarantees, that is also fast!

## Also in R and Python

The same estimators, from the same team, are available as [`did` for R](https://bcallaway11.github.io/did/) and [`csdid` for Python](https://d2cml-ai.github.io/csdid/index.html) (`pip install csdid`).

The three implementations agree to machine precision once the same options are set. We hope this facilitates conversations between researchers who have different software preferences.

If you find any discrepancy, please raise an [issue](https://github.com/pedrohcgs/csdid-stata/issues), and we will address it. But also make sure you are using the same options!

## How to use

<!-- norun -->

```stata
csdid y x1 x2, ivar(id) time(year) gvar(gvar)   // every ATT(g,t), doubly robust
estat event                                     // the event study, uniform bands
estat group                                     // one effect per group/cohort
```

The syntax is as simple as described above. Covariates go right after the outcome, and the default estimation method is a doubly robust DiD estimator; you set `method(reg)` or `method(ipw)` options to use regression-adjusted or (normalized/Hajek-based) IPW DiD estimators. The default comparison group is not-yet-treated units (if you use the `nevertreated` option, the comparison group becomes the never-treated units). The default inference procedure is based on a multiplier bootstrap procedure paired with simultaneous bands, so we address head-on the issues of multiple hypothesis tests; if you want to have pointwise analytical standard errors, use the `analytical` option. By default, all standard errors are clustered at the `id` level, though you can also use alternative clustering options, e.g., `cluster(state)` to cluster at a state level.

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
