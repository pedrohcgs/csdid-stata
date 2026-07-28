---
title: Sampling weights
---

# Sampling weights

Pass sampling weights as `[iw=varname]`. They enter the propensity score, the
outcome regression, and the aggregation weights, so a weighted run answers a
question about the weighted population rather than about the sample.

For county data, weighting by population changes the estimand from *the effect
on the average county* to *the effect on the average resident* — a real
difference when small rural counties behave differently from large urban ones.

## The data

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

If these differ materially, that is a finding about heterogeneity across county
size, not a problem to be tuned away. Report the one that matches the question
you are asking, and say which it is.

Only the scale of the weights is irrelevant — multiplying every weight by a
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

## Weights that change over time

A unit's weight can move between periods — county population changes every
year. Each 2×2 comparison then has two candidate weights for the same unit, and
something has to decide which to use. `fix_weights()` makes that explicit:

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

Fixing the weights keeps the target population constant across periods, so a
change in the estimate reflects the outcome rather than a shifting population.
Letting them vary tracks the population as it actually is. Neither is
universally right; state which you used.

When the weights happen to be constant within unit, the choice cannot matter and
the modes agree exactly.

## Weights are not clustering

Weights say how much each observation represents. Clustering says which
observations share correlated shocks. They are separate options answering
separate questions, and using one does not address the other:

```stata
use "jel_weighted.dta", clear
csdid mrate [iw=population_20_64], ivar(county_code) time(year) gvar(gvar) ///
    cluster(stfips) analytical
estat simple
display "clusters: " e(N_clusters)
```

Treatment here is assigned at the state level, so clustering on state is the
relevant choice regardless of how the observations are weighted. See
[Inference](inference.html).

```stata
capture erase "jel_weighted.dta"
```
