# Migrating from csdid Version 1.82

This guide maps each option of Stata `csdid` Version 1.82 onto csdid 2.0.0.
Version 1.82 is the last revision of the 1.8x line (November 2025; commit
`fdbae255` of this repository). SSC distributes Version 1.81, dated
2025-10-05, which differs from Version 1.82 in two places: its `method(ipw)`
did not normalize the weights (Version 1.82 and 2.0.0 do, as its
`method(stdipw)` did), and its aggregation standard errors on repeated cross
sections differ slightly. Where 2.0.0 and Version 1.82 disagree on a number,
2.0.0 follows R `did` 2.5.1, except for the two defaults described below. The
[upgrading guide](https://psantanna.com/csdid/articles/upgrading-from-182.html)
covers the same ground with runnable examples.

## Defaults

Apart from the comparison group and the base period, 2.0.0's defaults match
R `did` 2.5.1, including for unbalanced panels: when `ivar()` is supplied and
the panel is actually unbalanced, the default `bal(full)` drops the units not observed in every
period, once, and reports what it removed -- the same sample R takes.
Version 1.82 balanced each comparison separately instead; that is available only on request as `bal(pair)`. See the fuller statement of the three
`bal()` settings below.

Two omitted-option defaults deliberately differ from both R `did` 2.5.1 and
Stata `csdid` Version 1.82; they are the only two on which csdid and R
disagree when both are left at their defaults:

| | csdid 2.0.0 | R `did` and Version 1.82 | To reproduce those |
| --- | --- | --- | --- |
| comparison group | not-yet-treated | never-treated | `nevertreated` |
| base period | universal | varying | `base_period(varying)` |

State both options explicitly and csdid and R agree to machine precision. Both
are documented divergences.

The remaining defaults follow R: the method is `dr`, the confidence level is 95,
omitted inference is the multiplier bootstrap with simultaneous confidence
bands over 1000 iterations, and the propensity score is trimmed at `.995`. Use
`analytical` or `vce(analytical)` only when analytical standard errors are
deliberately needed; aggregations of an analytical fit still band
simultaneously (the band's critical value is bootstrapped, with a note) unless
`pointwise` is added. Three of these also differ from Version 1.82 and move
numbers: Version 1.82 reported analytical pointwise standard errors, did not
trim (`pscoretrim(1)` turns trimming off), and balanced each comparison
separately.

An unbalanced `ivar()` panel is balanced by dropping the units not observed in
every period -- `bal(full)`, matching R -- and csdid reports how many units and
observations that removed. `bal(none)` keeps every unit and uses the
repeated-cross-section computation. `bal(pair)` balances each 2x2 separately,
which is what Version 1.82 did: it said the panel was unbalanced, but not
which or how many units each comparison dropped. Use `bal(pair)` to reproduce
a result from that version.

To reproduce a Version 1.82 run, add `nevertreated base_period(varying)
analytical pscoretrim(1)`, and `bal(pair)` on an unbalanced panel. The ATT(g,t)
cells, their standard errors and the event-study, calendar and simple
aggregations then agree with Version 1.82, except as the last item below says.
Five differences remain, and no option removes them:

- `notyet` keeps a comparison unit when it is untreated in both periods of the
  comparison, which is Version 1.82's `asinr` rule. With a varying base
  period, Version 1.82's plain `notyet` compared a pre-treatment cell only
  with cohorts treated after *g*, so its pre-treatment cells and pre-test are
  not reproduced.
- `long` gives Version 1.82's `long2` cells, whose pre-treatment cells have the
  opposite sign to Version 1.82's `long`.
- The bootstrap draws Rademacher multipliers only; Version 1.82's `wboot` drew
  Mammen multipliers unless `wbtype(rademacher)` was given.
- The overall standard error of `estat group` differs from Version 1.82's;
  the cohort effects, their standard errors and, except as the next item says,
  the overall effect do not.
- On a balanced panel whose iweights vary over time, the aggregations move.
  Their cohort shares count each unit at its iweight in the first period, which
  is R `did`'s rule for a balanced panel (`compute.aggte.R:206-226`: one row
  per unit from the first period on a panel, each unit's mean over its rows on
  an unbalanced one); Version 1.82 counted each unit at its
  mean iweight over its periods. The simple, calendar and event-study
  aggregations, the overall effect of `estat group`, and their standard errors
  then differ from Version 1.82's. The two rules agree when each unit's iweight
  is constant, and on an unbalanced panel, where R, 2.0.0 under `bal(pair)` and
  Version 1.82 all use the mean. The ATT(g,t), their standard errors and the
  per-cohort effects of `estat group` do not move.

Omitting `ivar()` is repeated cross sections, matching R `panel = FALSE`; the
`rcs` option says the same thing explicitly and lets you keep `ivar()` when the
data carry an identifier anyway.

### The never-treated size check

`csdid` refuses to run when the never-treated comparison group is too small to
be a credible control, and warns about any small group. The size threshold is
`#covariates + 5`, as in R, and group size is measured the way R measures it
-- rows divided by the number of periods, the average number of units per
period (R's `pre_process_did` computes `gcnt / length(tlist)`). On a balanced
panel that is the number of distinct units; on an unbalanced panel it is
smaller. A never-treated group of 5 distinct units observed in only 19 of 20
possible unit-periods averages 4.75 units per period, so with `nevertreated`
and no covariates it is refused, exactly as R refuses it.

Version 1.82 had no size check, so this can stop a `nevertreated` run that
Version 1.82 estimated, on a balanced panel as well as an unbalanced one. The
refusal message names the fix, and it is the same one R recommends:

```stata
csdid y, ivar(id) time(t) gvar(g) notyet
```

`notyet` uses not-yet-treated units as the comparison group, which does not
depend on the never-treated group being large. Alternatively, supply more
never-treated units or fewer covariates (the threshold scales with the
covariate count). The check changes *whether the command runs*; it never
changes an estimate, a standard error, or a critical value.

The refusal is raised whether or not output is suppressed. R's `stop()` is not
conditional on verbosity, so `quietly csdid ...` refuses too rather than
silently proceeding.

## Option mapping

| Version 1.82 surface | 2.0.0 behavior |
| --- | --- |
| `method(dripw)` | Accepted with warning; canonical method is `dr`. |
| `method(stdipw)` | Accepted with warning; canonical method is `ipw`. |
| `method(ipw)` | The normalized estimator, as in Version 1.82. Version 1.81's `method(ipw)` did not normalize the weights; 2.0.0 has no unnormalized version. |
| `method(drimp)` | Refused with return code 198. The improved doubly robust estimator is not offered; `method(dr)` is Version 1.82's `method(dripw)`. |
| `asinr` | Accepted with warning as a no-op; the R-compatible not-yet-treated comparison group is governed by `notyet`, which follows Version 1.82's `asinr` rule. |
| `pscoretrim(#)` | Default `.995`, where Version 1.82 did not trim; `pscoretrim(1)` turns trimming off. |
| `wboot(wtype(rademacher))`, `wboot(wbtype(rademacher))` | Accepted; Rademacher is the only multiplier. |
| `wboot(wtype(mammen))`, `wboot(wtype(gaussian))`, `wboot(wtype(normal))` | Refused with return code 498; only Rademacher multipliers are drawn. Version 1.82 drew Mammen multipliers by default, so a plain `wboot` now draws Rademacher multipliers instead. `wtype()` and `wbtype()` are both accepted spellings of the sub-option, so these fail under either; giving both with different values is itself an error. |
| `wboot reps(#) seed(#)`, `wboot reps(#) rseed(#)` | Accepted as Stata-style shorthand for `wboot(reps(#) seed(#))` and `wboot(reps(#) rseed(#))`; top-level `reps()`, `biters()`, `seed()`, and `rseed()` are also accepted with default bootstrap inference. |
| `unbalanced`, `allowunbalanced`, `allow_unbalanced` | Supported, silent, and not deprecated. `unbalanced` is the documented spelling of the `bal(none)` synonym, typed in full; `allowunbalanced` / `allow_unbalanced` are the R-style longhand for the same thing, also typed in full, since that is the argument name R `did` gives the setting (`att_gt(allow_unbalanced_panel = TRUE)`), so code written with that vocabulary runs here unchanged. All of them mean `bal(none)`, which keeps every unit and uses the repeated-cross-section computation. It is not the default: an unbalanced `ivar()` panel is balanced with `bal(full)` unless you ask otherwise. No abbreviation of any of them is an option -- `unbal` is refused along with the rest, deliberately, since it would read as the refused `bal(unbal)`. Giving any of them together with a `bal()` that means something different is an error rather than a silent resolution. |
| `storeall`, `store_all` | Preferred full stored-result opt-in for users who need large matrices in `e()`. `store_all` is the same option spelled with an underscore. |
| `bal(full)`, `balance(full)`, `bal(unbal)` | `bal(full)` is the default and drops units not observed in every period; `balance()` is the same option written out in full, not a second option. `bal(unbal)` is not a value of `bal()` at all: the vocabulary is `full`, `pair`, `none`, and anything else is refused with return code 198. Not options, and never were: `bal(unbal)`, `bal(unbalanced)`, `bal(allow_unbalanced)`, `bal(all)`, `balanceall` and `balancepair` are options in neither Version 1.82 nor 2.0.0. `bal(none)` is the mode `bal(unbal)` was reaching for, and `unbalanced` (longhand `allowunbalanced`) is the supported synonym of it. None of them restores legacy per-comparison unit dropping -- that is `bal(pair)`. |
| `long`, `long2` | Accepted with a deprecation warning; when `baseperiod()` is omitted they select `baseperiod(universal)`. Both give Version 1.82's `long2` cells, so a do-file that used `long` sees every pre-treatment cell and pre-period event-study coefficient change sign, and the coefficients move one event time earlier (Version 1.82's `Tm1` is 2.0.0's `Tm2` with the sign reversed). |
| `id(idvar)` | Accepted as a Stata-style alias for `ivar(idvar)`; conflicting `id()` and `ivar()` values are rejected. |
| `notyettreated`, `nevertreated` | Accepted as readable comparison-group aliases; `notyettreated` maps to `notyet`, and `nevertreated` selects the never-treated comparison group, which is R's default and not csdid's. |
| `vce(cluster clustvar)` | Accepted as Stata-style syntax for `cluster(clustvar)`; conflicting `vce(cluster ...)` and `cluster()` values are rejected. |
| `dryrun` | Rejected as an internal legacy option. |
| `agg(event)` | Accepted: runs the dynamic aggregation after estimation and posts its coefficients. `agg(simple)`, `agg(group)`, `agg(calendar)` and `agg(attgt)` are refused; run `estat` *type* after `csdid`. |
| `csdid_stats event`, `csdid_stats, type(event)` | Accepted as aliases for dynamic aggregation. |
| `estat dynamic`, `estat simple`, `estat group`, `estat calendar` | Accepted as conventional postestimation aggregation forms backed by `csdid_stats`. |
| graph styling options | Refused with return code 198 on the drawn graph and on `saving()` alike; export the plot data with `csdid_plot, saving()` and style the figure with `twoway`. Version 1.82's `csdid_plot, group()` put periods to treatment on the x axis; 2.0.0's cohort panels use the calendar period, and the exported data carry `event_time` for the old axis. |

Each deprecated spelling above is opt-in, prints a message saying what it
resolved to, and leaves the defaults alone. `unbalanced` / `allowunbalanced`,
`balance()`, `store_all` and the other current synonyms above are present-tense
names for present-tense options, so they are silent by design and there is
nothing to warn about.

## Postestimation forms that are gone

Each of these ran in Version 1.82 and stops a do-file in 2.0.0.

| Version 1.82 | 2.0.0 |
| --- | --- |
| `estat pretrend` | `csdid` prints the pre-test below the ATT(g,t) table and stores it in `e(wald_stat)`, `e(wald_df)` and `e(wald_pvalue)`. `window()` has no equivalent |
| `estat cevent` | No equivalent. `estat event, window(# #)` reports the effects inside an event-time window |
| `estat all` | Run `estat simple`, `estat group`, `estat calendar` and `estat event` |
| `estore()`, `esave()` | `estat` *type*`, post`, then `estimates store` or `estimates save` |
| `estat event, balance(#)` | `csdid_stats event, balance(#)` |
| `csdid, version` | `csdid version` |
| `csdid_stats attgt`, `csdid_stats cevent` | `estat attgt`; `cevent` has no equivalent |
| `csdid_stats` with no type | Aggregates by group, where Version 1.82 redisplayed the active results. Name the type |
| `csdid_stats ..., wboot` | Bootstrap inference is chosen when `csdid` runs; aggregation from a saved RIF file is analytical |
| `csdid_stats ..., save` | `storeall` keeps the aggregation's influence functions in `e(agg_inffunc)` |
| `csdid_stats ..., post` | `estat` *type*`, post` |
| A RIF file written by Version 1.82 | `csdid_stats using` reads files written by 2.0.0's `saverif()`; run `csdid` again with `saverif()`. `csdid_stats` aggregates a file only through `using`, not after `use` |

Coefficient names and stored results have a new layout, documented in
`help csdid`: ATT(g,t) cells are named like `g2004___2005_2003` (Version 1.82:
`g2004:t_2003_2005`); the overall effect of `estat group` and `estat calendar`
is `Overall` (Version 1.82: `GAverage`, `CAverage`); `estat event` reports no
`Pre_avg`; and `e(b)`, `e(V)`, `e(attgt)` and `e(N_clusters)` take the place of
Version 1.82's `e(b_attgt)`, `e(V_attgt)`, `e(gtt)` and `e(N_clust)`.
