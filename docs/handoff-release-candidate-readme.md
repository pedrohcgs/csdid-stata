# csdid Stata 2.0.0-rc1 Release-Candidate Handoff

Date: 2026-07-09

This bundle contains the modern R-parity Stata implementation of `csdid`.
It is intended for collaborator review, stress testing, and release
preparation. The statistical oracle is R `did` 2.5.1.

This is a collaborator release-candidate bundle, not the final `v2.0.0` tag.
Final tagging is currently blocked by the required external Windows/Linux
platform rows, independent Stata/Mata and econometrics reviews, final
release-owner approval, and disposition of any collaborator/external-review
blocking findings. Historical R artifact drift under the R `did` 2.5.1 oracle
repin is recorded as an evidence-disposition item, not as a Stata-vs-R parity
blocker.

## Install

From Stata, change directory to this extracted folder and run:

```stata
do install.do
```

Equivalent direct install command:

```stata
net install csdid, from("<path-to-this-folder>") replace
```

Then verify:

```stata
csdid version
which csdid
help csdid
help csdid_postestimation
help csdid_estat
help csdid_stats
help csdid_plot
```

Run the bundled validation smoke test:

```stata
do validation-tests/install-and-smoke.do
```

Shell users can run the same check with:

```bash
bash validation-tests/run-install-smoke.sh
```

## Included Files

- `csdid.pkg` and `stata.toc` for Stata net install.
- `build/*.ado`, `build/*.mata`, and `build/*.sthlp` for the installable
  package.
- The universal macOS bootstrap plugin when the bundle is built on macOS.
  Unsupported or absent platform plugins fall back automatically to Mata;
  Windows and Linux compiled acceleration is not certified by this handoff.
- `NEWS.md`.
- Public release/support docs under `docs/`.
- Runnable public examples under `examples/`, including `examples/data/mpdta.csv`.
- External install-and-smoke tests under `validation-tests/`.
- Validation and audit summaries under `reports/`.
- Internal pre-signoff review packets under `reports/pre-signoff-*.md`.
- Staged final-release evidence under `reports/final-release/`, when present.
- Current validation outputs under `validation/`.

This bundle intentionally excludes the internal fixture harness, fixture
generators, cloned audit repositories, and build scratch trees. Full model
change and release gates referenced in the docs are run from the development
repository, not from this lean handoff bundle. The bundled
`validation-tests/` directory is the external install-and-smoke test surface.

## Core Behavior

- Estimator, sample-handling, aggregation, inference, plotting-data, and
  storage defaults are aligned to the frozen R `did` 2.5.1 contract.
- `method(dr)` is the default.
- Unbalanced panels default to R semantics through the repeated-cross-section
  path with correct standard-error behavior.
- Optimized computation and automatic storage are default-safe.
- `storeall` is the public full-storage opt-in.
- Legacy compatibility aliases are retained only where documented.

Inference default status: R `did` 2.5.1 defaults to multiplier bootstrap with
simultaneous bands and 1000 iterations. This RC now uses the same omitted
Stata inference default. Analytical standard errors are available only when
requested with `analytical` or `vce(analytical)`.

## Local Validation Status

The following local gates passed on 2026-07-09:

- Contract validation and all meta gates.
- Full smoke suite.
- JEL smoke suite.
- Opt-in performance suite.
- F026/F049/F050/F051, release-hardening, release-failure-mode, and
  adversarial differential gates.
- Public help surface gate.
- Exact bootstrap plugin kernel and plugin-vs-Mata integration gates.
- Seven-trial legacy-to-candidate time and process-RSS certification.
- Process-level RSS gate, including the 500,000-row workload.
- Stata batch log-tail scan for terminal failure markers.
- `git diff --check`.

The full JEL reproduction was rerun on 2026-07-09 against the copied JEL worktree
repinned to R `did` 2.5.1 at `9aba07d054a798558ac9b551887f5cb592d8db10`.
Both R and Stata masters exited `0` with no failure markers, the gate status is
`pass`, and `oracle_parity_status=pass`. Figures 3, 8, and 9 match regenerated
R displayed estimate/SE/CI labels, and the Table 7 display audit has zero
failures. Historical R artifacts drift under the oracle repin and are recorded
separately in the JEL report for release-owner evidence disposition.

Latest required F049 R-relative high points:

- `aggregation_bootstrap_dynamic_medium`: `1.83333`, hard budget `<= 3`.
- `medium_panel_bootstrap_reg`: `1.72857`, hard budget `<= 3`.
- `medium_panel_bootstrap_weighted_ipw`: `1.63855`, hard budget `<= 3`.
- `medium_panel_bootstrap_cband_reg`: `1.70423`, hard budget `<= 3`.
- Literal omitted-option DR/bootstrap/cband default: `1.66667`, binding budget
  `<= 1.8`.
- Covariate DR, weighted IPW, clustered REG, and unbalanced weighted DR
  bootstrap ratios range from `0.984615` to `1.63855`.

Latest high-risk non-bootstrap ratios:

- `medium_unbalanced_cov_weight_dr`: `1.28085`.
- `medium_panel_covariate_dr`: `1.15385`.
- `medium_panel_weighted_ipw`: `1.2`.
- `medium_panel_clustered_reg`: `0.788462`.

Latest opt-in scale evidence:

- `large_panel`: 500,000 rows with omitted inference options, `3.664` seconds.
- `bootstrap_medium`: 25,000 rows, 999 seeded reps, `0.268` seconds.

Measured peak RSS is 368.938 MB for default cband, 225.844 MB for seeded
balanced bootstrap, 225.047 MB for unbalanced weighted DR bootstrap, 155.562
MB for aggregation bootstrap, and 263.516 MB for the 500,000-row workload.

Against the pinned public Stata baseline, all 15 frozen A/B rows pass both
time and peak-RSS gates across seven isolated trials. The worst time 95% upper
bound is `0.442013`; the worst RSS upper bound is `0.996870`. See
`reports/legacy-candidate-performance-certification.md` and the machine-readable
files under `validation/`.

Local platform evidence:

- Stata 17 MP, Unix/macOS, Apple Silicon.
- Universal macOS bootstrap plugin selected and validated; Linux and Windows
  runtime rows remain required for final release.

## Suggested Collaborator Review

1. Install into an isolated Stata profile and confirm `csdid version`.
2. Run the examples under `examples/`.
3. Re-run representative published workflows.
4. Compare high-stakes internal examples against R `did` 2.5.1.
5. Stress unbalanced panels, covariates, weights, clusters, bootstrap,
   aggregation, and plot-data export.
6. Review `docs/testing-protocol.md`,
   `docs/validation-guide.md`,
   `docs/public-v2.0.0-blockers.md`,
   `reports/release-candidate-readiness.md`,
   `reports/release-next-steps-2026-07-09.md`,
   `reports/pre-signoff-stata-mata-review.md`,
   `reports/pre-signoff-econometrics-review.md`,
   `docs/versioning-and-release-policy.md`, and
   `docs/independent-review-packet.md` before treating this as a final-release
   candidate.
7. Use the structured issue templates in the source repository for numerical
   discrepancies, command failures, and performance regressions.

For any proposed estimator, optimization, inference, aggregation, plotting, or
storage change, require the gate in `docs/model-improvement-required-tests.md`.
