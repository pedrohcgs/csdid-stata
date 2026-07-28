# Oracle Review Report

Status: completed for conformance profile v1.

Reviewer: frontier-model Codex sub-agent `gpt-5.5`, read-only.

Review date: 2026-06-22.

Reviewed files:

- `docs/parity-verification-playbook.md`
- `docs/conformance-profile-v1.md`
- `docs/verification-criteria.md`
- `docs/behavior-decisions.md`
- `inst/spec/feature-matrix.csv`
- `docs/stata-engineering-references.md`
- `docs/tolerance-registry-v1.md`
- `docs/jel-replication-inventory.md`
- `docs/legacy-stata-compatibility.md`
- `PROVENANCE.md`

## Critical Feedback And Resolution

| Finding | Resolution |
| --- | --- |
| R oracle was not reproducible enough. | Expanded `tools/parity/reference-lock/r-did-lock.json` with commit, tree, archive hash, tracked-file manifest hash, package metadata, dependency floors, install command, observed R version, RNG kind, and fixture-generation requirements. |
| Fixture paths and schemas were under-specified and inconsistent. | Canonicalized matrix artifact paths, added `inst/spec/fixture-schemas.md`, and updated `docs/parity-verification-playbook.md`. |
| JEL acceptance had a `did` 2.3.0 vs 2.5.1 conflict. | Updated D006 and `docs/jel-replication-inventory.md` with two-layer JEL acceptance: original-artifact replication is release-blocking; R 2.5.1 remains the package oracle. |
| Legacy classifications still had unresolved conditionals. | Rewrote `docs/legacy-stata-compatibility.md` with concrete v1 classifications: retain, alias/no-op warning, compat-only, cosmetic-only, or unsupported-by-design. |
| Minimum Stata version was missing from the reviewed contract. | Added a Stata 15 runtime floor, Stata 17 primary verification target, and Stata 18+ preferred release check to `docs/conformance-profile-v1.md`, `docs/stata-engineering-references.md`, and `inst/spec/bench-budgets.yml`. |
| Performance was mandatory and needed frozen budgets. | Confirmed and retained frozen `inst/spec/bench-budgets.yml`; F049 remains mandatory. |

## Important Feedback And Resolution

| Finding | Resolution |
| --- | --- |
| Warning/error EXACT comparisons should be structured. | Added structured event schema in `inst/spec/fixture-schemas.md` with return code, type, stable key, offending option, and normalized message. |
| Source-test inventory should be machine-readable. | Added `tools/parity/source-test-inventory.csv` with RT/PY source hashes and mapped Stata tests. |
| Stata syntax and stored result names should be frozen before coding. | Added stored-result schema in `inst/spec/fixture-schemas.md`; command surfaces and option classifications are in `docs/legacy-stata-compatibility.md`. |
| Normalization rules were missing. | Added missing-value, NaN/Inf, sorting, label, path, and numeric-export rules in `inst/spec/fixture-schemas.md`. |
| Package license should be explicit before implementation. | `PROVENANCE.md` now keeps implementation clean-room by default and requires a future explicit license decision before copied/adapted code can be used. |

## Implementation-Risk Order

The reviewer recommended this de-risking order, now reflected in the contract:

1. ENG001-ENG005 plus fixture harness and reference locks.
2. F033/F010 method boundary and F001 static 2x2.
3. F016 unbalanced-panel repeated-cross-section default.
4. F019 and F021-F024 sample, timing, and validation edge cases.
5. F012 weights.
6. F013-F015 inference.
7. Remaining inherited aggregation edge tests after F003-F006 and F025 parity.
8. F041-F043 JEL smoke checks.

## Legacy Behaviors Not Preserved As Defaults

- pair-balanced/full-balanced unbalanced-panel behavior;
- silent unit dropping;
- hidden public `dryrun`;
- network installs in default tests;
- global ado dependence;
- legacy `ipw` fallback behavior that differs from R;
- old `long`/`long2` behavior except as warned compatibility aliases;
- graph styling as a parity surface;
- undocumented utility entry points;
- legacy bootstrap output as an oracle.

## Engineering Guidance

Adopt first:

- clean-room ado wrappers over deterministic Mata kernels;
- manifest-driven fixtures;
- explicit row/cell identity;
- base Stata/Mata fallback before optional fast paths;
- isolated ado paths and no global state;
- table-data and plot-data comparison before rendering.

Avoid for v1:

- patching legacy internals;
- copying implementation snippets from references;
- hard runtime dependencies on `reghdfe`, `gtools`, `ftools`, or `honestdid`;
- relying on installed SSC state;
- optimizing before baseline parity is correct;
- implementing compatibility modes before R-parity defaults are stable.
