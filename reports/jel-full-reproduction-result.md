# Full JEL Reproduction Result

Status: pass
R 2.5.1 oracle parity status: `pass`
Historical artifact status: `needs-review`

Date: 2026-07-09T23:06:05-0400
JEL-DiD commit: `50f4f183783d2344f85bc4f39bcbcc1b7eba6466`
Local csdid commit: `0ded7807da2840b3dfba8c820043fc37419490ed`
R master exit code: `0`
Stata master exit code: `0`
Failure markers: `0`

## Artifact Comparison Counts

| Status | Count |
| --- | ---: |
| `generated-new` | 1 |
| `hash-drift` | 7 |
| `hash-match` | 7 |
| `semantic-match` | 19 |

## Non-Matching Or Missing Artifacts

| Artifact | Status | Detail |
| --- | --- | --- |
| `tables/table7_R.tex` | `hash-drift` | tex-numeric-token-drift:32->32 |
| `tables/table7_stata.tex` | `hash-drift` | tex-numeric-token-drift:30->30 |
| `figures/figure3_R.pdf` | `hash-drift` | pdf-rendered-pixel-drift:10293 |
| `figures/figure4_R.pdf` | `hash-drift` | pdf-rendered-pixel-drift:4714 |
| `figures/figure6_R.pdf` | `hash-drift` | pdf-rendered-pixel-drift:8901 |
| `figures/figure8_R.pdf` | `hash-drift` | pdf-rendered-pixel-drift:1178 |
| `figures/figure9_R.pdf` | `hash-drift` | pdf-rendered-pixel-drift:1264 |

## Historical R Artifact Drift

These rows compare regenerated R `did` 2.5.1 outputs to the historical
committed JEL artifacts. They are release-review evidence, but they are
not by themselves Stata-vs-R oracle failures.

| Artifact | Detail |
| --- | --- |
| `tables/table7_R.tex` | tex-numeric-token-drift:32->32 |
| `figures/figure3_R.pdf` | pdf-rendered-pixel-drift:10293 |
| `figures/figure4_R.pdf` | pdf-rendered-pixel-drift:4714 |
| `figures/figure6_R.pdf` | pdf-rendered-pixel-drift:8901 |
| `figures/figure8_R.pdf` | pdf-rendered-pixel-drift:1178 |
| `figures/figure9_R.pdf` | pdf-rendered-pixel-drift:1264 |

## Approved Generated Stata Drift

These regenerated Stata artifacts intentionally differ from the
historical committed JEL outputs, and are governed by explicit
R `did` 2.5.1 oracle audits rather than raw hash identity.

| Artifact | Detail |
| --- | --- |
| `tables/table7_stata.tex` | tex-numeric-token-drift:30->30 |

## R vs Stata Figure Label Audit

Displayed aggregate labels are compared at the rounded precision used in
the PDFs. Estimates should match exactly after rounding; bootstrap SEs
and confidence intervals are marked `needs-review` only if
aggregate-bootstrap postprocessing or draw-order differences move the
displayed value by more than 0.005.

| Figure | Metric | R | Stata | Abs Diff | Status |
| --- | --- | ---: | ---: | ---: | --- |
| `figure3` | `estimate` | -0.7 | -0.7 | 0 | `display-match` |
| `figure3` | `std_error` | 2.03 | 2.03 | 0 | `display-match` |
| `figure3` | `ci_low` | -4.68 | -4.68 | 0 | `display-match` |
| `figure3` | `ci_high` | 3.27 | 3.27 | 0 | `display-match` |
| `figure8` | `estimate` | 0.09 | 0.09 | 0 | `display-match` |
| `figure8` | `std_error` | 1.94 | 1.94 | 0 | `display-match` |
| `figure8` | `ci_low` | -3.72 | -3.72 | 0 | `display-match` |
| `figure8` | `ci_high` | 3.89 | 3.89 | 0 | `display-match` |
| `figure9` | `estimate` | -2.25 | -2.25 | 0 | `display-match` |
| `figure9` | `std_error` | 4.07 | 4.07 | 0 | `display-match` |
| `figure9` | `ci_low` | -10.22 | -10.22 | 0 | `display-match` |
| `figure9` | `ci_high` | 5.72 | 5.72 | 0 | `display-match` |

## R vs Stata Table 7 Display Audit

Table 7 is audited directly against the regenerated R `did` 2.5.1
table. The historical upstream JEL Stata script used external `drdid`,
so the release harness adds a csdid-native reconstruction for this
display audit.

| Panel | Method | Metric | R | Stata | Abs Diff | Status |
| --- | --- | --- | ---: | ---: | ---: | --- |
| `unweighted` | `reg` | `estimate` | -1.62 | -1.62 | 0 | `display-match` |
| `unweighted` | `reg` | `std_error` | 4.65 | 4.65 | 0 | `display-match` |
| `unweighted` | `ipw` | `estimate` | -0.86 | -0.86 | 0 | `display-match` |
| `unweighted` | `ipw` | `std_error` | 4.6 | 4.6 | 0 | `display-match` |
| `unweighted` | `dr` | `estimate` | -1.23 | -1.23 | 0 | `display-match` |
| `unweighted` | `dr` | `std_error` | 4.92 | 4.92 | 0 | `display-match` |
| `weighted` | `reg` | `estimate` | -3.46 | -3.46 | 0 | `display-match` |
| `weighted` | `reg` | `std_error` | 2.42 | 2.42 | 0 | `display-match` |
| `weighted` | `ipw` | `estimate` | -3.84 | -3.84 | 0 | `display-match` |
| `weighted` | `ipw` | `std_error` | 3.36 | 3.36 | 0 | `display-match` |
| `weighted` | `dr` | `estimate` | -3.76 | -3.76 | 0 | `display-match` |
| `weighted` | `dr` | `std_error` | 3.21 | 3.21 | 0 | `display-match` |

## Stata Figure Semantic Audit

Committed Stata PDFs are treated as rendering artifacts, not as
the statistical oracle. Figures 1, 2, 4, 5, 6, and 7 must preserve
the committed Stata PDF text/tick token set. Figures 3, 8, and 9
may differ from the committed Stata labels only where the regenerated
Stata labels match the regenerated R labels at displayed precision.

| Figure | Text/Tick Status | Label Status | Render Detail | Status |
| --- | --- | --- | --- | --- |
| `figure1` | `text-token-match` | `not-applicable` | pdf-rendered-pixel-drift:472512 | `semantic-match` |
| `figure2` | `text-token-match` | `not-applicable` | pdf-rendered-pixel-drift:62126 | `semantic-match` |
| `figure3` | `text-token-match-ignoring-stale-labels` | `r-label-match` | pdf-rendered-pixel-drift:392002 | `semantic-match` |
| `figure4` | `text-token-match` | `not-applicable` | pdf-rendered-pixel-drift:593721 | `semantic-match` |
| `figure5` | `text-token-match` | `not-applicable` | pdf-rendered-pixel-drift:77890 | `semantic-match` |
| `figure6` | `text-token-match` | `not-applicable` | pdf-rendered-pixel-drift:590353 | `semantic-match` |
| `figure7` | `text-token-match` | `not-applicable` | pdf-rendered-pixel-drift:317762 | `semantic-match` |
| `figure8` | `text-token-match-ignoring-stale-labels` | `r-label-match` | pdf-rendered-pixel-drift:389958 | `semantic-match` |
| `figure9` | `text-token-match-ignoring-stale-labels` | `r-label-match` | pdf-rendered-pixel-drift:394318 | `semantic-match` |

## Stata PDF Render Drift Review

The current non-matching committed artifacts include rendered Stata PDFs.
Rendered pixels are retained as supporting evidence because local Stata
PDF output can drift in fonts, graph scheme, and antialiasing. The
status gate relies on the explicit semantic audits above rather than
raw pixel identity.

- Side-by-side render sheet: `/Users/pedrosantanna/Documents/csdid-stata-porting/build/jel-full-reproduction/outputs/visual-review/stata-pdf-drift-side-by-side.png`

## Generated Evidence

- JSON summary: `/Users/pedrosantanna/Documents/csdid-stata-porting/build/jel-full-reproduction/outputs/summary.json`
- Artifact manifest: `/Users/pedrosantanna/Documents/csdid-stata-porting/build/jel-full-reproduction/outputs/artifact-manifest.csv`
- Artifact comparison: `/Users/pedrosantanna/Documents/csdid-stata-porting/build/jel-full-reproduction/outputs/artifact-comparison.csv`
- Figure label audit: `/Users/pedrosantanna/Documents/csdid-stata-porting/build/jel-full-reproduction/outputs/figure-label-audit.csv`
- Table 7 display audit: `/Users/pedrosantanna/Documents/csdid-stata-porting/build/jel-full-reproduction/outputs/table7-display-audit.csv`
- Stata figure semantic audit: `/Users/pedrosantanna/Documents/csdid-stata-porting/build/jel-full-reproduction/outputs/stata-figure-semantic-audit.csv`
- Logs directory: `/Users/pedrosantanna/Documents/csdid-stata-porting/build/jel-full-reproduction/logs`
- Stata batch log: `/Users/pedrosantanna/Documents/csdid-stata-porting/build/jel-full-reproduction/worktree/run-stata-master.log`

Full reproduction is established only when both masters exit 0, failure
markers are absent, Stata outputs pass the explicit R `did` 2.5.1
oracle audits, and all historical table/figure artifact drift is either
hash matched, semantically matched, or dispositioned by a release owner.
