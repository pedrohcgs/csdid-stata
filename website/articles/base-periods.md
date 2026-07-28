---
title: Base periods
---

# Base periods: varying or universal

Every ATT(g,t) is a difference between period *t* and a **base period** — the
pre-treatment period the comparison is measured from. `base_period()` chooses
which one, and it changes the pre-treatment estimates, the shape of an event
study, and how many cells you get back. It does not change the post-treatment
effects.

- **`varying`** (the default) compares each pre-treatment period with the one
  immediately before it, and each post-treatment period with *g-1*.
- **`universal`** compares every period with *g-1*.

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
save "jel_balanced.dta", replace
```

## Varying: the default

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) base_period(varying) analytical
display "cells: " e(N_attgt)
estat event
```

Each pre-treatment number answers a **local** question: did this cohort's
outcome move between consecutive periods differently from the comparison group?
That makes the pre-treatment cells a sequence of one-period placebo tests.

## Universal

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) base_period(universal) analytical
display "cells: " e(N_attgt)
estat event
```

Each pre-treatment number now answers a **cumulative** question: how far had this
cohort drifted from the comparison group by period *t*, relative to *g-1*? This
is the layout most event-study plots assume, with everything measured from a
single normalized reference point.

## What actually differs

Two things change, and it is worth seeing both.

**You get more cells.** Universal reports the base period itself, which is zero
by construction, so each cohort contributes one extra row. That is why
`e(N_attgt)` grew above.

**Post-treatment effects are identical; pre-treatment ones are not.** Both
specifications measure post-treatment periods against *g-1*, so those cells
agree exactly. The pre-treatment cells differ because they are answering
different questions:

```stata
use "jel_balanced.dta", clear
quietly csdid mrate, ivar(county_code) time(year) gvar(gvar) base_period(varying) analytical
matrix V = e(attgt)
quietly csdid mrate, ivar(county_code) time(year) gvar(gvar) base_period(universal) analytical
matrix U = e(attgt)

mata {
    v = st_matrix("V"); u = st_matrix("U")
    dpost = 0; dpre = 0
    for (i = 1; i <= rows(v); i++) {
        for (j = 1; j <= rows(u); j++) {
            if (v[i,1] == u[j,1] & v[i,2] == u[j,2]) {
                d = abs(v[i,4] - u[j,4])
                if (v[i,2] >= v[i,1]) dpost = max((dpost, d))
                else                  dpre  = max((dpre, d))
            }
        }
    }
    printf("post-treatment cells, largest difference: %g\n", dpost)
    printf("pre-treatment  cells, largest difference: %g\n", dpre)
}
```

The post-treatment difference is zero to numerical precision. The pre-treatment
difference is not, and should not be.

Note the comparison is made on *(cohort, period)* rather than by row position:
the two runs return different numbers of rows, so lining them up by position
would compare unrelated cells.

## Which to use

Use **`varying`** to pre-test parallel trends. Each pre-treatment cell is its own
one-period test, so a violation shows up in the period where it happens instead
of being carried forward into every later cell. See
[Pre-testing](pre-testing.html).

Use **`universal`** when you want a conventional event-study plot with a single
normalized reference period, or when you are presenting cumulative pre-trends.
Be aware that pre-treatment estimates are then serially correlated by
construction — a single early deviation shifts every subsequent point — so a
run of "significant" pre-treatment coefficients can come from one bad period.

Post-treatment conclusions do not depend on this choice.

```stata
capture erase "jel_balanced.dta"
```
