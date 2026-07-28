# Platform Matrix

Status: required external-release platform matrix.

The local release candidate has been validated on the maintainer workstation.
Final `v2.0.0` should not be tagged until this matrix is filled by independent
or CI-like runs, or until the release owner records an explicit waiver.

## Required Rows

| OS | Stata | Edition | Required gates | Status |
| --- | --- | --- | --- | --- |
| macOS | 17 or newer | MP or SE | local release gates | pending recorded row |
| Windows | 17 or newer | MP or SE | local release gates | pending |
| Linux | 17 or newer | MP or SE | local release gates | pending |
| macOS | 15 or 16 | any supported | smoke plus F050/F051/F049 | recommended |
| Windows | 15 or 16 | any supported | smoke plus F050/F051/F049 | recommended |
| Linux | 15 or 16 | any supported | smoke plus F050/F051/F049 | recommended |

## Command

From the development repository:

```bash
bash tools/release/run-platform-release-row.sh reports/platform-matrix-local.csv
```

The release-row runner enables opt-in R-relative performance,
legacy-to-candidate A/B certification, and full JEL reproduction by default
before writing `release_gates_status=pass`.

If only `stata-se`, `stata`, or another local executable is available, set
`STATA_CMD` for the shell script and use that executable for the Stata row:

```bash
STATA_CMD=stata-se bash tools/release/run-platform-release-row.sh reports/platform-matrix-local.csv
```

## Required Evidence

Each platform row should attach:

- `reports/platform-matrix-local.csv`.
- The logs from `tests/run-smoke.sh`, `tests/run-jel-smoke.sh`, F049, F050,
  F051, and `test-release-hardening.do`.
- The `validation/r-stata-ratio.csv` file produced by F049.
- `build/memory-gate/results.csv` with measured peak RSS.
- `build/legacy-candidate-ab/runs.csv`, `summary.csv`, and `metadata.json`,
  with every time and RSS upper-bound gate passing.
- `test-bootstrap-plugin-integration.log`, the platform plugin SHA256, and
  confirmation that the platform-named binary was selected. If no binary is
  shipped for a row, record the Mata fallback status explicitly.
- The adversarial differential `comparison.csv`.
- The release failure-mode log.
- Any skipped gate and its reason.

The final evidence checker requires each platform CSV to contain
`release_gates_status=pass`. Rows written without the release-row runner are
treated as unverified and cannot unlock final `v2.0.0`.

## Release Rule

Platform failures are release blockers unless they are proven to be caused by a
missing optional local dependency rather than package behavior. Numerical
differences from R `did` 2.5.1 are release blockers unless recorded as approved
divergences in the frozen contract.
