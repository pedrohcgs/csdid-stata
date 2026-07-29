# csdid news

## csdid 2.0.0

A rewritten estimation engine. Everything below is what changes for someone upgrading from **csdid Version 1.82** —
the version SSC distributes today via `ssc install csdid`, dated 2025-10-05.
The command surface is deliberately the same, so most existing do-files run
unchanged.

### Changes that can affect your results

**Not-yet-treated is now the default comparison group.** Version 1.82 and the
reference implementation both default to never-treated. Version 2.0.0 uses every
unit not yet treated at *t* as a control. It uses more of the data, usually
gives tighter standard errors, and does not depend on a never-treated group
existing or being large enough to trust. `nevertreated` restores the old
behaviour.

One consequence: the refusal described below, when the never-treated group is
too small, no longer fires by default. That is correct — `notyet` is precisely
the remedy that refusal recommends.

**Universal base period is now the default.** Version 1.82 and the reference
implementation both default to a varying base period. Version 2.0.0 measures
every cell against *g-1*.

This is the layout an event-study plot assumes, and event studies are how these
results are nearly always presented. Post-treatment effects are identical under
either choice; only the pre-treatment cells differ, and universal additionally
reports the *g-1* normalisation row. Use `base_period(varying)` when
**pre-testing**: each pre-treatment cell is then its own one-period comparison,
so a violation shows up in the period where it happens rather than being carried
forward into every later cell.

Both of these are deliberate departures from the reference implementation as
well as from Version 1.82, and are recorded as such in
`inst/spec/feature-matrix.csv`.

**Standard errors are bootstrapped by default, with simultaneous confidence
bands.** Version 1.82 reported pointwise analytical standard errors unless you asked
for `wboot`.

This is deliberate. A staggered design produces one estimate per cohort and
period — often dozens — and pointwise intervals do not account for looking at
all of them at once. Reading a 95% pointwise band as though it covered the whole
event study understates uncertainty, and it is the most common way these results
are over-read. The default is now the multiplier bootstrap with simultaneous
bands over 1,000 iterations, so the interval you are shown is the one that
covers every reported effect jointly.

`analytical` (or `vce(analytical)`) restores pointwise analytical standard
errors, and `pointwise` gives pointwise intervals from the bootstrap. Point
estimates are unaffected by any of this.

**Unbalanced panels are balanced, and say so.** Version 1.82 dropped, without
comment, the units not observed in both periods of each comparison — silently
changing the estimand. Version 2.0.0 makes the choice explicit and reports it.
`bal()` takes three modes:

| | |
| --- | --- |
| `bal(full)` | drop units not observed in every period, once, for all comparisons. **Default**, matching the reference implementation. |
| `bal(pair)` | balance each 2x2 separately, keeping the units observed in both of its periods. This is what Version 1.82 did silently; ask for it to reproduce a result from that version. |
| `bal(none)` | keep every unit and use the repeated-cross-section computation. |

Whenever a mode discards observations, `csdid` reports how many units and how
many observations went. `e(panel_mode)` records the resolved layout.

**Repeated cross sections can be declared, not just inferred.** The new `rcs`
option is the counterpart of the reference implementation's `panel = FALSE`.
Previously the only way to say "these are cross sections" was to omit `ivar()`,
which forced anyone whose cross sections carried an identifier to withhold a
real variable. With `rcs` you keep it: it is validated and used to exclude
observations where it is missing, but each observation is its own unit.
`cluster()` is what puts that identifier back into the standard errors.

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

- **Repeated cross sections.** Omit `ivar()`, or declare them with `rcs` and
  keep the identifier for `cluster()`.
- **Clustered standard errors without the bootstrap.** `cluster()` with
  `analytical` reports cluster-robust standard errors at every aggregation
  level, and the parallel-trends pre-test under clustering.
- **`fix_weights()`** — control how time-varying sampling weights are resolved
  in each 2×2 comparison: `varying`, `base_period`, or `first_period`.
- **Parallel-trends pre-test** reported with the results and stored in
  `e(wald_stat)`, `e(wald_pvalue)` and `e(wald_df)`.
- **Influence functions** exported in `e(inffunc)` for sensitivity analysis or
  custom aggregation.
- **`estat event`, `estat group`, `estat calendar`, `estat simple`,
  `estat dynamic` and `estat attgt`** as conventional postestimation forms.
- **`saving()` on every `estat` subcommand**, which writes what that subcommand
  computed to a dataset — the same option `margins`, `simulate` and `graph`
  take, so there is no separate export command. Previously it worked on
  `estat tidy` and `estat glance` only: `estat attgt` refused it, and on the
  five aggregation subcommands it was parsed and then silently ignored, so
  `estat event, saving(f)` returned success and wrote no file.
- **`csdid_plot, saving()`** exports plot-ready data so you keep control of the
  graph styling.
- **Transformation and factor covariates** in the covariate list.
- Substantially faster on large panels, with lower peak memory.
- **No external dependencies.** Version 1.82 required `drdid` from SSC; 2.0.0 requires
  nothing beyond Stata itself.

### Legacy commands

`csgvar` (and its helper `_gcsgvar`) is carried forward and supported: it builds
the `gvar()` cohort variable from a treatment indicator.

`csdid_rif`, `csdid_table`, `dipt` and `tsvmat` still ship so existing do-files
keep running, but are **deprecated and will be removed in a future release**.
Each prints a notice when called. They are not covered by the numerical test
suite. `help csdid_legacy` documents what to use instead — in short,
`estat attgt, saving()` for a results dataset, with the saved-RIF path still
supported through `csdid_stats using`.

### Compatibility

These are accepted, warn, and map to the documented spelling. New code should
use the names in `help csdid`.

| Accepted | Canonical |
| --- | --- |
| `id()` | `ivar()` |
| `vce(cluster var)` | `cluster(var)` |
| `notyettreated` | `notyet`, the default control group |
| `allowunbalanced`, `allow_unbalanced` | `bal(none)` |
| `balanceall` | `bal(full)` |
| `balancepair` | `bal(pair)` |
| `storeall`, `store_all`, `performance(full)`, `performance(materialized)` | `storeall` |
| `baseperiod()`, bare `universal` / `varying` | `base_period()` |
| `method(dripw)`, `method(stdipw)` | `method(dr)`, `method(ipw)` |
| `wboot reps(#) seed(#)` | `wboot(reps(#) rseed(#))` |
| `asinr` | no-op; use `notyet` |
| `bal(all)` | `bal(full)` |
| `bal(unbal)`, `bal(unbalanced)`, `bal(allow_unbalanced)` | `bal(none)` |
| `long`, `long2` | deprecated; imply `baseperiod(universal)` when `baseperiod()` is omitted |
| `agg(event)`, `csdid_stats event` | dynamic aggregation |

### Upgrading

`docs/legacy-migration-guide.md` covers the migration in full, including how to
compare Version 1.82 and 2.0.0 output on your own data.

---

Development history before this release is in the git log. Verification
evidence — the feature matrix, conformance profile, and parity reports — lives
under `docs/`, `reports/` and `inst/spec/`.
