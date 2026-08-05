---
title: Anticipation
---

# Anticipation

Callaway–Sant'Anna assumes that units do not respond before treatment starts.
That assumption fails when treatment is announced in advance. A state's Medicaid
expansion is legislated well before it takes effect, and the behavior of
hospitals and households alike can move in between.

<div class="note" markdown="1">
If units respond *k* periods early, then those *k* periods are not clean
pre-treatment periods, and using one of them as the base period contaminates every
comparison drawn from it. `anticipation(#)` tells `csdid` to treat the last `#`
pre-treatment periods as already affected and to measure from before them.
</div>

## The data

Let's build the balanced sample once. It is the same block used elsewhere on this
site, and we run it twice below (once with an anticipation window and once
without).

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

The stored anticipation value is zero here (that is the default), and the run
returns the full set of pre-treatment cells, so this is the specification most
readers will assume you used.

## Allowing one period of anticipation

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) anticipation(1) analytical
display "anticipation: " e(anticipation)
display "cells: " e(N_attgt)
estat event
```

Two things happen here. The base period moves one period earlier, so that every
comparison is drawn from a period the cohort could not yet have responded to. The
period immediately before treatment is no longer reported as a pre-treatment
placebo. It is now part of the response.

Compare the event-study output from the two runs (the cell counts differ as
well). Under `anticipation(1)` the
effect at event time −1 is gone, because that period is no longer assumed to be
clean.

## Choosing the value

<div class="important" markdown="1">
`anticipation()` encodes an assumption about behavior; it does not test one. We
recommend setting it from what you know about the policy (when it was announced,
when it was signed, when it became widely expected) instead of by trying values
until the pre-trends look flat, which amounts to searching over specifications.
Searching over it and keeping the value with the best-looking pre-treatment
plot invalidates the pre-test you are then using to justify the design.
</div>

<div class="tip" markdown="1">
If you genuinely do not know, the two options we would consider are reporting the
default alongside a sensitivity check at one period, or moving to a design that
does not lean on the immediate pre-treatment period at all.
</div>

The cost is real, because each anticipated period removes one usable pre-treatment
period. Effects are then measured from further back, and cohorts treated early
enough in the sample may drop out entirely for want of a clean base period (the
earliest cohorts have the fewest pre-periods to spare). We would still take the
value from the institutional record, and we would not set the window to zero
simply to keep those cohorts in the sample.

## Interaction with the comparison group

With `notyet` (the default), later-treated cohorts serve as comparison units, and if those
cohorts are themselves anticipating, then they are not clean comparisons either.
`anticipation()` applies to them as well. A unit leaves the comparison group once
it is within the anticipation window of its own treatment date, which can be a
period earlier than the date itself. A unit can sit in the comparison group one
period and be out of it the next. That bookkeeping is done for you.

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) notyet anticipation(1) analytical
estat event
```

See [Comparison groups](comparison-groups.html) for the choice itself, and
[Pre-testing](pre-testing.html) for reading the pre-treatment cells that remain.
