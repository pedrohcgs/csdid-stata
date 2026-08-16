# Stored Results API

Status: public API policy for `2.0.0`.

## Stable Public Results

The following results are intended to be stable across compatible releases:

| Result | Type | Stability | Notes |
| --- | --- | --- | --- |
| `e(attgt)` | matrix | stable | Group-time ATT table with group, time, event time, estimate, standard error, counts, and `base_time`. Columns 1-9 (`group`, `time`, `event_time`, `att`, `se`, `n_treat_t`, `n_treat_pre`, `n_control_t`, `n_control_pre`) keep their positions; column 10 `base_time` is the reference period the cell was differenced against, and the row whose `base_time` equals its own `time` is the universal-base normalised cell. The printed table shows columns 1-9. |
| `e(b)` | matrix | stable | Posted coefficient vector for nonbase ATT(g,t) estimates when available. The excluded cell is the normalised reference cell identified by `base_time`, not by event time -1; each coefficient name carries the base period the cell actually used. |
| `e(V)` | matrix | stable | Full posted covariance matrix aligned to `e(b)` when available. Analytical runs use influence-function covariance; clustered runs use cluster-summed influence functions; bootstrap runs use bootstrap-draw correlations rescaled to the reported SEs. |
| `e(group_prob)` | matrix | stable | Treated-group probability and count metadata. |
| `e(inffunc)` | matrix | conditional stable | Stored only when `storeall` is requested; otherwise the influence functions stay in the Mata cache at every sample size. |
| `e(unit_group)` | matrix | conditional stable | Stored only when `storeall` is requested. |
| `e(cluster_vec)` | matrix | conditional stable | Stored when clustering is requested and the stored matrices are materialized. |
| `e(boot_attgt)` | matrix | stable when present | Bootstrap ATT(g,t) output when `wboot()` is requested. |
| `e(boot_draws)` | matrix | diagnostic-adjacent | Present for bootstrap runs when stored. Draw ordering is not a portable reproducibility contract. |
| `e(aggte)` | matrix | stable | Posted by `csdid_stats` and `estat` aggregation commands. |
| `e(agg_inffunc)` | matrix | conditional stable | Aggregation influence functions, subject to the same storage policy as ATT(g,t) IFs. |
| `e(boot_aggte)` | matrix | stable when present | Bootstrap aggregation output when the aggregation ran under the bootstrap. |
| `e(agg_boot_draws)` | matrix | diagnostic-adjacent | Aggregation bootstrap draws; same caveat as `e(boot_draws)`. |
| `e(boot_rng_state)` | matrix | replay | The bootstrap RNG state (1 x 625). Exists so `csdid_stats`/`estat` can replay the identical draw stream; not a user-facing result. |

## Stable Macros And Scalars

Stable macros include `e(cmd)`, `e(cmdline)`, `e(version)`, `e(method)`,
`e(method_requested)`, `e(control_group)`, `e(base_period)`, `e(panel_mode)`,
`e(timevar)`, `e(gvar)`, `e(idvar)`, `e(clustervar)`, `e(weightvar)`,
`e(fix_weights)`, `e(boot_dist)`, `e(boot_dist_requested)`, `e(boot_seed)`,
`e(storage)`, `e(yname)`, `e(wtype)`, `e(wexp)`, `e(rif_file)`, and — after an
aggregation — `e(agg_type)` and `e(agg_clustervar)`.

Stable scalars include `e(N)`, `e(N_units)`, `e(N_attgt)`, `e(N_groups)`,
`e(N_time)`, `e(N_aggte)`, `e(level)`, `e(agg_level)`, `e(agg_cband)`,
`e(bstrap)`, `e(cband)`, `e(biters)`, `e(pointwise)`, `e(N_clusters)`,
`e(anticipation)`,
`e(pscoretrim)`, `e(time_first)`, `e(allow_unbalanced)`, `e(crit_val)`,
`e(point_crit_val)`, and — when the pre-test ran — `e(wald_stat)`,
`e(wald_df)`, and `e(wald_pvalue)`.

Stata-convention interoperability results exist so that `estout`, `etable`,
`estat`, and `predict` machinery work without csdid-specific knowledge:
`e(depvar)` (same value as `e(yname)`), `e(vce)`, `e(vcetype)`, `e(reps)`
(same value as `e(biters)`), `e(rseed)` (same value as `e(boot_seed)`),
`e(estat_cmd)`, `e(predict)`, `e(properties)`, and `e(marginsnotok)`. The
csdid-named result is the canonical one of each pair; the convention alias is
stable but exists for third-party packages, not for csdid workflows.

`e(N)` counts the estimation sample, not the observations handed to the
command: it excludes units treated in the first usable period and the periods
removed when no never-treated group exists, both of which the estimator drops
before it computes anything. `e(sample)` marks exactly those observations, so
`summarize ... if e(sample)` and `estat summarize` describe the sample the
estimates come from, and on a balanced panel
`e(N)` = `e(N_units)` * `e(N_time)`. Before 2.0.0 the count and the marker came
from the pre-drop sample while `e(N_units)` came from the post-drop one, so the
three could not all be right at once.

`e(cband)` and `e(agg_cband)` answer different questions and are both stable.
`e(cband)` is the estimation's band request and governs the ATT(g,t) table.
`e(agg_cband)` reports the band the aggregation in `e(aggte)` actually carries,
which is 0 whenever the aggregation is banded pointwise however the estimation
was banded: `type(simple)`, whose single overall effect has no simultaneous
band distinct from the pointwise one, and an estimation whose settled time grid
has two periods. It is posted by every aggregation route, so code that draws
bands by hand should read `e(agg_cband)`, not `e(cband)`, after `csdid_stats`,
`estat` *type*, or `csdid ..., agg()`.

`e(fast_mode)`, `e(compute_path)`, `e(fast_used)`, `e(fast_requested)`,
`e(fast_auto)`, `e(fast_allowed)` and `e(mata_cache)` are
**diagnostics, not stable results**, exactly as `help csdid` marks them: they
describe which internal execution surface ran and may change as the engine is
refined. `e(fast_used)=1` means optimized computation was allowed by the
default `fast(auto)` or by explicit `fast`, and `e(compute_path)` reports the
resolved optimized surface for the data layout. `e(fast_used)` is therefore
identical to `e(fast_allowed)` by construction: neither is a report of which
kernel executed, and they must not be read as independent diagnostics. Neither is a promise that the
narrowest internal balanced, unweighted, no-covariate kernel handled every
cell; eligible cells may still use specialized or baseline Mata subroutines
when required for parity. Do not branch econometric workflows on any of the
four.

## Diagnostic Results

`e(profile)` is diagnostic, not a stable public API. It records internal timing
phases for profiling and support. Phase names may change when implementation
internals are reorganized, provided that numerical parity and stable public
results do not change.

Bootstrap diagnostics include `e(bootstrap_profile)`,
`e(bootstrap_kernel_profile)`, `e(agg_bootstrap_profile)`,
`e(bootstrap_accelerator)`, `e(bootstrap_accelerator_status)`,
`e(bootstrap_accelerator_file)`, `e(bootstrap_accelerator_rc)`, and
`e(bootstrap_accelerator_seconds)`. Seeded aggregation bootstrap also records
`e(agg_boot_accelerator)`, `e(agg_boot_accel_status)`, and
`e(agg_boot_accel_rc)`. These results survive immediate `agg(event)` posting.
They distinguish the optional compiled
multiplier engine from the mandatory Mata fallback and make fail-closed
behavior auditable. They are diagnostic-only and must not be used to select an
estimator or interpret an estimate.

Performance-related macros and scalars are stable only as user diagnostics.
They may be refined to expose better profiling, but they must not be required
for econometric workflows.

`e(mata_cache_token)` is an internal diagnostic used to reject stale lean-mode
postestimation caches. It is not a reproducibility identifier and should not be
used in analysis code.

## Storage Policy

Storage is lean at every sample size. The large influence-function and unit-map
matrices are held in the Mata cache and are not copied into `e()`, whether the
job is small or large; there is no size threshold and no automatic switch.
Requesting `storeall` (equivalently `store_all`) materializes those matrices
in `e()`. There is no option that asks for the default and no `performance()`
option: those spellings have never been part of any release and are refused
with return code 198. Numbers are identical either way -- the choice affects only
where the matrices live.

This policy is part of the public API because one uniform rule means a workflow
that works on a test extract behaves the same way on the full dataset, and
because it protects users from accidental memory blowups while preserving an
explicit compatibility path.
