---
title: csdid
---

<div class="hero" markdown="1">

# `csdid`

<p class="tagline">Difference-in-differences with multiple time periods,
following Callaway and Sant'Anna (2021), written for Stata by the authors
of the method.</p>

Group-time average treatment effects ATT(g,t) under staggered adoption,
with doubly robust estimation, covariates, sampling weights, unbalanced
panels, repeated cross sections, and simultaneous confidence bands. The
command estimates every cell the design supports. Aggregation is left to
you, so the summary you report is one you asked for rather than an
average taken over weights you never chose. The output reports the
aggregation you name and no other.

<!-- norun -->
```stata
net install csdid, from("https://raw.githubusercontent.com/pedrohcgs/csdid-stata/main") replace
```

<p class="meta-line">version 2.0.0 &nbsp;·&nbsp; Stata 14 or newer &nbsp;·&nbsp; no dependencies &nbsp;·&nbsp; MIT</p>

</div>

<div class="cards">
<div class="card" markdown="1">
### The estimand does not move with the sample

An estimand is a population quantity. `csdid` weights cohorts by the
population shares P(G=g). The other commands weight by the observations
each wave happened to contribute. Make the survey waves unequal in size,
change nothing else, and coverage for those commands falls to
2–38%, while `csdid` stays at 95%.

[The evidence](articles/csdid-against-the-field.html)
</div>
<div class="card" markdown="1">
### Doubly robust by default

The default estimator is consistent if *either* the outcome model *or*
the treatment-probability model is right. Break the outcome model and
every one-model command in the comparison drifts by +0.19 to +0.49,
while `csdid dr` reads −0.06 with coverage at the nominal level; break
the propensity score instead and `dr` again tracks the target. In each of
those two cells we broke exactly one of the two models.

[Misspecification, measured](articles/csdid-against-the-field.html)
</div>
<div class="card" markdown="1">
### What the output contains

Every ATT(g,t) cell comes with its own standard error. The aggregation
weights are available in closed form, and the balancing rule you chose
(or defaulted to) is reported in `e(panel_mode)`. Overlap failures are
printed, never absorbed into the estimate. A cell the data cannot
support comes back as a refusal.

[The transparency scorecard](articles/csdid-against-the-field.html)
</div>
<div class="card" markdown="1">
### Timings against the SSC version

On every workload we measured, this version runs 5–28× faster than csdid
Version 1.82, and it is never slower. These are wall-clock times on our
hardware, and they say nothing about the accuracy of either version. A
million-row event study with clustered standard errors finishes in under
two seconds.

[The benchmarks](articles/csdid-against-the-field.html)
</div>
</div>

## In one screen

<!-- norun -->
```stata
csdid y x1 x2, ivar(id) time(year) gvar(gvar)   // every ATT(g,t), doubly robust
estat event                                     // the event study, uniform bands
estat group                                     // one effect per cohort
```

Covariates go right after the outcome, the comparison group is
not-yet-treated units by default (`nevertreated` switches to the
never-treated units only), and inference is a multiplier bootstrap with
simultaneous bands (`analytical` gives pointwise analytical standard
errors instead). Every example on this site runs from a clean Stata
session, on a fixed and dated copy of the data. The numbers printed here
are the numbers the same lines produce for you. Note that where a result
depends on a random draw, the seed that produced it is shown in the code.

## Guides
{: #guides}

The three guides below are where we would start, and the full set is on
the [guides page](guides.html).

| | |
| --- | --- |
| [Getting started](getting-started.html) | the estimand, the three choices you make, and a first estimate |
| [How csdid compares](articles/csdid-against-the-field.html) | same data, five other estimators: targets, misspecification, precision, inference, speed |
| [Code appendix](code-appendix.html) | every script behind the comparison guide, click to expand |

[All seventeen guides](guides.html)

## Reference

From inside Stata: `help csdid`, `help csdid_postestimation`,
`help csdid_estat`, `help csdid_stats`, `help csdid_plot`.
