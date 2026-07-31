---
title: csdid
---

<div class="hero" markdown="1">

# `csdid`

<p class="tagline">A Stata package for difference-in-differences with staggered treatment adoption, from the authors of Callaway and Sant'Anna (2021).</p>

`csdid` estimates group-time average treatment effects, ATT(g,t), and the event studies and summaries built from them. It covers the designs applied researchers actually face: staggered adoption across many cohorts, block designs where every treated unit adopts at once, covariates through doubly robust estimation, sampling weights, unbalanced panels, repeated cross sections, anticipation windows, and simultaneous confidence bands over the whole event-study path. Every cell it estimates can be inspected, and every decision it makes along the way is reported.

<!-- norun -->
```stata
net install csdid, from("https://raw.githubusercontent.com/pedrohcgs/csdid-stata/main") replace
```

<p class="meta-line">version 2.0.0 &nbsp;&middot;&nbsp; Stata 14 or newer &nbsp;&middot;&nbsp; no dependencies &nbsp;&middot;&nbsp; MIT</p>

</div>

<div class="cards">
<div class="card" markdown="1">
### What it is built for

Staggered adoption is the hard case, and block adoption is the easy special case of it. Either way, the target is a population quantity, and it should not change because the sample arrived in a different shape. In our simulations, making survey waves unequal (and changing nothing else) drops the other commands' coverage to 2&ndash;38%. `csdid` stays at 95%.

[The evidence](articles/csdid-against-the-field.html)
</div>
<div class="card" markdown="1">
### Doubly robust by default

The default estimator is consistent when either the outcome model or the treatment-probability model is correct. In our experiments, breaking the outcome model biases every one-model command by +0.30 to +0.49 while `csdid dr` reads &minus;0.06 with nominal coverage; breaking the propensity score instead leaves `dr` on target again. Note that double robustness protects against one wrong model, and not against both being wrong at once.

[Misspecification, measured](articles/csdid-against-the-field.html)
</div>
<div class="card" markdown="1">
### We compared, so you do not have to guess

We ran `csdid` against five other Stata commands on one population with known truths. The differences that matter are the ones that are easy to miss: targets that move with the sampling, covariate assumptions that restrict more than their option names suggest, and standard errors that differ across commands even where the point estimates agree exactly. We would not compare estimates across estimators unless you know how each one behaves; the guide is our attempt to make that knowledge available.

[How csdid compares](articles/csdid-against-the-field.html)
</div>
<div class="card" markdown="1">
### Fast enough that care is free

A million-row event study with clustered standard errors finishes in 1.8 seconds with analytical standard errors (2.4 seconds at the bootstrap default), and every workload we measured runs 4.9&times; to 28&times; faster than the SSC version. Those are wall-clock times on our hardware. They say nothing about the accuracy of either version.

[The benchmarks](articles/csdid-against-the-field.html)
</div>
</div>

## Transparency is the point

We built `csdid` so that its output can be taken apart. Every ATT(g,t) comes with its own standard error, the aggregation weights are available in closed form, the sample decisions are stored in `e()`, overlap failures are reported as refusals and not as numbers, and every simulation in the comparison guide can be recomputed from a seed with the scripts in the [code appendix](code-appendix.html). We see the choice of an estimator as a conversation between empirical researchers and econometricians, and that conversation goes better when both sides can recompute the numbers in front of them. None of this replaces judgment about the identifying assumptions in your application.

## Also in R and Python

The same estimators, from the same team, are available as [`did` for R](https://github.com/bcallaway11/did) and [`csdid` for Python](https://github.com/DrSquare/csdid) (`pip install csdid`). The three implementations agree to machine precision once the same options are set; two omitted-option defaults differ deliberately in Stata, and `NEWS.md` documents both.

## In one screen

<!-- norun -->
```stata
csdid y x1 x2, ivar(id) time(year) gvar(gvar)   // every ATT(g,t), doubly robust
estat event                                     // the event study, uniform bands
estat group                                     // one effect per cohort
```

Covariates go right after the outcome. The comparison group is not-yet-treated units by default (`nevertreated` switches). Inference is a multiplier bootstrap with simultaneous bands (`analytical` gives pointwise analytical standard errors). Every example on this site runs from a clean Stata session, on a fixed, dated copy of the data.

## Guides
{: #guides}

Three places to start; the full set is on the [guides page](guides.html).

| | |
| --- | --- |
| [Getting started](getting-started.html) | the estimand, the three choices you make, and a first estimate |
| [How csdid compares](articles/csdid-against-the-field.html) | same data, five other estimators: targets, misspecification, precision, inference, speed |
| [Code appendix](code-appendix.html) | every script behind the comparison guide, click to expand |

[All seventeen guides](guides.html)

## Reference

From inside Stata: `help csdid`, `help csdid_postestimation`, `help csdid_estat`, `help csdid_stats`, `help csdid_plot`.
