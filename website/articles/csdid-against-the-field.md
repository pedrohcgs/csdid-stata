---
title: "How csdid compares with other DiD Stata commands"
permalink: /articles/comparing-did-commands.html
math: true
---
# How csdid compares with other DiD Stata commands

We are living in a time where applied econometrics papers are commonly paired with Stata, R, or Python packages. On one hand, this is really great, as it substantially lowers the barrier to using modern econometric methods in concrete applications. Everything else equal, we all like fast and reliable implementations of econometrics papers. On the other hand, when multiple packages implementing related procedures are available, one may be tempted to try several of them, perhaps without going back to the original papers. This is where we enter some potentially dangerous territory. At the end of the day, do these different estimators even target the same causal parameter? Do they reflect similar notions of uncertainty to warrant comparisons in precision? These questions are very important for econometric theory and practice, as they can lead to never-ending discussions.

When it comes to Difference-in-Differences (DiD), this is perhaps even more interesting and important, as DiD is arguably the most popular observational causal inference method in economics; [see here for some evidence](https://paulgp.com/econlit-pipeline/paper.html). In recent years we have seen a boom of modern DiD tools aimed at allowing for richer notions of heterogeneity than standard two-way fixed effects specifications, each paired with a companion Stata command: [Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001) with `csdid` (this package), [Wooldridge (2025)](https://doi.org/10.1007/s00181-025-02807-z) with `jwdid`, [Borusyak, Jaravel, and Spiess (2024)](https://doi.org/10.1093/restud/rdae007) with `did_imputation`, de Chaisemartin and D'Haultfœuille ([2020](https://doi.org/10.1257/aer.20181169), [2026](https://doi.org/10.1162/rest_a_01414)) with `did_multiplegt_dyn`, [Dube et al. (2025)](https://doi.org/10.1002/jae.70000) with `lpdid`, [Sun and Abraham (2021)](https://doi.org/10.1016/j.jeconom.2020.09.006) with `eventstudyinteract`, and [Deb et al. (2026)](https://www.nber.org/papers/w33026) with `flexdid`, among others. For someone who has not been breathing the DiD literature every day, it is tempting to treat these packages as interchangeable ways to obtain "the" event study. But, as we discuss in this article, that is not always the case. Our main goal here is to compare what each command estimates and how it conducts inference. To that end, we use simulations that you can reproduce line by line. We focus **exclusively** on binary treatments and staggered designs here. Stata itself also ships official commands for this setting, `xthdidregress` for panels and `hdidregress` for repeated cross sections, and we include them too: they are the commands a user reaches for without installing anything, so leaving them out would misrepresent the choice actually facing an applied researcher. The statistical comparisons use `csdid` 2.0.1 and the official commands shipped with StataNow/MP 19.5. The speed comparisons use `csdid` 2.0.3, measured on 31 October 2026. Each campaign records the installed versions of the other commands and holds them fixed throughout. For simplicity, we assume that (conditional) parallel trends hold in all periods and across all groups, and covariates are time-invariant (but their effects can be time-varying). We note that in this setting, none of these procedures we discuss is semiparametrically efficient [Chen, Sant'Anna, Xie (2025)](https://psantanna.com/files/Efficient_DiD.pdf).

To summarize our findings (as this is not a mystery novel), it is worth pinpointing some broader cases:

- ***Balanced panel data without covariates***: most of the point estimates agree across packages, though their standard errors may differ even when the point estimates are the same. This can happen because some procedures treat the treatment group as fixed rather than random. Following [Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001), `csdid` treats cohort membership as random, so uncertainty in the estimated cohort shares enters its standard errors; `eventstudyinteract` makes the same choice, and accounts for the sampling uncertainty of its estimated cohort shares. Most other packages condition on treatment assignments, or deliberately report conservative standard errors when treatment effects are heterogeneous, as `did_imputation` documents. When it comes to point estimates, a notable exception is the `lpdid` package: by default it targets a different type of event study (ES) aggregation, therefore producing an inconsistent (and biased) estimate for the ES parameter as discussed in [Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001) (and many others). By using its `rw` option, though, one can request to bypass this concern and target the same parameter.
- ***Unbalanced panel without covariates***: by default, packages do not agree on the (population) weights used to aggregate ATT(g,t)'s into ES parameters, so they are often not even targeting the same parameter. This, per se, makes comparison across methods delicate. What reconciles several of these targets is not unbalancedness being random per se, as the missingness never depends on cohort, covariates, or potential outcomes in our simulations. It is an auxiliary (strong) condition that the missingness rate is the same in all periods, so that each period contributes an equally sized cross-section. We also note that packages behave differently in how they handle unbalanced panels: what they drop, what they keep, and &mdash; for the commands that take a treatment indicator rather than a cohort variable &mdash; whether missing rows silently change which cohort a unit belongs to. We document all of this, with seeded diagnostics, in [What a missing row does to each command](#what-a-missing-row-does-to-each-command).
- ***Repeated cross-sectional data***: Some packages such as `eventstudyinteract`, `did_multiplegt_dyn`, and `lpdid` do not accommodate this sampling scheme. Others, such as `flexdid`, are built mainly targeting this case. Among those procedures that can handle it, `jwdid`, `did_imputation`, and `flexdid` share one aggregation scheme and `csdid` another, so they do not generally target the same ES parameter. As in the unbalanced panel data case, comparability is restored by the same auxiliary condition: that every period contributes an equally sized cross-section.
- ***The role of covariates***: Not all packages accommodate general heterogeneous treatment effects with respect to covariates, or covariate-specific trends in untreated outcomes. `csdid`, `jwdid`, `flexdid`, and `did_imputation` allow for that. `did_multiplegt_dyn` relies on a different parallel trends assumption, based on outcomes residualized on the *first differences* of the covariates in a linear model, with the covariate coefficient fixed across cohorts and periods. What that assumption rules out can be practically important: any role for time-invariant covariates, which first differencing annihilates; covariate effects on untreated trends that differ across periods, since a single coefficient is imposed across them; and continuous covariates, which the documented fallback `trends_nonparam()` cannot match on at all. `lpdid` and `eventstudyinteract` impose an additional separability condition between covariates and cohorts, too, and are not suitable to capture richer notions of heterogeneity. In [One design that tells them apart](#one-design-that-tells-them-apart) we construct a single balanced panel data generating process, with conditional parallel trends holding exactly, in which all of these restrictions bind at once.
- ***Speed***: `csdid` tends to be faster than the other packages in most of our designs, though sometimes (but definitely not always) the differences are in the milliseconds. The gains depend on the number of observations, cohorts, and time periods, as well as on whether the panel is balanced or not. Speed is nice, of course, but we emphasize that being clear about target parameters and sources of uncertainty matters more.

One aspect we would like to make clear is that, in our view, target parameters need to be defined ex ante, and ideally should not depend on the sampling scheme. We view target parameters as "ideals": what we would like to know if all the data in the world were available.

Before diving into any details, here is a picture of what is at stake. We
take one of the simpler designs from this article &mdash; same population,
no covariates, but survey waves of different sizes across periods &mdash;
and run the six plotted commands, under the benchmark settings, on the same
500 simulated samples. Here `csdid` uses analytical inference and `bal(none)`. The left panel shows where each
command's event-study estimates at e=0 land relative to the population
target; the right panel shows whether their 95% confidence intervals cover
it.

![Ridge densities of event-study estimates and zipper plots of confidence intervals for six DiD commands under unequal period sampling; csdid is centered on the truth with 95% coverage, while the other five commands are biased with coverage between 2% and 51%](../assets/img/field-hero-varmiss.png)

Nothing about the population changed across these commands; they simply do
not target the same parameter, and some targets move with the sampling
scheme while others do not. Some of these commands have options to address the estimand part, though, to address something, you first need to be aware! So we are trying to make people aware here. The rest of this article digs more into these issues by discussing
[what each command computes](#what-each-command-is-actually-computing), how
the aggregation weights differ, and
[what happens across sampling schemes](#reliability-part-i-no-covariates).

Another aspect that we want to mention is related to speed: `csdid` tends to be very fast, and scales well with different aspects of the data.

![Comparing run time across different Stata DiD estimators](../assets/img/field-speed.png)

The [Speed section](#speed) discusses more about these run time differences, in multiple settings.

## Some Monte Carlo details
The main Monte Carlo settings start with 1,000 panel units, seven periods,
and 500 simulation draws. The repeated-cross-section designs instead use
7,000 distinct individuals, averaging 1,000 observations per period. When we deviate from this setting, such as when we compare speed across packages, we document it clearly.

In our simulations about DiD setups without covariates, discussions about precision and simultaneous inference, we have a more plain DGP, in which untreated outcomes are

$$Y_{it}(0) \;=\; \mu_i + 0.3\,t + \varepsilon_{it},$$

with unit effects and errors drawn from independent standard normal distributions. We consider four
equally sized groups, with cohorts first treated at $$g \in \{3,4,5\}$$ as the "eventually-treated" cohorts and a
never-treated group. In our baseline simulations, treatment effects for each cohort $$g$$ at time $$t$$ are given by $$\tau(g,t) = (g-2) + 0.5\,(t-g)$$, so the building
blocks are $$ATT(g,\,g+e) = (g-2) + 0.5\,e$$ and the
event-study targets are exactly 2.0, 2.5, and 3.0 at $$e = 0, 1, 2$$. Note that, here, we impose homogeneous treatment effect dynamics (with different jumps at $$e=0$$), and that parallel trends hold in all periods. In fact, in all our simulations, parallel trends will hold in all periods, though sometimes it requires you to condition on covariates and allow for covariate-specific trends.

The baseline and combined-design simulations assign cohort membership
deterministically, with equal cohort counts in every draw. Outcomes and, where
included, covariates are redrawn within these fixed cohorts. Randomly drawing
cohort membership would still leave the population target fixed; it would add
sampling variation in cohort counts. Our stratified design excludes that source
of variation, so unconditional variance formulas that include estimated-cohort-share
uncertainty can exceed the Monte Carlo variance for this reason. The panel
comparisons use unit-level variance or clustering, without a coarser cluster.
Coverage and standard-error ratios therefore describe this sampling design;
they do not establish a general ranking of inferential validity.

In some sections, especially when we want to stress the role of some aspects of the estimators, e.g. how they handle covariates, we modify the DGPs and discuss how we do it. We want to be very explicit that our simulations here are designed to be pedagogical, so we can highlight what happens with different procedures when some aspects of the DGP change. We make these modifications so the results change loudly and we can report them clearly in tables and plots. In concrete empirical applications, these differences may be more nuanced, but, hey, we don't control the environment there! So, again, the value of our exercises is to make clear the differences between DiD procedures implemented in Stata.

<nav class="toc">
<div class="toc-title">Contents</div>
<ul>
<li><a href="#what-each-command-is-actually-computing">The command map</a></li>
<li><a href="#speed">Speed</a></li>
<li><a href="#reliability-part-i-no-covariates">Reliability I — no covariates</a></li>
<li><a href="#what-a-missing-row-does-to-each-command">Missing rows</a></li>
<li><a href="#reliability-part-ii-covariates-and-the-case-for-doubly-robust">Reliability II — covariates and DR</a></li>
<li><a href="#one-design-that-tells-them-apart">One design that tells them apart</a></li>
<li><a href="#precision">Precision</a></li>
<li><a href="#simultaneous-inference">Simultaneous inference</a></li>
<li><a href="#reproducing-everything">Reproducing everything</a></li>
<li><a href="#what-we-take-from-this">What we take from this</a></li>
</ul>
</nav>

## What each command is actually computing

We start the discussion by trying to understand better what each command computes. This is something that we view as first-order important, and it is not something we can always settle by reading the documentation and the papers. Sometimes, software evolves, and we start covering cases that we did not fully discuss in the paper---this often arises as users request new use-cases to cover their specific setting. So, with time, there is some natural drifting. However, most users do not follow the nitty-gritty details of everything, and end up comparing different implementations, believing they are actually comparable. But guess what, this is not always the case.

In this section, we take stock and try to tackle this relevant problem. We prefer to use numerical exercises rather than detailed statistical derivations. More precisely, we run several controlled simulations, changing one feature of the design at a time and checking the numbers against what each procedure warrants, and add some explanations to justify/rationalize the findings. This sometimes involves reverse-engineering code, cross-checking papers, and the like. But it turns out to be fun to do, and we hope it is useful to you!

Before contrasting the alternatives, we should be explicit about our own benchmark. Following [Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001), `csdid` first estimates the average treatment effect for each group (or cohort; we use the terms interchangeably) that started treatment at period *g* at each period *t* &mdash; the ATT(*g*,*t*) &mdash; from a two-by-two comparison: group *g*'s outcome change from its base period (g-1) to *t*, against the same change among units not yet treated at *t* (the default; `nevertreated` restricts the comparison to never-treated units). Our procedures (flexibly) accommodate covariates via outcome regression, inverse probability weighting, or the doubly robust combination of the two (the default in our package). These ATT(*g*,*t*)'s are the building blocks of the analysis: every other parameter `csdid` reports, including all the event studies, is a weighted average of these ATT(*g*,*t*)'s, with weights given by estimated cohort shares.

The rest of this article covers each of these choices in detail and how different commands differ from ours. As one can foresee, some important dimensions include the choice of the comparison group, the base period used, how one incorporates covariates (and how flexible this is), the aggregation weights used to construct event study aggregations, what variables are treated as random and fixed, among others.

**Building blocks.** Every command here builds its event study from
group-time comparisons of a treated cohort with its untreated counterfactual, and the
commands fall into two camps in how they construct that counterfactual. First, let's talk about the baseline period used. `csdid`, `did_multiplegt_dyn`, `lpdid`, and `eventstudyinteract` compare each cohort with its base period, the period just before treatment. `jwdid` and `did_imputation`, on the other hand, do something
different: they use all untreated observations to fit unit and time
fixed effects, and then impute Y(0) from that fit. This is done in a "literal" sense in the `did_imputation` package, while `jwdid` uses parsimonious regressions with multiple interactions to arrive there. It is worth being explicit about what this implies for the comparison group and the base period: both `did_imputation` and `jwdid` use every untreated observation as part of their comparison group, and use all pre-treatment periods as valid baseline periods, too. This involves some trade-offs, and we return to this later. The default specification of `flexdid` follows a similar route as `jwdid`, but as it implements the estimator of [Deb, Norton, Wooldridge, and Zabel (2026)](https://www.nber.org/papers/w33026), developed for repeated cross-sections, we include it only in those
comparisons. In the balanced-panel simulations below, the largest absolute point-estimate gaps between `jwdid` and `did_imputation` are 8.58e-08 without covariates and 1.44e-07 in the linear-outcome covariate design. Their standard errors reflect different sources of uncertainty, as we discuss below.

`eventstudyinteract` is the one command here that, in setups with a balanced panel and no covariates, agrees with `csdid`
exactly rather than approximately. It implements the interaction-weighted
estimator of [Sun and Abraham (2021)](https://doi.org/10.1016/j.jeconom.2020.09.006),
which shares `csdid`'s logic:
cohort-by-cohort estimates averaged with estimated cohort shares, and the
sampling uncertainty of those shares carried into the standard errors. On a
balanced panel with the `nevertreated` comparison group and no covariates,
the two returned identical point estimates to eight decimal places. When covariates are used, or the data is an unbalanced panel, though, `csdid` and `eventstudyinteract` stop agreeing with each other. Essentially, `eventstudyinteract` leverages covariates in a linear fashion, without interacting the group indicators, which can restrict treatment effect heterogeneity---`csdid`, on the other hand, considers more flexible adjustments, and, therefore, can capture richer notions of heterogeneity; in the design of Part II below, we show the bias of `eventstudyinteract` estimates grows from +0.29 at e=0 to +0.88 at e=2 with coverage of zero, while `csdid` remains unbiased and with solid inference properties. We also show that the weights used by `eventstudyinteract` to aggregate the ATT(*g*,*t*)'s into event study summary parameters vary depending on whether the data is a balanced or unbalanced panel. These are interesting findings, as [Sun and Abraham (2021)](https://doi.org/10.1016/j.jeconom.2020.09.006) establish the validity of their interaction-weighted estimators only for balanced panel data without covariates, a boundary the command's own help file is admirably candid about.

`did_multiplegt_dyn` is another interesting comparison for `csdid`. The
command implements the estimators of de Chaisemartin and D'Haultfœuille
([2020](https://doi.org/10.1257/aer.20181169), [2026](https://doi.org/10.1162/rest_a_01414)), which are built for different problems than the one we study here:
treatments that may turn on and off, for example. In our staggered setup, though, they share similarities. In the balanced-panel simulations without covariates, the largest absolute point-estimate gap between `csdid` and `did_multiplegt_dyn` is 1.11e-07. Both use not-yet-treated comparison units and anchor the baseline at g-1. The standard errors of these procedures do not agree, but we will discuss this more below. With unbalanced panels (and no covariates), though, this equivalence breaks down, as `did_multiplegt_dyn`'s event-study aggregation weights groups by the number of treated observations available at each horizon rather than by cohort
shares, as we do in `csdid`. The way `did_multiplegt_dyn` handles covariates also differs from ours, as their adjustment rests on a parallel trends assumption
for outcomes residualized on the *first differences* of the covariates, with
one coefficient shared by all cohorts and periods. We view this alternative parallel trends assumption as restrictive and not very natural when one wants to embrace heterogeneity in DiD settings; we discuss this further in Part II below.

**What each command treats as random.** As we mentioned above, some commands
agree on point estimates but not on standard errors. This deserves some
discussion, as it matters in practice. In the separate 50,000-unit heterogeneous-effects draw, the largest absolute
point-estimate gap between `jwdid` and `did_imputation` is 6.59e-09. When treatment
effects vary with covariates, `did_imputation` reports standard errors that
are deliberately conservative under this type of heterogeneity, while
`jwdid` reports conventional sampling-based inference. In a simulation with n = 50,000 and treatment effects that vary with covariates, the difference between them grew from 11% at event time 0 to 55% at event time 2. Here, we stress that one should not say that `jwdid` is "more precise" than `did_imputation`. Well, they have the same point estimates but differ on the type of uncertainty they reflect! By default, both commands treat the covariates and the cohort indicators as fixed; `jwdid`, however, allows you to account for the sampling uncertainty associated with them (use the `vce(unconditional)` option in its `estat` commands, for example), while `did_imputation` does not offer this option. Again, [Borusyak, Jaravel, and Spiess (2024)](https://doi.org/10.1093/restud/rdae007) are clear about the peculiarities of their inference procedures, but we are unsure if practitioners are fully aware. If we were to choose between `jwdid` and `did_imputation`, we would lean towards `jwdid`, as its inference options let you match the uncertainty statement to the sampling scheme.

Something similar happens with `csdid` and `did_multiplegt_dyn`. In the separate 20,000-unit balanced-panel diagnostic, the maximum absolute
point-estimate gap is 8.67e-08, while the standard errors differ by
about 8&ndash;10% in the example we report in the code appendix. Why?
Because they do not treat the same things as random. Following
[Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001),
`csdid` treats cohort membership as random, so uncertainty in the estimated
cohort shares enters its standard errors. The same is true for covariates. `did_multiplegt_dyn`, on the other hand, conditions on the realized cohort membership rather than carrying that share-estimation term. Conditional inference need not assert that treatment timing could never have been random; it conditions on the assignment observed. These different variance constructions are documented in de Chaisemartin and D'Haultfœuille ([2020](https://doi.org/10.1257/aer.20181169), [2026](https://doi.org/10.1162/rest_a_01414)) and [Callaway and Sant'Anna (2021)](https://doi.org/10.1016/j.jeconom.2020.12.001). Both commands use unit-level uncertainty in this diagnostic. Because its cohort counts are fixed, the standard-error gap alone does not determine which construction would give better inference under a different sampling scheme.

**Aggregation.** One dimension from our list above that we have only
touched in passing is the aggregation weights. Every summary parameter these
commands report is a weighted average of the
ATT(g,t) building blocks; the weights, however, differ across commands. We focus on event study aggregations as they are arguably the most popular ones:

<p class="table-title" markdown="span">Event-study aggregation weights, by command</p>

| command                                                    | a cohort's weight at event time e | the weight moves when...    |
| ------------------------------------------------------------ | ----------------------------------- | ----------------------------- |
| `csdid`                                                    | its population share, P(G=g \| G+e ∈ [1,T]) | the population changes      |
| `jwdid`, `did_imputation`, `did_multiplegt_dyn`, `flexdid` | its treated observations at e: P(G=g \| G+e ∈ [1,T], S<sub>G+e</sub>=1) | the sampling changes        |
| `lpdid`                                                    | its effective 2x2 sample size (no population formula) | the adoption *order* changes |
| `eventstudyinteract`                                       | its estimated cohort share at e: P(G=g \| G+e ∈ [1,T], S<sub>G+e</sub>=1) | the period sizes change     |

Here, S<sub>t</sub> is an indicator for a unit being observed in period t;
we unpack all of this notation in the rest of this section. Note that
`lpdid` is the one row without a population formula, and this is not an
oversight on our part &mdash; we discuss why below.

For `csdid`, the weights come from writing
the target parameter as an expectation, that is, the event study parameter at horizon
$$e$$ is given by

$$\mathrm{ES}(e) \;=\; E\big[\, ATT(G, G+e) \,\big|\, G+e \in [1,T] \,\big],$$

i.e., the average of the group-time effects over the distribution of
the cohort variable $$G$$, among treated units whose horizon-$$e$$ effect
is inside our study window [1,T]. Here, note that once the building blocks ATT(g,t) are given, aggregation is purely a
matter of taking expectations, and the only random object involved is
$$G$$. Furthermore, $$G$$ is a cross-sectional variable as our setting presumes that cohort membership is observed for every unit, even when outcomes
are missing (otherwise, you know, non-classical measurement error stuff can come into play). Taken together, these features highlight that `csdid` event-study aggregation weights depend only on the cross-sectional
distribution of $$G$$, and the target parameter is the same under any
sampling scheme &mdash; balanced or unbalanced panels, repeated cross
sections. In practice, these shares need to be estimated, but this is easily done by using their sample analogues (from the pooled cross-sectional data of G). As we discuss above, `csdid` accounts for these steps naturally.

It is natural to ask whether the other weighting schemes can be written in
the same expectation format. We tried, and here is what we found. For the
observation-weighted commands &mdash; `jwdid`, `did_imputation`,
`did_multiplegt_dyn`, and `flexdid` &mdash; the answer is yes, but the
conditioning set has to grow: their targets take the form

$$\mathrm{ES}_{S}(e) \;=\; E\big[\, ATT(G, G+e) \,\big|\, G+e \in [1,T],\ S_{G+e}=1 \,\big],$$

where $$S_{t}$$ denotes an indicator for a unit being observed in period
$$t$$. We index this parameter by $$S$$ as the estimand itself now
depends on the missingness process, and this can have some consequences.
$$\mathrm{ES}_{S}(e)$$ moves when the sampling scheme moves, while
$$\mathrm{ES}(e)$$ does not. On a balanced panel, though, the extra conditioning is vacuous, as every unit is observed in every
period, so all the discussed commands will agree on the estimand. With unbalanced panels or repeated cross-section data, though, this is no
longer the case; this is the mechanism behind the unbalanced-panel
divergence we described for `did_multiplegt_dyn` above.
`eventstudyinteract` has the same structure, with the cohort shares
estimated separately at each relative time, which is why its weights move
with period sizes. For `lpdid`'s default, the answer is essentially no. Sure, its weights are
convex and add up to one, so one can always call them "a distribution". But
this distribution is not something you probably thought about and were explicitly seeking; it is just implicit from the regression specification. These are "variance weights" and reflect how much variation in treatment exposure the adoption order
creates in each 2x2 comparison, and they barely move when cohort sizes
change. In the end, `lpdid`'s default target is still a well-defined
weighted average, but its weights are pinned down by the regression design
rather than by the population, so we cannot really view it as fixed ex
ante.

So, when do the observation-weighted targets coincide with ours? Exactly
when $$S_{G+e}$$ carries no information about the cohort $$G$$ (and,
therefore, no information about $$ATT(G, G+e)$$, either). This condition is
a bit more subtle than it looks, though. Take our unbalanced-panel
simulations: there, missingness does not depend on cohort, covariates, or
potential outcomes within any given period, and yet the condition fails
because the missingness rate varies across periods. Why? Cohort $$g$$
reaches horizon $$e$$ at calendar period $$g+e$$, so, when period sizes are
unequal, different cohorts have different probabilities of being observed
at a given horizon. In fact, asking $$S_{G+e}$$ to be uninformative about
$$G$$ at every horizon is the same as asking the missingness rate to be
constant across periods, which is exactly the auxiliary condition we
flagged when we summarized our findings: each period contributes an equally
sized cross-section. We also stress that this condition plays no role in
identifying the ATT(g,t) building blocks; all commands identify those under
the same type of ignorability of $$S$$. The condition only matters for
making the observation-based weights recover a population quantity.

Let us make all of this concrete with a simple (deterministic) example.
Take two treated cohorts with equal population shares, $$g=2$$ and
$$g=3$$, and let $$ATT(2,3)=1$$ and $$ATT(3,4)=3$$. At horizon $$e=1$$,
the population parameter is $$0.5 \times 1 + 0.5 \times 3 = 2$$; this is
`csdid`'s target, and it does not depend on how the data was collected. Say that, for whatever reason, we only observe half of the sample in
period 4, while everyone is observed in period 3. In this case, at horizon
1, cohort 2 gets weight 2/3 and cohort 3 gets weight 1/3, and the
observation-weighted target is now $$5/3 \approx 1.67$$. If the missing
half is in period 3 instead, the weights flip, and we get
$$7/3 \approx 2.33$$. Notice that nothing changed in the population or in
the treatment effects; we just changed the missingness pattern, and the
estimand moved from 1.67 to 2.33. In other words, two researchers studying
the same population, but with different data collection schemes, would be
estimating different parameters, even when running the exact same command.
This can be complicated, especially when comparing across studies, as is
common in meta-analysis and other science-aggregation procedures.

We want to be clear that none of these weighting schemes is wrong! They
simply answer different questions. But if what you want is the average
treatment effect for treated units in the population, then the cohort-share
weights used by `csdid` retain that interpretation no matter how your sample
happened to be collected. This is the view we stated in the introduction:
target parameters are ideals, defined ex ante, and should not depend on the
sampling scheme.

## Speed

We all like fast commands, that is for sure. All else equal, faster is always better. So, for a moment, let's ignore everything else and focus *exclusively* on speed to see how things currently are in the Stata DiD space. First, the good news: at the sample sizes used in many applications, all the Stata commands we discuss here are fast. Some are faster than others, but the differences, especially with balanced panel data, are not material. They can matter if you are doing bootstrap, repeating over many specifications, or in the larger and richer designs we discuss below. But again, we want to commend all researchers behind these commands: it is not common to have this many options, running this fast!

Every speed entry in this section is the median of 10 timed runs, after one
discarded warmup that loads libraries and plugins. The reported times include
estimation and event-study aggregation with clustered standard errors.
For `csdid`, `jwdid`, `xthdidregress` and `hdidregress`, the estimation and
`estat` calls are timed separately and summed; commands that return the event
study directly are timed in one call. The amount of work still differs:
`csdid`, `jwdid`, and `eventstudyinteract` estimate every underlying cell
&mdash; all ATT(g,t)'s, or the full set of cohort-by-relative-time interactions
&mdash; while `lpdid`, `did_multiplegt_dyn`, and `did_imputation` estimate only
the horizons requested. This difference helps explain the timings as the
number of periods and cohorts grows. We report the number of units (n),
periods (T), cohorts (G), and
the resulting number of rows, as these levers impact speed directly. We
separately discuss balanced panels, unbalanced panels, and repeated cross-sections.
The timing campaign in this section completed on 31 October 2026 with StataNow/MP 19.5
on Mac (Apple Silicon) with 10 processors, using a separate Stata process for each
benchmark tier and a discarded warmup for each package and dataset.

### Balanced panel: analytical and default inference

We start delving into the balanced panel data case. The first thing we highlight here is that different commands have different defaults. `csdid` uses bootstrap-based inference as the default, as that is necessary to conduct simultaneous/uniform inference across event times and groups. Most of the other packages use analytical/plug-in inference procedures, and, therefore, comparing `csdid` and all these other packages is not an apples to apples comparison. Yet, speed matters!

To clear this bar, our first comparison is within `csdid` only. We compare speeds using analytical standard errors with uniform confidence bands turned off (`analytical pointwise`) against 999 multiplier-bootstrap-based procedures, allowing for uniform confidence bands.

<p class="table-title" markdown="span">`csdid` on a balanced panel, seconds for estimation and event-study aggregation</p>

| n (T=10, G=4) | rows | `csdid` | `csdid` default |
| --- | ---: | ---: | ---: |
| 100 | 1,000 | 0.01 | 0.06 |
| 1,000 | 10,000 | 0.02 | 0.07 |
| 10,000 | 100,000 | 0.17 | 0.23 |
| 100,000 | 1,000,000 | 1.31 | 1.58 |

<p class="table-note" markdown="span">Every entry is the median of the timed runs after a discarded warmup. Commands that deliver the event study in a second call &mdash; `csdid`, `jwdid`, `xthdidregress` and `hdidregress` &mdash; are charged for that call as well as the estimation call.</p>

At one million rows, analytical inference takes 1.31 seconds and the
bootstrap-based default takes 1.58 seconds. The timing cost to get uniform
confidence bands and address concerns about multiple testing is fairly low! To
us, this should be a no-brainer, but we are the authors of the package!

With that caveat on the table, here is the comparison across packages on the
same fully balanced ladder, with `csdid` at analytical clustered standard
errors as in every other cross-package table.

<p class="table-title" markdown="span">Balanced panel, seconds per run</p>

| n (T=10, G=4) | rows | `csdid` | `lpdid` | `jwdid` | `eventstudyinteract` | `did_imputation` | `did_multiplegt_dyn` | `xthdidregress` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 10,000 | 0.03 | 0.22 | 0.41 | 0.27 | 0.88 | 1.00 | 0.65 |
| 10,000 | 100,000 | 0.16 | 0.98 | 1.69 | 1.75 | 4.27 | 5.76 | 5.25 |
| 100,000 | 1,000,000 | 1.27 | 8.55 | 12.2 | 15.3 | 44.2 | 61.5 | 67.3 |

<p class="table-note" markdown="span">Every entry is the median of the timed runs after a discarded warmup. Commands that deliver the event study in a second call &mdash; `csdid`, `jwdid`, `xthdidregress` and `hdidregress` &mdash; are charged for that call as well as the estimation call.</p>

At one million rows, `lpdid` takes about 7 times as long as `csdid`, `jwdid`
about 10 times, `eventstudyinteract` about 12 times, and `did_imputation`
about 35 times. Stata's own `xthdidregress` is the slowest column here, at
about 53 times. Reading the two tables together: `csdid` at its shipped
default &mdash; bootstrap, uniform bands, and all &mdash; still comes in at
under a fifth of the next-fastest command's analytical run at this size.

### Unbalanced panels

For this exercise we randomly delete 15% of the rows from an initially
balanced panel. We report all three `bal()` choices, because they define
different estimation samples and different estimands, and their timings
should therefore not be compared without keeping that sample change in mind.

`bal(none)` keeps all available observations, as the other commands do, and
is the column to look at for a common-sample comparison. `bal(pair)` balances
each 2x2 comparison separately; this is the estimand used in Version 1.82,
and it remains available on request. The default, `bal(full)`, retains only
units observed in every period. We should be upfront that it is faster mainly
because it estimates on a smaller sample, whose size is given below, and not
because it uses a faster algorithm. We report it because it is the default,
but its timing is the timing for that smaller sample. The rows column gives
the input sample; `bal(full)` retains 1,870, 20,600 and 197,490 rows in the
three designs, respectively.

<p class="table-title" markdown="span">Unbalanced panel, 15% of rows deleted, seconds per run</p>

| n (T=10, G=4) | rows | `csdid bal(full)` | `csdid bal(pair)` | `csdid bal(none)` | `lpdid` | `jwdid` | `eventstudyinteract` | `did_imputation` | `did_multiplegt_dyn` | `xthdidregress` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 8,496 | 0.02 | 0.04 | 0.07 | 0.19 | 0.36 | 0.30 | 0.62 | 0.98 | 0.89 |
| 10,000 | 85,219 | 0.10 | 0.22 | 0.40 | 0.79 | 1.48 | 1.53 | 4.42 | 4.89 | 7.01 |
| 100,000 | 849,905 | 0.86 | 1.71 | 3.23 | 6.03 | 11.1 | 13.8 | 39.2 | 60.0 | 102.5 |

<p class="table-note" markdown="span">Every entry is the median of the timed runs after a discarded warmup. Commands that deliver the event study in a second call &mdash; `csdid`, `jwdid`, `xthdidregress` and `hdidregress` &mdash; are charged for that call as well as the estimation call.</p>

### Repeated cross sections

The next table reports times with and without one covariate, each command
again invoked at its own documented covariate specification.

<p class="table-title" markdown="span">Repeated cross sections, seconds per run</p>

| n per period (T=10, G=4) | rows | `csdid` | `flexdid` | `jwdid` | `did_imputation` | `hdidregress` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 10,000 | 0.09 | 0.17 | 0.33 | 0.25† | 1.00 |
| 10,000 | 100,000 | 0.63 | 0.81 | 1.66 | 1.60† | 5.56 |
| 100,000 | 1,000,000 | 6.17 | 6.97 | 13.0 | 20.1† | 71.4 |
| with a covariate: | |  |  |  |  |  |
| 1,000 | 10,000 | 0.12 | 0.27 | 0.59 | 0.28† | 1.03 |
| 10,000 | 100,000 | 0.78 | 1.21 | 3.13 | 1.70† | 5.69 |
| 100,000 | 1,000,000 | 7.27 | 9.98 | 25.6 | 21.1† | 73.8 |

<p class="table-note" markdown="span">Every entry is the median of the timed runs after a discarded warmup. Commands that deliver the event study in a second call &mdash; `csdid`, `jwdid`, `xthdidregress` and `hdidregress` &mdash; are charged for that call as well as the estimation call. Entries marked † record invocation time only: autosample dropped every requested horizon, so no requested effects or inference were returned.</p>

`csdid` has the shortest recorded invocation time at every size in this
table. The margin over `flexdid` is modest: 0.63 against 0.81 seconds at
100,000 rows, and 6.17 against 6.97 seconds at one million. With one
covariate, the one-million-row times are 7.27 for `csdid`, 9.98 for
`flexdid`, 25.6 for `jwdid`, and 73.8 seconds for `hdidregress`.

The six `did_imputation` entries require a separate qualification:
`autosample` dropped every requested horizon, tau0 through tau5, in each
call. Their marked times record command completion without the requested
effects or inference. These experiments use one covariate, and we do not
extrapolate the ordering to specifications with many covariates.

### More periods, more cohorts

Sample size is not the only determinant of computation time. We next vary
the number of periods while holding n = 10,000 fixed.

<p class="table-title" markdown="span">Growing the number of periods, seconds per run</p>

| T (n=10,000, G=4) | rows | `csdid` | `lpdid` | `jwdid` | `did_imputation` | `did_multiplegt_dyn` | `eventstudyinteract` | `xthdidregress` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 5 | 50,000 | 0.09 | 0.46 | 0.67 | 1.76 | 1.78 | 0.41 | 1.17 |
| 10 | 100,000 | 0.14 | 0.94 | 1.55 | 3.97 | 4.88 | 1.67 | 4.76 |
| 20 | 200,000 | 0.26 | 1.92 | 4.66 | 9.51 | 11.4 | 7.52 | 25.1 |
| 40 | 400,000 | 0.58 | 3.77 | 17.1 | 22.5 | 34.3 | 45.1 | &mdash; |

<p class="table-note" markdown="span">Every entry is the median of the timed runs after a discarded warmup. Commands that deliver the event study in a second call &mdash; `csdid`, `jwdid`, `xthdidregress` and `hdidregress` &mdash; are charged for that call as well as the estimation call. Cells with no entry were not timed &mdash; `xthdidregress` at 40: single warmup call took 120.6s.</p>

The timing for `csdid` is approximately linear in T, whereas `jwdid` and
`eventstudyinteract` grow faster than linearly over this range. At T=40,
`csdid` takes 0.58 seconds, `jwdid` takes 17.1 seconds and `did_imputation`
takes 22.5 seconds &mdash; about 29 times and about 39 times the
`csdid` time. `xthdidregress` has
no entry at T=40 because its discarded warmup took 120.6 seconds, past the
harness's per-call cap. No median was recorded for that cell. These gaps
matter when a researcher considers many specifications.

The number of cohorts is the other lever, and it separates the commands more
sharply than the number of periods does, because every extra adoption date
adds ATT(g,t) cells that some commands estimate and others do not.

<p class="table-title" markdown="span">Growing the number of cohorts, seconds per run</p>

| G (n=10,000, T=20) | rows | `csdid` | `lpdid` | `did_imputation` | `jwdid` | `did_multiplegt_dyn` | `xthdidregress` | `eventstudyinteract` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | 200,000 | 0.24 | 1.87 | 9.68 | 3.58 | 11.1 | 17.4 | 4.17 |
| 6 | 200,000 | 0.33 | 1.83 | 8.65 | 8.49 | 12.8 | 40.7 | 18.4 |
| 12 | 200,000 | 0.46 | 2.03 | 7.33 | 12.3 | 12.9 | 82.6 | 75.0 |
| 18 | 200,000 | 0.52 | 2.17 | 7.32 | 12.5 | 12.9 | 95.1 | 110.4 |

<p class="table-note" markdown="span">Every entry is the median of the timed runs after a discarded warmup. Commands that deliver the event study in a second call &mdash; `csdid`, `jwdid`, `xthdidregress` and `hdidregress` &mdash; are charged for that call as well as the estimation call.</p>

The data size is identical in every row here. G denotes the requested count;
the final row realizes 14 treated cohorts within the 20-period calendar.
Four assigned adoption dates fall beyond that calendar, so those groups are
untreated throughout the observed sample. The never-treated share also
varies across these designs. `csdid` goes from 0.24 to 0.52 seconds across the range, and
`lpdid` barely moves, because it estimates only the horizons asked for. The
commands that estimate every underlying cell pay for the extra cohorts:
`eventstudyinteract` goes from 4.17 to 110.4 seconds and `xthdidregress` from
17.4 to 95.1. Reading this table next to the periods table above is the
clearest illustration of the point made at the top of this section &mdash;
what a command is asked to compute matters more than how fast it computes.

The tables include aggregation in the reported time. The comparison with
`csdid` Version 1.82, where the measured speed gains range from 11x to 305x
depending on the design, is reported separately:
[Speed against Version 1.82](speed-vs-182.html).

One last timing note. The non-default option rows that appear in the
reliability tables below are not free, either: `lpdid` with `rw` adds about
25% to the run time, and the `jwdid` unconditional route costs roughly 2.3
times the default at 100,000 rows, as it can no longer absorb the fixed
effects. The [four appendix timing probes](https://github.com/pedrohcgs/csdid-stata/blob/main/tools/bench/field/results/appendix-timings/metadata.json)
retain their separate protocols and results. The repeated-cross-section
probe certifies invocation completion and elapsed time; it does not check
finite requested effects or inference.

## Reliability, part I: no covariates

We now hold the population fixed and change only the way observations enter
the sample. The population has three treated cohorts of equal size and a
never-treated group. Treatment effects are 2.0, 2.5, and 3.0 at event times
0, 1, and 2. We do not include covariates in this section. This allows us to
study the role of sampling and aggregation without introducing model
specification issues.

One note on how to read the tables. Beyond each command's default, we also
report rows for non-default options that change the comparison &mdash;
`jwdid` uncond, `lpdid rw`, `did_imputation` wtr, and, in Part II,
`did_multiplegt_dyn` with `trends_nonparam()` &mdash; as we think it would
be unfair to only compare defaults. We discuss each of these rows when it
first becomes relevant.

### A balanced panel

We first consider a balanced panel. Every command can be applied in this
design, and all except `lpdid` are centered around the population target.

<p class="table-title" markdown="span">Balanced panel, no covariates: bias and coverage at e=0</p>

| estimator            | bias at e=0 | 95% coverage |
| ---------------------- | ------------: | -------------: |
| `csdid`              |      +0.004 |         0.97 |
| `jwdid`              |      +0.004 |         0.96 |
| `jwdid` uncond       |      +0.004 |         0.98 |
| `did_imputation`     |      +0.004 |         0.96 |
| `did_multiplegt_dyn` |      +0.004 |         0.94 |
| `lpdid`              |   **-0.13** |     **0.52** |
| `lpdid rw`           |      +0.004 |         0.95 |
| `eventstudyinteract` |      +0.004 |         0.97 |

The `lpdid` bias is 6.3% of the true effect. At n=1,000 the estimated bias is -0.1265 (Monte Carlo standard error 0.0030);
at n=4,000 it is -0.1322 (Monte Carlo standard error 0.0015). It also
does not reflect an implementation error. The result follows from
effective-sample-size weighting: later cohorts receive less weight because
earlier cohorts are no longer available as clean comparisons. Consequently,
the event-study estimate averages a different distribution of cohorts from
the one in the population.

This result also shows that missing data are not required for the choice of
estimand to matter. The `lpdid` weights still define a meaningful parameter;
it is simply not the population average used as the target in this exercise.

This reading is confirmed by the command's own `rw` option, which requests an
equally weighted ATE instead of the default weighting. With `rw`, the bias at
e=0 falls from -0.13 to +0.004 and coverage returns to 0.95. Nothing else
about the command changes, so the gap is entirely a matter of which average is
being reported. We report the default because it is what a user gets without
reading the option list, but `rw` is the right choice if the population
average is the target.

The `jwdid` uncond row, here and in every table that follows, is the
inference route we mentioned in the command map: it stops conditioning on
the realized cohorts and covariates via the `vce(unconditional)` option in
its `estat` commands (this is possible because `jwdid` aggregations run
through `margins`). In practice, getting this option to work requires
attention to two details that we think are easy to miss. You need to use
`method(regress)`, as the default `reghdfe` fit cannot return the scores
that `margins` needs, and you also need the `corr` option. Why? Because
specifying `method()` silently switches the command from panel-identifier
fixed effects to group fixed effects, and these are not the same estimator
when panels are unbalanced; `corr` applies a Mundlak-type correction that
restores the original estimator. Across the three sampling designs, the maximum absolute point-estimate gap
between the default and unconditional routes is 5.87e-13. The standard errors
widen by 10 to 15% in these designs, and this is
what moves the coverage of the uncond rows relative to the default `jwdid`
rows.

### Unequal sampling across periods

Next, we allow the probability that an observation is recorded to vary by
calendar period, as it would with survey waves of different sizes. The
population, treatment assignment, outcomes, and composition remain
unchanged. The stationarity condition in Callaway and Sant'Anna (2021,
Assumption B.1) holds exactly. The only failure is the auxiliary condition
that each period contributes an equally sized cross-section.

<p class="table-title" markdown="span">Unequal period sizes: bias and coverage at e=0</p>

| estimator                  | bias at e=0 | 95% coverage |
| ---------------------------- | ------------: | -------------: |
| `csdid bal(none)`         |      +0.003 |         0.95 |
| `jwdid`                    |       -0.16 |         0.36 |
| `jwdid` uncond             |       -0.16 |         0.48 |
| `did_imputation`           |       -0.16 |         0.38 |
| `did_imputation` wtr       |      +0.007 |         0.96 |
| `did_multiplegt_dyn`       |       -0.29 |         0.16 |
| `lpdid`                    |       -0.40 |         0.02 |
| `lpdid rw`                 |       -0.29 |         0.19 |
| `eventstudyinteract`       |       -0.17 |         0.51 |

Why do the results change when the population has not changed? The
observation-weighted estimators place more weight on the cohort-period cells
that happen to be sampled more often. Their targets therefore depend on the
sampling probabilities, and their confidence intervals cover the population
effect only 2% to 38% of the time. `csdid` continues to weight cohorts using
their population shares, P(G=g | G+e ∈ [1,T]), which are unchanged in this
experiment.

The `did_imputation` wtr row shows that this is a choice rather than a
limitation of the imputation approach. Its `wtr()` option lets the user state
the estimand directly, and once the weights give each cohort its population
share the bias disappears and coverage returns to nominal. What the default
does is aggregate over the treated observations that happen to be in the
sample, and that is what moves with the sampling. Nothing about imputing
Y(0) requires it. We also note that constructing these weights is
straightforward in applications, as they only involve cohort membership and
cell counts, which are observed; there is nothing simulation-specific here.
In fact, one can also use `wtr()` to isolate a single ATT(g,t), which is
handy if you want to recover results that the command does not print by
default.

The separate uniform-missingness runs use the same observation probability
in every period. They provide a comparison in which period-specific
sampling probabilities do not drive the aggregation weights, while the
retained observations and precision still change.

The `lpdid rw` row is worth reading carefully here. In the balanced design,
`rw` removed the weighting bias completely. In this one it does not: the bias
improves from -0.40 to -0.29 and coverage from 0.02 to 0.19, which is still
far from nominal. The two problems are distinct. `rw` fixes how cohorts are
weighted into the event study; it does nothing about a target that moves with
the sampling probabilities. Choosing the right aggregation option does not
protect against this.

<div class="important" markdown="1">
This is the result we would worry about most in an applied study. Survey
waves of different sizes are common, and many empirical descriptions would
not treat them as an important feature of the design.
</div>

### Repeated cross sections

We obtain a similar result with repeated cross sections. When a fresh sample
is drawn in each period and period sizes are equal, the commands that support
this data structure perform well: `csdid` with `rcs`, `jwdid`,
`did_imputation` with group fixed effects, and `flexdid` for its intended
design target.

When period sizes differ, the bias for `jwdid` is -0.16 at e=0 and
+0.23 at e=2. Hence, the bias changes sign over
the event-study horizon. This can exaggerate growth along the event-study path relative to the
population effects. At the same event times, the biases for `csdid` are 0.004
and 0.001, with coverage 0.94 to 0.95. Across the settings in this part of the guide, the largest absolute
Monte Carlo bias among the reported ATT(g,t) cells is 0.021.

The benchmark omits `did_multiplegt_dyn` and `lpdid` from these
individual-level repeated-cross-section runs: the sample does not supply
the longitudinal treatment paths their panel interfaces use. These missing
rows record that benchmark choice, rather than an observed command refusal.

### The transparency scorecard

The next table is based on the documentation for each command, rather than
on a simulation. It records what the command reports and what information is
available for reconstructing the reported estimates.

<p class="table-title" markdown="span">What each command reports</p>

|                      | reports every ATT(g,t)        | weights stated in closed form | target fixed under sampling | balance choice explicit                     | uniform bands |
| ---------------------- | ------------------------------- | ------------------------------- | ----------------------------- | --------------------------------------------- | --------------- |
| `csdid`              | yes                           | yes                           | yes                         | yes (`bal()`, disclosed in `e(panel_mode)`) | yes           |
| `jwdid`              | recoverable from coefficients | no                            | no                          | no                                          | no            |
| `flexdid`            | recoverable from coefficients | no                            | no                          | no                                          | no            |
| `did_imputation`     | via `wtr()`                   | no (`saveweights` exports)    | via `wtr()`                 | yes (`hbalance`)                            | no            |
| `did_multiplegt_dyn` | no                            | no                            | no                          | no (imputes treatment paths)                | no            |
| `lpdid`              | no                            | no                            | no                          | no                                          | no            |
| `eventstudyinteract` | recoverable from coefficients | yes (`e(ff_w)`)               | no                          | no (uses all observations)                  | no            |

We would not be comfortable reporting an aggregate estimate that we could
not reconstruct from its ATT(g,t) estimates and weights. `csdid` reports
each ATT(g,t) and its standard error, gives the aggregation weights in closed
form, records the resolved sample in `e(panel_mode)`, and makes the balancing
rule explicit through `bal()`. Several of the other commands do not report
the underlying cells.

In our view, the emphasis on reporting these components is related to the
stability of the target in the preceding experiments. This is an
interpretation of the commands' design, however, and not a result established
by the simulations.

## What a missing row does to each command

The aggregation weights above are one consequence of an unbalanced panel.
There is a second one, and it operates even where the weights agree: the
commands do not process a missing outcome row the same way, and the
differences start before any estimation happens. Our
[missing-row diagnostic](https://github.com/pedrohcgs/csdid-stata/blob/main/tools/bench/field/missing_rows_diagnostic.do)
records the comparisons below, asserts the supported paired-cell matches,
and retains the counterexamples as well as the agreements.

The command's *interface* matters. `csdid`, `jwdid`, `did_imputation`,
and `eventstudyinteract` take a cohort variable (or user-built cohort
dummies), so the stated treatment date remains available when rows are
missing. `xthdidregress`, `did_multiplegt_dyn`, and `lpdid` instead take a
treatment *indicator*. An unobserved first treated row can change the
treatment history they infer from the observed path. Their subsequent
sample rules differ, so this does not imply that they discard the same
information.

<p class="table-title" markdown="span">How each command processes a missing outcome row</p>

| command              | estimation sample                    | unit missing its base period                 | cohort labels                |
| -------------------- | ------------------------------------ | -------------------------------------------- | ---------------------------- |
| `csdid bal(full)`    | whole units not seen in every period | excluded with the rest of its unit, loudly   | trusted                      |
| `csdid bal(pair)`    | per 2x2: requires both periods        | out of every post cell; still in shares      | trusted                      |
| `csdid bal(none)`    | observed rows                        | still contributes at t (cross-section cells) | trusted                      |
| `jwdid`              | observed rows with a unit screen     | kept if another untreated row remains        | trusted                      |
| `did_imputation`     | untreated rows and imputable treated rows | kept if any untreated row remains            | trusted                      |
| `eventstudyinteract` | observed rows                        | kept (no per-unit anchoring)                 | trusted (user dummies)       |
| `xthdidregress`      | observed rows and derived labels     | paired reconstruction can lack base support | *derived from observed rows* |
| `did_multiplegt_dyn` | comparisons from the observed path  | depends on the available treatment history  | *derived from observed rows* |
| `lpdid`              | per-window sample                    | horizon-specific exclusions                  | *derived from observed rows* |

One deleted row already distinguishes these rules. In a balanced panel
with 500 units and seven periods, remove one cohort-4 unit's period-4 row,
its first treated period. Compare the resulting event-study estimates
with those from deleting that unit outright. For `xthdidregress`, the
estimates at event times 0, 1, and 2 agree within 1e-12. For `lpdid`, event
times 1 and 2 agree within 1e-12, but event time 0 differs by 0.000992.
For `did_multiplegt_dyn`, the largest difference over those three horizons
is 0.000838. The surviving contributions therefore depend on the command and horizon.

We also reconstructed the `xthdidregress` cells on the panel with 2,000
units, ten periods, and 15% of rows missing at random. For the 22
post-treatment cells with paired base/current observations on its
*derived* cohort labels, hand-built pairs and `csdid bal(pair)` reproduce
its coefficients within 2e-15. This reconstruction has a limit: 6 additional
post cells have no paired base observations. `csdid bal(pair)` leaves those cells missing,
while `xthdidregress` reports finite coefficients. The paired-cell
equivalence applies to the supported cells.

In this design, 242 of 1,615 treated units carry a different derived
cohort label. Switching from derived labels to the supplied true labels
moves the event study by up to 0.0521, with a sign that varies across
horizons. As in Part I, averaging across event times would hide this
rather than reveal it.

The useful remedy in `xthdidregress` is its `usercohort()` option. Its
documentation recommends supplying the cohort variable when "there are
gaps in the estimation sample, but you know a group was treated at the
time when the gap is present." With the true cohorts supplied, all 22
post-treatment cells in this design match both the hand-built true-label
pairs and `csdid, method(reg) nevertreated bal(pair)` within 2e-15.
Code never-treated units 0: coding them missing instead produces
an internal error, r(3301), in this probe. `did_multiplegt_dyn` and `lpdid`
have no analogous cohort-input option.

Two disclosures about our own side, in the same spirit. First, `csdid`
keeps every unit in the estimated cohort shares even when missingness
leaves no cell that can use its outcomes; that is deliberate &mdash; the
shares are a cross-sectional quantity and keeping them complete is what
holds the target parameter fixed &mdash; but it means a unit can influence
the weights without influencing any ATT(g,t). Second, the default `jwdid`
call excludes from estimation a treated unit whose retained rows all fall
at or after its treatment date, treating that unit as always treated. In
our 15%-missingness panel it excluded 6 observations from 1 unit
without announcing the exclusion. The dataset itself retained every row.

If you work with an unbalanced panel, this three-line check flags units
whose first observed treated period differs from the supplied cohort:

<!-- This runs against the reader's own panel, using their id, D, t and gvar,
     so there is no dataset it could be executed against from a clean session. -->
<!-- norun -->
```stata
bysort id: egen first_obs_treated = min(cond(D == 1, t, .))
generate byte relabeled = (first_obs_treated != gvar) if gvar > 0
tabulate relabeled
```

A nonzero count motivates checking how each command uses that observed
history. For `xthdidregress`, `usercohort()` supplies the treatment date
that the observed indicator path cannot recover.

## Reliability, part II: covariates, and the case for doubly robust

Covariates are often included in a DiD analysis because treated cohorts
differ in baseline characteristics that are related to untreated outcome
trends. We introduce this feature by adding time-invariant characteristics,
such as gender or earnings measured before the sample begins. Their
distribution differs across cohorts, and they affect both the level and the
trend of untreated outcomes. Conditional parallel trends holds, but
unconditional parallel trends does not. Treatment effects do not vary with
the covariates, so the population targets remain the same as before.

We first use a balanced panel whose conditional untreated trend is exactly
linear in the covariates. The propensity working model is a linear logit.
Not-yet-treated comparisons can pool cohorts with different covariate
distributions, so this logit need not equal the true conditional score even
in the baseline. The correctly specified outcome regression supplies the
consistency guarantee for `csdid dr` here. The table reports bias and
coverage at e=0 over 500 replications.

<p class="table-title" markdown="span">Linear outcome trend: bias and coverage at e=0</p>

| estimator            |       bias | coverage |
| ---------------------- | -----------: | ---------: |
| `csdid dr`           |     +0.001 |     0.95 |
| `csdid ipw`          |     +0.004 |     0.95 |
| `csdid reg`          |     -0.001 |     0.95 |
| `jwdid`              |     +0.001 |     0.95 |
| `jwdid` uncond       |     +0.001 |     0.97 |
| `did_imputation`     |     +0.001 |     0.95 |
| `did_multiplegt_dyn` | **+0.119** | **0.61** |
| `lpdid`              | **-0.139** | **0.46** |
| `lpdid rw`           |     -0.000 |     0.96 |
| `eventstudyinteract` | **+0.294** | **0.02** |

The `csdid`, `jwdid`, and `did_imputation` estimates are centered around the
target. `lpdid` retains the weighting bias discussed in Part I, and `rw`
removes it here as well: adding covariates does not change the fact that the
gap is about aggregation weights rather than covariate adjustment. For
`did_multiplegt_dyn`, the bias is +0.119 at e=0 and increases to +0.88 at
e=2. We use the current SSC release as of this writing, dated June 29,
2026. This result comes from the estimand associated with its covariate
adjustment, rather than a problem in the implementation. The `controls()`
option imposes parallel trends after residualizing outcomes on first
differences of the covariates, using one coefficient that is common across
groups and periods.

This assumption differs from conditional parallel trends in Callaway and
Sant'Anna (2021) in two important respects. First, the first difference of a
time-invariant characteristic is zero. For covariates such as gender, race,
or baseline earnings, residualization therefore leaves the unconditional
comparison unchanged. In this case, the condition reduces to unconditional
parallel trends, even though these covariates were included precisely to
make a conditional parallel trends assumption more plausible.

Second, the common coefficient restricts the effect of covariates on trends
to be the same across groups and periods. We should be careful about which
half of that is a fair criticism. Conditional parallel trends also requires
untreated trends to agree across cohorts once you condition on the
covariates, so it rules out cohort-varying covariate effects just as firmly;
a design that violated them would defeat `csdid` too. The restriction that
does separate the two is the one across periods. Conditional parallel trends
says nothing about the relationship being stable over time, and `csdid`
estimates each (g,t) cell separately, so an effect that changes from period
to period is absorbed rather than assumed away.

We built a design to check exactly this. The covariate effect on the
untreated trend varies by period and is common across cohorts, so conditional
parallel trends holds exactly and every estimator here is identified in
principle. Over 100 replications, `csdid dr` has a bias of +0.006 at e=0 and
+0.001 at e=2. The `controls()` route starts at +0.597 and reaches -0.555,
because one coefficient cannot track an effect that moves. Much of the recent
DiD literature is motivated by problems created by homogeneous
treatment-effect restrictions in TWFE regressions. Here, a homogeneity
restriction appears instead in the coefficients on the covariates.

These experiments use time-invariant baseline characteristics. The
documentation recommends
`trends_nonparam()` for time-invariant discrete characteristics. This option
uses exact matching, so it needs a partition coarser than the group
variable. Matching on our binary covariate reduces the bias at
e=2 from +0.88 to +0.66 over 100 replications, but does not eliminate it,
and continuous covariates are not covered by that option.

The conditional parallel trends assumption of Callaway and Sant'Anna (2021)
does not impose either restriction: untreated trends may depend flexibly on
the covariates and the relationship may vary across cohorts. The doubly
robust estimator in `csdid` conditions on the covariates themselves, which
explains its performance in this experiment.

Including covariates also leaves the conclusion from Part I unchanged. In the covariate repeated-cross-section runs, `csdid` biases range from
-0.001 to +0.006 across the three horizons and both period-size designs, with
coverage 0.93 to 0.96. The regression-based
commands again change when period sizes are unequal. Covariate adjustment
does not correct the aggregation weights.

Why do we use `dr` as the default in `csdid`? The doubly robust estimator of
Sant'Anna and Zhao (2020) is consistent if either the outcome model or the
treatment-probability model is correctly specified. The other commands in
this comparison rely on outcome regression alone. The simulations below
compare observed performance under specific working models.

We next make the untreated trend depend on the square of a continuous
covariate, while keeping the treatment-effect targets fixed. The working
outcome regressions continue to include covariates in levels, omitting this
nonlinear term. The linear propensity logit is also still an approximation
when the comparison group mixes cohorts, so this exercise does not isolate
a case with exactly one correct nuisance model. The table reports bias and
coverage at e=1.

<p class="table-title" markdown="span">Misspecified outcome model: bias and coverage at e=1</p>

| estimator            |       bias | coverage |
| ---------------------- | -----------: | ---------: |
| `csdid dr`           |     -0.058 |     0.94 |
| `csdid ipw`          |     -0.054 |     0.93 |
| `csdid reg`          | **+0.300** | **0.46** |
| `jwdid`              | **+0.490** | **0.26** |
| `jwdid` uncond       | **+0.490** | **0.30** |
| `did_imputation`     | **+0.490** | **0.28** |
| `did_multiplegt_dyn` | **+0.303** | **0.22** |
| `lpdid`              | **-0.162** | **0.68** |
| `lpdid rw`           |     +0.006 |     0.95 |
| `eventstudyinteract` | **+0.459** | **0.07** |

(`did_multiplegt_dyn` and `lpdid` already differ from the target in the
linear-outcome experiment; their aggregation and covariate restrictions
remain relevant here.)

Several estimators that rely only on the outcome regression are now biased. The
bias also increases with the horizon: for `jwdid`, it reaches +0.67 at e=2,
with coverage of 0.29. This is not a defect in any one implementation. A misspecified outcome regression can fail to remove the relevant
untreated-trend differences. The observed `csdid dr` biases at e=0,1,2 are -0.050, -0.058, and +0.006;
the `ipw` biases are -0.050, -0.054, and -0.000. These results describe the
approximate working models in this design, rather than proving a clean
one-model-correct consistency case.

<div class="tip" markdown="1">
The theoretical protection supplied by a correctly specified propensity
score is an important reason to consider `dr`. It is distinct from the
approximate propensity specification in this particular experiment.
</div>

An additional variance-shift design lets the spread of the continuous
covariate differ across cohorts, creating selection that a linear logit
cannot represent. The observed `ipw` biases at e=0,1,2 are -0.000, -0.001,
and -0.005. Nonlinearity in the score alone does not determine the size of
the bias: its interaction with the untreated outcome trend matters.

A stronger transformed-index design follows the construction in
Sant'Anna and Zhao (2020). Selection depends on a latent index, while the
observed covariate is a standardized exponential transformation of that
index. This makes selection nonlinear in the observed covariate, whereas
the fitted logit uses the covariate in levels. Because the observed
covariate is skewed, the resulting specification error is related to the
untreated trend. The cell-specific outcome model remains linear in the observed covariate
and is correctly specified, while the linear propensity logit is
misspecified. The table again reports bias and coverage at e=1.

<p class="table-title" markdown="span">Misspecified propensity score: bias and coverage at e=1</p>

| estimator            |       bias | coverage |
| ---------------------- | -----------: | ---------: |
| `csdid dr`           |     +0.001 |     0.95 |
| `csdid ipw`          | **-0.094** |     0.97 |
| `csdid reg`          |     -0.001 |     0.95 |
| `jwdid`              |     +0.001 |     0.92 |
| `jwdid` uncond       |     +0.001 |     0.95 |
| `did_imputation`     |     +0.001 |     0.92 |
| `did_multiplegt_dyn` | **+0.229** | **0.28** |
| `lpdid`              | **-0.112** | **0.66** |
| `lpdid rw`           |     -0.000 |     0.96 |
| `eventstudyinteract` | **+0.321** | **0.10** |

(The earlier aggregation and covariate restrictions of `did_multiplegt_dyn`
and `lpdid` remain relevant here.)

The outcome-regression estimators do not fit a propensity score. Within `csdid`, the bias of `ipw` increases with the event
horizon: -0.04, -0.09, and -0.14. One cell-level illustration is ATT(5,6), where
never-treated units are the only available comparison group. Here `ipw` has a
bias of -0.23 and a standard error of 0.35. The standard error for `dr` is
0.16. Thus, propensity-score misspecification affects both the bias and the
precision of `ipw`. Its relatively wide intervals also explain why coverage
does not fall as much as it did for `reg` under outcome-model
misspecification. The `dr` estimator remains centered around the target
because its outcome model is correct.

For the event study at e=1, `ipw` has missing estimates in 36 of
500 draws, and `dr` in 36. The missing-draw sets differ in
0 draws. Each arm's table entries condition on its finite estimates;
coverage additionally requires a finite positive standard error. These
denominators are retained with the simulation outputs.

These exercises stress the estimators under working-model error. The
double-robustness theorem guarantees consistency when either nuisance model
is truly correct. The nonlinear-outcome exercise with not-yet-treated
mixtures does not cleanly isolate that guarantee. The transformed-index
exercise does maintain a correct cell-specific outcome regression, which
supplies the guarantee for `dr` despite the misspecified propensity score.
The theorem provides no general protection when both nuisance models are
misspecified.

## One design that tells them apart

So far, each difference between the commands needed its own experiment: one
design for the aggregation weights, another for the covariate adjustments, a
third for inference. That is the right way to isolate mechanisms, but it
invites a fair question: do these issues matter together, or only in
carefully separated laboratories? In this section we answer with a single
data generating process that separates essentially every command in this
guide, at every option we could find. We were guided by one principle: the
design must be hard, but it cannot be rigged. Conditional parallel trends
&mdash; the identifying assumption every one of these commands invokes &mdash;
holds exactly, in every period and for every comparison group, and the
target parameters are available in closed form before any estimator touches
the data. Every failure below is therefore a failure to accommodate
heterogeneity, never a failure of identification.

### The data generating process

There are $$T=7$$ periods and four equally sized groups: cohorts first
treated at $$g \in \{3,4,5\}$$ and a never-treated group. Each unit carries
two time-invariant covariates whose distributions differ across cohorts,

$$
x_{1i}\mid G_i=g \;\sim\; \mathrm{Bernoulli}(0.15+0.10\,g), \qquad
x_{2i}\mid G_i=g \;\sim\; N\big(0.4\,(g-4),\,1\big),
$$

with $$x_{1i}\sim \mathrm{Bernoulli}(0.35)$$ and $$x_{2i}\sim N(-0.5,\,1)$$
for the never-treated group. Untreated outcomes are

$$
Y_{it}(0) \;=\; \mu_i + 0.3\,t + 0.4\,x_{1i} + 0.6\,x_{2i}
 + x_{1i}\,h_1(t) + x_{2i}\,h_2(t) + \varepsilon_{it},
$$

$$
h_1(t) = 2.0\,\sin(1.6\,t), \qquad h_2(t) = 2.2\,\cos(1.3\,t),
$$

with $$\mu_i$$ and $$\varepsilon_{it}$$ independent standard normals. The
functions $$h_1$$ and $$h_2$$ are deliberately not linear in calendar time.
But notice that they do not depend on $$G$$: for any two periods $$s<t$$,

$$
\mathbb{E}\big[\,Y_{it}(0)-Y_{is}(0)\,\big|\,X_i,\,G_i\,\big]
 \;=\; 0.3\,(t-s) \;+\; x_{1i}\,\{h_1(t)-h_1(s)\}
 \;+\; x_{2i}\,\{h_2(t)-h_2(s)\},
$$

and the right-hand side is free of $$G_i$$. Conditional parallel trends
holds exactly, for every period pair and every comparison group. The
right-hand side is also exactly linear in $$(x_1,x_2)$$ once the period
pair $$(s,t)$$ is fixed &mdash; a fact worth remembering below.

Treatment effects vary by cohort, by event time, by covariates, and by
covariates interacted with event time:

$$
\tau(g,t,X) \;=\; (g-2) \;+\; 0.5\,(t-g) \;+\; a_g\,x_1 \;+\; b_g\,x_2\,(t-g),
$$

$$
(a_3,a_4,a_5) = (0.3,\;0.8,\;1.5), \qquad
(b_3,b_4,b_5) = (0.2,\;0.6,\;1.2).
$$

The building blocks then have closed forms. Writing
$$p_g=\mathbb{E}[x_1\mid G=g]$$ and $$m_g=\mathbb{E}[x_2\mid G=g]$$,

$$
ATT(g,\,g+e) \;=\; (g-2) + 0.5\,e + a_g\,p_g + b_g\,m_g\,e,
$$

which evaluates to $$1.135+0.42\,e$$, $$2.44+0.5\,e$$, and $$3.975+0.98\,e$$
for cohorts 3, 4, and 5. Averaging with the equal cohort shares gives the
event-study target

$$
ES(e) \;=\; 2.5167 + 0.6333\,e, \qquad e = 0,1,2.
$$

A separate draw with 200,000 units gives empirical-minus-closed-form
differences of +0.000101, +0.002138, and +0.004175 at event times 0, 1, and 2. Rounding the
targets and empirical averages to three decimals gives equal values for
1 of the three horizons.

### Two mechanisms, one design

The design carries exactly two threats, aimed at different structures.

**Mechanism 1: the covariate effect moves with calendar time.** Consider an
estimator that adjusts for covariates with a single coefficient per event
horizon, pooling switch events that occur at different calendar dates. This
is what `lpdid` does &mdash; one regression per horizon $$h$$. Its covariate
term is correctly specified only if $$h_j(t+h)-h_j(t-1)$$ is constant in
$$t$$, that is, only if $$h_j$$ is affine. Any curvature in calendar time
defeats a single coefficient, and cohorts switching at different dates
guarantee that the pooled cells disagree. `did_multiplegt_dyn` fails for the
more basic reason documented earlier: it residualizes on *first differences*
of the covariates, which are identically zero here, so its adjustment
vanishes entirely and what remains is unconditional parallel trends &mdash;
which fails, because $$\mathbb{E}[X\mid G]$$ differs across cohorts.

**Mechanism 2: treatment effects vary with covariates.** This one is
subtler, and it is aimed at `eventstudyinteract` in its best specification
&mdash; covariates interacted with time dummies, the specification that
survived every design above. The command estimates one vector of covariate
coefficients $$\gamma_t$$ per period, common across cohorts, in a regression
whose cohort-by-relative-time dummies absorb only cell *means*. Within a
treated cell $$(g,e)$$, the within-cell slope of the outcome on $$x_2$$ is
not $$\gamma_{2,t}$$ but $$\gamma_{2,t} + b_g\,e$$: the treatment-effect
heterogeneity leaks into the covariate slope. Ordinary least squares
converges to a variance-weighted average of the within-cell slopes across
all cells at $$t$$, so

$$
\hat\gamma_{2,t} \;\xrightarrow{\;p\;}\; \gamma_{2,t} + c_t,
\qquad c_t > 0 \text{ and growing in } t,
$$

and the contamination propagates into every estimated cell effect through
the cohort differences in $$\bar X$$ in the additive and x-by-time
specifications tested here. Those specifications do not give each treatment
cell its own covariate slope. The command accepts a user-supplied covariate
list, so this comparison does not establish an impossibility result for
every custom design matrix or its subsequent aggregation.

Neither mechanism touches `csdid`, for one structural reason. Its outcome
regressions are estimated on comparison units only, one $$(g,t)$$ cell at a
time. Fixing the period pair makes the trend exactly linear in
$$(x_1,x_2)$$, so the cell-level model is correctly specified by
construction; and never touching a treated outcome means no amount of
treatment-effect heterogeneity can leak into the adjustment.

### What happens

Bias and coverage of nominal 95% intervals at each event time, over 100
replications with $$n=2{,}000$$:

<p class="table-title" markdown="span">One design, every command: bias / coverage by event time</p>

| estimator | e=0 | e=1 | e=2 |
| --- | --- | --- | --- |
| `csdid reg` | -0.002 / 0.97 | -0.006 / 0.97 | -0.013 / 0.95 |
| `csdid dr` | -0.003 / 0.96 | -0.008 / 0.97 | -0.015 / 0.93 |
| `jwdid` | +0.004 / 0.90 | -0.002 / 0.94 | -0.008 / **0.80** |
| `jwdid` uncond | +0.004 / 0.98 | -0.002 / 0.99 | -0.008 / 0.95 |
| `did_imputation` | +0.004 / 0.91 | -0.002 / 0.94 | -0.008 / 0.92 |
| `lpdid` | **+0.302** / 0.02 | -0.072 / 0.94 | **-0.555** / 0.00 |
| `lpdid rw` | **+0.594** / 0.00 | +0.211 / 0.68 | **-0.555** / 0.00 |
| `lpdid controls()` | **+0.335** / 0.02 | -0.184 / 0.73 | **-1.174** / 0.00 |
| `lpdid rw controls()` | **+0.781** / 0.00 | +0.506 / 0.06 | **-0.782** / 0.00 |
| `did_multiplegt_dyn` | **+0.594** / 0.00 | +0.211 / 0.59 | **-0.555** / 0.00 |
| `did_multiplegt_dyn` trends_nonparam | **+0.334** / 0.00 | +0.025 / 0.96 | **-0.513** / 0.00 |
| `eventstudyinteract` additive | **+1.039** / 0.00 | +0.663 / 0.00 | **-0.555** / 0.00 |
| `eventstudyinteract` x-by-time | **-0.119** / 0.36 | -0.338 / 0.00 | **-0.596** / 0.00 |

Three things stand out to us before we turn to why.

First, the bias changes sign.

The bias of `lpdid controls()` moves from $$+0.34$$ at $$e=0$$ to
$$-1.17$$ at $$e=2$$. Its mean estimated effects are $$2.85$$ and
$$2.61$$, while the true effects are $$2.52$$ and $$3.78$$.
The estimated dynamics are distorted, although the mean estimated effect
remains positive at both endpoints. A sign change in bias is not itself a
sign change in the treatment effect.

Second, none of the options in this table removes all the biases in the
methods sensitive to these two mechanisms. `eventstudyinteract` with x-by-time
interactions is biased by $$-0.119$$, $$-0.338$$, $$-0.596$$.
Relative to the separately simulated Mechanism 2 design, the bias differences
are $$+0.003$$, $$-0.001$$, and $$-0.001$$. Its time dummies absorb $$h_1$$ and $$h_2$$ exactly, so
Mechanism 1 never touches it; its entire failure is the contamination.
For `lpdid rw`, the bias differences from the separately simulated
Mechanism 1 design are $$-0.003$$, $$+0.000$$, and $$+0.000$$. For
`did_multiplegt_dyn` they are $$-0.003$$, $$+0.000$$, and $$+0.000$$.
These Monte Carlo comparisons use different sample sizes and draw counts,
so exact agreement of the simulated means is not expected. The single-mechanism
designs isolate the two channels; the combined design shows their joint effect.

Third, the survivors: `csdid`, `jwdid`, and `did_imputation` are centered at
every horizon. Why they survive, and what surviving costs their standard
errors, ties the whole guide together &mdash; so it gets its own discussion.

### Why the survivors survive, and what it costs their inference

To see one source of the differences, consider an outcome-regression cell
estimator on our balanced panel of the form

$$
\widehat{ATT}(g,t) \;=\; \frac{1}{n_g}\sum_{i:\,G_i=g}
\Big[\,(Y_{it}-Y_{i,g-1}) \;-\; \widehat m_{g,t}(X_i)\,\Big],
$$

an average over cohort $$g$$ of each treated unit's observed change minus an
estimate of its untreated change, where
$$m_{g,t}(x) = \mathbb{E}\big[Y_{t}(0)-Y_{g-1}(0)\,\big|\,X=x\big]$$ is
identified from untreated observations under conditional parallel trends.
This representation highlights why the observations and restrictions used
to estimate $$\widehat m_{g,t}$$ matter.

**Point estimation.** The danger is treatment-effect heterogeneity leaking
into $$\widehat m$$. Among treated units in cell $$(g,t)$$, the within-cell
slope of the outcome change in $$x$$ is not $$\partial m/\partial x$$ but
$$\partial m/\partial x + \partial\tau/\partial x$$. Any fit that pools
covariate coefficients across cells and lets treated observations into the
pool therefore converges to $$m$$ plus a contamination term whenever
$$\tau$$ varies with $$X$$. Two protections against this contamination
appear in the commands that remain centered here:

- *Exclusion*: $$\widehat m$$ never sees a treated outcome. `csdid` fits it
  on the comparison group, separately for each $$(g,t)$$ cell;
  `did_imputation` fits $$Y(0)$$ on all untreated observations. Nothing
  about $$\tau$$ can reach either fit.
- *Saturation*: treated observations enter, but every cohort-by-time cell
  gets its own covariate coefficients (`jwdid`, which demeans the covariates
  and interacts them with each cell), so a treated cell's
  $$\partial\tau/\partial x$$ stays in that cell and contaminates nothing
  else.

`eventstudyinteract` takes neither route &mdash; one $$\gamma_t$$ per
period, common across cells, partly estimated from treated cells &mdash; and
that is its row in the table.

**Inference.** Agreement on point estimates leaves a separate question about
uncertainty. With $$\widehat m$$ consistent, decompose the error on a balanced panel as

$$
\widehat{ATT}(g,t) - ATT(g,t) \;=\;
\underbrace{\frac{1}{n_g}\sum_{i:\,G_i=g}\big\{\tau_i - ATT(g,t)\big\}}_{\text{composition}}
\;+\;
\underbrace{\frac{1}{n_g}\sum_{i:\,G_i=g}\big\{\Delta u_i \;-\; (\widehat m_{g,t}-m_{g,t})(X_i)\big\}}_{\text{estimation}},
$$

where $$\tau_i$$ is unit $$i$$'s treatment effect. The composition term has
variance $$\mathrm{Var}(\tau_i \mid G_i=g)/n_g$$ &mdash; the same order as
everything else, and invisible to any variance formula that conditions on
the realized covariates of the treated. This within-cohort covariate variation
is redrawn even though our cohort counts are fixed. Cohort-share variation is
a separate component that this Monte Carlo does not redraw. The following
comparisons describe the resulting coverage and reported standard errors:

- `csdid` builds its standard errors from the influence function, which
  carries the estimation and composition pieces jointly: coverage 0.93 to
  0.97 in the table, with no options required.
- `did_imputation` documents conservative inference under heterogeneity: coverage 0.91 to 0.94 here.
- `jwdid` is the instructive case. The saturation that protects its point
  estimate moves the $$\tau(X)$$ variation out of the residuals and into
  fitted coefficients, so its conventional variance conditions on the
  realized composition: coverage falls to 0.80 at $$e=2$$. Its unconditional
  option (`method(regress) corr` at estimation, then
  `estat event, vce(unconditional)`) allows for random covariates and cohort
  shares and reports coverage 0.95 &mdash; at standard errors 52% wider. The difference between the default and unconditional standard errors
  is 34% of the unconditional standard error at e=2. Across the simpler designs of
  this guide its mean standard errors run 0 to 18% above the Monte Carlo
  standard deviation (coverage 0.95&ndash;0.98), while its mean standard error is
  1.052 times its Monte Carlo standard deviation here at $$e=2$$.

The point estimates and uncertainty calculations answer distinct questions.
This design shows how redrawing covariates within fixed cohorts affects
coverage, and how `jwdid`'s unconditional option changes its reported standard
errors. Because cohort counts never vary across draws, these results cannot
rank the commands' inference under sampling schemes that also redraw cohort
membership. The uncertainty statement should match the intended sampling
scheme and target.

### Reproducing this section

The script `master.do` in the [code appendix](../code-appendix.html) runs
the full design, every arm including the unconditional-inference one; the
DGP is defined in `fielddgp.do`, with a separate 200,000-unit target check.
Replication $$r$$ in the main Monte Carlo designs is seeded at $$90000+r$$;
the band experiment and fixed-draw diagnostics record their own seeds. The companion single-mechanism designs are
`ctvar_all.do` (Mechanism 1) and `cohorthet.do` (Mechanism 2), and
`eqgate.do` checks 9 refactored arms against their literal commands on
3 seeds, at all 3 reported horizons. `eventstudyinteract` is version 0.1
(24jan2022); all other packages are at the versions dated above.

## Precision

Which estimator is more precise? The answer depends on the error process.
We restrict this comparison to a balanced panel without covariates, where
the estimators have a common target, and consider two designs. The
population and the 500 simulation draws are the same; only the within-unit
errors change.

<p class="table-title" markdown="span">Two error processes, standard deviation of the event-study estimate</p>

| errors    | `csdid` sd | `jwdid`/`did_imputation` sd | tighter              |
| ----------- | -----------: | ----------------------------: | ---------------------- |
| iid       |      0.067 |                       0.052 | poolers, by ~22% |
| unit root |      0.047 |                       0.062 | `csdid`, by ~24% |

With iid errors, the estimators that use all pre-treatment periods have a
standard deviation of 0.052, compared with 0.067 for `csdid`: a
22% smaller standard deviation. This is consistent with the theoretical advantage of
pooling in that error design. With unit-root errors, shocks accumulate within
a unit and the ranking reverses: the standard deviation is 0.047 for
`csdid` and 0.062 for `jwdid` and `did_imputation`, a difference of about
24%. Unit-root-type persistence is common in panel outcomes.

All these estimators are unbiased in both experiments; only their variances
change. We therefore would not make a general precision comparison without
also describing the error process. `lpdid` is omitted because, for the
weighting reason discussed above, it is biased relative to the common
population parameter in both designs. Changing the error process does not
address that weighting issue.

Chen, Sant'Anna, and Xie (2025) provide the general result: the efficient
estimator depends on the covariance structure of the outcomes. None of the
packages considered here, including `csdid`, attains the semiparametric
efficiency bound in general. Thus, a standard-error comparison based on one
error process describes performance in that particular design, not an
unconditional ranking of the estimators.

## Simultaneous inference

Researchers usually inspect the entire event-study path, rather than one
coefficient chosen in advance. In that case, pointwise 95% confidence
intervals do not provide 95% coverage for the path as a whole. `csdid`
reports uniform confidence bands based on the multiplier bootstrap by
default. None of the other commands in this comparison provides a uniform
band option. The next table reports joint coverage for the three
post-treatment event times in the balanced-panel design.

<p class="table-title" markdown="span">Joint coverage of the post-treatment path</p>

|                                      | joint coverage of ES(0), ES(1), ES(2) |
| -------------------------------------- | --------------------------------------: |
| `csdid` uniform band                 |                             **0.966** |
| `csdid` three pointwise CIs          |                                 0.906 |
| `jwdid` / `did_imputation` pointwise |                                 0.888 |
| `did_multiplegt_dyn` pointwise       |                                 0.862 |
| `lpdid` pointwise                    |                                 0.444 |

The uniform band has joint coverage of 0.966. Using three pointwise 95%
intervals as if they covered the entire path gives joint coverage between
0.862 and 0.906 among the unbiased estimators, a loss of roughly 4 to 9
percentage points. The 0.444 coverage for `lpdid` mainly reflects its bias,
rather than the distinction between pointwise and simultaneous inference.
For a nested set of additional event times, joint coverage cannot increase.
How much it changes depends on the dependence across the intervals.

Pointwise intervals are appropriate for inference on a coefficient selected
in advance. If a figure is interpreted as evidence about the full path, we
recommend reporting a uniform band. The uniform band is wider by
construction, so simultaneous coverage does come at a cost.

## Reproducing everything

The scripts use fixed seeds, and the recorded package versions and file
hashes identify the software used in the comparison. We compute each population target once, directly from the
data-generating process, and never recompute it from a simulation draw. The producing code is available in the [code appendix](../code-appendix.html)
and the linked diagnostic sources. The
[combined diagnostic wrapper](https://github.com/pedrohcgs/csdid-stata/blob/main/tools/bench/field/publication_diagnostics.do)
also exports the point estimates, standard errors, and event labels used in
the fixed-draw comparisons. These sources
reproduce the results for the designs studied here. Different designs may,
of course, produce different comparisons.

## What we take from this

These exercises compare the commands above using common simulated populations and
population targets fixed in advance. To be clear, we are not saying that the
other commands are incorrectly implemented. The researchers who developed them
have made important contributions to the DiD literature. The differences we
document are mainly consequences of choices about counterfactuals,
aggregation, and inference. Those choices lead to different questions.

Several practical conclusions follow. First, agreement on a balanced panel
does not imply agreement when the probability of appearing in the sample
varies across periods. In our experiments, observation-based aggregation
changes the target and leads to large coverage distortions even though the
population is unchanged.

Second, model specification matters in a familiar way. When the outcome
model is misspecified, estimators that rely only on that model can be
biased. The doubly robust estimator remains consistent when either the
outcome model or the treatment-probability model is correct, although it
does not protect against both being misspecified.

Third, pointwise confidence intervals and uniform confidence bands answer
different inferential questions. A set of pointwise 95% intervals should not
be interpreted as providing 95% coverage for an event-study path.

Finally, we think researchers should be able to reconstruct a reported
aggregate from the underlying ATT(g,t) estimates, their standard errors, and
the aggregation weights. They should also be able to determine which sample
was used. This is why `csdid` reports all ATT(g,t) cells, gives its weights
in closed form, records sample decisions in `e()`, reports overlap failures,
and provides uniform bands by default. Computational speed is relevant
because these diagnostics and inferential procedures should be practical to
use routinely.

Overall, we recommend evaluating any of these commands by whether its output
can be understood and recomputed. This is the standard we have tried to
apply to `csdid`. It performs well in most of the exercises, but not in all
of them, and the code appendix reproduces the cases in which another command
is faster or more precise as well. These simulations do not establish that
`csdid` is the right command for every application. They show which
differences matter in the designs we studied; a design not considered here
can reverse any of the rankings on this page.
