# csdid news

## csdid 2.0.0

A rewritten estimation engine. Everything below is what changes for someone
upgrading from `csdid` 1.82; the command surface is deliberately the same, so
most existing do-files run unchanged.

### Changes that can affect your results

**Standard errors are bootstrapped by default.** 1.82 reported analytical
standard errors unless you asked for `wboot`. 2.0.0 defaults to the multiplier
bootstrap with simultaneous confidence bands and 1,000 iterations. Add
`analytical` (or `vce(analytical)`) for pointwise analytical standard errors.
Point estimates are unaffected.

**Unbalanced panels are no longer silently balanced.** 1.82 dropped units that
were not observed in both periods of a comparison, which changes the estimand
without saying so. 2.0.0 keeps every unit and estimates the unbalanced panel
directly. `e(panel_mode)` reports `allow_unbalanced` when this applies. The
`bal()` and `balance()` options are accepted but no longer restore the old
dropping.

**A too-small never-treated group is now refused.** `csdid` stops when the
never-treated group is smaller than `#covariates + 5`, and warns about any
small group. Group size is measured as rows divided by periods — the average
number of units per period — not as distinct units. The two agree on balanced
panels and differ only on unbalanced ones, where the guard now fires in cases
earlier versions estimated. If it fires, `notyet` uses not-yet-treated units as
controls and does not depend on the never-treated group being large. This
changes *whether the command runs*, never an estimate.

### Options that now error instead of being accepted quietly

| Option | 2.0.0 |
| --- | --- |
| `wboot(wtype(mammen\|gaussian\|normal))` | Errors. Only the Rademacher multiplier is supported; these used to be coerced to it silently |
| `wboot(reps(#))` with `#` ≤ 20 | Errors. Fewer than ~20 iterations cannot support a simultaneous band; 1,000 is the default |
| `pscoretrim(#)` with `#` ≤ 0 | Errors. Omit it for the default of .995, or pass 1 (or more) for no trimming |
| `gvar()` with negative values | Errors. `gvar()` is 0 for never-treated units and 1 or more for treated cohorts |
| `time()` below 1 | Errors. Cohorts and periods share one positive calendar-time axis; a monotone relabelling leaves every estimate unchanged |
| `from()` | No longer supported. Use `window(# #)` on `estat event` for event-time windows |
| `dryrun` | Rejected; it was an internal option |

### Fixed

**`csdid` no longer changes a Stata session setting.** Running it left
`matastrict` on, so any Mata code compiled afterwards that did not declare its
variables would fail — including `csdid_rif`, and any Mata of your own. Results
are unaffected.

### New

- **Repeated cross sections.** Omit `ivar()`.
- **Clustered standard errors without the bootstrap.** `cluster()` with
  `analytical` reports cluster-robust standard errors at every aggregation
  level, and the parallel-trends pre-test under clustering.
- **`fix_weights()`** — control how time-varying sampling weights are resolved
  in each 2×2 comparison: `varying`, `base_period`, or `first_period`.
- **Parallel-trends pre-test** reported with the results and stored in
  `e(wald_stat)`, `e(wald_pvalue)` and `e(wald_df)`.
- **Influence functions** exported in `e(inffunc)` for sensitivity analysis or
  custom aggregation.
- **`estat tidy` and `estat glance`**, plus `estat event`, `estat group`,
  `estat calendar`, `estat simple` as conventional postestimation forms.
- **`csdid_plot, saving()`** exports plot-ready data so you keep control of the
  graph styling.
- **Transformation and factor covariates** in the covariate list.
- Substantially faster on large panels, with lower peak memory.
- **No external dependencies.** 1.82 required `drdid` from SSC; 2.0.0 requires
  nothing beyond Stata itself.

### Legacy commands

`csgvar` (and its helper `_gcsgvar`) is carried forward and supported: it builds
the `gvar()` cohort variable from a treatment indicator.

`csdid_rif`, `csdid_table`, `dipt` and `tsvmat` still ship so existing do-files
keep running, but are **deprecated and will be removed in a future release**.
Each prints a notice when called. They are not covered by the numerical test
suite. `help csdid_legacy` documents what to use instead — in short,
`estat tidy, saving()` for a results dataset, with the saved-RIF path still
supported through `csdid_stats using`.

### Compatibility

These are accepted, warn, and map to the documented spelling. New code should
use the names in `help csdid`.

| Accepted | Canonical |
| --- | --- |
| `id()` | `ivar()` |
| `vce(cluster var)` | `cluster(var)` |
| `notyettreated`, `nevertreated` | `notyet`, default control group |
| `allowunbalanced`, `allow_unbalanced` | already the default for unbalanced `ivar()` data |
| `storeall`, `store_all`, `performance(full)`, `performance(materialized)` | `storeall` |
| `baseperiod()`, bare `universal` / `varying` | `base_period()` |
| `method(dripw)`, `method(stdipw)` | `method(dr)`, `method(ipw)` |
| `wboot reps(#) seed(#)` | `wboot(reps(#) rseed(#))` |
| `asinr` | no-op; use `notyet` |
| `bal(full)`, `balance(full)`, `bal(unbal)` | `allowunbalanced` — does **not** restore unit dropping |
| `long`, `long2` | deprecated; imply `baseperiod(universal)` when `baseperiod()` is omitted |
| `agg(event)`, `csdid_stats event` | dynamic aggregation |

### Upgrading

`docs/legacy-migration-guide.md` covers the migration in full, including how to
compare 1.82 and 2.0.0 output on your own data.

---

Development history before this release is in the git log. Verification
evidence — the feature matrix, conformance profile, and parity reports — lives
under `docs/`, `reports/` and `inst/spec/`.
