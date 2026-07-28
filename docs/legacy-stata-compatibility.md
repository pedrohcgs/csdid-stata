# Legacy Stata Compatibility

Status: frozen for conformance profile v1.

## Source

Repository: `https://github.com/pedrohcgs/csdid-stata`

Observed HEAD on 2026-06-22:
`fdbae25521a941314af8d84ec0c93fb0596daa8e`

The checked out ado header reports `version: 1.82`. No top-level license file
was observed. Current Stata behavior is not the estimator oracle; R `did` 2.5.1
is the oracle.

## Compatibility Policy

Legacy behavior may be retained only when:

- it is explicitly requested by an option;
- it emits a compatibility/deprecation warning;
- it has tests comparing old behavior and new R-parity behavior;
- it does not change R-parity defaults;
- it is documented in the migration guide.

Generic warning prefix for retained legacy modes:

`csdid legacy compatibility: this option reproduces behavior from Stata csdid 1.82 and is not the R did 2.5.1 default; see help csdid migration.`

## Command Surface

| Surface | Legacy source | v1 decision |
| --- | --- | --- |
| `csdid` | `codes/csdid.ado`, `codes/csdid.sthlp` | retain as primary command with R-parity defaults |
| `csdid_estat` | `codes/csdid_estat.ado`, postestimation help | retain as Stata postestimation wrapper over R-parity aggregation |
| `csdid_stats` | `codes/csdid_stats.ado`, postestimation help | retain for saved-RIF workflows and R-parity aggregation |
| `csdid_plot` | `codes/csdid_plot.ado` | retain, but tests compare plot data before rendering |
| `csdid_rif` | `codes/csdid_rif.ado` | shipped as deprecated; prints a notice, not covered by the parity suite. Replacement: `estat tidy, saving()`; the saved-RIF path itself remains via `csdid_stats using` |
| `csdid_table` | `codes/csdid_table.ado` | shipped as deprecated; prints a notice, not a parity oracle |
| `csgvar`, `_gcsgvar` | utility ado files | **supported**: builds the `gvar()` cohort variable; verified against `csdid` in `tests/stata/test-legacy-commands.do` |
| `dipt`, `tsvmat` | utility ado files | shipped as deprecated; print a notice, no replacement, never a documented surface |

## Option Inventory

| Option or syntax | Legacy behavior | v1 classification | Contract |
| --- | --- | --- | --- |
| outcome varlist | outcome plus optional covariates | R-parity default | retain |
| `[if] [in]` | Stata sample restrictions | R-parity default | retain and test sample masks |
| `[iw]` | Stata iweights | R-parity syntax sugar | normalize to R `weightsname` contract |
| `[aw] [pw]` wrapper parsing | observed in outer wrapper | unsupported-by-design for v1 | reject with message to use a numeric weight variable through the R-parity weight path |
| `ivar()` | panel id | R-parity default when panel data | retain |
| `id()` | panel id alias | Stata-style alias | map to `ivar()` and reject conflicts |
| omitted `ivar()` | repeated cross sections | R-parity default for RC | retain |
| `time()` | time variable | R-parity default | retain |
| `gvar()` | first treatment period, `0` never-treated | R-parity default | retain with R validation |
| `notyet` | use not-yet-treated controls | R-parity nondefault alias | map to R `control_group = "notyettreated"` |
| `notyettreated` | readable not-yet-treated control alias | Stata-style alias | map to `notyet` |
| `nevertreated` | readable never-treated control alias | Stata-style alias | accept as the R default control-group spelling and reject conflict with `notyet` |
| automatic not-yet when no never-treated | current help says automatic | R-parity warning/coercion | retain only as R 2.5.1 warning/coercion behavior and test under F020 |
| `long` | legacy pre-treatment gaps | compat-only | warn and map to R-compatible ATT(g,t) output and legacy coefficient posting |
| `long2` | legacy event-study sign/gap variant | compat-only | warn and map to R-compatible ATT(g,t), dynamic/event aggregation, and legacy coefficient posting |
| `asinr` | legacy option to mimic R not-yet pre-treatment selection | alias/no-op warning | accept with warning because R-compatible selection is governed by default/D003 and `notyet` |
| `pscoretrim()` | propensity-score trimming | legacy-compatible | retain as compatibility option for DRDID delegation; test default and nondefault. Legacy's default was `1.0`; values >= 1 are accepted and mean NO trimming, matching `DRDID` (`trim.ps[D==0] <- ps < trim.level`, ps capped at `1-1e-06`, no error for `trim.level >= 1`). Only nonpositive/missing refuse. `did::att_gt` exposes no trim argument, so this is a Stata-only extension. |
| `method()` | DRDID estimator method | R-parity default/nondefault plus soft-deprecated aliases | map `dr`, `reg`, and `ipw` to R `did` methods; accept `dripw` as `dr` and `stdipw` as `ipw` with warnings; reject non-R legacy names such as `drimp` and `aipw` unless a future frozen DRDID compatibility decision retains them |
| `agg(event)` | immediate event aggregation output | R-parity nondefault Stata convenience | retain as wrapper over frozen dynamic `aggte` equivalent; other `agg()` types use `csdid_stats` |
| `wboot` | bootstrap option surface | R-parity default-compatible | map to R multiplier bootstrap semantics; legacy wild-bootstrap-only behavior is unsupported |
| `wboot(reps())`, `reps()` | bootstrap reps | R-parity default-compatible | retain |
| `wboot(wtype())`, `wboot(wbtype())` | Bootstrap multiplier naming variants | compat-only | retain only `rademacher`; unsupported values error rather than silently changing the multiplier distribution |
| `wboot(rseed())`, `rseed()` | random seed | R-parity default-compatible | retain and record seed in manifests |
| `wboot reps(#) seed(#)`, `wboot reps(#) rseed(#)` | bootstrap shorthand | Stata-style alias | map to nested `wboot(reps(#) seed(#))` / `wboot(reps(#) rseed(#))`; top-level controls are valid unless analytical inference is explicitly requested |
| `wboot(cluster())` | cluster bootstrap variable | R-parity nondefault | retain and map to R clustering rules |
| `cluster()` | clustered SE | R-parity nondefault | retain and test nested/invalid clusters |
| `vce(cluster clustvar)` | clustered SE | Stata-style alias | map to `cluster(clustvar)` and reject conflicts |
| `level()` | confidence level | R-parity default/nondefault | retain |
| `pointwise` | pointwise CI instead of uniform bands | R-parity nondefault | retain as `cband = FALSE`/pointwise interval request |
| `saverif()` | save RIF dataset | R-parity Stata extension | retain with F034 saved-artifact schema |
| `replace` | overwrite saved artifacts | Stata file behavior | retain |
| `from()` | legacy lower EVENT-TIME bound on the simple/group/calendar aggregations | **unsupported-by-design** | refuse by name. Legacy gated those aggregations on `tlvl[j]-glvl[i] >= from` (default 0). R fixes that bound at event time 0 -- `compute.aggte()` selects simple/group with `which(group <= t & t <= (group + max_e))`, where `group <= t` hardcodes e >= 0 and only the upper bound is adjustable; `min_e` applies solely to `type="dynamic"`. So nonzero `from()` has no R counterpart, and `from(0)`, the legacy default, is already what csdid does. Refused on `csdid`, `csdid_stats` and `csdid_estat`, pointing at `window(# #)` on `type(dynamic)`. |
| `window()` in `csdid_stats`/`estat event` | postestimation event window | Stata-style alias | map to `min_e`/`max_e` |
| `balance()` in `csdid_stats` | balance event windows | Stata-style alias | map to `balance_e` behavior and test under F025/F051 |
| `type(event)` / positional `event` in `csdid_stats` | dynamic aggregation alias | Stata-style alias | map to `type(dynamic)` |
| `estat dynamic`, `estat simple`, `estat group`, `estat calendar` | aggregation replay | Stata-style postestimation | compute through `csdid_stats` and replay `e(aggte)` |
| `estore()` | store estimates | Stata postestimation convenience | retain with state-leak tests |
| `esave()` | save estimates | Stata postestimation convenience | retain with deterministic save schema |
| `post` | post aggregation to e() | Stata postestimation convenience | retain with schema in `inst/spec/fixture-schemas.md` |
| `save` | save graph/data artifacts | Stata convenience | retain with explicit paths only |
| `plot` | immediate postestimation plot | Stata convenience | retain after plot-data parity |
| graph `style()` | plot styling | legacy-compatible | not parity-critical; cosmetic only |
| graph `title()`, `xtitle()`, `ytitle()`, `name()` | plot styling/output | retain as Stata UX | excluded from numeric parity |
| graph `group()` | plot group selection | R-parity nondefault | retain and test plot-data subset |
| graph `pstyle*`, `color*`, `lwidth*`, `legend()` | plot styling | legacy-compatible | cosmetic only |
| `dryrun` | observed internal option | unsupported-by-design for users | reject for public commands |
| `allowunbalanced` / `allow_unbalanced` | explicit unbalanced-panel readability option | Stata-style spelling plus R-parity alias | accept as a no-op because unbalanced `ivar()` data already use the D003 path |
| balance source paths `bal(full)`, `balance(full)`, pair-balanced default, `bal(unbal)` | current unbalanced-panel behavior | soft-deprecated aliases | warn and map to `allowunbalanced`; never restore legacy pair-balanced/full-balanced dropping |

## Required Legacy Tests

- F016: R-parity unbalanced-panel default.
- F017: soft-deprecated `bal()`/`balance()` alias tests for legacy balancing
  modes.
- F035: wild/bootstrap options and seed handling.
- F036: option inventory classification.
- F045: old defaults behind explicit options.
- F046: deprecation warning text.

## Removed Or Unsupported Candidates

These behaviors are not preserved as v1 defaults:

- hidden/internal `dryrun` as a user option;
- old pair-balanced unbalanced-panel behavior as a default;
- old `bal()`/`balance()` pair-balanced and full-balanced unbalanced-panel
  semantics; the option spellings are retained only as warning aliases;
- graph styling syntax that cannot be represented as stable plot-data parity;
- undocumented utility entry points not needed by public commands;
- required network installation of dependencies during default tests.
