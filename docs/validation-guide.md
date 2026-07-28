# Collaborator Validation Guide

Status: bundled validation guide for `csdid` Stata `2.0.0-rc1`.

Date: 2026-07-09

## Verify The Bundle

From the directory containing the zip:

```bash
shasum -a 256 csdid-stata-2.0.0-rc1-collaborator-2026-07-09.zip
cat csdid-stata-2.0.0-rc1-collaborator-2026-07-09.zip.sha256
```

The two hashes should match.

## Install

Unzip the bundle, open Stata, change directory to the extracted bundle root,
and run:

```stata
do install.do
csdid version
which csdid
which csdid_stats
which csdid_estat
which csdid_plot
```

Expected version:

```text
2.0.0-rc1
```

## Run The Bundled Smoke Test

From Stata:

```stata
do validation-tests/install-and-smoke.do
```

From a shell:

```bash
bash validation-tests/run-install-smoke.sh
```

This test installs from the extracted bundle into an isolated temporary Stata
profile, verifies the public commands, runs default bootstrap/cband on a small
panel, runs unbalanced weighted clustered analytical estimation, exercises
aggregation and plot-data export, checks the platform bootstrap plugin when one
is included, and runs the MPDTA public example.

## Run Public Examples

```stata
do examples/01_balanced_panel.do
do examples/02_unbalanced_weighted_clustered.do
do examples/03_repeated_cross_section.do
do examples/04_postestimation_exports.do
do examples/05_legacy_migration.do
do examples/06_mpdta_workflow.do
```

## Inspect Evidence

The bundle contains:

- `validation/f049-r-stata-ratio.csv`: current R-relative performance ratios;
- `validation/memory-gate-results.csv`: measured process-level peak RSS;
- `validation/bootstrap-plugin-sha256.txt`: checksums for included compiled
  accelerators;
- `validation/adversarial-differential-comparison.csv`: R-vs-Stata adversarial
  differential results;
- `validation/jel-full-summary.json`: JEL full reproduction summary;
- `validation/jel-figure-label-audit.csv`: current Figure 3/8/9 JEL
  bootstrap-label parity status;
- `validation/table7-display-audit.csv`: current R-vs-Stata Table 7 displayed
  estimate and bootstrap-SE audit;
- `reports/release-candidate-readiness.md`: local release-candidate status;
- `docs/public-v2.0.0-blockers.md`: blockers before final public release.

Current JEL status for this rc1 bundle is pass against regenerated R `did`
2.5.1. Figure 3/8/9 displayed estimate/SE/CI labels match regenerated R, and
the Table 7 display audit has zero failures. Historical R artifact drift under
the R-oracle repin remains recorded separately for release-owner evidence
disposition.

The full fixture generator and exhaustive parity harness remain in the
development repository, not the lean collaborator zip.
