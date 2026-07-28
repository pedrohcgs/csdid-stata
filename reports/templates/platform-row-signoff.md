# Platform Row Sign-Off

Reviewer:

Date:

Repository commit:

Operating system:

Stata version:

Stata edition:

Machine type:

## Required Commands Run

- `bash tools/release/run-local-release-gates.sh`
- `stata-mp -b do tools/release/write-platform-row.do reports/platform-matrix-local.csv`
- `python3 tools/release/run-adversarial-differential.py`
- `stata-mp -b do tests/stata/test-release-failure-modes.do`

## Attached Evidence

- Platform row CSV:
- Smoke logs:
- F049 ratio CSV:
- JEL smoke log:
- Opt-in performance log, if run:
- Skipped gates and reasons:

## Sign-Off

Release gates status: pending

I confirm this platform row is valid release evidence:

Reviewer signature:
