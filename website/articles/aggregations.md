---
title: Aggregations
---

# Aggregations

<div class="note" markdown="1">
ATT(g,t) is a table, and an aggregation is what turns that table into an answer.
Which one you want depends on the question you are asking. They answer different
questions -- about exposure, about cohorts, about calendar time -- so a
difference between two of them is information rather than a problem to be
reconciled.
</div>

## The data

The runs below use the county mortality panel from the
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

All four aggregation commands read the same table of cohort-period estimates.
They differ only in how they average its rows (one row per cohort and period).
Note that all four come from one estimation, so you can look at every one without
paying for the bootstrap again!

| | answers |
| --- | --- |
| `event` / `dynamic` | how the effect evolves with exposure |
| `group` | whether cohorts treated at different times differ |
| `calendar` | whether the effect differs by period |
| `simple` | a single summary, weighted by cohort size |

We recommend reporting at least the event study and one overall number, the event
study first. The two together let a reader see whether the single summary is
hiding a trend across exposure. None of these aggregations changes the underlying
estimates; they change only which weighted average of those estimates you are
reading. Disagreement among them tells you about heterogeneity in the data. It
does not mean that one of them is wrong.

## Event-time windows

<div class="important" markdown="1">
At long event times only the early-treated cohorts contribute (by construction),
so a trend across
event time can be **composition, not dynamics**.
</div>

We have two tools for this, and they are not interchangeable.

```stata
csdid_stats, type(dynamic) window(-3 3)     // restrict the event-time range
csdid_stats, type(dynamic) balance(1)       // only cohorts observed 1+ periods post
```

`window()` truncates the range shown; nothing is re-estimated. `balance()` is the
stronger instrument. It restricts the aggregation to cohorts observed for a
common number of post-treatment periods, so the composition of the sample is held
fixed across event time. If the event-study shape changes materially under
`balance()`, the original shape was partly composition. We would then report the
balanced version alongside the unbalanced one.

`min_e()` and `max_e()` are synonyms for the two bounds of `window()`, and
`balance_e()` for `balance()`. We list both spellings because you will meet both
in other people's code (and in ours).

## Missing cells

Some cells cannot be estimated: too few units, no overlap, or a 2×2 comparison
that failed outright. The header of the estimation output tells you when this has
happened. By default an aggregation containing a missing cell is itself missing,
which is loud on purpose. No average is taken over whatever cells happened to
survive. `na_rm` drops the missing cells and averages the rest, which is
sometimes the right thing to do:

```stata
csdid_stats, type(dynamic) na_rm
```

<div class="important" markdown="1">
Use it deliberately. It changes the estimand from "the average over these
cells" to "the average over the cells that worked". That is a different
parameter, not a cleaner estimate of the same one.
</div>

That change is not visible in the reported number. If you use it, we recommend
saying so in the notes to the table, together with how many cells were dropped
and why they failed. A reader who is told that three cells were dropped for lack
of overlap will read the remaining average rather differently from one who is
told nothing at all.

Next: [unbalanced panels](unbalanced-panels.html).
