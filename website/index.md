---
title: csdid
---

<div class="hero" markdown="1">

# `csdid`

<p class="tagline">Difference-in-differences with multiple time periods —
Callaway and Sant'Anna (2021), built for Stata by the authors of the
method.</p>

Group-time average treatment effects ATT(g,t) under staggered adoption,
with doubly robust estimation, covariates, sampling weights, unbalanced
panels, repeated cross sections, and simultaneous confidence bands. Every
number it reports can be taken apart, and every decision it makes is
disclosed.

<!-- norun -->
```stata
net install csdid, from("https://raw.githubusercontent.com/pedrohcgs/csdid-stata/main") replace
```

<p class="meta-line">version 2.0.0 &nbsp;·&nbsp; Stata 14 or newer &nbsp;·&nbsp; no dependencies &nbsp;·&nbsp; MIT</p>

</div>

<div class="cards">
<div class="card" markdown="1">
### The target stands still

An estimand is a population quantity; it should not move because your
sample did. Make survey waves unequal — nothing else — and the other
commands' coverage falls to 2–38%. `csdid` stays at 95%, because
P(G=g) does not care how the sample arrived.

[The evidence →](articles/csdid-against-the-field.html)
</div>
<div class="card" markdown="1">
### Wrong once, for free

The default is doubly robust: right if *either* the outcome model *or*
the treatment-probability model is right. Break the outcome model and
every one-model command drifts by +0.19 to +0.49; `csdid dr` reads
−0.06 with nominal coverage. Break the propensity score instead — `dr`
walks again.

[Misspecification, measured →](articles/csdid-against-the-field.html)
</div>
<div class="card" markdown="1">
### Built to be audited

Every ATT(g,t) cell with its own standard error. Aggregation weights in
closed form. The balancing rule you chose — or defaulted to — reported
in `e(panel_mode)`. Overlap failures printed, never absorbed. If you
cannot take an estimator apart, you cannot check it.

[The transparency scorecard →](articles/csdid-against-the-field.html)
</div>
<div class="card" markdown="1">
### Speed is a by-product

5–28× faster than csdid Version 1.82 on every workload measured, never
slower. A million-row event study with clustered standard errors runs
in under two seconds. Being careful costs nothing here.

[The benchmarks →](articles/csdid-against-the-field.html)
</div>
</div>

## In one screen

<!-- norun -->
```stata
csdid y x1 x2, ivar(id) time(year) gvar(gvar)   // every ATT(g,t), doubly robust
estat event                                     // the event study, uniform bands
estat group                                     // one effect per cohort
```

Covariates go right after the outcome. The comparison group is
not-yet-treated units by default (`nevertreated` switches). Inference is a
multiplier bootstrap with simultaneous bands (`analytical` for pointwise
analytical standard errors). Every example on this site runs from a clean
Stata session, on a fixed, dated copy of the data — the numbers you see
are the numbers you get.

## Guides
{: #guides}

Three places to start; the full set is on the [guides page](guides.html).

| | |
| --- | --- |
| [Getting started](getting-started.html) | the estimand, the three choices you make, and a first estimate |
| [How csdid compares](articles/csdid-against-the-field.html) | same data, five other estimators: targets, misspecification, precision, inference, speed |
| [Code appendix](code-appendix.html) | every script behind the comparison guide, click to expand |

[All seventeen guides →](guides.html)

## Reference

From inside Stata: `help csdid`, `help csdid_postestimation`,
`help csdid_estat`, `help csdid_stats`, `help csdid_plot`.
