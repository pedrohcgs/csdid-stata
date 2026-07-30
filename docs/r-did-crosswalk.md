# R `did` 2.5.1 <-> Stata `csdid` crosswalk

This is a complete, two-way mapping between the R package
[`did`](https://bcallaway11.github.io/did/) 2.5.1 (Callaway and Sant'Anna) and
this Stata `csdid` package. Read it left to right if you are porting R code to
Stata, and right to left if you are reading a Stata log and want to know which
R call produced the same numbers.

The Stata side of every row was read off the `syntax` lines in
`src/ado/*.ado` and exercised in Stata; the R side of every row was read off
the installed package (`args(did::att_gt)`, `args(did::aggte)`, and the package
help). Nothing here is inferred from documentation alone.

Contents:

1. [How the two packages line up](#1-how-the-two-packages-line-up)
2. [`att_gt()` arguments -> `csdid` options](#2-att_gt-arguments---csdid-options)
3. [`aggte()` arguments -> `csdid_stats` options](#3-aggte-arguments---csdid_stats-options)
4. [R return values -> Stata `e()` results](#4-r-return-values---stata-e-results)
5. [Other R entry points](#5-other-r-entry-points)
6. [Where the two deliberately differ](#6-where-the-two-deliberately-differ)
7. [Not available on the Stata side](#7-not-available-on-the-stata-side)
8. [Worked example: the same analysis in both languages](#8-worked-example-the-same-analysis-in-both-languages)
9. [How to reproduce this document](#9-how-to-reproduce-this-document)

---

## 1. How the two packages line up

| R `did` | Stata `csdid` |
| --- | --- |
| `att_gt()` | `csdid` |
| `aggte()` | `csdid_stats`, or `estat` after `csdid` (`csdid_estat`) |
| `tidy()` / `glance()` | `estat tidy` / `estat glance` |
| `ggdid()` | `csdid_plot` (writes plot **data**; you draw the graph) |
| `summary()` | the table `csdid` and `csdid_stats` print, and `estat attgt` |
| the `MP` object | the `e()` results left by `csdid` |
| the `AGGTEobj` object | the `e()` results left by `csdid_stats` |
| a `data.frame` argument | the dataset in memory, plus `if` / `in` |

R composes objects (`mp <- att_gt(...)`, then `aggte(mp, ...)`). Stata composes
through `e()`: `csdid ...` leaves the group-time results in `e()`, and
`csdid_stats` reads them from there. The only Stata-side state you must be aware
of is that `csdid_stats` (and `estat dynamic|group|calendar|event`) posts
`e(aggte)`, which changes what `csdid_plot` exports; rerun `csdid` to get back to
the group-time results.

---

## 2. `att_gt()` arguments -> `csdid` options

R signature (verified with `args(did::att_gt)` against the installed 2.5.1):

```r
att_gt(yname, tname, idname = NULL, gname, xformla = NULL, data,
       panel = TRUE, allow_unbalanced_panel = FALSE,
       control_group = c("nevertreated", "notyettreated"),
       anticipation = 0, weightsname = NULL, fix_weights = NULL,
       alp = 0.05, bstrap = TRUE, cband = TRUE, biters = 1000,
       clustervars = NULL, est_method = "dr", base_period = "varying",
       faster_mode = TRUE, print_details = FALSE, pl = FALSE, cores = 1,
       compute_inffunc = TRUE, ...)
```

Stata syntax (from `src/ado/csdid.ado`):

```stata
csdid depvar [covariates] [if] [in] [iweight] , time(tvar) gvar(gvar) [options]
```

| R argument | R default | csdid option | csdid default | Notes |
| --- | --- | --- | --- | --- |
| `yname` | required | `depvar`, the first variable in the varlist | required | Must be numeric. |
| `tname` | required | `time(varname)` | required | Must be numeric. |
| `idname` | `NULL` | `ivar(varname)` (alias `id()`) | none = repeated cross sections | Must be **numeric** in Stata; `egen id = group(strid)` first. |
| `gname` | required | `gvar(varname)` | required | `0` = never treated in both packages; negative values are rejected. |
| `xformla` | `NULL` (`~1`) | the covariates after `depvar` in the varlist | none | `xformla = ~ x1 + x2` is `csdid y x1 x2, ...`. Factor-variable notation (`i.x`, `c.x##c.x`) is expanded before estimation. The intercept is always included, as in R. |
| `data` | required | the dataset in memory | - | Restrict the sample with `if` / `in` rather than subsetting a data frame. |
| `panel` | `TRUE` | `ivar()` specified or not | not specified | `panel = FALSE` (repeated cross sections) is `csdid` **without** `ivar()`. `e(panel_mode)` reports which mode ran. |
| `allow_unbalanced_panel` | `FALSE` | `allowunbalanced` (alias `allow_unbalanced`) | see notes | **Deliberate divergence.** In Stata an unbalanced `ivar()` panel already uses R's unbalanced (repeated-cross-section) computation; the option is accepted as an explicit, no-op declaration and prints a note. See [section 6](#6-where-the-two-deliberately-differ). |
| `control_group` | `"nevertreated"` | `notyet` (aliases `notyettreated`); `nevertreated` / `never` are accepted no-ops | `nevertreated` | `e(control_group)` reports `nevertreated` or `notyettreated`. Specifying both errors. |
| `anticipation` | `0` | `anticipation(#)` | `0` | Must be nonnegative. |
| `weightsname` | `NULL` | `[iweight = varname]` | none | Stata weight syntax, normalized to R's `weightsname` contract. |
| `fix_weights` | `NULL` | `fix_weights()` (alias `fixweights()`) | none | Accepted values: `varying`, `base` / `baseperiod` / `base_period`, `first` / `firstperiod` / `first_period`. `base` and `first` require `ivar()`, as in R. `e(fix_weights)` reports the canonical value. |
| `alp` | `0.05` | `level(#)` | `c(level)`, i.e. 95 unless you changed it | `level = 100 * (1 - alp)`. `alp = 0.10` is `level(90)`. |
| `bstrap` | `TRUE` | bootstrap is the default; `analytical` or `vce(analytical)` turns it off | bootstrap | `e(bstrap)` is 1/0. `reps()`, `biters()`, `seed()`, `rseed()` with `analytical` is an error, not a silent no-op. |
| `cband` | `TRUE` | `pointwise` turns uniform bands off | uniform bands | `cband = FALSE` is `pointwise`. `e(cband)` is 1/0. Uniform bands require the bootstrap in both packages. |
| `biters` | `1000` | `biters(#)`, `reps(#)`, `wboot(biters(#))`, or `wboot(reps(#))` | `1000` | All four spellings set the same thing; two spellings that disagree is an error. |
| `clustervars` | `NULL` | `cluster(varname)`, `vce(cluster varname)`, or `wboot(cluster(varname))` | none (unit level) | R takes at most two variables and one of them must be `idname`; Stata takes the one non-unit clustering variable, which is the same thing. Must be numeric. `e(N_clusters)` reports the count. |
| `est_method` | `"dr"` | `method(dr\|reg\|ipw)` | `dr` | Legacy aliases: `dripw` -> `dr`, `stdipw` -> `ipw`, both with a deprecation note. A user-supplied estimator function has no Stata equivalent. |
| `base_period` | `"varying"` | `base_period()` / `baseperiod()`, or the bare keywords `varying` / `universal` | `varying` | `e(base_period)` reports it. |
| `faster_mode` | `TRUE` | `fast` / `nofast` (closest analogue, not a port of R's internals) | optimization allowed | Both are speed switches that leave the estimand alone, and both default to on, but they optimize different code: R reorganizes its data handling, Stata selects specialized Mata kernels. `nofast` is the way to ask for the unoptimized path, as `faster_mode = FALSE` is in R. `e(fast_used)` reports whether the optimized path actually engaged and `e(compute_path)` names it. |
| `print_details` | `FALSE` | prefix the command with `quietly` to suppress, run it plain to see diagnostics | diagnostics shown | Stata's `c(noisily)` gate replaces the argument; there is no `print_details()` option. |
| `pl`, `cores` | `FALSE`, `1` | - | - | No parallel backend; the engine is single-threaded Mata. |
| `compute_inffunc` | `TRUE` | - | always computed | No equivalent: influence functions are always computed and kept internal. `storeall` materializes them in `e()`; `saverif()` writes them to a dataset. |
| `...` (extra args for a custom `est_method`) | - | - | - | Custom estimators are not supported. |
| `set.seed(n)` before the call | - | `rseed(#)`, `seed(#)`, `wboot(rseed(#))`, `wboot(seed(#))` | unseeded | For the same integer, the Stata run reproduces R's multiplier draws; see [section 8](#8-worked-example-the-same-analysis-in-both-languages). |

Stata-only options on `csdid`, with no R counterpart:

| csdid option | What it does |
| --- | --- |
| `pscoretrim(#)` | Propensity-score trimming threshold passed to the doubly robust / IPW step (default `0.995`). |
| `saverif(filename) [replace]` | Writes the influence functions to a dataset that `csdid_stats using` can re-aggregate later without re-estimating. |
| `agg(event)` | Runs `csdid` and then the dynamic aggregation in one command, posting the event-study coefficients. Other aggregation types go through `csdid_stats`. |
| `lean`, `storeall`, `performance(auto\|lean\|full)` | Storage policy for the large influence-function matrices: internal by default at every sample size; `storeall` (or `performance(full)`) materializes them in `e()`. Numbers are identical either way. |
| `vce(analytical)`, `vce(cluster var)` | Stata-idiomatic spellings of `bstrap = FALSE` and `clustervars`. |
| `long`, `long2`, `asinr`, `never`, `bal()` / `balance()`, `performance(materialized)`, `dripw`, `stdipw` | Legacy Stata `csdid` Version 1.82 compatibility spellings. Each either maps to an R-parity setting or is a warned no-op; see `docs/legacy-stata-compatibility.md`. |

---

## 3. `aggte()` arguments -> `csdid_stats` options

R signature (verified with `args(did::aggte)`):

```r
aggte(MP, type = "group", balance_e = NULL, min_e = -Inf, max_e = Inf,
      na.rm = FALSE, bstrap = NULL, biters = NULL, cband = NULL,
      alp = NULL, clustervars = NULL)
```

Stata syntax (from `src/ado/csdid_stats.ado`):

```stata
csdid_stats [type] [, type(type) level(#) window(min max) balance(#) dropmissing ...]
csdid_stats using filename [, ...]
```

| R argument | R default | csdid_stats option | csdid_stats default | Notes |
| --- | --- | --- | --- | --- |
| `MP` | required | the `csdid` results already in `e()` | - | Or `csdid_stats using rif.dta`, reading a file written by `csdid, saverif()`. |
| `type` | `"group"` | `type(simple\|group\|dynamic\|calendar)`, or the same word as a positional argument | `group` | `type(event)` and the positional `event` are accepted aliases for `type(dynamic)`. `e(agg_type)` reports the canonical value. |
| `balance_e` | `NULL` | `balance(#)` or `balance_e(#)` | none | Dynamic aggregation only. Matches R's event-time grid and values. |
| `min_e` | `-Inf` | `min_e(#)`, or the first number in `window(min max)` | `-Inf` | `min_e()` and `window()` cannot be combined. |
| `max_e` | `Inf` | `max_e(#)`, or the second number in `window(min max)` | `Inf` | Both packages ignore `min_e` / `max_e` / `balance_e` for `type(calendar)`; R does so silently, Stata prints a warning first. |
| `na.rm` | `FALSE` | `dropmissing`, `na_rm`, or `na.rm` | `FALSE` | All three spellings are the same option. |
| `alp` | inherited from the `MP` object | `level(#)` | inherited from `e(level)` | Omitting `level()` inherits the estimation-time level, exactly as R inherits `alp` from the `MP` object. `e(agg_level)` reports what was used. |
| `bstrap` | inherited | - | inherited from `e(bstrap)` | **Cannot be overridden at aggregation.** See [section 6](#6-where-the-two-deliberately-differ). |
| `biters` | inherited | - | inherited from `e(biters)` | Same. |
| `cband` | inherited | - | inherited from `e(cband)` | Same. |
| `clustervars` | inherited | `cluster(varname)` or `clustervars(varname)` | inherited from `e(clustervar)` | Accepted only when it names the variable `csdid` already clustered on; anything else is refused with return code 498 and a message telling you to re-run `csdid`. R has the same restriction (it can only honor clusters `att_gt()` stored); when it cannot honor the request it warns and reports *unclustered* standard errors. Stata refuses instead of reporting a different quantity than you asked for. |

`estat` is a thin wrapper over the same code path, for users who prefer Stata's
postestimation idiom:

| `estat` call | Equivalent |
| --- | --- |
| `estat attgt` | redisplay `e(attgt)` |
| `estat event [, window(a b) level(#) post]` | `csdid_stats, type(dynamic) na_rm ...`, then post event-study coefficients |
| `estat dynamic \| simple \| group \| calendar [, window() level() post]` | `csdid_stats, type(...)` |
| `estat tidy, saving(f) [replace]` | a `broom::tidy()`-shaped dataset |
| `estat glance, saving(f) [replace]` | a `broom::glance()`-shaped dataset |

With `post`, the aggregated effects become `e(b)` / `e(V)` so that `test` and
`lincom` operate on them. Coefficient names are `Tm#` / `Tp#` plus `Post_avg`
for dynamic aggregation, `G#` plus `Overall` for group, `T#` plus `Overall` for
calendar, and `ATT` for simple.

---

## 4. R return values -> Stata `e()` results

### 4.1 `att_gt()` / the `MP` object

| R (`mp$...`) | Stata | Notes |
| --- | --- | --- |
| `group` | `e(attgt)`, column `group` | |
| `t` | `e(attgt)`, column `time` | Stata also exports `event_time` = `t - g`, which R computes on the fly. |
| `att` | `e(attgt)`, column `att` | Also posted to `e(b)`, named `g<g>___<t>_<g-1>` (e.g. `g2004___2005_2003`). Cells at event time -1 and cells with a missing ATT are not posted, so `e(b)` can be shorter than `e(attgt)` has rows. |
| `se` | `e(attgt)`, column `se` | Bootstrap SE when `bstrap`, analytical otherwise - same rule as R. Under the bootstrap, `e(boot_attgt)` carries both `se_boot` and `se_analytic`. |
| `c` | `e(crit_val)` | The simultaneous critical value under `cband`, the pointwise one otherwise. `e(point_crit_val)` always holds the normal quantile. |
| `inffunc` | `e(inffunc)` under `storeall`, or `saverif()` as a dataset | One column per ATT(g,t), one row per unit (per observation for repeated cross sections), as in R. R identifies rows by `rownames`; Stata identifies them by the `id` column of `e(unit_group)`. Stored subject to the storage policy in `docs/stored-results-api.md`. |
| `V_analytical` | `e(V)`, with a caveat | Under `analytical` / `vce(analytical)`, `e(V)` is the influence-function covariance, i.e. R's `V_analytical`. Under the bootstrap, `e(V)` is instead built from the bootstrap draws and rescaled to the reported SEs, so it is *not* R's `V_analytical`. R returns both objects; Stata posts one. |
| `n` | `e(N_units)` | `e(N)` is the number of observations, not units. |
| `alp` | `e(level)` | `level = 100 * (1 - alp)`. |
| `W`, `Wpval` | not implemented | The Wald pre-test statistic and its p-value are not computed. `csdid` does emit R's warnings when no usable pre-treatment cells exist. |
| `aggte` | `e(aggte)` after `csdid_stats` | |
| `DIDparams` | the option macros | `e(cmdline)`, `e(method)`, `e(control_group)`, `e(base_period)`, `e(panel_mode)`, `e(fix_weights)`, `e(clustervar)`, `e(anticipation)`, `e(bstrap)`, `e(cband)`, `e(biters)`, `e(boot_seed)`, `e(pscoretrim)`. |

`e(attgt)` columns, in order:
`group`, `time`, `event_time`, `att`, `se`, `n_treat_t`, `n_treat_pre`,
`n_control_t`, `n_control_pre`. The last four counts have no R counterpart.

### 4.2 `aggte()` / the `AGGTEobj` object

| R (`agg$...`) | Stata | Notes |
| --- | --- | --- |
| `type` | `e(agg_type)` | |
| `egt` | `e(aggte)`, column `egt` | Event time, cohort, or calendar period depending on `type`. |
| `att.egt` | `e(aggte)`, column `att` | |
| `se.egt` | `e(aggte)`, column `se` | |
| `overall.att` | `e(aggte)`, column `overall_att` | Constant down the column, so it survives `matlist`. `estat <type>, post` puts it in `e(b)`. |
| `overall.se` | `e(aggte)`, column `overall_se` | |
| `crit.val.egt` | `e(crit_val)` under bootstrap inference | Under the bootstrap, `csdid_stats` posts the aggregation's own `e(crit_val)` and `e(point_crit_val)`. Under analytical inference it posts neither, and `e(crit_val)` still holds the value from the estimation step: the aggregation's critical value is then the normal quantile at `e(agg_level)`. `estat tidy` and `csdid_plot` already apply that rule; if you build bands by hand, apply it too. |
| `inf.function` | `e(agg_inffunc)` | Columns `effect1 ... effectK`, then `overall`. |
| `min_e`, `max_e`, `balance_e` | not stored | The values you passed are honored but are not echoed into `e()`; `e(cmdline)` and your own do-file are the record. |
| `DIDparams` | inherited `e()` macros from the estimation step | `csdid_stats` does not clear them. |

`e(aggte)` columns, in order: `egt`, `att`, `se`, `overall_att`, `overall_se`.

---

## 5. Other R entry points

| R | Stata | Notes |
| --- | --- | --- |
| `ggdid(mp)` | `csdid_plot, saving(f) replace` after `csdid` | Writes ATT(g,t) plot data; you draw it. See `help csdid_plot`. |
| `ggdid(agg)` | `csdid_plot, saving(f) replace` after `csdid_stats` | Same for the active aggregation. `type(simple)` has no plot in either package (R stops, Stata exits 498, same message). |
| `ggdid(..., group = c(...))` | `group(numlist)` | Same fallback behavior and message when a requested cohort does not exist. |
| `tidy(mp)`, `tidy(agg)` | `estat tidy, saving(f) replace` | Same columns (order may differ), with `.` replaced by `_` in the Stata variable names (`std_error`, `conf_low`, `point_conf_high`, ...) and the R spelling kept as the variable label. Same `term` strings, including `ATT(Average)` / `ATT(simple average)`, and the same leading `Average` row for group aggregation. |
| `glance(mp)`, `glance(agg)` | `estat glance, saving(f) replace` | Same columns: `nobs`, `ngroup`, `ntime`, `control_group`, `est_method`, plus `type` for an aggregation. |
| `summary(mp)` | the table `csdid` prints, or `estat attgt` | |
| `did::mpdta` | `examples/data/mpdta.csv` | R's column `first.treat` is `first_treat` in the CSV, since Stata names cannot contain `.`. |
| `conditional_did_pretest()` | not implemented | |
| `did::mboot()` | internal Mata (`e(boot_draws)`, `e(boot_rng_state)`) | Not a public Stata entry point. |

---

## 6. Where the two deliberately differ

Each of these is a recorded decision, not an accident.

**6.1 Unbalanced panels default to R's unbalanced computation.**
R's `allow_unbalanced_panel` defaults to `FALSE`, which silently drops units not
observed in every period. In Stata, an unbalanced `ivar()` panel is analyzed
with R's *unbalanced* (repeated-cross-section) computation by default; no units
are dropped for being unbalanced. `allowunbalanced` is accepted as an explicit
declaration of that intent and prints a note; `bal()` / `balance()` are
soft-deprecated legacy spellings that also map to it. `e(panel_mode)` always
tells you which of `panel`, `allow_unbalanced`, or `repeated-cross-section`
actually ran. Rationale and scope: decision D003 in `docs/behavior-decisions.md`.
To reproduce R's default, balance the panel yourself before calling `csdid`.

**6.2 Aggregation inference is inherited, not re-specifiable.**
R's `aggte()` lets you flip `bstrap`, `biters`, and `cband` at the aggregation
step. `csdid_stats` reads them from `e()` and does not accept overrides: an
aggregation reports the same kind of inference as the estimation it aggregates.
`level()` *is* accepted, and omitting it inherits `e(level)`. If you want a
different bootstrap setting, re-run `csdid`.

**6.3 A mismatched aggregation cluster is refused, not silently downgraded.**
Both packages can only cluster at aggregation on information `att_gt()` /
`csdid` already stored. When the request cannot be honored, R warns and returns
standard errors that do not account for clustering at all; `csdid_stats` exits
with return code 498 and tells you to re-run `csdid` with the cluster you want.
Neither behavior is wrong, but the Stata one cannot be missed in a log.

**6.4 Plotting produces data, not a figure.**
`ggdid()` returns a `ggplot` object with a fixed theme. `csdid_plot` writes a
dataset with the estimates, band bounds, x values, and pre/post labels, and
leaves rendering to `twoway`. Styling options are rejected rather than ignored.

**6.5 Numeric identifiers are required.**
R accepts any `idname` column type. Stata requires `ivar()`, `time()`, `gvar()`,
and `cluster()` to be numeric and errors otherwise (`egen id = group(strid)`).

**6.6 The bootstrap engine is pure Mata.**
No compiled component is installed with the package. The multiplier bootstrap
runs in Mata and reproduces R's random-number stream; `e(bootstrap_accelerator)`
and `e(bootstrap_accelerator_status)` report which path ran.

Legacy-Stata-facing divergences (options that exist only to ease migration from
Stata `csdid` Version 1.82, and that R has no notion of) are catalogued separately in
`docs/legacy-stata-compatibility.md` and `docs/legacy-migration-guide.md`.

---

## 7. Not available on the Stata side

Say so plainly rather than papering over it. These R features have no Stata
equivalent in this release:

- a user-supplied `est_method` function, and the `...` arguments that feed it;
- `compute_inffunc = FALSE` (point estimates only, no influence functions);
- `pl` / `cores` parallel execution;
- `print_details = TRUE` (use `quietly` / plain execution to control output);
- the `W` / `Wpval` Wald pre-test of parallel trends on the `MP` object;
- `conditional_did_pretest()`;
- re-specifying `bstrap` / `biters` / `cband` inside `aggte()` (see 6.2);
- `min_e` / `max_e` / `balance_e` echoed back as stored results (see 4.2).

Conversely, these Stata features have no R equivalent: `saverif()` and
`csdid_stats using`, `pscoretrim()`, `agg(event)`, the storage-policy options,
`estat` posting of aggregated coefficients for `test` / `lincom`, and the
diagnostic `e(profile)` / accelerator results.

---

## 8. Worked example: the same analysis in both languages

Data: the Callaway and Sant'Anna county teen-employment panel - `did::mpdta` in
R, `examples/data/mpdta.csv` in Stata (2,500 observations, 500 counties, 2003-2007,
cohorts 2004 / 2006 / 2007 and never-treated).

Specification: outcome `lemp`, covariate `lpop`, never-treated controls, doubly
robust estimation, varying base period.

### 8.1 Analytical standard errors

```r
library(did)
data(mpdta)
out <- att_gt(yname = "lemp", tname = "year", idname = "countyreal",
              gname = "first.treat", xformla = ~lpop, data = mpdta,
              control_group = "nevertreated", est_method = "dr",
              bstrap = FALSE, cband = FALSE)
es <- aggte(out, type = "dynamic", na.rm = TRUE)
gp <- aggte(out, type = "group",   na.rm = TRUE)
```

```stata
import delimited using "examples/data/mpdta.csv", clear asdouble varnames(1)
csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat) vce(analytical)
csdid_stats event, dropmissing
csdid_stats group, dropmissing
```

ATT(g,t), both packages, printed to ten decimals:

| g | t | R `att` | Stata `att` | R `se` | Stata `se` |
| --- | --- | --- | --- | --- | --- |
| 2004 | 2004 | -0.0145296683 | -0.0145296683 | 0.0221291572 | 0.0221291572 |
| 2004 | 2005 | -0.0764218817 | -0.0764218817 | 0.0286713142 | 0.0286713142 |
| 2004 | 2006 | -0.1404483368 | -0.1404483368 | 0.0353781547 | 0.0353781547 |
| 2004 | 2007 | -0.1069038981 | -0.1069038981 | 0.0328864930 | 0.0328864930 |
| 2006 | 2004 | -0.0004721461 | -0.0004721461 | 0.0222234370 | 0.0222234370 |
| 2006 | 2005 | -0.0062025246 | -0.0062025246 | 0.0184957019 | 0.0184957019 |
| 2006 | 2006 | 0.0009605737 | 0.0009605737 | 0.0194001954 | 0.0194001954 |
| 2006 | 2007 | -0.0412938656 | -0.0412938656 | 0.0197211441 | 0.0197211441 |
| 2007 | 2004 | 0.0267277962 | 0.0267277962 | 0.0140656608 | 0.0140656608 |
| 2007 | 2005 | -0.0045765708 | -0.0045765708 | 0.0157177631 | 0.0157177631 |
| 2007 | 2006 | -0.0284474872 | -0.0284474872 | 0.0181808812 | 0.0181808812 |
| 2007 | 2007 | -0.0287813610 | -0.0287813610 | 0.0162389530 | 0.0162389530 |

Critical value: R `out$c` = 1.959963984540053, Stata `e(crit_val)` =
1.9599639845.

Dynamic aggregation (`aggte(type = "dynamic")` <-> `csdid_stats event`):

| e | R `att.egt` | Stata `att` | R `se.egt` | Stata `se` |
| --- | --- | --- | --- | --- |
| -3 | 0.0267277962 | 0.0267277962 | 0.0140656608 | 0.0140656608 |
| -2 | -0.0036164714 | -0.0036164714 | 0.0129283311 | 0.0129283311 |
| -1 | -0.0232439872 | -0.0232439872 | 0.0144851302 | 0.0144851302 |
| 0 | -0.0210603598 | -0.0210603598 | 0.0114942117 | 0.0114942117 |
| 1 | -0.0530032043 | -0.0530032043 | 0.0163464516 | 0.0163464516 |
| 2 | -0.1404483368 | -0.1404483368 | 0.0353781547 | 0.0353781547 |
| 3 | -0.1069038981 | -0.1069038981 | 0.0328864930 | 0.0328864930 |

Overall (R `overall.att` / `overall.se`; Stata `overall_att` / `overall_se`):
-0.0803539498 and 0.0189575572 in both.

Group aggregation (`aggte(type = "group")` <-> `csdid_stats group`):

| cohort | R `att.egt` | Stata `att` | R `se.egt` | Stata `se` |
| --- | --- | --- | --- | --- |
| 2004 | -0.0845759462 | -0.0845759462 | 0.0245648746 | 0.0245648746 |
| 2006 | -0.0201666459 | -0.0201666459 | 0.0174696250 | 0.0174696250 |
| 2007 | -0.0287813610 | -0.0287813610 | 0.0162389530 | 0.0162389530 |

Overall: -0.0328195972 and 0.0118981787 in both.

### 8.2 Seeded multiplier bootstrap

R seeds with `set.seed()` immediately before `att_gt()`; Stata passes the same
integer to `rseed()`:

```r
set.seed(20260726)
outb <- att_gt(yname = "lemp", tname = "year", idname = "countyreal",
               gname = "first.treat", xformla = ~lpop, data = mpdta,
               bstrap = TRUE, biters = 1000, cband = TRUE)
```

```stata
csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat) ///
    wboot(reps(1000) rseed(20260726))
```

| g | t | R bootstrap `se` | Stata bootstrap `se` |
| --- | --- | --- | --- |
| 2004 | 2004 | 0.0238683921 | 0.0238683921 |
| 2004 | 2005 | 0.0303044730 | 0.0303044730 |
| 2004 | 2006 | 0.0389630003 | 0.0389630003 |
| 2004 | 2007 | 0.0334402756 | 0.0334402756 |
| 2006 | 2004 | 0.0223693692 | 0.0223693692 |
| 2006 | 2005 | 0.0177528143 | 0.0177528143 |
| 2006 | 2006 | 0.0195012553 | 0.0195012553 |
| 2006 | 2007 | 0.0192487929 | 0.0192487929 |
| 2007 | 2004 | 0.0164228817 | 0.0164228817 |
| 2007 | 2005 | 0.0158417227 | 0.0158417227 |
| 2007 | 2006 | 0.0193036276 | 0.0193036276 |
| 2007 | 2007 | 0.0161492992 | 0.0161492992 |

Simultaneous critical value: R `outb$c` = 2.7069128461, Stata `e(crit_val)` =
2.7069128461. Point estimates are unchanged from 8.1 in both packages.

This is not a coincidence of this dataset: the port reproduces R's
random-number stream, so for the same integer seed the raw multiplier draw
matrix, the bootstrap standard errors, and the simultaneous critical values
agree with R to within 3.4e-14 of the quantity's own scale, including on
unbalanced panels and with `cluster()`.

### 8.3 `balance_e`, the trickiest option to port

`balance_e` drops cohorts that are not observed for at least `#` post-treatment
periods, which changes the event-time grid as well as the values:

```r
aggte(out, type = "dynamic", balance_e = 0, na.rm = TRUE)   # egt -3 .. 0
aggte(out, type = "dynamic", balance_e = 1, na.rm = TRUE)   # egt -2 .. 1
```

```stata
csdid_stats event, dropmissing balance(0)
csdid_stats event, dropmissing balance(1)
```

| `balance_e` | grid | R overall | Stata overall |
| --- | --- | --- | --- |
| 0 | -3, -2, -1, 0 | -0.0210603598 (se 0.0114942117) | -0.0210603598 (se 0.0114942117) |
| 1 | -2, -1, 0, 1 | -0.0286030223 (se 0.0139374782) | -0.0286030223 (se 0.0139374782) |

Both the grid and the values match; the event-time truncation agrees with R to
1.1e-15.

---

## 9. How to reproduce this document

Everything above was produced from R `did` 2.5.1 with `DRDID` 1.3.0 and this
Stata tree. To regenerate the numbers in section 8:

```bash
Rscript -e 'args(did::att_gt)'    # section 2 signature
Rscript -e 'args(did::aggte)'     # section 3 signature
```

then run the R and Stata blocks in section 8 verbatim; print with
`sprintf("%.10f", ...)` on the R side and
`matrix list e(attgt), format(%20.10f)` on the Stata side.

Broader evidence for the parity claims quoted here: the package ships a
57-test certification suite (all passing) built on frozen R fixtures, and
`docs/parity-verification-playbook.md` describes how the fixtures are
regenerated. Group-time and dynamic-aggregation estimates agree with R to
7e-15 under `method(dr)`, `method(ipw)`, and `method(reg)` with analytical
standard errors, on weighted, unbalanced, and `mpdta` fixtures.

Related reading:

- `help csdid` carries an abbreviated one-table version of section 2 for quick
  lookup at the keyboard; this document is the complete two-way reference
- `help csdid_stats`, `help csdid_estat`, `help csdid_plot`
- `docs/behavior-decisions.md` - the frozen decisions behind section 6
- `docs/legacy-stata-compatibility.md`, `docs/legacy-migration-guide.md` - the
  Stata Version 1.82 -> 2.0 mapping, which is a different question from this document
- `docs/stored-results-api.md` - stability guarantees for the `e()` results in
  section 4
