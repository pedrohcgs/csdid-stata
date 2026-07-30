---
title: csdid
---

# csdid

Group-time average treatment effects, ATT(g,t), for difference-in-differences
designs with staggered treatment timing, following
[Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001).

<!-- norun -->
```stata
net install csdid, from("https://raw.githubusercontent.com/pedrohcgs/csdid-stata/main") replace
```

Stata 14 or newer. The engine is pure Mata and ships precompiled — no
platform-specific binaries, nothing else to install.

## Guides
{: #guides}

| | |
| --- | --- |
| [How csdid compares](articles/csdid-against-the-field.html) | same data, five other estimators: speed, targets, and inference |
| [Getting started](getting-started.html) | the estimand, the three choices you make, and a first estimate |
| [Why not two-way fixed effects](articles/why-not-twfe.html) | what a TWFE coefficient actually averages under staggered timing |
| [Balanced panels](articles/balanced-panel.html) | the standard case, end to end |
| [Covariates and estimators](articles/covariates-and-estimators.html) | `dr`, `reg`, `ipw`, and what each assumes |
| [Aggregations](articles/aggregations.html) | event study, cohort, calendar, overall, and event-time windows |
| [Comparison groups](articles/comparison-groups.html) | `notyet` or never-treated, and what to do with no never-treated units |
| [Base periods](articles/base-periods.html) | `universal` or `varying`, and what each pre-treatment number means |
| [Anticipation](articles/anticipation.html) | when units respond before treatment starts |
| [Pre-testing](articles/pre-testing.html) | the Wald pre-test, reading pre-treatment cells, what to do if it fails |
| [Sampling weights](articles/weights.html) | `[iw=]`, and `fix_weights()` when weights change over time |
| [Unbalanced panels](articles/unbalanced-panels.html) | `bal(full)`, `bal(none)`, and what is never done silently |
| [Repeated cross sections](articles/repeated-cross-sections.html) | when units are not followed over time |
| [Inference](articles/inference.html) | bootstrap, simultaneous bands, clustering, the pre-test |
| [Trimming and overlap](articles/trimming-and-overlap.html) | `pscoretrim()`, the overlap warning, and how to keep overlap |
| [Working with results](articles/working-with-results.html) | results as a dataset, `e()`, influence functions, plot data |
| [Upgrading from Version 1.82](articles/upgrading-from-182.html) | what moves, what is deprecated, and what each old option is called now |

Every example on this site is runnable from a clean Stata session. The data are
downloaded from a pinned commit, never shipped with the package, so the numbers
shown stay reproducible.

## Reference

From inside Stata: `help csdid`, `help csdid_postestimation`,
`help csdid_estat`, `help csdid_stats`, `help csdid_plot`.

[References](references.html) — the papers behind the estimator, two reviews of
the DiD literature, and how to cite `csdid`.
