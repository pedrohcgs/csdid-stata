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

The short version: on a balanced panel with equal-sized periods, most of
these estimators agree, and speed looks like the only difference — most,
not all, as the first table below shows. Take
anything away from that ideal — unequal sampling across periods, an
unbalanced panel, repeated cross sections — and they quietly stop estimating
the same parameter. Not with worse precision: with different targets.

<div class="note" markdown="1">
A target parameter is an estimand. It should be a fixed feature of the
population, and it should not move because your sample did.
</div>

Everything below uses one data-generating process (1,000 units per draw,
seven periods), fixed effect sizes, and 500 simulation draws per setting.
We report bias against the *population* targets — never against a
sample-dependent quantity — along with the standard deviation across draws
and the coverage of nominal 95% intervals.

<nav class="toc">
<div class="toc-title">Contents</div>
<ul>
<li><a href="#what-each-command-is-actually-computing">The command map</a></li>
<li><a href="#speed">Speed</a></li>
<li><a href="#reliability-part-i-no-covariates">Reliability I &mdash; no covariates</a></li>
<li><a href="#reliability-part-ii-covariates-and-the-case-for-doubly-robust">Reliability II &mdash; covariates and DR</a></li>
<li><a href="#precision-and-a-word-on-efficiency">Precision</a></li>
<li><a href="#simultaneous-inference">Simultaneous inference</a></li>
<li><a href="#reproducing-everything">Reproducing everything</a></li>
<li><a href="#the-bottom-line">The bottom line</a></li>
</ul>
</nav>

## What each command is actually computing

Before any comparison can be fair, the commands have to be placed on a
common map. We did this by controlled experiment, not by reading
documentation: each claim below was confirmed against a quantitative
prediction, usually to four decimal places.

**Two ways to build the counterfactual.** `csdid`, `did_multiplegt_dyn`, and
`lpdid` difference each cohort against its base period, the period right
before treatment. `jwdid` and `did_imputation` instead fit unit and time
fixed effects on *all* untreated observations and impute Y(0) from the fit —
on a balanced panel those two produce identical point estimates, with and
without covariates (we verified agreement to six decimals with each
command's documented covariate specification), and `flexdid`'s default
specification joins them. Identical points are not identical inference,
though: when effects vary with covariates, `did_imputation`'s standard
errors are deliberately conservative under that heterogeneity while
`jwdid` reports conventional regression inference — on one of our draws
the gap grew from 11% at event time 0 to 55% at event time 2. Same
estimator, two inference philosophies; a practitioner comparing printed
standard errors across the two would conclude they disagree when their
point estimates could not agree more. The same lesson holds on the
differencing side: on designs where `csdid` and `did_multiplegt_dyn`
produce identical point estimates, their standard errors differ by
roughly 8%, because the inference conventions differ in what they treat
as random — ours follows Callaway and Sant'Anna (2021) in treating
cohort membership as sampled, so the estimated cohort shares contribute
uncertainty. Pooling every pre-period
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

## Speed

Every cell below is the mean of 10 timed runs in a fresh Stata process with
one discarded warmup, so nobody pays the one-time library load and nobody
benefits from a warm cache. Standard deviations across the timed runs never
exceed a few hundredths of a second at the sizes shown. A dash marks a
workload without a measured time; `flexdid` is timed in the
repeated-cross-section table, where it is a native competitor. Rows =
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
covariates the ordering reverses. The remaining gap is the cost of
computing forty auditable ATT(g,t) cells rather than one regression.

### Estimation methods, 100,000 rows with covariates

`csdid` `reg` 0.24s, `ipw` 0.44s, `dr` 0.46s — against `lpdid` 1.03s,
`jwdid` 1.67s, `did_imputation` 4.50s, `did_multiplegt_dyn` 7.84s. The
doubly robust estimator, which the covariates section below argues you
should want anyway, is not a speed compromise: it is 2x faster than the fastest
alternative with covariates.

Aggregation is not in these numbers because it is not worth a table:
`estat event` takes a fraction of a second after any of these estimations,
at any size shown.

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

`lpdid` is off by 6.5% of the true effect on a perfectly balanced panel with
nothing exotic anywhere. This is not a bug, and it is not noise (it is the
same at n = 4,000). It is the effective-sample-size weighting doing exactly
what it does: later cohorts get less weight because earlier cohorts are no
longer clean comparisons, so its event study averages a different mix of
cohorts than the population has. (`flexdid`'s 1.00 in the coverage column
is the opposite, milder anomaly: its intervals over-cover — conservative
rather than wrong, and it recurs in every table it appears in.) You do not
need missing data for the estimand question to matter.

### Unequal sampling across periods

Now the same population, but the probability that an observation is
recorded varies by calendar period — think survey waves of different sizes.
Nothing about treatment, outcomes, or composition changes; the stationarity
condition of Callaway and Sant'Anna (2021, Assumption B.1) holds exactly.
The only casualty is the auxiliary condition that every period contributes
equal cross-sections.

| estimator | bias at e=0 | 95% coverage |
| --- | ---: | ---: |
| `csdid` (any `bal()` mode) | +0.003 | 0.95 |
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
not unbalancedness itself.

<div class="important" markdown="1">
We find this the single most consequential table in the guide, and it
comes from a violation so mild that most applied descriptions of the data
would not even mention it.
</div>

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

### The transparency scorecard

Nothing below is a simulation result. It is documentation-verified fact
about what each command reports and how it says it computes it:

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
whole game. Effects still do not depend on the covariates, so the targets have not
moved.

With every model correctly specified, on a balanced panel (500 reps,
bias / coverage at e=0):

| estimator | bias | coverage |
| --- | ---: | ---: |
| `csdid dr` | +0.001 | 0.95 |
| `csdid ipw` | +0.004 | 0.95 |
| `csdid reg` | -0.001 | 0.95 |
| `jwdid` | +0.001 | 0.95 |
| `did_imputation` | +0.000 | 0.96 |
| `flexdid` | -0.001 | 1.00 |
| `did_multiplegt_dyn` | **+0.119** | **0.61** |
| `lpdid` | **-0.139** | **0.46** |

Everyone who handles covariates correctly is fine. The exception worth
understanding is `did_multiplegt_dyn` (SSC version dated January 17,
2026, the current release as we write), which drifts with the horizon —
+0.88 by e=2 — not because of a defect, but because its covariate
adjustment answers a different question. Its `controls()` option imposes
parallel trends on outcomes residualized on the first differences of the
covariates, with a single coefficient common to all groups and periods.
That is a different assumption from conditional parallel trends in
Callaway and Sant'Anna (2021), and it is more restrictive in two specific
ways. For time-invariant covariates — gender, race, baseline earnings,
most of what applied researchers actually condition on — the first
differences are zero, so the residualization leaves the unconditional
comparison unchanged and the condition collapses to unconditional
parallel trends. And by giving every group and period one common
coefficient, it implicitly restricts how covariates may shift trends
heterogeneously across cohorts — which is exactly the heterogeneity that
conditional parallel trends exists to allow. There is an irony here worth
stating plainly: the entire point of this literature is that imposing
homogeneity on treatment effects breaks TWFE, and this covariate scheme
re-imposes that kind of homogeneity one layer down.

On its own terms — genuinely time-varying covariates whose effect on
trends really is common across cohorts — the approach works, and our
experiments confirm it. But those terms are narrow, and they are not the
terms most applied covariate stories satisfy. The documentation offers
`trends_nonparam()` — exact matching on discrete covariates — as the
route for time-invariant characteristics; matching on our binary
covariate removes its share of the drift (+0.88 falls to +0.66 at e=2),
and continuous covariates are outside that option's scope. Conditional
parallel trends as in Callaway and Sant'Anna (2021) asks for none of
this: the trend may depend on the covariates flexibly and heterogeneously, and
`csdid`'s doubly robust estimator conditions on the covariates
themselves — which is why its column of this table is clean. And the same
covariates change nothing about Part I's conclusion: rerunning the
repeated-cross-section comparison with the covariates included, `csdid dr` stays on
target in both sampling regimes while the regression-style estimators
reproduce their unequal-period drift, covariates and all — adjusting for
covariates cannot repair a weighting scheme.

Why prefer `dr` among the three csdid methods, when all three are clean
here? Because correct specification is exactly what you do not get to
assume. The doubly robust estimator (Sant'Anna and Zhao, 2020) is
consistent if *either* the outcome model *or* the treatment-probability
model is right — two chances instead of one, at no speed cost (the Speed section above) and, in
these simulations, no precision cost either. Every other command in this
comparison is an outcome-regression estimator with one chance.

So we broke the models on purpose, one at a time, same population and
targets as above. First the outcome model: add a nonlinear term to the
untreated trend — it now depends on the square of the continuous
covariate — while every estimator keeps conditioning on the covariates in
levels. This is the world where the outcome model you wrote down is wrong,
and it is not an exotic world. Bias and coverage at e=1:

| estimator | bias | coverage |
| --- | ---: | ---: |
| `csdid dr` | -0.058 | 0.94 |
| `csdid ipw` | -0.054 | 0.93 |
| `csdid reg` | **+0.300** | **0.46** |
| `jwdid` | **+0.490** | **0.26** |
| `did_imputation` | **+0.189** | **0.72** |
| `flexdid` | **+0.327** | **0.93** |
| `did_multiplegt_dyn` | **+0.303** | **0.22** |
| `lpdid` | **-0.162** | **0.68** |

(`did_multiplegt_dyn` and `lpdid` arrive at this cell already carrying
their correctly-specified-cell biases; the misspecification compounds on
top.)

Every outcome-regression command breaks together, and the bias grows with
the horizon — `jwdid` reaches +0.67 by e=2, coverage 0.29. This is not a
defect in any one implementation; it is the same wrong outcome model
failing everywhere it is the only line of defense. The two `csdid`
estimators that do not lean on it walk through: `ipw` because the
treatment-probability model is still correct, `dr` because one correct
model is all it needs.

<div class="tip" markdown="1">
That second chance is not a luxury option — in this comparison, no other
command has it at all.
</div>

Second, the propensity score. Our first attempt at this cell is worth
reporting precisely because it failed: we made cohorts differ in the
*spread* of the continuous covariate — a logit linear in X cannot
represent that — and nothing broke, `ipw` included. The reason is
instructive. A fitted logit projects the selection it can see onto the
covariates you gave it, so the error a misspecification leaves behind is
close to orthogonal to anything linear in those covariates — and our
trend is linear in them. An error that is orthogonal to the trend has
nothing to load on. A misspecification experiment only teaches you
something when the error is aimed at the target.

So we aimed it. In the redesigned cell, selection is driven by a latent
index, and the covariate the researcher observes is a nonlinear
(exponential) transform of that index — the same device as in Sant'Anna
and Zhao (2020). Now the true propensity score is a logit in the *log* of
the observed covariate, the fitted logit in the covariate itself is
genuinely wrong, and because the observed covariate is skewed, the error
loads on the trend. The outcome stays linear in what the researcher
observes, so every outcome model remains correct — only the
treatment-probability model is broken. Bias and coverage at e=1:

| estimator | bias | coverage |
| --- | ---: | ---: |
| `csdid dr` | +0.001 | 0.95 |
| `csdid ipw` | **-0.094** | 0.97 |
| `csdid reg` | -0.001 | 0.95 |
| `jwdid` | +0.001 | 0.92 |
| `did_imputation` | +0.002 | 0.93 |
| `flexdid` | -0.001 | 0.99 |
| `did_multiplegt_dyn` | **+0.229** | **0.28** |
| `lpdid` | **-0.112** | **0.66** |

(As before, `did_multiplegt_dyn` and `lpdid` carry their
correctly-specified-cell biases into this one.)

The outcome-regression commands are fine here — a wrong propensity score
is invisible to an estimator that never uses one. The action is inside
`csdid`: `ipw`'s bias grows with the horizon (−0.04, −0.09, −0.14) and
concentrates exactly where the propensity score does the most work — in
the ATT(5,6) cell, where the never-treated are the only comparison left,
`ipw` is off by −0.23 *and* pays more than twice `dr`'s standard error
(0.35 against 0.16). The wrong weights cost it twice, in location and in
spread; those wide intervals are also why its coverage does not collapse
the way `reg`'s did in the outcome cell. `dr`, with one correct model in
hand, pays neither price.

One more thing happened in this cell, and we consider it a feature: in 36
of the 500 draws, `csdid` refused to estimate the worst-overlap cell at
all and printed the overlap violation it found. The reported `ipw` and
`dr` rows condition on the draws that passed that check — which, if
anything, flatters `ipw`, since the refused draws are the ones where its
weights are most extreme. No other command in this comparison checks. Put
the two sabotage cells side by side and the doubly robust case makes
itself: break the outcome model and every rival breaks with `reg` while
`dr` walks; break the propensity score and `ipw` drifts while `dr` walks
again. Every other command is a one-model estimator that happens to live
in the world where its model is the broken one or not. `dr` is the only
one that gets to be wrong once for free.

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
both settings; only the variances move. `lpdid` is biased in both, for the
same weighting reason as above, which no error process fixes — bias is also
why it has no row in a table about precision.

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
already costs 4 to 9 points of coverage among the unbiased estimators —
`lpdid`'s 0.444 is mostly its bias, not its intervals — and with the ten or
fifteen event times of a typical application the arithmetic only gets
worse. The uniform
band is the interval that means what readers think the plotted band means.

## Reproducing everything

Every table above is generated by a script with a fixed seed, package
versions pinned to their current SSC releases, and population targets that
are computed once, by hand, from the data-generating process — never
re-derived from a draw. Every script is in the
[code appendix](../code-appendix.html), ready to run.

## The bottom line

Six commands, one population, one set of targets that never moved. That
was the whole experiment, and it is worth being plain about what it did
and did not show.

It did not show that anyone else's software is broken. Every command in
this comparison was written by researchers whose work moved this
literature forward, and the differences we measured are not bugs — they
are design choices, made in the open by people who understood them,
that answer slightly different questions.

What it showed is that "slightly different questions" stops being slight
the moment your data are less than ideal. Change nothing about the
population and only how the sample arrives, and commands that "mostly
agree" split by whole coverage points, because their targets travel with
the sample while the truth stands still. Break one model quietly, and
every estimator with one model breaks with it — the doubly robust
default is the only one in this comparison that gets a second chance.
Read pointwise intervals as a band, and the certainty on the plot is
more than the certainty you have. None of these failures announces
itself. That is precisely what makes them dangerous, and precisely why
we built `csdid` to announce everything: a target fixed in the
population, every ATT(g,t) cell with its own standard error, aggregation
weights in closed form, sample decisions disclosed in `e()`, overlap
failures printed rather than absorbed, and uniform bands that mean what
readers think bands mean. The speed is not the point; it is what makes
refusing to compromise on the rest cost nothing.

Our opinion, stated once more as an opinion: an estimator you can take
apart is an estimator you can trust, and the tables above exist because
`csdid` is built to be taken apart. The point of this guide is not that
`csdid` wins those tables, although it does. The point is that every
number in them can be recomputed, from a seed, by anyone — including the
ones we lost. That is the standard we think this literature should hold
every estimator to. Ours first.
