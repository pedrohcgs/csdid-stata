# Release Checklist

Status: release-candidate checklist for conformance profile v1.

Current public handoff version: `2.0.0-rc1`. Final `v2.0.0` requires passing
the local release gates, recording release-owner disposition for historical R
artifact drift under the R `did` 2.5.1 oracle repin, and completing the
platform and independent-review evidence listed below.

## Required Before Tagging

- `python3 tools/validate-contract.py`
- `for f in tests/meta/*.sh; do bash "$f" || exit 1; done`
- `tests/run-smoke.sh`
- `tests/run-jel-smoke.sh`
- `CSDID_RUN_OPTIN_PERF=1 tests/run-optin-performance.sh`
- `bash tests/run-legacy-candidate-ab.sh`, using the clean pinned legacy
  repository at commit `fdbae25521a941314af8d84ec0c93fb0596daa8e`
- `CSDID_RUN_JEL_FULL=1 tests/run-jel-full-reproduction.sh`
- `git diff --check`
- `stata-mp -b do src/build.do`
- `bash tools/release/check-stata-log-tail.sh build.log` after Stata batch
  commands when the log is available.
- isolated install gate: `tests/stata/test-f050.do`
- release default/UX gate: `tests/stata/test-f051.do`
- release hardening gate: `tests/stata/test-release-hardening.do`
- release failure-mode gate: `tests/stata/test-release-failure-modes.do`
- adversarial differential gate: `python3 tools/release/run-adversarial-differential.py`
- benchmark gate: `tests/stata/test-f049.do`
- plugin build and exactness gates:
  `bash tools/plugin/build-bootstrap-plugin.sh auto`,
  `tests/stata/test-bootstrap-plugin.do`, and
  `tests/stata/test-bootstrap-plugin-integration.do`
- measured memory gate: `python3 tools/bench/run-memory-gate.py`
- final evidence checker before `v2.0.0`:
  `python3 tools/release/check-final-release-evidence.py --evidence-dir reports/final-release`
- handoff bundle rebuild:
  `bash tools/release/build-handoff-bundle.sh`
- isolated handoff install verification:
  `stata-mp -b do tools/release/verify-handoff-install.do dist/csdid-stata-2.0.0`

## Evidence To Review

- `reports/hardening-status.md`
- `reports/engineering-audit.md`
- `reports/jel-replication-summary.md`
- `reports/jel-full-reproduction-result.md`
- `reports/release-candidate-readiness.md`
- `reports/final-release-certification-status.md`
- `reports/legacy-candidate-performance-certification.md`
- `reports/platform-matrix-local.csv` for local platform evidence, plus
  external platform rows before final `v2.0.0`.
- `reports/oracle-review.md`
- `PROVENANCE.md`
- `NEWS.md`
- `docs/versioning-and-release-policy.md`
- `docs/stored-results-api.md`
- `docs/bootstrap-scope.md`
- `docs/platform-matrix.md`
- `docs/independent-review-packet.md`
- `docs/release-notes-v2.0.0-rc1.md`
- `docs/testing-protocol.md`
- `docs/validation-guide.md`
- `docs/public-v2.0.0-blockers.md`
- `docs/final-release-certification.md`
- `docs/public-api-freeze-v2.md`
- `docs/support-runbook.md`
- `docs/adversarial-differential-testing.md`
- `docs/release-engineering.md`
- `docs/handoff-release-candidate-readme.md`
- `docs/worldwide-release-governance.md`
- `.github/ISSUE_TEMPLATE/numerical-discrepancy.yml`
- `.github/ISSUE_TEMPLATE/bug-report.yml`
- `.github/ISSUE_TEMPLATE/performance-regression.yml`
- `.github/workflows/static-release-gates.yml`
- `.github/workflows/plugin-build.yml`

## Release Notes

- State that R `did` 2.5.1 is the statistical oracle.
- State that the owner-directed unbalanced-panel default uses the
  repeated-cross-section computation path while preserving standard-error
  behavior.
- List soft-deprecated compatibility aliases, including `bal()`/`balance()`,
  and unsupported internal legacy options such as `dryrun`.
- State that F051 passed for R-matching omitted defaults, Stata-style naming
  aliases including bare `universal`/`varying`, `id()`,
  `notyettreated`/`nevertreated`, `vce(cluster ...)`, bootstrap shorthand,
  `storeall` full-storage compatibility, default postestimation handoffs,
  `csdid_stats event`, `estat dynamic/simple/group/calendar`, plot-data export
  diagnostics, and optimized computation/storage metadata.
- Confirm direct Stata help is installed for `csdid`, `csdid_estat`,
  `csdid_stats`, `csdid_plot`, and the postestimation overview.
- Confirm public help passes `tests/meta/test-public-help-surface.sh`, with
  fixture and internal contract details kept out of `.sthlp` files.
- Confirm the examples under `examples/` run under the release build.
- Confirm the bundled collaborator smoke test under `validation-tests/` runs
  from the extracted handoff zip.
- State that JEL-DiD full reproduction passed through the opt-in full gate
  against regenerated R `did` 2.5.1, and separately disclose any historical
  upstream artifact drift that requires release-owner evidence disposition.
- State that `large_panel` and `bootstrap_medium` passed through the opt-in
  performance gate, or record the environment-specific skip.
- State that every frozen legacy-to-candidate row passed both the time and
  process-RSS paired-median and bootstrap-upper-bound gates, or block release.
- State which platform plugin binaries are shipped and runtime-certified,
  their SHA256 values, and that the Mata fallback remains mandatory.
- State that Stata PDF byte/pixel drift is accepted only through semantic
  figure audits.
- State whether the external-release review blockers are closed, deferred to a
  pre-release/beta, or explicitly out of scope for the tag.
- State that `2.0.0-rc1` is a release candidate and that final `v2.0.0`
  requires recorded platform and independent-review evidence unless waived by
  the release owner.

## Tagging

Tag only after the required checks pass on a clean worktree. If a release check
is skipped because the target environment lacks licensed Stata, R, Python, or
JEL dependencies, record the skipped check and reason in the release notes
instead of marking the release complete.

Do not tag final `v2.0.0` until `docs/platform-matrix.md` and
`docs/independent-review-packet.md` are satisfied or explicitly waived.
The final evidence checker must pass against the release evidence directory
before the tag is cut.
