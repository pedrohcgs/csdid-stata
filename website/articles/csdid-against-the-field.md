---
title: "How csdid compares: same data, five other estimators"
---

# How csdid compares: same data, five other estimators

Stata now has several commands for staggered difference-in-differences:
`csdid` (this package), `jwdid`, `did_imputation`, `did_multiplegt_dyn`,
`lpdid`, and `flexdid`. They are often described as interchangeable, in the
sense that you pick whichever syntax you like best and get "the" event
study. In this guide we use simulations (you can re-run them line by line)
to show that they are not interchangeable. We also say where the
differences show up, and why.

The short version is this. On a balanced panel with equal-sized periods,
most of these estimators agree and speed looks like the only difference
(with one exception, as the first table below shows). Once you move away
from that ideal, by (i) letting the sampling vary across periods, (ii)
unbalancing the panel, or (iii) moving to repeated cross sections, the
commands stop estimating the same parameter, and the difference shows up in
the target, not in the precision.

<div class="note" markdown="1">
A target parameter is an estimand. It should be a fixed feature of the
population, and it should not move because your sample did.
</div>

Everything below uses one data-generating process (1,000 units per draw,
seven periods), fixed effect sizes, and 500 simulation draws per setting.
We report bias against the *population* targets (never against a
sample-dependent quantity), along with the standard deviation across draws
and the coverage of nominal 95% intervals.

<nav class="toc">
<div class="toc-title">Contents</div>
<ul>
<li><a href="#what-each-command-is-actually-computing">The command map</a></li>
<li><a href="#speed">Speed</a></li>
<li><a href="#reliability-part-i-no-covariates">Reliability I &mdash; no covariates</a></li>
<li><a href="#reliability-part-ii-covariates-and-the-case-for-doubly-robust">Reliability II &mdash; covariates and DR</a></li>
<li><a href="#precision">Precision</a></li>
<li><a href="#simultaneous-inference">Simultaneous inference</a></li>
<li><a href="#reproducing-everything">Reproducing everything</a></li>
<li><a href="#what-we-take-from-this">What we take from this</a></li>
</ul>
</nav>

## What each command is actually computing

Before any comparison can be fair, the commands have to be placed on a
common map. We built that map by controlled experiment, not by reading
documentation. Each claim below was confirmed against a quantitative
prediction (usually to four decimal places).

**Two ways to build the counterfactual.** `csdid`, `did_multiplegt_dyn`, and
`lpdid` difference each cohort against its base period (the period right
before treatment). `jwdid` and `did_imputation` instead fit unit and time
fixed effects on *all* untreated observations and impute Y(0) from the fit,
and on a balanced panel those two produce identical point estimates (with
and without covariates; we verified agreement to six decimals with each
command's documented covariate specification). `flexdid`'s default
specification joins them. One domain note before any table: `flexdid`
implements Deb, Norton, Wooldridge and Zabel (2025), whose title scopes the
estimator to repeated cross sections, so this guide compares it there, and
only there.

Identical point estimates are not identical inference. When effects vary
with covariates, `did_imputation`'s standard errors are deliberately
conservative under that heterogeneity, while `jwdid` reports conventional
regression inference (on one of our draws the gap grew from 11% at event
time 0 to 55% at event time 2). The two commands run the same estimator
under two inference philosophies, so a practitioner comparing printed
standard errors across them would conclude that they disagree, at the very
point where their point estimates agree to every decimal we checked in
these runs.

The same lesson holds on the differencing side. On designs where `csdid`
and `did_multiplegt_dyn` produce identical point estimates, their standard
errors differ by roughly 8%, because the inference conventions differ in
what they treat as random; ours follows Callaway and Sant'Anna (2021) in
treating cohort membership as sampled, so the estimated cohort shares
contribute uncertainty. Pooling every pre-period buys efficiency when
parallel trends holds exactly in every period, and pays for it with
non-locality (anything that happened five periods before treatment is still
in the estimate).

**Three ways to average the cells.** Every command reports some average of
the group-time effects ATT(g,t), and this is where the estimand question
lives:

| command | a cohort's weight at event time e | the weight moves when... |
| --- | --- | --- |
| `csdid` | its population share, P(G=g) | the population changes |
| `jwdid`, `did_imputation`, `did_multiplegt_dyn`, `flexdid` | its treated observations at e | the sampling changes |
| `lpdid` | its effective 2x2 sample size | the adoption *order* changes |

The first column is a fixed population quantity. The second moves with the
realized sample, so deleting rows changes the target. The third is a
regression artifact: `lpdid`'s weights come out of pooling switch events
with time fixed effects, and they are nearly invariant to how *large* a
cohort is. Neither of the last two columns is wrong as arithmetic, and each
answers a well-defined question. Our reading is that if the question is
"what is the average effect for treated units," only the first column
answers it regardless of how the sample arrived.

## Speed

We should say up front that on an ordinary balanced panel (at ordinary
sizes) every command in this comparison is fast enough for real work. The
differences start to matter once you bootstrap or iterate over
specifications. However, at the sizes and designs in the lower rows of these
tables they matter a great deal. Every cell below is the median of 10 timed
runs with one discarded warmup (the first `csdid` call in a session pays a
one-time library load that no later call pays), with event-study estimation
and clustered standard errors throughout, and with cells labeled by the
design (units n, periods T, cohorts G) and the row count derived from them.
A dash marks a cell without a measured time, and the note says why.

### A balanced panel, and what the default costs

The commands' own defaults differ in how much inference they buy. These two
columns are the same `csdid` estimation run twice: once with pointwise
analytical standard errors, and once with the shipped default of 999
multiplier-bootstrap draws with simultaneous confidence bands (the macOS
accelerator that ships with the package is active; every other platform
computes identical numbers in Mata).

| n (T=10, G=4) | rows | analytical | full default: 999 draws + uniform bands |
| --- | ---: | ---: | ---: |
| 100 | 1,000 | 0.01 | 0.04 |
| 1,000 | 10,000 | 0.04 | 0.07 |
| 10,000 | 100,000 | 0.26 | 0.32 |
| 100,000 | 1,000,000 | 1.80 | **2.38** |

The premium for complete inference shrinks with size (32% at a million
rows), and the full default is still faster than any rival's *pointwise
analytical* time at that size. Complete inference costs about half a second
per million rows here. These times depend on the machine and on the Stata
version, so the comparison between columns is more portable than the levels
are.

### Unbalanced panels

Fifteen percent of rows deleted at random from balanced panels. All three
`bal()` modes are shown, because they are three different estimands whose
speeds are comparable to the rivals' but not to each other. `bal(none)`
keeps every observation (the way the other commands do). That is the
apples-to-apples column. `bal(pair)` balances each 2x2 comparison
separately (Version 1.82's estimand, available on request). `bal(full)`,
the default, is fastest because it drops the units not observed in every
period before estimating, so its speed comes from a smaller (and disclosed)
sample and not from a faster algorithm. We keep it in the table for
completeness because it is what users get if they say nothing, and its time should be
read as the time for the default's sample, not as `csdid` outrunning the
field.

| n (T=10, G=4) | rows | `csdid bal(none)` | `csdid bal(pair)` | `csdid bal(full)` | `jwdid` | `lpdid` | `did_imputation` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 8,500 | 0.10 | 0.04 | 0.02 | 0.20 | 0.32 | 0.57 |
| 10,000 | 85,000 | 0.69 | 0.29 | 0.11 | 0.70 | 0.85 | 3.85 |
| 100,000 | 850,000 | **3.79** | 2.07 | 0.89 | 6.28 | 5.83 | 38.0 |

### Repeated cross sections

The next table reports times with and without one covariate, at each
command's documented covariate specification.

| n per period (T=10, G=4) | rows | `csdid` | `flexdid` | `jwdid` | `did_imputation` |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 10,000 | 0.12 | 0.19 | 0.16 | 0.24 |
| 10,000 | 100,000 | 0.86 | 0.71 | 0.76 | 1.48 |
| 100,000 | 1,000,000 | 5.56 | 5.53 | 7.22 | 20.9 |
| with a covariate: | | | | | |
| 1,000 | 10,000 | 0.18 | 0.33 | 0.35 | 0.27 |
| 10,000 | 100,000 | 1.18 | 1.03 | 1.74 | 1.58 |
| 100,000 | 1,000,000 | **6.70** | 7.41 | 17.96 | 21.5 |

`flexdid` holds a modest but genuine edge at the middle size without
covariates, and the million-row comparison without covariates is close to
a dead heat. Once the covariate is added, `csdid`
leads at the largest size, while `jwdid`'s time grows two and a half times
over its own no-covariate run. These are single-covariate designs, and we
don't extrapolate the ordering to specifications with many covariates.

### More periods, more cohorts

Design richness separates the architectures as sharply as sample size does.
We vary the number of periods first, holding n = 10,000 fixed.

| T (n=10,000, G=4) | rows | `csdid` | `jwdid` | `lpdid` | `did_imputation` |
| --- | ---: | ---: | ---: | ---: | ---: |
| 5 | 50,000 | 0.13 | 0.26 | 0.55 | 1.44 |
| 10 | 100,000 | 0.26 | 0.67 | 1.05 | 3.44 |
| 20 | 200,000 | 0.52 | 2.76 | 1.92 | 8.99 |
| 40 | 400,000 | **1.07** | 12.1 | 3.66 | 20.0 |

`csdid` scales linearly in T while `jwdid` does not (at forty periods the
gap is 11x, and `did_imputation`'s is 19x). In long panels the difference
is large enough to constrain how many specifications a researcher can
afford to run. Cohorts are milder for everyone: from G=3 to G=18 at 200,000
rows, `csdid` goes 0.45s to 1.52s (there are simply more cells to estimate
and report), and it stays about 4x ahead of the field throughout.

Aggregation is not in these numbers because `estat event` takes a fraction
of a second after any of these estimations (a table would add nothing). The
comparison against `csdid` Version 1.82, where the gains run from 16x to
208x depending on the design, has its own page:
[Speed against Version 1.82](speed-vs-182.html).

## Reliability, part I: no covariates

We simulate one population (three treated cohorts of equal size plus a
never-treated group, with effects of 2.0, 2.5, and 3.0 at event times 0, 1,
and 2) and vary only *how the sample arrives* from one setting to the
next. Nothing in this section
involves covariates, which is deliberate, because the estimand question
already bites with the cleanest data you are ever likely to see.

### A balanced panel

Let's start with the cleanest case of all. Every command runs on this
design, and all of them except `lpdid` agree with the target.

| estimator | bias at e=0 | 95% coverage |
| --- | ---: | ---: |
| `csdid` | +0.005 | 0.96 |
| `jwdid` | +0.005 | 0.96 |
| `did_imputation` | +0.005 | 0.96 |
| `did_multiplegt_dyn` | +0.005 | 0.95 |
| `lpdid` | **-0.13** | **0.53** |

`lpdid` is off by 6.5% of the true effect on a perfectly balanced panel
(with nothing exotic in it). The number is neither a bug nor sampling
noise (the bias is the same at n = 4,000). It is what effective-sample-size
weighting does: later cohorts get less weight (because earlier cohorts are
no longer clean comparisons), so the reported event study averages a
different mix of cohorts than the population has. Note that you do not need
missing data for the estimand question to matter, and none of this says
that the weights are the wrong answer to the question they do answer.

### Unequal sampling across periods

Next, we keep the same population but let the probability that an
observation is recorded vary by calendar period (think of survey waves of
different sizes). Nothing about treatment, outcomes, or composition
changes, and the stationarity condition of Callaway and Sant'Anna (2021,
Assumption B.1) holds exactly. What fails is the auxiliary condition that
every period contributes an equally sized cross-section.

| estimator | bias at e=0 | 95% coverage |
| --- | ---: | ---: |
| `csdid` (any `bal()` mode) | +0.003 | 0.95 |
| `jwdid` | -0.16 | 0.36 |
| `did_imputation` | -0.17 | 0.38 |
| `did_multiplegt_dyn` | -0.29 | 0.16 |
| `lpdid` | -0.40 | 0.02 |

Every observation-weighted estimator is now targeting a different quantity
(one that moves with the sampling), and its confidence intervals cover the
true effect between 2% and 38% of the time. `csdid` does not move, because
P(G=g) does not move. Restoring equal period sizes (ordinary uniform
missingness) brings the other estimators right back, so the mechanism is
the unequal weighting, not unbalancedness itself.

<div class="important" markdown="1">
In our view this is the most consequential table in the guide, and it
comes from a violation so mild that most applied descriptions of the data
would not even mention it.
</div>

### Repeated cross sections

With fresh samples each period and equal period sizes, the commands that
support repeated cross sections (`csdid` via `rcs`, `jwdid`,
`did_imputation` with group fixed effects, and `flexdid`, on its design
target and the one place it appears in our comparisons) are all fine. Once
the period sizes are unequal (which is entirely ordinary in survey data),
the drift returns, and this time it *flips sign across event times* instead
of merely growing with the horizon (-0.16 at e=0, +0.23 at e=2 for the
observation-weighted commands). The estimated
event study does not simply shift up or down; its shape bends toward
whatever the sampling did, so a reader would see effects "growing" that do
not grow. `csdid` reports 0.004 and 0.001 bias at those event times, with
nominal coverage, and its individual ATT(g,t) cells are within 0.02 of
their known truths in every one of the settings we ran.

`did_multiplegt_dyn` does not claim repeated cross-section support and
returns nothing here, and `lpdid` refuses to run at all. We prefer the
refusal (a command that stops is easier to deal with than one that returns
a number it cannot support).

### The transparency scorecard

Nothing in the next table is a simulation result. Each entry is a
documentation-verified statement about what a command reports and about how
it says it computes what it reports.

| | reports every ATT(g,t) | weights stated in closed form | target fixed under sampling | balance choice explicit | uniform bands |
| --- | --- | --- | --- | --- | --- |
| `csdid` | yes | yes | yes | yes (`bal()`, disclosed in `e(panel_mode)`) | yes |
| `jwdid` | recoverable from coefficients | no | no | no | no |
| `flexdid` | recoverable from coefficients | no | no | no | no |
| `did_imputation` | no | no | no | no (`autosample` decides) | no |
| `did_multiplegt_dyn` | no | no | no | no (imputes treatment paths) | no |
| `lpdid` | no | no | no | no | no |

`csdid` reports every ATT(g,t) cell with its standard error, states its
aggregation weights in closed form, discloses the resolved sample in
`e(panel_mode)`, and leaves the balancing rule (`bal()`) to you. Several of
the other commands never show the cells at all. Thus we treat
decomposability as a requirement: we cannot audit an estimator whose
output we cannot take apart. The
command whose cells are visible is also the one whose target did not move
in these tables, which we do not think is a coincidence (though that is a
judgment about how these commands were designed rather than a simulation
result).

## Reliability, part II: covariates, and the case for doubly robust

Now we add covariates: time-invariant unit characteristics (think of
gender, or of earnings in a year before the sample starts) whose
distribution differs across cohorts, and which shift both the level and the
trend of the untreated outcome. This is a conditional parallel trends
design, so the unconditional comparison is biased by construction and
everything turns on how a command handles the covariates. Treatment effects
still do not depend on the covariates (so the targets are the ones we
started with).

The first table takes a balanced panel with every model correctly specified
(500 reps, bias and coverage at e=0).

| estimator | bias | coverage |
| --- | ---: | ---: |
| `csdid dr` | +0.001 | 0.95 |
| `csdid ipw` | +0.004 | 0.95 |
| `csdid reg` | -0.001 | 0.95 |
| `jwdid` | +0.001 | 0.95 |
| `did_imputation` | +0.000 | 0.96 |
| `did_multiplegt_dyn` | **+0.119** | **0.61** |
| `lpdid` | **-0.139** | **0.46** |

Every command that handles covariates the way its own documentation
describes is fine here. The exception is `did_multiplegt_dyn` (SSC version
dated January 17, 2026, the current release as we write), whose bias drifts
with the horizon (reaching +0.88 by e=2), and the reason is not a defect in
the code but a covariate adjustment that answers a different question. Its
`controls()` option imposes parallel trends on outcomes residualized on the
first differences of the covariates (with a single coefficient common to
all groups and periods).

That is a different assumption from conditional parallel trends in Callaway
and Sant'Anna (2021), and it is more restrictive in two specific ways.
First, for time-invariant covariates (gender, race, baseline earnings, and
most of what applied researchers condition on in practice) the first
differences are zero, so the residualization leaves the unconditional
comparison unchanged and the condition collapses to unconditional parallel
trends, which is the assumption the covariates were brought in to relax.
Second, giving every group and period one common coefficient
restricts how covariates may shift trends heterogeneously across cohorts,
which is the heterogeneity that conditional parallel trends is there to
allow. Note that this literature began from the observation that imposing
homogeneity on treatment effects breaks TWFE, and this covariate scheme
re-imposes homogeneity one layer down (on the covariate coefficients rather
than on the effects).

On its own terms (genuinely time-varying covariates whose effect on trends
really is common across cohorts) the approach works, and our experiments
confirm that it works. Those terms are narrow, though, and they are not the
terms that most applied covariate stories satisfy. The documentation offers
`trends_nonparam()`, which does exact matching on discrete covariates, as
the route for time-invariant characteristics; matching on our binary
covariate removes its share of the drift (+0.88 falls to +0.66 at e=2), and
continuous covariates are outside that option's scope. Conditional parallel
trends as in Callaway and Sant'Anna (2021) asks for none of this, since the
trend may depend on the covariates flexibly and heterogeneously, and
`csdid`'s doubly robust estimator conditions on the covariates themselves
(which is why its column of this table is clean).

The covariates also change nothing about the conclusion of Part I.
Rerunning the repeated-cross-section comparison with the covariates
included, `csdid dr` stays on target in both sampling regimes while the
regression-style estimators reproduce their unequal-period drift,
covariates and all, so adjusting for covariates does not repair a weighting
scheme.

We prefer `dr` among the three `csdid` methods, even where all three are
clean, because correct specification is not something a researcher gets
to assume. The doubly robust estimator (Sant'Anna and Zhao, 2020) is
consistent if *either* the outcome model *or* the treatment-probability
model is correctly specified, which gives two chances instead of one at no
speed cost (see the Speed section above) and, in these simulations, at no
precision cost either. Every other command in this comparison is an
outcome-regression estimator, and so gets one chance at the specification.

Let's break the models on purpose then, one at a time, using the same
population and the same targets as above. Take the outcome model first, and
add a nonlinear term to the untreated trend (it now depends on the square
of the continuous covariate) while every estimator keeps conditioning on
the covariates in levels. This is the case where the outcome model the
researcher wrote down is wrong, and it is not an exotic case. Bias and
coverage at e=1 are as follows.

| estimator | bias | coverage |
| --- | ---: | ---: |
| `csdid dr` | -0.058 | 0.94 |
| `csdid ipw` | -0.054 | 0.93 |
| `csdid reg` | **+0.300** | **0.46** |
| `jwdid` | **+0.490** | **0.26** |
| `did_imputation` | **+0.189** | **0.72** |
| `did_multiplegt_dyn` | **+0.303** | **0.22** |
| `lpdid` | **-0.162** | **0.68** |

(`did_multiplegt_dyn` and `lpdid` arrive at this cell already carrying
their correctly-specified-cell biases; the misspecification compounds on
top.)

Every outcome-regression command breaks together, and the bias grows with
the horizon (`jwdid` reaches +0.67 by e=2, with coverage 0.29). This is not
a defect in any one implementation; it is the same wrong outcome model
failing everywhere it is the only line of defense. The two `csdid`
estimators that do not rely on it remain consistent here: `ipw` because the
treatment-probability model is still correct, and `dr` because one correct
model is all it requires.

<div class="tip" markdown="1">
We think of that second chance as basic insurance, and no other command in
this comparison offers it.
</div>

Next, the propensity score. Our first attempt at this cell is worth
reporting because it failed: we made cohorts differ in the *spread* of the
continuous covariate (a logit linear in X can't represent that) and nothing
broke, `ipw` included. The reason is instructive. A fitted logit projects
the selection it can see onto the covariates you gave it, so the error that
the misspecification leaves behind is close to orthogonal to anything
linear in those covariates, and our trend here is linear in them by
construction. An error
orthogonal to the trend has nothing to load on. We read this as a caution
about misspecification experiments in general, in that they teach you
something only when the error is aimed at the target.

In the redesigned cell, selection is driven by a latent index, and the
covariate the researcher observes is a nonlinear (exponential) transform of
that index, which is the same device used in Sant'Anna and Zhao (2020). The
true propensity score is then a logit in the *log* of the observed
covariate, the fitted logit in the covariate itself is genuinely wrong, and
(because the observed covariate is skewed) the error loads on the trend.
The outcome stays linear in what the researcher observes, so every outcome
model remains correct and only the treatment-probability model is broken.
Bias and coverage at e=1 are as follows.

| estimator | bias | coverage |
| --- | ---: | ---: |
| `csdid dr` | +0.001 | 0.95 |
| `csdid ipw` | **-0.094** | 0.97 |
| `csdid reg` | -0.001 | 0.95 |
| `jwdid` | +0.001 | 0.92 |
| `did_imputation` | +0.002 | 0.93 |
| `did_multiplegt_dyn` | **+0.229** | **0.28** |
| `lpdid` | **-0.112** | **0.66** |

(As before, `did_multiplegt_dyn` and `lpdid` carry their
correctly-specified-cell biases into this one.)

The outcome-regression commands are fine here, since a wrong propensity
score is invisible to an estimator that never uses one. What moves is
inside `csdid`: `ipw`'s bias grows with the horizon (−0.04, −0.09, −0.14)
and concentrates where the propensity score does the most work. In the
ATT(5,6) cell, where the never-treated are the only comparison left, `ipw`
is off by −0.23 *and* pays more than twice `dr`'s standard error (0.35
against 0.16). The wrong weights cost it twice (in location and in spread),
and those wide intervals are also why its coverage does not collapse the
way `reg`'s did in the outcome cell. `dr` pays neither price here, because
it still has one correctly specified model in hand.

One more thing happened in this cell, and we regard it as a feature: in 36
of the 500 draws, `csdid` refused to estimate the worst-overlap cell at all
and printed the overlap violation it found. The reported `ipw` and `dr` rows
condition on the draws that passed that check, which, if
anything, flatters `ipw`, since the refused draws are the ones where its
weights are most extreme. No other command in this comparison performs such
a check.

Reading the two sabotage cells together, `dr` is the only estimator here
that stays consistent in both of them: with a wrong outcome model, every
outcome-regression command is biased and `dr` is not, and with a wrong
propensity score, `ipw` drifts and `dr` is again unaffected. Every other
command in the comparison relies on a single model, so whether it is
consistent depends on whether that model happens to be the broken one. We
recommend `dr` as the default for that reason (double robustness buys
protection against one wrong model, and it does not cover both being wrong
at once).

## Precision

Where the targets coincide (a balanced panel with no covariates), comparing
spread is fair. Which estimator is more precise, though, is not a fact
about the estimators; it is a fact about the error process, and one
simulation setting cannot settle it. We therefore ran two. The population
and the 500 draws are the same in both, and only the within-unit error
process changes.

| errors | `csdid` sd | `jwdid`/`did_imputation` sd | tighter |
| --- | ---: | ---: | --- |
| iid | 0.067 | 0.052 | poolers, by ~22% |
| unit root | 0.047 | 0.062 | **`csdid`, by ~25%** |

With iid errors, pooling every pre-period is close to the right thing to do
and the Wooldridge/imputation estimators are tighter (as theory predicts).
With unit-root errors (each unit's shocks accumulate, which is what much
real panel data looks like), the ranking reverses and base-period
differencing wins by about the same margin. We would therefore not report a
precision ranking without saying which error process produced it. Every
estimator remains unbiased in both settings, and only the variances move.
`lpdid` is biased in both (for the same weighting reason as above), and no
error process repairs that, which is also why it has no row in a table
about precision.

The general statement is in Chen, Sant'Anna, and Xie (2025): the efficient
estimator for these designs depends on the covariance structure of the
outcomes, and none of the packaged estimators (ours included, in either
error world) attains the semiparametric efficiency bound in general. We
would therefore read any cross-package standard-error comparison that does
not state the error process as a statement about the setting that was
chosen, not about the estimators.

## Simultaneous inference

An event study is a family of estimates, and the interval that matters is
the one that covers the whole path at once. `csdid` reports uniform
confidence bands from the multiplier bootstrap by default, and no other
command in this comparison offers a band option at all. The next table
shows what that is worth on the balanced panel with three post-treatment
event times.

| | joint coverage of ES(0), ES(1), ES(2) |
| --- | ---: |
| `csdid` uniform band | **0.966** |
| `csdid` three pointwise CIs | 0.908 |
| `jwdid` / `did_imputation` pointwise | 0.888 |
| `did_multiplegt_dyn` pointwise | 0.862 |
| `lpdid` pointwise | 0.444 |

Reading three pointwise 95% intervals as if they jointly covered the path
already costs 4 to 9 points of coverage among the unbiased estimators
(`lpdid`'s 0.444 is mostly its bias, not its intervals), and with the ten
or fifteen event times of a typical application the arithmetic only gets
worse. We recommend reporting the uniform band whenever the figure will be
read as a statement about the whole path, since that is the interval whose
stated coverage matches the way a plotted band is usually read. Note that
the band is wider than the pointwise intervals by construction, so it is
not a free improvement.

## Reproducing everything

Every table above is generated by a script with a fixed seed, with package
versions pinned to their current SSC releases, and with population targets
computed once, by hand, from the data-generating process (never re-derived
from a draw). Every script is in the
[code appendix](../code-appendix.html), ready to run. Note that a fixed seed
makes our numbers reproducible, and it does not make them general beyond
the designs we chose to simulate.

## What we take from this

The experiment was six commands run against one simulated population, with
the population targets computed in advance and held fixed throughout. We
want to be clear about what it did and did not show.

It did not show that anyone else's software is broken. Every command in
this comparison was written by researchers whose work moved this
literature forward, and the differences we measured are not bugs; they are
design choices (made in the open, by people who understood them) that
answer slightly different questions.

What the tables do show is that "slightly different questions" stops being
a small difference as soon as the data are less than ideal. Holding the
population fixed and changing only how the sample arrives, commands that
mostly agree on a balanced panel separate by whole coverage points, because
their targets travel with the sample while the truth does not. Break one
model and every estimator that relies on a single model breaks with it,
while the doubly robust default in this comparison still has a second model
to fall back on. Read pointwise intervals as if they were a band and the
plotted figure claims more certainty than the estimates support. A reader
looking only at a printed table would see none of those three failures.
That is why we built `csdid` to report the things that would reveal them: a
target fixed in the population, every ATT(g,t) cell with its own standard
error, aggregation weights in closed form, sample decisions disclosed in
`e()`, overlap failures printed rather than absorbed, and uniform bands
whose stated coverage applies to the whole path. Speed matters here because
the reporting has to be cheap enough to leave switched on by default.

We recommend judging any of these commands by whether its output can be
taken apart and recomputed, which is the standard we tried to hold `csdid`
to, and the tables above are what came of trying. `csdid` does come out
ahead in most of them, though the reason we are showing them is that every
number in them can be recomputed from a seed by anyone, including the
numbers where `csdid` loses. Note that none of this establishes that
`csdid` is the right command for any particular application: these are
simulations from designs we chose, and a design we did not simulate can
reverse any ranking on this page.
