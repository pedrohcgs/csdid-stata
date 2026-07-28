# Independent Review Packet

Status: required before final `v2.0.0` tag.

This packet is for reviewers who were not involved in the implementation.
Reviewers should treat R `did` 2.5.1 as the econometric oracle and the frozen
contract under `docs/` and `inst/spec/` as the release contract.

Internal pre-signoff aids are available in:

- `reports/pre-signoff-stata-mata-review.md`
- `reports/pre-signoff-econometrics-review.md`

These files summarize local evidence and known review risks. They are not
independent approvals and must not replace the final signoff files under
`reports/final-release/`.

The minimum-command section below requires the full development repository.
The collaborator handoff bundle intentionally excludes `tools/`, `tests/`,
fixture generators, GitHub workflow files, and cloned audit repositories; it is
for installation and exploratory testing, not independent release signoff.

## Reviewer Roles

Stata/Mata implementation reviewer:

- Inspect ado/Mata organization, parser complexity, memory policy, error
  handling, dependency policy, and Stata package install behavior.
- Run the platform matrix on at least one clean Stata installation.
- Verify that `storeall`, lean/default storage, postestimation, and plot-data
  export behave as documented.
- Review parser complexity and alias normalization against
  `docs/public-api-freeze-v2.md` and `docs/support-runbook.md`.
- Review support and failure behavior against `docs/support-runbook.md`.

Econometrics reviewer:

- Review DR, IPW, REG, weights, covariates, clusters, bootstrap, unbalanced
  panels, aggregation, and JEL replication evidence.
- Select at least three high-stakes designs and compare Stata output against R
  `did` 2.5.1 directly.
- Review all approved divergences and confirm none affects default R parity.
- Run or extend `tools/release/run-adversarial-differential.py` with at least
  three reviewer-selected designs.

## Minimum Commands

```bash
python3 tools/validate-contract.py
for f in tests/meta/*.sh; do bash "$f" || exit 1; done
bash tests/run-smoke.sh
bash tests/run-jel-smoke.sh
CSDID_RUN_OPTIN_PERF=1 bash tests/run-optin-performance.sh
stata-mp -b do tests/stata/test-f049.do
stata-mp -b do tests/stata/test-f050.do
stata-mp -b do tests/stata/test-f051.do
stata-mp -b do tests/stata/test-release-hardening.do
stata-mp -b do tests/stata/test-release-failure-modes.do
python3 tools/release/run-adversarial-differential.py
git diff --check
```

Publication replication reviewer:

```bash
CSDID_RUN_JEL_FULL=1 bash tests/run-jel-full-reproduction.sh
```

## Review Checklist

- Estimator, sample, and omitted-inference defaults match R `did` 2.5.1,
  including bootstrap inference, simultaneous bands, and 1000 iterations.
- Unbalanced panels use the R-compatible repeated-cross-section path by default.
- Covariates, weights, DR/IPW/REG, clusters, bootstrap, aggregation, and plots
  pass parity gates.
- Legacy aliases warn or error exactly as documented.
- No unsupported legacy behavior silently changes results.
- Help files are understandable to a normal Stata user and do not expose
  internal fixture names.
- Performance diagnostics are useful but not required for ordinary workflows.
- The parser is acceptable for `2.0.0`, or a post-release parser decomposition
  issue is opened before final tag.

## Sign-Off Record

Before final tag, record reviewer names, dates, platform rows, commands run,
failures found, fixes incorporated, and any release-owner waivers in
the final signoff files under `reports/final-release/`.
