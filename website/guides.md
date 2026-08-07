---
title: Guides
---

# Guides

Each guide runs from a clean Stata session and is organized around one
choice you have to make in a real application (the comparison group, the
base period, the balancing rule), so the options named in the text, and
the defaults they replace, are the ones you will type. The four guides
under "Start here" are enough to run an analysis end to end, and each of
the rest answers one question.

Every script loads its own data, some of it over the network, so nothing
here depends on a file you do not have and nothing needs a package other
than `csdid`. The numbers shown are the numbers the code produces, and
they are not empirical findings about the applications whose data the
guides borrow.

**Start here**

| | |
| --- | --- |
| [Getting started](getting-started.html) | the estimand, the three choices you make, and a first estimate |
| [How csdid compares](articles/csdid-against-the-field.html) | same data, five other estimators: targets, misspecification, precision, inference, speed |
| [Why not two-way fixed effects](articles/why-not-twfe.html) | what a TWFE coefficient actually averages under staggered timing |
| [Code appendix](code-appendix.html) | every script behind the comparison guide, click to expand |

**The choices you make**

| | |
| --- | --- |
| [Comparison groups](articles/comparison-groups.html) | `notyet` or never-treated, and what to do with no never-treated units |
| [Base periods](articles/base-periods.html) | `universal` or `varying`, and what each pre-treatment number means |
| [Covariates and estimators](articles/covariates-and-estimators.html) | `dr`, `reg`, `ipw`, and what each assumes |
| [Anticipation](articles/anticipation.html) | when units respond before treatment starts |
| [Sampling weights](articles/weights.html) | `[iw=]`, and `fix_weights()` when weights change over time |

**How your data arrive**

| | |
| --- | --- |
| [Balanced panels](articles/balanced-panel.html) | the standard case, end to end |
| [Unbalanced panels](articles/unbalanced-panels.html) | `bal(full)`, `bal(none)`, and what is never done silently |
| [Repeated cross sections](articles/repeated-cross-sections.html) | when units are not followed over time |
| [Trimming and overlap](articles/trimming-and-overlap.html) | `pscoretrim()`, the overlap warning, and how to keep overlap |

**Inference and results**

| | |
| --- | --- |
| [Inference](articles/inference.html) | bootstrap, simultaneous bands, clustering |
| [Pre-testing](articles/pre-testing.html) | the Wald pre-test, reading pre-treatment cells, what to do if it fails |
| [Aggregations](articles/aggregations.html) | event study, cohort, calendar, overall, and event-time windows |
| [Working with results](articles/working-with-results.html) | results as a dataset, `e()`, influence functions, plot data |

**Coming from elsewhere**

| | |
| --- | --- |
| [Upgrading from Version 1.82](articles/upgrading-from-182.html) | what moves, what is deprecated, and what each old option is called now |
| [Speed against Version 1.82](articles/speed-vs-182.html) | the gains by sample size, periods, cohorts, and sampling scheme, from 17x to 334x |
| [References](references.html) | the papers behind the estimator, and how to cite `csdid` |

