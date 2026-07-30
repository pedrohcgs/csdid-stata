---
title: "How csdid compares: same data, five other estimators"
---

# How csdid compares: same data, five other estimators

Stata now has several commands for staggered difference-in-differences:
`csdid` (this package), `jwdid`, `did_imputation`, `did_multiplegt_dyn`,
`lpdid`, and `flexdid`. They are often described as interchangeable — pick
your favorite syntax, get "the" event study. Our main goal in this guide is
to show, with simulations you can re-run line by line, that this is not the
case, and to be precise about *when* it is not the case and *why*.

The short version: on a balanced panel with equal-sized periods, these
estimators mostly agree, and speed is the only visible difference. Take
anything away from that ideal — unequal sampling across periods, an
unbalanced panel, repeated cross sections — and they quietly stop estimating
the same parameter. Not with worse precision: with different targets. A
target parameter is an estimand. It should be a fixed feature of the
population, and it should not move because your sample did.

Everything below uses one data-generating process, fixed effect sizes, and
500 simulation draws per setting; seeds and scripts are in the replication
appendix. We report bias against the *population* targets — never against a
sample-dependent quantity — along with the standard deviation across draws
and the coverage of nominal 95% intervals.

## What each command is actually computing

Before any comparison can be fair, the commands have to be placed on a
common map. We did this by controlled experiment, not by reading
documentation: each claim below was confirmed against a quantitative
prediction, usually to four decimal places.

**Two ways to build the counterfactual.** `csdid`, `did_multiplegt_dyn`, and
`lpdid` difference each cohort against its base period, the period right
before treatment. `jwdid` and `did_imputation` instead fit unit and time
fixed effects on *all* untreated observations and impute Y(0) from the fit —
on a balanced panel with no covariates, those two produce identical numbers,
and `flexdid`'s default specification joins them. Pooling every pre-period
buys efficiency when parallel trends holds exactly in every period, and
pays for it with non-locality: anything that happened five periods before
treatment is still in the estimate.

**Three ways to average the cells.** Every command reports some average of
the group-time effects ATT(g,t), and this is where the estimand question
lives:

| command | a cohort's weight at event time e | the weight moves when... |
| --- | --- | --- |
| `csdid` | its population share, P(G=g) | the population changes |
| `jwdid`, `did_imputation`, `did_multiplegt_dyn`, `flexdid` | its treated observations at e | the sampling changes |
| `lpdid` | its effective 2x2 sample size | the adoption *order* changes |

The first column is a fixed population quantity. The second moves with the
realized sample — delete rows and the target changes. The third is a
regression artifact: `lpdid`'s weights come out of pooling switch events
with time fixed effects, and they are nearly invariant to how *large* a
cohort is. None of the second or third columns is wrong as arithmetic. But
if the question is "what is the average effect for treated units," only the
first column answers it regardless of how the sample arrived.

## Reliability, part I: no covariates

We simulate one population — three treated cohorts of equal size plus a
never-treated group, effects of 2.0, 2.5, and 3.0 at event times 0, 1, and
2 — and vary only *how the sample arrives*. Nothing here involves
covariates. That is deliberate: the estimand question already bites with
the cleanest data you will ever see.

### A balanced panel

Every command runs; most agree. One does not:

| estimator | bias at e=0 | 95% coverage |
| --- | ---: | ---: |
| `csdid` | +0.005 | 0.96 |
| `jwdid` | +0.005 | 0.96 |
| `did_imputation` | +0.005 | 0.96 |
| `did_multiplegt_dyn` | +0.005 | 0.95 |
| `flexdid` | +0.004 | 1.00 |
| `lpdid` | **-0.13** | **0.53** |

`lpdid` is off by 5% of the true effect on a perfectly balanced panel with
nothing exotic anywhere. This is not a bug, and it is not noise (it is the
same at n = 4,000). It is the effective-sample-size weighting doing exactly
what it does: later cohorts get less weight because earlier cohorts are no
longer clean controls, so its event study averages a different mix of
cohorts than the population has. You do not need missing data for the
estimand question to matter.

### Unequal sampling across periods

Now the same population, but the probability that an observation is
recorded varies by calendar period — think survey waves of different sizes.
Nothing about treatment, outcomes, or composition changes; the stationarity
condition of Callaway and Sant'Anna (2021, Assumption B.1) holds exactly.
The only casualty is the auxiliary condition that every period contributes
equal cross-sections.

| estimator | bias at e=0 | 95% coverage |
| --- | ---: | ---: |
| `csdid` (either `bal()` mode) | +0.003 | 0.95 |
| `jwdid` | -0.16 | 0.36 |
| `did_imputation` | -0.17 | 0.38 |
| `did_multiplegt_dyn` | -0.29 | 0.16 |
| `flexdid` | -0.17 | 0.73 |
| `lpdid` | -0.40 | 0.02 |

Every observation-weighted estimator is now estimating a different — and
moving — quantity, and its confidence intervals cover the true effect
between 2% and 38% of the time. `csdid` does not move, because P(G=g) does
not move. Restore equal period sizes (ordinary uniform missingness) and the
other estimators come right back: the mechanism is the unequal weighting,
not unbalancedness itself. We find this the single most consequential table
in the guide, and it comes from a violation so mild that most applied
descriptions of the data would not even mention it.

### Repeated cross sections

With fresh samples each period and equal period sizes, the commands that
support repeated cross sections (`csdid` via `rcs`, `jwdid`, `did_imputation`
with group fixed effects, `flexdid`) are all fine. Make the period sizes
unequal — entirely ordinary in survey data — and the drift returns with a
twist: it *flips sign across event times* (-0.16 at e=0, +0.23 at e=2 for
the observation-weighted commands). The estimated event study does not just
shift; its shape bends toward whatever the sampling did. A reader would see
effects "growing" that do not grow. `csdid` reports 0.004 and 0.001 bias at
those event times, with nominal coverage, and its individual ATT(g,t) cells
are within 0.02 of their known truths in every setting we ran.

`did_multiplegt_dyn` does not claim repeated cross-section support and
returns nothing here; `lpdid` refuses outright — which we consider the
honest failure mode.

### What this section establishes

Transparency, mostly. The scorecard below is documentation-verified fact,
not simulation:

| | reports every ATT(g,t) | weights stated in closed form | target fixed under sampling | balance choice explicit | uniform bands |
| --- | --- | --- | --- | --- | --- |
| `csdid` | yes | yes | yes | yes (`bal()`, disclosed in `e(panel_mode)`) | yes |
| `jwdid` | recoverable from coefficients | no | no | no | no |
| `flexdid` | recoverable from coefficients | no | no | no | no |
| `did_imputation` | no | no | no | no (`autosample` decides) | no |
| `did_multiplegt_dyn` | no | no | no | no (imputes treatment paths) | no |
| `lpdid` | no | no | no | no | no |
 `csdid` reports every ATT(g,t) cell with its standard
error, states its aggregation weights in closed form, discloses the
resolved sample in `e(panel_mode)`, and lets you pick the balancing rule
(`bal()`) instead of picking one for you. Several of its competitors never
show you the cells at all. Our opinion, stated as an opinion: an estimator
you cannot decompose is an estimator you cannot audit, and the fact that
the decomposable one is also the one whose target never moved in these
tables is not a coincidence.

## Reliability, part II: covariates, and the case for doubly robust

Now the covariates: time-invariant unit characteristics — think gender, or
earnings in a year before the sample starts — whose distribution differs
across cohorts, and which shift both the level and the trend of the
untreated outcome. That is conditional parallel trends: the unconditional
comparison is biased by construction, and the covariate handling is the
whole game. Effects still do not depend on X, so the targets have not
moved.

With every model correctly specified, on a balanced panel (500 reps,
bias / coverage at e=0):

| estimator | bias | coverage |
| --- | ---: | ---: |
| `csdid dr` | -0.000 | 0.95 |
| `csdid ipw` | -0.000 | 0.95 |
| `csdid reg` | -0.000 | 0.95 |
| `jwdid` | +0.001 | 0.95 |
| `did_imputation` | +0.001 | 0.95 |
| `flexdid` | -0.001 | 1.00 |
| `did_multiplegt_dyn` | +0.032 | 0.92 |
| `lpdid` | **-0.135** | **0.49** |

Everyone who handles X correctly is fine, with one exception that deserves
a close look. `did_multiplegt_dyn` drifts with the horizon (+0.20 by e=2),
and its own documentation explains why: its `controls()` residualizes the
outcome's first differences on the *first differences* of the controls,
with one coefficient common to all groups and periods. Think about what
that assumption buys you. For time-invariant covariates — gender, race,
baseline earnings, most of what applied researchers actually condition on —
the first differences are zero, the residualization does nothing, and the
condition collapses to unconditional parallel trends. We verified this the
hard way: on this design, its estimates with and without `controls(x1 x2)`
are numerically identical to the last digit. The command accepts the
option, runs without a word, and returns the unadjusted number — a
researcher who typed the controls believing they had conditioned on them
has not, and nothing in the output says so.

Its documentation points to `trends_nonparam()` as the remedy for
time-invariant covariates: exact matching on their values, documented as
requiring the covariates to be discrete (coarser than the unit). We tested
that too. `trends_nonparam(x1)` does what it says: matching on the binary
covariate removes its share of the bias (+0.87 falls to +0.66 at e=2),
leaving the share owed to the continuous one. Passing the continuous
covariate — `trends_nonparam(x1 x2)` — cannot work, and to the command's
credit it prints an explanation (Design Restriction 1 is not satisfied).
But it exits with return code zero and leaves the PREVIOUS command's
results posted in `e()`. A script that checks the return code and then
harvests the results — which is what scripts do — silently gets the
previous run's numbers. We state this with confidence because our own
first harvest did exactly that, and only a fresh-session check caught it.
So the command's two covariate options fail in two different silent ways:
`controls()` estimates and is silently unadjusted; `trends_nonparam()`
with an unusable covariate refuses on screen but hands your script
someone else's estimates.

And even on `controls()`'s intended domain — time-varying covariates,
where we verify it does work — the assumption requires the covariate effect on trends to be
linear with a single homogeneous coefficient. There is an irony here worth
stating plainly: the entire point of this literature is that imposing
homogeneity on treatment effects breaks TWFE, and this covariate scheme
re-imposes exactly that kind of homogeneity one layer down. Conditional
parallel trends as in Callaway and Sant'Anna (2021) asks for none of it:
the trend may depend on X flexibly, heterogeneously, and `csdid`'s doubly
robust estimator conditions on the covariates themselves — which is why its
column of this table is clean. And the same
covariates change nothing about Part I's conclusion: rerunning the
repeated-cross-section comparison with X included, `csdid dr` stays on
target in both sampling regimes while the regression-style estimators
reproduce their unequal-period drift, covariates and all — adjusting for X
cannot repair a weighting scheme.

Why prefer `dr` among the three csdid methods, when all three are clean
here? Because correct specification is exactly what you do not get to
assume. The doubly robust estimator (Sant'Anna and Zhao, 2020) is
consistent if *either* the outcome model *or* the treatment-probability
model is right — two chances instead of one, at no speed cost (§1) and, in
these simulations, no precision cost either. Every other command in this
comparison is an outcome-regression estimator with one chance. We are
completing a set of misspecification experiments that make each failure
mode bite separately — designing a data-generating process where the
nonlinearity genuinely defeats linear controls turns out to be a sharper
exercise than it sounds, and we would rather publish cells we can explain
than cells that merely look decisive. They will appear here.

## Speed

Every cell below is the mean of 10 timed runs in a fresh Stata process with
one discarded warmup, so nobody pays the one-time library load and nobody
benefits from a warm cache. Standard deviations are in the replication log;
none exceeds a few hundredths of a second at the sizes shown. Rows =
units x 10 periods, 4 cohorts, event-study estimation with clustered
standard errors.

### Balanced panels, no covariates (seconds)

| rows | `csdid` | `jwdid` | `did_imputation` | `lpdid` | `did_multiplegt_dyn` |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 0.01 | 0.06 | 0.20 | 0.24 | 0.66 |
| 10,000 | 0.04 | 0.15 | 0.61 | 0.34 | 0.99 |
| 100,000 | 0.27 | 0.66 | 3.41 | 0.98 | 4.62 |
| 1,000,000 | **1.78** | 5.84 | 44.6 | 7.91 | not run |

`csdid` is the fastest command in every cell — about 3x `jwdid` and 25x
`did_imputation` at a million rows. `did_multiplegt_dyn` was capped at
100,000 rows for runtime.

### Unbalanced panels (~850,000 rows)

| | `csdid` | `jwdid` | `did_imputation` | `lpdid` |
| --- | ---: | ---: | ---: | ---: |
| no covariates | **3.9** | 6.1 | 40.3 | 5.7 |
| with covariates | **4.6** | 15.3 | 49.8 | — |

### Repeated cross sections (1,000,000 rows)

| | `csdid` | `flexdid` | `jwdid` | `did_imputation` |
| --- | ---: | ---: | ---: | ---: |
| no covariates | 5.7 | **5.3** | 7.0 | 21.6 |
| with covariates | **6.5** | 7.6 | — | 22.5 |

Credit where due: `flexdid` is the faster command at the largest
repeated-cross-section size without covariates, by about 7%; with
covariates the ordering reverses. Chasing that 7% is what led us to
profile this path and take 12% off it — the remaining gap is the cost of
computing forty auditable ATT(g,t) cells rather than one regression.

### Estimation methods, 100,000 rows with covariates

`csdid` `reg` 0.24s, `ipw` 0.44s, `dr` 0.46s — against `lpdid` 1.03s,
`jwdid` 1.67s, `did_imputation` 4.50s, `did_multiplegt_dyn` 7.84s. The
doubly robust estimator, which the next section argues you should want
anyway, is not a speed compromise: it is 2x faster than the fastest
alternative with covariates.

Aggregation is not in these numbers because it is not worth a table:
`estat event` takes a fraction of a second after any of these estimations,
at any size shown.

## Precision, and a word on efficiency

Where the targets coincide — a balanced panel, no covariates — it is fair to
compare spread. But which estimator is more precise is not a fact about the
estimators; it is a fact about the error process, and one simulation setting
cannot settle it. So we ran two. Same population, same 500 draws, only the
within-unit error process changes:

| errors | `csdid` sd | `jwdid`/`did_imputation` sd | tighter |
| --- | ---: | ---: | --- |
| iid | 0.067 | 0.052 | poolers, by ~22% |
| unit root | 0.047 | 0.062 | **`csdid`, by ~25%** |

With iid errors, pooling every pre-period is close to the right thing and
the Wooldridge/imputation estimators are tighter — exactly as theory says.
With unit-root errors (each unit's shocks accumulate, which is what much
real panel data looks like), the ranking reverses and base-period
differencing wins by the same margin. Every estimator remains unbiased in
both settings; only the variances move. lpdid is biased in both, for the
same weighting reason as above, which no error process fixes.

The general statement is in Chen, Sant'Anna, and Xie (2025): the efficient
estimator for these designs depends on the covariance structure of the
outcomes, and none of the packaged estimators — ours included, in either
error world — attains the semiparametric efficiency bound in general.
Comparing standard errors across packages without saying what the error
process is amounts to picking the setting where your favorite wins.

## Simultaneous inference

An event study is a family of estimates, and the interval that matters is
the one that covers the whole path at once. `csdid` reports uniform
confidence bands from the multiplier bootstrap by default; no other command
in this comparison offers a band option at all. What that is worth, on the
balanced panel with three post-treatment event times:

| | joint coverage of ES(0), ES(1), ES(2) |
| --- | ---: |
| `csdid` uniform band | **0.966** |
| `csdid` three pointwise CIs | 0.908 |
| `jwdid` / `did_imputation` pointwise | 0.888 |
| `did_multiplegt_dyn` pointwise | 0.862 |
| `lpdid` pointwise | 0.444 |

Reading three pointwise 95% intervals as if they jointly covered the path
already costs 6 to 14 points of coverage; with the ten or fifteen event
times of a typical application the arithmetic only gets worse. The uniform
band is the interval that means what readers think the plotted band means.

## Simultaneous inference

*(Band coverage results land here tonight.)* One structural fact needs no
simulation: an event study is a family of estimates, and `csdid` is the
only command in this comparison with uniform confidence bands over the
whole path (`wboot`, the default). Reading pointwise intervals across ten
event times as if they jointly covered the path is the most common way
these figures get over-read.

## Reproducing everything

Every table above is generated by a script with a fixed seed, package
versions pinned to their current SSC releases, and population targets that
are computed once, by hand, from the data-generating process — never
re-derived from a draw. The appendix lists each script.
