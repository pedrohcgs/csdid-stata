---
title: Anticipation
---

# Anticipation

Callaway–Sant'Anna assumes units do not respond before treatment starts. That
fails when treatment is announced in advance: a state's Medicaid expansion is
legislated before it takes effect, and behaviour can move in between.

If units respond *k* periods early, then those *k* periods are not clean
pre-treatment periods — using one of them as the base period contaminates every
comparison drawn from it. `anticipation(#)` tells `csdid` to treat the last `#`
pre-treatment periods as already affected and to measure from before them.

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

## No anticipation: the default

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) analytical
display "anticipation: " e(anticipation)
display "cells: " e(N_attgt)
estat event
```

## Allowing one period of anticipation

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) anticipation(1) analytical
display "anticipation: " e(anticipation)
display "cells: " e(N_attgt)
estat event
```

Two things happen. The base period moves one period earlier, so every comparison
is drawn from a period the cohort could not yet have responded to. And the
period immediately before treatment is no longer reported as a pre-treatment
placebo — it is now treated as part of the response.

Compare the event-study output from the two runs. Under `anticipation(1)` the
effect at event time −1 is gone, because that period is no longer assumed clean.

## Choosing the value

`anticipation()` is an assumption, not a diagnostic. Set it from what you know
about the policy — when it was announced, signed, or became widely expected —
not by trying values until the pre-trends look flat. Searching over it and
keeping the value with the best-looking pre-treatment plot invalidates the
pre-test you are using to justify the design.

If you genuinely do not know, the honest options are to report the default
alongside a sensitivity check at one period, or to use a design that does not
lean on the immediate pre-treatment period.

The cost is real: each anticipated period removes one usable pre-treatment
period, so effects are measured from further back and cohorts treated early
enough may drop out entirely for want of a clean base period.

## Interaction with the comparison group

With `notyet`, later-treated cohorts serve as controls. If those cohorts are
themselves anticipating, they are not clean controls either. `anticipation()`
applies to them as well — a unit is removed from the comparison group once it is
within the anticipation window of its own treatment date, not only once treated.

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) notyet anticipation(1) analytical
estat event
```

See [Comparison groups](comparison-groups.html) for the choice itself, and
[Pre-testing](pre-testing.html) for reading the pre-treatment cells that remain.

```stata
capture erase "jel_balanced.dta"
```
