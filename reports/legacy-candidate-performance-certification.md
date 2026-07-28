# Legacy-to-Candidate Performance Certification

Date: 2026-07-28

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
| balanced_reg_analytical | 0.273400000 | 7.268400000 | 0.036111 | 0.042355 | 584.219 | 619.703 | 0.942740 | 0.956213 |
| balanced_dr_covariates_analytical | 0.418666667 | 8.302333333 | 0.049980 | 0.052676 | 419.109 | 451.094 | 0.926801 | 0.946041 |
| balanced_weighted_ipw_analytical | 0.305600000 | 7.718000000 | 0.038770 | 0.046291 | 585.969 | 624.875 | 0.937588 | 0.950940 |
| balanced_cluster_reg_analytical | 0.246800000 | 6.814400000 | 0.038418 | 0.041565 | 588.344 | 626.359 | 0.936283 | 0.948187 |
| balanced_reg_bootstrap | 0.423500000 | 9.397000000 | 0.044993 | 0.046998 | 332.688 | 372.547 | 0.888648 | 0.897412 |
| balanced_dr_covariates_bootstrap | 0.605500000 | 10.756500000 | 0.053405 | 0.056954 | 338.031 | 371.922 | 0.908361 | 0.933072 |
| balanced_weighted_ipw_bootstrap | 0.468000000 | 11.033000000 | 0.042573 | 0.043766 | 325.859 | 372.188 | 0.877959 | 0.891865 |
| balanced_cluster_reg_bootstrap | 0.424500000 | 11.941000000 | 0.035321 | 0.037976 | 336.484 | 367.109 | 0.916513 | 0.927647 |
| unbalanced_dr_weighted_analytical | 1.444000000 | 9.410500000 | 0.153875 | 0.157750 | 329.812 | 356.766 | 0.930145 | 0.932497 |
| unbalanced_dr_weighted_bootstrap | 1.597000000 | 13.423000000 | 0.118573 | 0.123220 | 347.266 | 364.469 | 0.952799 | 0.963109 |
| balanced_event_analytical | 1.543000000 | 7.949666667 | 0.194096 | 0.198299 | 446.234 | 449.422 | 0.988096 | 1.001252 |
| balanced_event_bootstrap | 2.632500000 | 13.887500000 | 0.189250 | 0.192878 | 365.344 | 364.094 | 0.998656 | 1.006611 |
| balanced_event_cband_bootstrap | 2.804000000 | 14.083500000 | 0.197151 | 0.213521 | 360.672 | 370.969 | 0.970264 | 0.988485 |
| balanced_cluster_event_cband_bootstrap | 2.569500000 | 12.639000000 | 0.207849 | 0.218882 | 363.500 | 372.141 | 0.982817 | 0.985241 |
| large_balanced_dr_weighted_analytical | 2.073000000 | 28.883000000 | 0.071399 | 0.073157 | 203.703 | 282.609 | 0.722817 | 0.769917 |

## Decision

All `15` scenarios pass both gates. The worst time
upper bound is `0.218882` for
`balanced_cluster_event_cband_bootstrap`. The worst RSS upper bound is
`1.006611` for `balanced_event_bootstrap`.

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
