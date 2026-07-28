# Three-way benchmark: legacy csdid vs csdid 2.0.0 vs R `did`

Covers the unbalanced-panel and repeated-cross-section shapes that
`legacy-candidate-ab-workload.do` does not (it has no RCS scenario and never
compares against R). Results: `reports/benchmark-unbalanced-rcs-2026-07-26.md`.

Paths are absolute at the top of each script; edit them for your machine.

    Rscript gen.R              # write the two shared fixtures (both engines read these)
    Rscript r.R                # R timings
    stata-mp -b do bench.do candidate
    stata-mp -b do bench.do legacy
    stata-mp -b do parity.do          # candidate ATT(g,t)
    stata-mp -b do parity-legacy.do   # legacy   ATT(g,t)
    Rscript cmp-legacy.R       # cell-by-cell accuracy of both against R
    stata-mp -b do bootbench.do       # table vs blocked-dense multiplier bootstrap

Notes for anyone re-running this:

- `bench.do` **asserts which `csdid.ado` actually resolved** and aborts if it is
  the wrong one. There is an SSC `csdid` in `ado/plus` that will otherwise
  shadow whichever build you meant to time.
- Read ATT(g,t) from `e(attgt)` (candidate) or `e(b_attgt)`/`e(gtt)` (legacy).
  `e(b)` is the aggregation and has a different length — comparing it across
  engines produces nonsense.
- Legacy `e(b_attgt)` is 15 ATT estimates followed by 15 weights; the cell key
  is `e(gtt)[i,1]` (cohort) and `e(gtt)[i,3]` (t1), not column 2 (t0).
- Legacy has no `bal()` option, so it always uses the pairwise-balanced
  estimand on unbalanced panels and cannot be aligned to R. Compare `e(N)`.
