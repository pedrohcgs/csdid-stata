---
title: Base periods
---

# Base periods: varying or universal

<div class="note" markdown="1">
Every ATT(g,t) is a difference between period *t* and a *base period*, the
pre-treatment period the comparison is measured from. `base_period()` chooses
which one. It changes the pre-treatment estimates, the shape of an event study,
and how many cells you get back. Nothing in this choice moves the headline
number: the post-treatment effects are identical under either setting.
</div>

- **`universal`** (the default) compares every period with *g-1*.
- **`varying`** compares each pre-treatment period with the one immediately
  before it, and each post-treatment period with *g-1*.

Here *g-1* means the last observed period before treatment, with no
anticipation. With `anticipation(#)`, the reference is the last observed
period before *g - anticipation*; it need not be exactly *g-1* on a gapped
calendar. `e(attgt)` records each cell's reference in `base_time`.

Universal is the default because it is the layout an event-study plot assumes,
and event studies are how these results are almost always presented. R `did`
and Stata `csdid` Version 1.82 both default to `varying` instead, so this is a
deliberate departure from both, and `base_period(varying)` restores their
base-period convention.

## The data

Let's build the balanced sample once. It is the same block used on the other pages
(nothing here is specific to base periods), and both specifications run on it.

```stata
import delimited using ///
    "https://raw.githubusercontent.com/pedrohcgs/JEL-DiD/50f4f18/data/county_mortality_data.csv", ///
    clear varnames(1) bindquote(strict) stringcols(_all)
destring deaths population_20_64 year yaca county_code stfips unemp_rate poverty_rate, ///
    replace force
generate double mrate = 100000 * deaths / population_20_64
drop if missing(mrate) | population_20_64 <= 0
generate int gvar = yaca
replace gvar = 0 if missing(gvar) | gvar > 2019
bysort county_code: generate byte nyears = _N
keep if nyears == 11
save "jel_balanced.dta", replace
```

## Universal: the default

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) analytical
display "cells: " e(N_attgt)
estat event
```

Each pre-treatment number answers a *cumulative* question: how far this cohort
had drifted from the comparison group by period *t*, measured relative to *g-1*.
This is the layout that most event-study plots assume, with everything measured
from a single normalized reference point. We expect most readers of your paper to
have it in mind, and that is why we made it the default.

## Varying

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) base_period(varying) analytical
display "cells: " e(N_attgt)
estat event
```

Each pre-treatment number now answers a *local* question: whether this cohort's
outcome moved between consecutive periods differently from the comparison group.
The pre-treatment cells become a sequence of one-period placebo tests. That is
what you want when the question is *where* a violation happened rather than
*how far* it had accumulated by the time treatment began. See
[Pre-testing](pre-testing.html).

## What actually differs

Two things change between the two runs. One of them is cosmetic and the other is
not, and both are worth seeing.

**Cell counts.** Universal includes the first observed period, comparing it
with the cohort's common base. Varying omits that first period because there
is no preceding observation to compare it with, so it has one fewer row per
cohort here. The universal base-period row is zero by construction; under
varying, that same period is an estimated comparison with the preceding
period. Switching to varying does not simply delete the normalized rows.

**Which cells agree.** Both specifications measure post-treatment periods against
*g-1*, so those cells agree exactly, while the pre-treatment cells differ because
they are answering different questions:

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

The post-treatment difference is zero to numerical precision. That is the result
we wanted, and it is cheap to verify on your own data. The pre-treatment
difference is not zero, and it should not be: the two specifications are asking
different questions of the same data!

Note that the comparison is keyed on *(cohort, period)*. The two runs return
different numbers of rows, so lining them up by row position would silently
compare unrelated cells.

## Which to use

<div class="tip" markdown="1">
Use **`varying`** to examine changes between adjacent observed periods. This
can help locate when groups begin to diverge. These comparisons can still be
correlated, and a temporary shock can affect both the change into that period
and the change out of it. See
[Pre-testing](pre-testing.html).
</div>

<div class="important" markdown="1">
Use **`universal`** when you want a conventional event-study plot with a single
normalized reference period, or when you are presenting cumulative pre-trends.
The estimates share a reference period, so a shock in that reference can
affect many contrasts. Read the full pattern and its uncertainty rather than
counting significant coefficients.
</div>

Whichever you pick, the post-treatment point estimates target the same
effects. The pre-treatment comparisons and the set of cells entering a joint
test or simultaneous band change, so the inference need not be identical.
