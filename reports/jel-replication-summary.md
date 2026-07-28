# JEL Replication Summary

Status: full JEL R `did` 2.5.1 oracle parity passes locally. Historical
repinned-R artifact drift against the frozen upstream JEL files remains
recorded separately for release-owner evidence disposition.

Date: 2026-07-08.

## Verification Result

The full JEL-DiD empirical reproduction gate runs the R and Stata master
pipelines in an isolated worktree with the local `csdid` package ahead of
SSC/global ado paths. The latest full run completed both masters cleanly under
the copied-worktree R `did` 2.5.1 oracle. Displayed bootstrap SE/CI labels for
Figures 3, 8, and 9 now match regenerated R labels at displayed precision, and
the Table 7 display audit has zero failures.

Primary evidence:

- Full report: `reports/jel-full-reproduction-result.md`
- Wrapper: `tools/jel/run-full-reproduction.py`
- Gate: `CSDID_RUN_JEL_FULL=1 tests/run-jel-full-reproduction.sh`
- Re-analysis gate: `CSDID_RUN_JEL_FULL=1 tests/run-jel-full-reproduction.sh --analyze-existing`

Recorded result:

- R master exit code: `0`
- Stata master exit code: `0`
- Failure markers: `0`
- Gate status: `pass`
- Oracle parity status: `pass`
- Figure label audit failures: `0`
- Table 7 display audit failures: `0`
- Historical artifact status: `needs-review`, limited to frozen upstream R
  artifacts that differ after the R `did` 2.5.1 oracle repin

## Figure Labels

The displayed point estimates, bootstrap SEs, and confidence-interval labels in
Figures 3, 8, and 9 now match R at the rounded precision used in the PDFs:

- Figure 3: estimate `-0.70`, SE/CI `2.03`, `[-4.68, 3.27]`
- Figure 8: estimate `0.09`, SE/CI `1.94`, `[-3.72, 3.89]`
- Figure 9: estimate `-2.25`, SE/CI `4.07`, `[-10.22, 5.72]`

## Table 7

The upstream JEL Stata Table 7 code historically called `drdid` directly for
the 2x2 covariate table. The full reproduction wrapper now adds a csdid-native
Table 7 reconstruction and audits the displayed values directly against
regenerated R `did` 2.5.1 output using the exported R bootstrap state. The
latest display audit found:

- R `did` 2.5.1 Table 7 point estimates:
  `-1.62`, `-0.86`, `-1.23`, `-3.46`, `-3.84`, `-3.76`
- Stata csdid-native Table 7 point estimates: same at displayed precision
- R `did` 2.5.1 Table 7 SEs:
  `4.65`, `4.60`, `4.92`, `2.42`, `3.36`, `3.21`
- Stata csdid-native Table 7 SEs: same at displayed precision
- Table 7 display-audit failures: `0`

The legacy external-`drdid` Table 7 discrepancy is no longer a local
Stata-vs-R blocker for this release candidate because the csdid-native Table 7
path matches regenerated R at displayed precision.

## Stata PDF Rendering

Regenerated Stata PDFs are not required to byte-match the committed PDFs,
because local Stata graph rendering can differ by font, scheme, antialiasing,
and PDF metadata. The full gate therefore records rendered-pixel drift as
supporting evidence and accepts each Stata figure only through explicit
semantic checks:

- Figures 1, 2, 4, 5, 6, and 7 preserve the committed Stata PDF text/tick token
  set.
- Figures 3, 8, and 9 preserve the non-label text/tick token set and their
  regenerated Stata labels now match the regenerated R labels at displayed
  precision.

## Default Smoke Evidence

The default JEL smoke gate still avoids the expensive full master rerun. It
verifies fixture manifests, artifact hashes, full-reproduction evidence links,
and the targeted JEL analytical smoke fixtures:

- F040: Python/R JEL inheritance map and fast-request optimized equality
- F041: Table 7 analytical two-period covariate-adjusted sample
- F042: 2xT event-study sample
- F043: GxT staggered-adoption sample
- F044 and JEL001-JEL018: all JEL artifacts mapped to the full reproduction
  report

Full reproduction is the release-blocking empirical evidence; the smoke gate is
the cheap regression guard.
