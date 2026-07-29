# Legacy-to-Candidate Performance Certification

Date: 2026-07-29

Status: `pass` on the recorded platform.

## Baseline And Policy

- Legacy baseline: `pedrohcgs/csdid-stata@fdbae25521a941314af8d84ec0c93fb0596daa8e`.
- Trials per implementation and scenario: `7`.
- Each implementation runs in a fresh Stata process after one warmup.
- Candidate/legacy execution order alternates by trial.
- Estimator time excludes startup and data loading.
- Peak RSS is sampled from the operating-system process every 2 ms.
- A row passes only when its paired median ratio is below `1.0` and
  the deterministic bootstrap 95% upper bound is also at or below `1.0`
  for both estimator time and peak RSS.
- Unbalanced rows are performance comparisons across intentionally
  different semantics: the candidate performs the R-compatible
  repeated-cross-section computation and the legacy package does not.

## Results

| Scenario | Candidate s | Legacy s | Time ratio | Time upper95 | Candidate MB | Legacy MB | RSS ratio | RSS upper95 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| balanced_reg_analytical | 0.261800000 | 6.043200000 | 0.043321 | 0.044659 | 584.688 | 621.328 | 0.939166 | 0.941029 |
| balanced_dr_covariates_analytical | 0.459333333 | 7.632000000 | 0.059859 | 0.064061 | 414.469 | 447.547 | 0.935430 | 0.937611 |
| balanced_weighted_ipw_analytical | 0.324400000 | 7.686600000 | 0.042928 | 0.044351 | 589.391 | 622.219 | 0.945407 | 0.957216 |
| balanced_cluster_reg_analytical | 0.307000000 | 6.861600000 | 0.044775 | 0.045336 | 589.719 | 623.531 | 0.945026 | 0.947439 |
| balanced_reg_bootstrap | 0.449500000 | 10.613000000 | 0.042354 | 0.042597 | 333.594 | 371.172 | 0.901870 | 0.915007 |
| balanced_dr_covariates_bootstrap | 0.622500000 | 12.540500000 | 0.050590 | 0.050904 | 337.953 | 366.641 | 0.911429 | 0.934500 |
| balanced_weighted_ipw_bootstrap | 0.497500000 | 11.922000000 | 0.041268 | 0.043345 | 338.641 | 370.625 | 0.909413 | 0.920727 |
| balanced_cluster_reg_bootstrap | 0.379000000 | 10.818500000 | 0.034386 | 0.039076 | 334.234 | 365.938 | 0.909404 | 0.917044 |
| unbalanced_dr_weighted_analytical | 0.690000000 | 8.198500000 | 0.082202 | 0.085915 | 324.688 | 356.047 | 0.912883 | 0.930462 |
| unbalanced_dr_weighted_bootstrap | 0.882500000 | 12.288500000 | 0.071411 | 0.073278 | 336.141 | 361.625 | 0.918064 | 0.944003 |
| balanced_event_analytical | 1.120333333 | 6.775666667 | 0.165832 | 0.168784 | 438.719 | 446.219 | 0.983674 | 1.002270 |
| balanced_event_bootstrap | 1.847000000 | 13.023000000 | 0.142596 | 0.144119 | 355.453 | 364.531 | 0.977964 | 0.981051 |
| balanced_event_cband_bootstrap | 1.994500000 | 13.038000000 | 0.152247 | 0.159054 | 362.062 | 368.047 | 0.985910 | 0.987597 |
| balanced_cluster_event_cband_bootstrap | 1.742500000 | 13.140500000 | 0.135061 | 0.136822 | 360.953 | 363.656 | 0.988304 | 1.016499 |
| large_balanced_dr_weighted_analytical | 2.104000000 | 23.913000000 | 0.087902 | 0.090362 | 189.641 | 275.406 | 0.699925 | 0.720677 |

## Decision

All `15` scenarios pass both gates. The worst time
upper bound is `0.168784` for
`balanced_event_analytical`. The worst RSS upper bound is
`1.016499` for `balanced_cluster_event_cband_bootstrap`.

This certifies that the candidate is faster and uses less peak RSS
than the pinned public legacy package on every frozen workload on
this platform. It is not a universal mathematical claim for every
possible dataset, operating system, or Stata release. Windows and
Linux require their own recorded platform rows before final release.
Numerical correctness is governed separately by the R `did` 2.5.1
parity, smoke, adversarial, and JEL gates.

Machine-readable evidence:

- `build/legacy-candidate-ab/runs.csv`
- `build/legacy-candidate-ab/summary.csv`
- `build/legacy-candidate-ab/metadata.json`
