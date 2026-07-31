---
title: Sampling weights
---

# Sampling weights

Pass sampling weights as `[iw=varname]`. They enter the propensity score, the
outcome regression, and the aggregation weights. A weighted run answers a
question about the weighted population.

<div class="important" markdown="1">
For county data, weighting by population changes the estimand from *the effect
on the average county* to *the effect on the average resident*, which is a real
difference whenever small rural counties behave differently from large urban ones
(and in mortality data they usually do).
</div>

## The data

Let's build the sample once (the same block used elsewhere on this site) and run
it both ways, weighted and unweighted.

```stata
import delimited using ///
    "https://raw.githubusercontent.com/pedrohcgs/JEL-DiD/50f4f18/data/county_mortality_data.csv", ///
    clear varnames(1) bindquote(strict) stringcols(_all)
destring deaths population_20_64 year yaca county_code stfips unemp_rate poverty_rate, ///
    replace force
generate double mrate = 100000 * deaths / population_20_64
drop if missing(mrate) | population_20_64 <= 0
generate int gvar = yaca
replace gvar = 0 if missing(gvar) | gvar > 2016
bysort county_code: generate byte nyears = _N
keep if nyears == 11
save "jel_weighted.dta", replace
```

## Unweighted and weighted

We run the same specification twice, once without weights and once with county
population as the weight (everything else about the two commands is identical).

```stata
use "jel_weighted.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) analytical
estat simple
```

```stata
use "jel_weighted.dta", clear
csdid mrate [iw=population_20_64], ivar(county_code) time(year) gvar(gvar) analytical
estat simple
```

The two runs differ only in the weight expression. The estimates they produce need
not agree, and when they disagree it is because the counties that carry most of
the population are not the counties that carry most of the rows in the dataset.

<div class="tip" markdown="1">
If these differ materially, that is a finding about heterogeneity across county
size. We recommend reporting the one that matches the question you are asking,
and saying in the text which one it is.
</div>

Only the scale of the weights is irrelevant. Multiplying every weight by a
constant leaves every ATT(g,t) unchanged:

```stata
use "jel_weighted.dta", clear
quietly csdid mrate [iw=population_20_64], ivar(county_code) time(year) gvar(gvar) analytical
matrix A = e(attgt)
generate double w2 = population_20_64 * 1000
quietly csdid mrate [iw=w2], ivar(county_code) time(year) gvar(gvar) analytical
matrix B = e(attgt)
mata: printf("largest difference after rescaling weights: %g\n", ///
             max(abs(st_matrix("A")[.,4] - st_matrix("B")[.,4])))
```

The largest difference across all cells comes back at numerical noise (machine
precision), which is what we wanted to see!

## Weights that change over time

A unit's weight can move between periods; county population changes every year.
Each 2×2 comparison then has two candidate weights for the same unit, and
something has to decide which of them to use. `fix_weights()` makes that choice
explicit, so it is never left to the order of your data:

| | |
| --- | --- |
| `fix_weights(varying)` | use each observation's own weight |
| `fix_weights(base_period)` | fix every unit's weight at its base-period value |
| `fix_weights(first_period)` | fix every unit's weight at its first-period value |

```stata
use "jel_weighted.dta", clear
csdid mrate [iw=population_20_64], ivar(county_code) time(year) gvar(gvar) ///
    fix_weights(base_period) analytical
estat simple
```

```stata
use "jel_weighted.dta", clear
csdid mrate [iw=population_20_64], ivar(county_code) time(year) gvar(gvar) ///
    fix_weights(varying) analytical
estat simple
```

Compare the two overall numbers before deciding which convention to adopt. Fixing
the weights keeps the target population constant across periods, so a change in
the estimate reflects a change in the outcome and not a change in who is being
counted. Letting the weights vary instead tracks the population as it actually
was over the sample window, migration included. Neither is universally right.
However, whichever you use, state which one it was and why.

None of this changes what parallel trends means. Weighting changes the population
the assumption is applied to (and therefore the estimand), and it does not change
the assumption itself.

When the weights happen to be constant within unit, the choice cannot matter and
the modes agree exactly. Check that before spending time on the decision.

## Weights are not clustering

<div class="note" markdown="1">
Weights say how much of the population each observation represents. Clustering
says which observations share correlated shocks. They are separate options
answering separate questions, and using one of them does not address the other:
</div>

```stata
use "jel_weighted.dta", clear
csdid mrate [iw=population_20_64], ivar(county_code) time(year) gvar(gvar) ///
    cluster(stfips) analytical
estat simple
display "clusters: " e(N_clusters)
```

Treatment here is assigned at the state level, so clustering on state is the
relevant choice regardless of how the observations are weighted, and a weighted
run with the wrong cluster variable is no safer than an unweighted one. See
[Inference](inference.html).

```stata
capture erase "jel_weighted.dta"
```
