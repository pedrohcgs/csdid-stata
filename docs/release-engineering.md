# Release Engineering

Status: release-manager checklist for final `v2.0.0`.

## Build Discipline

Final release must be cut from an intentional release commit. The handoff zip
must be rebuilt from that commit, and its SHA256 must be recorded in the release
notes.

## Required Commands

```bash
python3 tools/validate-contract.py
for f in tests/meta/*.sh; do bash "$f" || exit 1; done
python3 tools/release/run-adversarial-differential.py
stata-mp -b do tests/stata/test-release-failure-modes.do
bash tests/run-smoke.sh
bash tests/run-jel-smoke.sh
CSDID_RUN_OPTIN_PERF=1 bash tests/run-optin-performance.sh
CSDID_RUN_LEGACY_AB=1 bash tests/run-legacy-candidate-ab.sh
CSDID_RUN_JEL_FULL=1 bash tests/run-jel-full-reproduction.sh
git diff --check
```

The opt-in performance gate includes paired R/Stata runtime ratios and a
process-level RSS gate. The RSS results are written to
`build/memory-gate/results.csv`; `c(memory)` is not accepted as evidence of
peak allocation.

The legacy-to-candidate gate requires a clean checkout of
`pedrohcgs/csdid-stata@fdbae25521a941314af8d84ec0c93fb0596daa8e`. It runs
both packages in alternating isolated Stata processes and fails if any frozen
workload's time or peak-RSS 95% upper bound exceeds legacy. Evidence is written
to `build/legacy-candidate-ab/` and summarized in
`reports/legacy-candidate-performance-certification.md`.

Build the current platform's optional bootstrap accelerator with:

```bash
bash tools/plugin/build-bootstrap-plugin.sh auto
```

The build downloads only Stata's official plugin SDK files, verifies pinned
SHA256 checksums, and writes a canonical local plugin plus a platform-named
release artifact. GitHub Actions compile the Linux, Windows, and universal
macOS artifacts. A runtime platform row remains required before any compiled
binary is certified for public release.

For platform evidence, use:

```bash
bash tools/release/run-platform-release-row.sh reports/platform-matrix-local.csv
```

This command enables the opt-in R-relative performance, legacy-to-candidate,
and full JEL gates before writing `release_gates_status=pass`.

Then rebuild the handoff zip, run `tools/release/verify-handoff-install.do`,
and record the zip hash.

Use the repeatable bundle builder after the gates pass:

```bash
bash tools/release/build-handoff-bundle.sh
stata-mp -b do tools/release/verify-handoff-install.do dist/csdid-stata-2.0.0
shasum -a 256 dist/csdid-stata-2.0.0.zip
```

The handoff zip must stay lean: installable Stata files, public docs, examples,
review reports, validation summaries, and the small external
`validation-tests/` smoke surface only. Do not include the internal fixture
harness, fixture generators, cloned reference repositories, or build scratch
trees.

## Final Evidence Checker

Use:

```bash
python3 tools/release/check-final-release-evidence.py --evidence-dir reports/final-release
```

The evidence directory must contain platform rows and reviewer sign-offs. This
checker is intentionally stricter than local release-candidate gates.

## Rollback

Keep the previous legacy release install instructions and a clear rollback note
in the public release announcement. If a P0 issue appears after release, publish
a temporary warning and patched release candidate before changing defaults.
