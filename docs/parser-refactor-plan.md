# Parser Refactor Plan

Status: required post-`2.0.0` maintainability plan.

The current `csdid.ado` parser is heavily tested, but it owns too many
responsibilities in one program. That is acceptable for the release candidate
because a pre-release parser refactor would be high risk. It is not acceptable
as the long-term maintenance shape for a high-use public Stata command.

## Refactor Goals

Split parser responsibilities without changing behavior:

- syntax collection;
- R alias normalization;
- Stata alias normalization;
- legacy compatibility diagnostics;
- bootstrap option parsing;
- cluster and VCE parsing;
- performance/storage parsing;
- immediate aggregation dispatch;
- normalized option reporting for diagnostics.

## Required Safety Gates

Every parser refactor step must pass:

- F036 option inventory.
- F045 defaults.
- F046 legacy migration.
- F051 release default/API/UX.
- `tests/stata/test-release-hardening.do`.
- `tests/stata/test-release-failure-modes.do`.
- full smoke before merge.

## Target Helper Shape

Post-release helper programs should be small and unit-testable:

- `_csdid_parse_aliases`
- `_csdid_parse_baseperiod`
- `_csdid_parse_controls`
- `_csdid_parse_bootstrap`
- `_csdid_parse_storage`
- `_csdid_parse_vce`
- `_csdid_parse_legacy`
- `_csdid_parse_post`

These names are planning targets, not a current public API.

## Non-Negotiable Rule

Parser refactors may not change numerical results, defaults, warning policy,
stored result names, or accepted compatibility aliases unless a separate API
change has already been approved.
