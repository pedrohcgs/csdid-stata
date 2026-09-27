# csdid news

## csdid 2.0.0

A rewritten estimation engine. Everything below is what changes for someone
upgrading from **csdid Version 1.82**, the last revision of the 1.8x line
(November 2025). SSC distributes Version 1.81, dated 2025-10-05; the two ways
it differs from Version 1.82 are listed at the end of the next section. The
command surface is deliberately the same, so most existing do-files run
unchanged.

### Changes that can affect your results

**Not-yet-treated is now the default comparison group.** Version 1.82 defaults
to never-treated. Version 2.0.0 also uses later-treated cohorts while they
remain eligible controls, accounting for the base period and `anticipation()`.
This can use more of the data and does not require a never-treated group.
`nevertreated` restores the old comparison group.

**Universal base period is now the default.** Version 1.82 defaults to a
varying base period. Version 2.0.0 uses one reference period per cohort: the
last observed period before treatment can affect outcomes, or *g-1* on a
consecutive calendar without anticipation.

This is the layout an event-study plot assumes, and event studies are how these
results are nearly always presented. Post-treatment effects are identical under
either choice; only the pre-treatment cells differ, and universal additionally
reports the *g-1* normalisation row. Use `base_period(varying)` when
**pre-testing**: each pre-treatment cell is then its own one-period comparison,
so a violation shows up in the period where it happens rather than being carried
forward into every later cell.

**Standard errors are bootstrapped by default, with simultaneous confidence
bands.** Version 1.82 reported pointwise analytical standard errors unless you asked
for `wboot`.

This is deliberate. A staggered design produces one estimate per cohort and
period — often dozens — and pointwise intervals do not account for looking at
all of them at once. Reading a 95% pointwise band as though it covered the whole
event study understates uncertainty, and it is the most common way these results
are over-read. The default is now the multiplier bootstrap with simultaneous
bands over 1,000 iterations, so the interval you are shown on each estimated
effect is the one that covers them jointly. (An aggregation's overall summary
effect is the exception: being a single number, it is reported with a pointwise
interval.)

`analytical` (or `vce(analytical)`) restores analytical standard errors; an
aggregation's per-effect rows still carry a simultaneous band — its critical
value is bootstrapped, with a note, because there is no other way to compute
one — unless `pointwise` is added. `pointwise` gives pointwise intervals from
either inference. Point estimates are unaffected by any of this.

One effect is deliberately exempt: the overall summary of an aggregation —
`Post_avg` on the event study, `Overall` on the group and calendar
aggregations, `ATT` on the simple one, and the `ATT(Average)` row of
`estat tidy` — is reported with a *pointwise* interval even when the effects
it summarizes carry a simultaneous band. A simultaneous band answers whether a
whole set of effects lies inside its intervals at once; a single summary number
has no set to be simultaneous over. An `estat event` table can therefore show
both kinds of interval at once, and it says so beneath the table.

**The bootstrap draws Rademacher multipliers.** Version 1.82's `wboot` drew
Mammen multipliers unless `wbtype(rademacher)` was given. Version 2.0.0 draws
Rademacher multipliers only, so a do-file that bootstraps gets different draws
and therefore different bootstrap standard errors and bands; `wbtype(mammen)`
is refused.

**Propensity scores are trimmed at .995.** Version 1.82 did not trim. Under
`method(dr)` and `method(ipw)`, Version 2.0.0 drops comparison observations
whose estimated propensity score is .995 or more, without a message, and where
that binds the estimates move. `pscoretrim(1)` turns trimming off.

**Unbalanced panels are balanced once, and csdid says how many units went.**
Version 1.82 balanced each comparison separately: it said the panel was
unbalanced, but not which or how many units each comparison dropped.
Version 2.0.0 makes the choice explicit and reports it. `bal()` takes three modes:

| | |
| --- | --- |
| `bal(full)` | drop units not observed in every period, once, for all comparisons. **Default**. |
| `bal(pair)` | balance each 2x2 separately, keeping the units observed in both of its periods. This is what Version 1.82 did; ask for it to reproduce a result from that version. |
| `bal(none)` | keep every unit and use the repeated-cross-section computation. |

Whenever a mode discards observations, `csdid` reports how many units and how
many observations went. `e(panel_mode)` records the resolved layout.
`unbalanced` is a supported synonym of `bal(none)`, for when that reads better
than a mode inside `bal()`; `allowunbalanced` and `allow_unbalanced` are the
longhand forms of the same setting. All three are typed in full — no abbreviation of them is an
option.

**`notyet` pre-treatment cells follow Version 1.82's `asinr` rule.** In a
pre-treatment cell with a varying base period, Version 1.82's `notyet`
compared cohort *g* only with cohorts treated after *g*; its `asinr` option
compared it with every cohort not yet treated at *t*. Version 2.0.0's `notyet`
keeps a comparison unit when it is untreated in both periods of the
comparison, which is the `asinr` rule. Under `notyet base_period(varying)` the
pre-treatment cells, the event study's pre-period coefficients and the
pre-test therefore differ from Version 1.82's plain `notyet`, and no option
reproduces them; post-treatment cells do not change.

**`long` reports pre-treatment cells with the opposite sign.** Version 1.82's
`long` and `long2` gave the same pre-treatment cells with opposite signs. In
2.0.0 both select `base_period(universal)`, which is Version 1.82's `long2`.
A do-file that used `long` therefore sees every pre-treatment ATT(g,t) change
sign, and each pre-period event-study coefficient change sign and move one
event time earlier: Version 1.82's `Tm1` is 2.0.0's `Tm2` with the sign
reversed, and 2.0.0's `Tm1` is the reference row, fixed at 0.

**The group aggregation's overall standard error.** `estat group` reports the
same cohort effects, cohort standard errors and overall effect as Version 1.82,
and a different standard error for the overall effect: 0.0119 against
Version 1.82's 0.0118 on the package's `mpdta` example with `lpop` as
covariate, and a wider gap under sampling weights. The event-study, calendar and simple
aggregations report Version 1.82's standard errors.

**Time-varying iweights move the aggregations on a balanced panel.** The
cohort shares behind the simple, calendar and event-study aggregations, and
behind the overall effect of `estat group`, count each unit at its iweight in
the first period; Version 1.82 counted it at its mean iweight over its periods.
Where a unit's iweight varies over time, those estimates and their standard
errors differ from Version 1.82's, including the ones the previous paragraph
lists as unchanged. The two rules agree when each unit's iweight is constant,
and on an unbalanced panel under `bal(pair)`, which also uses the mean. The
ATT(g,t), their standard errors and the per-cohort effects of `estat group` do
not move.

**Repeated cross sections can be declared, not just inferred.** Use the new
`rcs` option to declare this sampling structure explicitly.
In Version 1.82 the only way to say "these are cross sections" was to omit `ivar()`,
which forced anyone whose cross sections carried an identifier to withhold a
real variable. With `rcs` you keep it: it is validated and used to exclude
observations where it is missing, but each observation is its own unit.
`cluster()` is what puts that identifier back into the standard errors.

**A never-treated comparison group that is too small is refused.**
Version 1.82 had no size check. When never-treated units are the comparison group
(`nevertreated`), Version 2.0.0 stops if that group is smaller than
`#covariates + 5`, and it warns about any small group. Group size is measured
as rows divided by periods — the average number of units per period. The
check can stop a `nevertreated` run that Version 1.82 estimated, on a balanced
panel as well as an unbalanced one; `notyet`, the default, does not depend on
the never-treated group being large. This changes *whether the command runs*,
never an estimate.

**A panel that is not shaped like a panel is refused, and the message says
which variable is at fault.** With `ivar()` supplied, Version 2.0.0 makes three
checks before it estimates anything, each its own error: a unit may appear at
most once per period, `gvar()` must be constant within a unit (treatment timing
is irreversible), and `cluster()`, when given, must be constant within a unit
too.

The middle one is new. Version 1.82 estimated a panel in which a unit's cohort
changed from one period to the next — a treatment history that has no reading.
The other two were already stopped, but by the machinery underneath the command
rather than by the command: a duplicated row surfaced as `repeated time values
within panel` and a moving cluster as `panels are not nested within clusters`,
neither of which mentions `csdid` or the option that caused it. The sample must
also contain at least two distinct units; that case used to fail with a
conformability error from inside the estimator.

All three are judged on the data as `if` and `in` leave it, before any row is
set aside for carrying a missing value and before `bal(full)` balances the
panel. A duplicated row is still a duplicated row when the second copy has no
outcome, no weight or no covariate, and a fault inside a unit that balancing
would drop is still reported instead of disappearing with the unit. The
two-distinct-units requirement is counted the other way round — after every
reduction and after `bal(full)` — because it describes the sample that will
actually be estimated. Like the refusal above, this changes *whether the
command runs*, never an estimate.

**An outcome that never changes is refused.** When the outcome takes the same
value in every observation of the estimation sample, Version 2.0.0 stops with
`r(459)` and names the variable and the value. Version 1.82 estimated it, and
returned a table in which every ATT(g,t) was exactly 0 with a missing standard
error — which reads like a precisely estimated null rather than like an empty
result. Warnings did fire, but each named the symptom (standard errors could
not be computed) and none named this cause.

The test is exact equality of the extremes, and it is applied to the estimation
sample: an outcome flattened by an `if` is refused even when the variable
varies elsewhere, and an outcome that varies by one part in a million is
degenerate-but-estimable and still runs. This is the third refusal that changes
*whether the command runs*, never an estimate.

**Upgrading from Version 1.81, the SSC release.** Two further differences
apply. Version 1.81's `method(ipw)` weighted without normalizing the weights;
Version 1.82 and 2.0.0 normalize them (Version 1.81's `method(stdipw)`), so
`method(ipw)` estimates change and 2.0.0 has no unnormalized version. And the
aggregation standard errors on repeated cross sections differ slightly from
Version 1.81's.

**To reproduce a Version 1.82 run**, add `nevertreated base_period(varying)
analytical pscoretrim(1)`, and `bal(pair)` on an unbalanced panel. Five things
stay different: `notyet` pre-treatment cells, the sign convention of `long`,
Mammen bootstrap draws, the overall standard error of `estat group`, and, on a
balanced panel whose iweights vary over time, the aggregations.

### Stored results

**`e()` carries the estimation contract; unit-level objects stay internal.**
The influence functions — one row per unit, one column per ATT(g,t) — drive
every standard error, aggregation, and bootstrap, and they live inside the
estimation engine. Every feature computes from that internal copy: `estat`,
`csdid_stats`, `test`/`lincom` (with full covariances), `csdid_plot`, and
`saverif()`. This is the same division of labor official Stata commands use
for unit-level quantities, and it is what keeps large estimations fast:
copying an n-unit matrix into `e()` costs quadratic time in the number of
units. Two explicit routes expose the influence functions when you want them —
`storeall` materializes `e(inffunc)`, `e(unit_group)`, and `e(cluster_vec)`
as Stata matrices, and `saverif()` writes the durable dataset that
`csdid_stats using` aggregates in any later session.

### Options that now error

| Option | 2.0.0 |
| --- | --- |
| `method(drimp)` | Errors. The improved doubly robust estimator is not offered; `method(dr)` is Version 1.82's `method(dripw)` |
| `wboot(wbtype(mammen))` | Errors. Only the Rademacher multiplier is supported |
| `wboot(reps(#))` with `#` ≤ 20 | Errors. `reps()` must exceed 20; 1,000 is the default |
| `pscoretrim(#)` with `#` ≤ 0 | Errors. Omit it for the default of .995, or pass 1 (or more) for no trimming |
| `gvar()` with negative values | Errors. `gvar()` is 0 for never-treated units and 1 or more for treated cohorts |
| `time()` below 1 | Errors. Add the same constant to time and treated cohort codes; leave never-treated codes at zero |
| `from()` | Errors. Use `window(# #)` on `estat event` for event-time windows |
| `dryrun` | Rejected; it was never a documented option |

### Postestimation forms that are gone

Each of these ran in Version 1.82 and stops a do-file in 2.0.0.

| Version 1.82 | 2.0.0 |
| --- | --- |
| `estat pretrend` | `csdid` prints the pre-test below the ATT(g,t) table and stores it in `e(wald_stat)`, `e(wald_df)` and `e(wald_pvalue)`. `window()` has no equivalent |
| `estat cevent` | No equivalent. `estat event, window(# #)` reports the effects inside an event-time window |
| `estat all` | Run `estat simple`, `estat group`, `estat calendar` and `estat event` |
| `estore()`, `esave()` | `estat` *type*`, post`, then `estimates store` or `estimates save` |
| `estat event, balance(#)` | `csdid_stats event, balance(#)` |
| `csdid ..., agg(simple)`, `agg(group)`, `agg(calendar)` or `agg(attgt)` | `csdid`, then `estat` *type*. `agg(event)` still works |
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

### New

- **`rcs`**, which declares repeated cross sections and keeps the identifier
  for `cluster()`.
- **`fix_weights()`** — control how time-varying sampling weights are resolved
  in each 2×2 comparison: `varying`, `base_period`, or `first_period`.
- **Parallel-trends pre-test** printed below the ATT(g,t) table and stored in
  `e(wald_stat)`, `e(wald_pvalue)` and `e(wald_df)`.
- **Influence functions on request** — `storeall` materializes them as
  `e(inffunc)` for sensitivity analysis or custom aggregation, and
  `csdid_stats using` aggregates a `saverif()` file later, in another session
  or on another machine.
- **`estat dynamic`, `estat plot`, `estat tidy` and `estat glance`** join
  `estat event`, `estat group`, `estat calendar`, `estat simple` and
  `estat attgt`. `estat plot` is `csdid_plot` under its `estat` spelling.
- **`saving()` on every `estat` subcommand**, which writes what that subcommand
  computed to a dataset — the same option `margins`, `simulate` and `graph`
  take, so there is no separate export command.
- **`csdid_plot, saving()`** exports plot-ready data — estimates, band bounds,
  and axis values — so you can draw the figure with `twoway` exactly as you
  want it. A bare `csdid_plot` still draws: ATT(g,t) panels by cohort, or the
  active event-study, cohort, or calendar aggregation. Unlike Version 1.82, that drawn
  graph takes no styling options; `saving()` is the styling route.
- **No external dependencies.** Version 1.82 required `drdid` from SSC; 2.0.0 requires
  nothing beyond Stata itself.

### Performance

Version 2.0.0 is a rewritten engine, and speed at scale was a design goal
alongside accurate estimation and inference.

**Against Version 1.82, on identical data with 2.0.0 pinned to that
version's own defaults so both versions compute the same numbers: gains range
from 10x to 308x**, depending
on the design — this range comes from designs whose size is varied on purpose
(periods, cohorts, rows), which is a different measurement from the
fixed-size workload table in the README. The gain grows with the number of
periods and the number of
cohorts, because those are what drive the number of ATT(g,t) cells: 27x at
five periods and 308x at forty, 106x at three cohorts and 194x at six. It is
smallest on repeated cross sections, which was Version 1.82's fastest path,
at 10x.
At one million rows Version 1.82 could not be timed at all inside a
two-minute per-call ceiling, where 2.0.0 takes 1.53 seconds.

These scaling comparisons were measured on 21 August 2026 with StataNow/MP
19.5 on a 10-core Apple M1 Max. The
[Version 1.82 comparison](https://psantanna.com/csdid/articles/speed-vs-182.html)
documents their settings. In the same measurement campaign, the
[within-package comparison](https://psantanna.com/csdid/articles/csdid-against-the-field.html#speed)
records:

- A one-million-row panel estimates and aggregates the event study in 1.24
  seconds with analytical standard errors, and in 1.40 seconds at 999 bootstrap
  replications with uniform confidence bands. (The shipped default is
  `reps(1000)`; 999 is what these runs were timed at.)

Separate measurements on 7 August 2026, also using StataNow/MP 19.5 on
Apple Silicon, cover the following workflows. Their
[recorded timings](https://github.com/pedrohcgs/csdid-stata/blob/main/tools/bench/field/results/news-timings.csv)
identify the measured design and whether a warmup was discarded.

- A 350,000-row panel takes between 0.39 and 0.74 seconds for every method
  (`dr`, `reg`, `ipw`), with or without covariates. A 400,000-observation
  repeated cross section with 20 periods and 12 cohorts takes about 3.2 seconds.
- Aggregations reuse the ATT(g,t) estimates and their influence functions.
  In these workloads, including aggregation inference,
  `estat event` takes 0.06 seconds after a 20,000-unit estimation and 0.26
  seconds after 100,000 units (a million-row panel).
- In the multiplier bootstrap, 199 replications on a 350,000-row panel add
  about 0.02 seconds over the analytical fit. On macOS a compiled plugin shipped with the package
  runs explicitly seeded (`rseed()`) bootstraps; unseeded draws, and every
  other platform, use Mata, which draws the same multipliers and agrees to
  floating-point rounding.
- `saverif()` writes its dataset in about 0.27 seconds at 20,000
  units.

The design rule behind these numbers: no object with one row per unit ever
crosses into Stata's classic-matrix layer, whose cost is quadratic in a
matrix's longest dimension. Unit-level results live in the engine, in
variables, or in files — never in `e()` matrices, unless you ask with
`storeall`.

### Legacy commands

`csgvar` (and its helper `_gcsgvar`) is carried forward and supported: it builds
the `gvar()` cohort variable from a treatment indicator.

`csdid_rif`, `csdid_table`, `dipt` and `tsvmat` still ship so existing do-files
keep running, but are **deprecated and will be removed in a future release**.
Each prints a notice when called. They are not covered by the numerical test
suite. `help csdid_legacy` documents what to use instead — in short,
`estat attgt, saving()` for a results dataset, with the saved-RIF path still
supported through `csdid_stats using` for files written by 2.0.0's `saverif()`.

### Compatibility

These are accepted and map to the documented spelling. Six print a message
saying what they resolved to: `method(dripw)`, `method(stdipw)`, `asinr`,
`long`, `long2` and `never`. The rest are current names rather than
deprecations and run silently. New code should use the names in `help csdid`.

| Accepted | Canonical |
| --- | --- |
| `id()` | `ivar()` |
| `vce(cluster var)` | `cluster(var)` |
| `notyettreated` | `notyet`, the default comparison group |
| `storeall`, `store_all` | `storeall` |
| `balance()` | `bal()`, the same option unabbreviated |
| `unbalanced` | `bal(none)`. Supported and silent, not deprecated: the documented synonym, for when it reads better than a mode inside `bal()`. Typed in full; `unbal` is not an option, since it would read as the refused `bal(unbal)`. Combining it with a conflicting `bal()` is an error |
| `allowunbalanced`, `allow_unbalanced` | `bal(none)`, same as `unbalanced`. Supported, silent, not deprecated, and typed in full |
| `baseperiod()`, bare `universal` / `varying` | `base_period()` |
| `method(dripw)`, `method(stdipw)` | `method(dr)`, `method(ipw)` |
| `wboot reps(#) seed(#)` | `wboot(reps(#) rseed(#))` |
| `asinr` | no-op; use `notyet` |
| `long`, `long2` | deprecated; imply `baseperiod(universal)` when `baseperiod()` is omitted. `long` reverses the sign of Version 1.82's `long` pre-treatment cells (see above) |
| `never` | `nevertreated`, which is not the default |
| `agg(event)`, `csdid_stats event` | dynamic aggregation |

#### Spellings that are not options

None of these is an option in Version 1.82 or in 2.0.0. Each is refused as an
unknown option (return code 198).

| Not an option | Use instead |
| --- | --- |
| `bal(unbal)`, `bal(unbalanced)`, `bal(allow_unbalanced)` | `bal(none)`, or the `unbalanced` spelling of it (longhand `allowunbalanced`) |
| `balanceall`, `bal(all)` | `bal(full)` |
| `balancepair` | `bal(pair)` |
| `lean`, `performance()` in every form | nothing to type: storage is internal at every sample size, and `storeall` is the one switch that changes it |

`unbalanced` and `allow_unbalanced` are not in this table: as *options* they
are supported (see above). What is refused is `unbalanced` or
`allow_unbalanced` as a *value inside* `bal()`.
`e(allow_unbalanced)` and the `allow_unbalanced` value of `e(panel_mode)` are
stored-result names and are unaffected.

### Upgrading

The [migration guide](https://psantanna.com/csdid/articles/upgrading-from-182.html)
covers the migration in full, including how to compare Version 1.82 and
2.0.0 output on your own data.
