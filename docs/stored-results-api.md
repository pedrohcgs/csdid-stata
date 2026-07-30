# Stored Results API

Status: frozen public API policy for `2.0.0-rc1`.

## Stable Public Results

The following results are intended to be stable across compatible releases:

| Result | Type | Stability | Notes |
| --- | --- | --- | --- |
| `e(attgt)` | matrix | stable | Group-time ATT table with group, time, event time, estimate, standard error, and counts. |
| `e(b)` | matrix | stable | Posted coefficient vector for nonbase ATT(g,t) estimates when available. |
| `e(V)` | matrix | stable | Full posted covariance matrix aligned to `e(b)` when available. Analytical runs use influence-function covariance; clustered runs use cluster-summed influence functions; bootstrap runs use bootstrap-draw correlations rescaled to the reported SEs. |
| `e(group_prob)` | matrix | stable | Treated-group probability and count metadata. |
| `e(inffunc)` | matrix | conditional stable | Stored only when `storeall` is requested. Large jobs may keep IFs in Mata cache. |
| `e(unit_group)` | matrix | conditional stable | Stored only when `storeall` is requested. |
| `e(cluster_vec)` | matrix | conditional stable | Stored when clustering is requested and large matrices are materialized. |
| `e(boot_attgt)` | matrix | stable when present | Bootstrap ATT(g,t) output when `wboot()` is requested. |
| `e(boot_draws)` | matrix | diagnostic-adjacent | Present for bootstrap runs when stored. Draw ordering is not a portable reproducibility contract. |
| `e(aggte)` | matrix | stable | Posted by `csdid_stats` and `estat` aggregation commands. |
| `e(agg_inffunc)` | matrix | conditional stable | Aggregation influence functions, subject to the same storage policy as ATT(g,t) IFs. |

## Stable Macros And Scalars

Stable macros include `e(cmd)`, `e(cmdline)`, `e(version)`, `e(method)`,
`e(method_requested)`, `e(control_group)`, `e(base_period)`, `e(panel_mode)`,
`e(timevar)`, `e(gvar)`, `e(idvar)`, `e(clustervar)`, `e(weightvar)`,
`e(fix_weights)`, `e(boot_dist)`, `e(boot_seed)`, `e(fast_mode)`,
`e(performance_mode)`, `e(performance_resolved)`, and `e(compute_path)`.

Stable scalars include `e(N)`, `e(N_units)`, `e(N_attgt)`, `e(N_groups)`,
`e(N_time)`, `e(level)`, `e(bstrap)`, `e(cband)`, `e(biters)`, `e(pointwise)`,
`e(N_clusters)`, `e(fast_used)`, `e(mata_cache)`, `e(store_all)`, and
`e(lean)`.

`e(fast_used)` and `e(compute_path)` describe the public optimized execution
surface: `e(fast_used)=1` means optimized computation was allowed by
`fast(auto)` or `fast`, and `e(compute_path)` reports the resolved optimized
surface for the data layout. It is not a promise that the narrowest internal
balanced, unweighted, no-covariate kernel handled every cell; eligible cells may
still use specialized or baseline Mata subroutines when required for parity.

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

The default storage mode is automatic. Small jobs materialize the expected
stored matrices for convenience. Large jobs avoid copying large influence
function and unit-map matrices into `e()` unless the user requests `storeall`.
This policy is part of the public API because it protects users from accidental
memory blowups while preserving an explicit compatibility path.
