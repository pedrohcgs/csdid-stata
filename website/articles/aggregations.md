---
title: Aggregations
---

# Aggregations

<div class="note" markdown="1">
ATT(g,t) is a table. An aggregation turns it into an answer. Which one you want
depends on the question, and they answer different questions — a difference
between them is information, not a problem to reconcile.
</div>

## The data

Every guide on this site is self-contained: run this first and the rest of the
page follows. It is the county mortality panel from the
[JEL-DiD](https://github.com/pedrohcgs/JEL-DiD) replication package.

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
```

```stata
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)

estat event         // by time since treatment (event study)
estat group         // by cohort
estat calendar      // by calendar period
estat simple        // one overall number
```

| | answers |
| --- | --- |
| `event` / `dynamic` | how the effect evolves with exposure |
| `group` | whether cohorts treated at different times differ |
| `calendar` | whether the effect differs by period |
| `simple` | a single summary, weighted by cohort size |

## Event-time windows

<div class="important" markdown="1">
At long event times only the early-treated cohorts contribute, so a trend across
event time can be **composition rather than dynamics**.
</div>

Two tools:

```stata
csdid_stats, type(dynamic) window(-3 3)     // restrict the event-time range
csdid_stats, type(dynamic) balance(1)       // only cohorts observed 1+ periods post
```

`window()` truncates the range shown. `balance()` is the stronger instrument: it
restricts the aggregation to cohorts observed for a common number of
post-treatment periods, so the composition is held fixed across event time. If
the event-study shape changes materially under `balance()`, the original shape
was partly composition.

`min_e()` and `max_e()` are synonyms for the two bounds of `window()`, and
`balance_e()` for `balance()`.

## Missing cells

Some cells cannot be estimated — too few units, no overlap, a failed 2×2. By
default an aggregation containing a missing cell is missing, which is loud on
purpose. `na_rm` drops them and averages the rest:

```stata
csdid_stats, type(dynamic) na_rm
```

<div class="important" markdown="1">
Use it deliberately: it changes the estimand from "the average over these cells"
to "the average over the cells that worked."
</div>

Next: [unbalanced panels](unbalanced-panels.html).
