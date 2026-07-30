# Stored Results API

Status: public API policy for `2.0.0`.

## Stable Public Results

The following results are intended to be stable across compatible releases:

| Result | Type | Stability | Notes |
| --- | --- | --- | --- |
| `e(attgt)` | matrix | stable | Group-time ATT table with group, time, event time, estimate, standard error, and counts. |
| `e(b)` | matrix | stable | Posted coefficient vector for nonbase ATT(g,t) estimates when available. |
| `e(V)` | matrix | stable | Full posted covariance matrix aligned to `e(b)` when available. Analytical runs use influence-function covariance; clustered runs use cluster-summed influence functions; bootstrap runs use bootstrap-draw correlations rescaled to the reported SEs. |
| `e(group_prob)` | matrix | stable | Treated-group probability and count metadata. |
| `e(inffunc)` | matrix | conditional stable | Stored only when `storeall` is requested; otherwise the influence functions stay in the Mata cache at every sample size. |
| `e(unit_group)` | matrix | conditional stable | Stored only when `storeall` is requested. |
| `e(cluster_vec)` | matrix | conditional stable | Stored when clustering is requested and the stored matrices are materialized. |
| `e(boot_attgt)` | matrix | stable when present | Bootstrap ATT(g,t) output when `wboot()` is requested. |
| `e(boot_draws)` | matrix | diagnostic-adjacent | Present for bootstrap runs when stored. Draw ordering is not a portable reproducibility contract. |
| `e(aggte)` | matrix | stable | Posted by `csdid_stats` and `estat` aggregation commands. |
| `e(agg_inffunc)` | matrix | conditional stable | Aggregation influence functions, subject to the same storage policy as ATT(g,t) IFs. |

## Stable Macros And Scalars

Stable macros include `e(cmd)`, `e(cmdline)`, `e(version)`, `e(method)`,
`e(method_requested)`, `e(control_group)`, `e(base_period)`, `e(panel_mode)`,
`e(timevar)`, `e(gvar)`, `e(idvar)`, `e(clustervar)`, `e(weightvar)`,
`e(fix_weights)`, `e(boot_dist)`, `e(boot_seed)`, and `e(storage)`.

Stable scalars include `e(N)`, `e(N_units)`, `e(N_attgt)`, `e(N_groups)`,
`e(N_time)`, `e(level)`, `e(bstrap)`, `e(cband)`, `e(biters)`, `e(pointwise)`,
and `e(N_clusters)`.

`e(fast_mode)`, `e(compute_path)`, `e(fast_used)` and `e(mata_cache)` are
**diagnostics, not stable results**, exactly as `help csdid` marks them: they
describe which internal execution surface ran and may change as the engine is
refined. `e(fast_used)=1` means optimized computation was allowed by the
default `fast(auto)` or by explicit `fast`, and `e(compute_path)` reports the
resolved optimized surface for the data layout. Neither is a promise that the
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
