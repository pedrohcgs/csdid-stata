# Implementation Status

Status: terminal matrix gates pass with approved divergences; not a
public-release signoff.

Date: 2026-06-22.

Verification update on 2026-06-23:

- `python3 tools/validate-contract.py` passed.
- `for f in tests/meta/*.sh; do bash "$f" || exit 1; done` passed.
- `tests/run-jel-smoke.sh` passed.
- `tests/run-smoke.sh` passed.
- Strict Stata log scan across `*.log` found no uncaught `r(...)`, assertion,
  merge, syntax, type, conformability, unrecognized-command, disallowed-option,
  or break markers.

## Completed

- Contract validator: `tools/validate-contract.py`.
- Clean-room package scaffold under `src/ado`, `src/mata`, and `src/help`.
- Local package metadata: `csdid.pkg` and `stata.toc`.
- Build script: `src/build.do`.
- Isolated install smoke test: `tests/stata/install-isolated.do`.
- Basic Stata smoke test: `tests/stata/smoke-basic.do`.
- Smoke harness: `tests/run-smoke.sh` now scans Stata batch logs for uncaught
  `r(...)` errors instead of trusting Stata's process exit status alone.
  It also now runs the completed Python inheritance gates for plotting,
  glance, tidy, and validation coverage rather than leaving them as
  targeted-only evidence.
- First R parity fixture:
  - generator: `tools/parity/generators/f001/generate.R`;
  - input: `tests/fixtures/parity/f001/inputs/input.csv`;
  - R expected output: `tests/fixtures/parity/f001/expected/r/attgt.csv`;
  - manifest: `tests/fixtures/parity/f001/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f001.do`.
- Balanced staggered-panel parity fixture:
  - generator: `tools/parity/generators/f002/generate.R`;
  - input: `tests/fixtures/parity/f002/inputs/input.csv`;
  - R expected output: `tests/fixtures/parity/f002/expected/r/attgt.csv`;
  - manifest: `tests/fixtures/parity/f002/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f002.do`;
  - status: F002 `parity-verified`.
- Simple aggregation parity fixture:
  - generator: `tools/parity/generators/f003/generate.R`;
  - input: `tests/fixtures/parity/f003/inputs/input.csv`;
  - R expected output: `tests/fixtures/parity/f003/expected/r/aggte.csv`;
  - manifest: `tests/fixtures/parity/f003/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f003.do`;
  - status: F003 `parity-verified`.
- Group aggregation parity fixture:
  - generator: `tools/parity/generators/f004/generate.R`;
  - input: `tests/fixtures/parity/f004/inputs/input.csv`;
  - R expected output: `tests/fixtures/parity/f004/expected/r/aggte.csv`;
  - manifest: `tests/fixtures/parity/f004/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f004.do`;
  - status: F004 `parity-verified`.
- Calendar aggregation parity fixture:
  - generator: `tools/parity/generators/f005/generate.R`;
  - input: `tests/fixtures/parity/f005/inputs/input.csv`;
  - R expected output: `tests/fixtures/parity/f005/expected/r/aggte.csv`;
  - manifest: `tests/fixtures/parity/f005/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f005.do`;
  - status: F005 `parity-verified`.
- Dynamic aggregation parity fixture:
  - generator: `tools/parity/generators/f006/generate.R`;
  - input: `tests/fixtures/parity/f006/inputs/input.csv`;
  - R expected output: `tests/fixtures/parity/f006/expected/r/aggte.csv`;
  - manifest: `tests/fixtures/parity/f006/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f006.do`;
  - status: F006 `parity-verified`.
- Aggregation-window parity fixture:
  - generator: `tools/parity/generators/f025/generate.R`;
  - input: `tests/fixtures/parity/f025/inputs/input.csv`;
  - R expected outputs: `tests/fixtures/parity/f025/expected/r/aggte-windows.csv`
    and `tests/fixtures/parity/f025/expected/r/events.json`;
  - manifest: `tests/fixtures/parity/f025/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f025.do`;
  - status: F025 `parity-verified`.
- R `test-aggte-comprehensive.R` inheritance fixture:
  - generator: `tools/parity/generators/rt002/generate.R`;
  - input: `tests/fixtures/parity/rt002/inputs/aggte-data.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt002/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/rt002/expected/contract/upstream-test-map.json`,
    `tests/fixtures/parity/rt002/expected/contract/approved-divergence.csv`,
    `tests/fixtures/parity/rt002/expected/contract/approved-divergence.json`,
    and `tests/fixtures/parity/rt002/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/rt002/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-aggte-comprehensive.do`;
  - status: RT002 `approved-divergence`. The gate maps 30 public assertions
    from R `tests/testthat/test-aggte-comprehensive.R` at sha256
    `99cf542b7b8dc91ca403cdd5b12028256631d48f4095997012dcf2b4211741ae`.
    Stata verifies simple/dynamic/group/calendar aggregation, event windows,
    `balance_e`, `na_rm`, public metadata, level preservation, and the group
    `max_e`/`na_rm` exclusion regression. `RT002-DIV001` records R AGGTEobj
    aggregation influence-function slots and `RT002-DIV002` records
    aggregation-level bootstrap cband critical values, both outside the
    current public Stata aggregation contract.
- R `test-aggte-edge-coverage.R` inheritance fixture:
  - generator: `tools/parity/generators/rt003/generate.R`;
  - inputs:
    `tests/fixtures/parity/rt003/inputs/single-treated.csv` and
    `tests/fixtures/parity/rt003/inputs/dynamic-window.csv`;
  - R expected output: `tests/fixtures/parity/rt003/expected/r/aggte.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt003/expected/contract/upstream-test-map.csv`
    and
    `tests/fixtures/parity/rt003/expected/contract/upstream-test-map.json`;
  - manifest: `tests/fixtures/parity/rt003/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-aggte-edge-coverage.do`;
  - status: RT003 `parity-verified`. The gate maps both source tests from
    R `tests/testthat/test-aggte-edge-coverage.R`, covering simple/group/
    dynamic/calendar aggregation for one treated group plus never-treated
    controls and dynamic `min_e=-1`/`max_e=1` event-window consistency.
- Stored-results fixture:
  - generator: `tools/parity/generators/f026/generate.R`;
  - input: `tests/fixtures/parity/f026/inputs/input.csv`;
  - expected Stata schema:
    `tests/fixtures/parity/f026/expected/new-stata/ereturn.json`;
  - manifest: `tests/fixtures/parity/f026/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f026.do`;
  - status: F026 `parity-verified` for stored `e()` surfaces, including
    `e(N_time)` and the `e(unit_group)` `id`/`group`/`weight` schema.
    Exportable tables, plot data, and richer saved RIF artifacts remain
    F027/F028/F034.
- Exportable table smoke fixture:
  - generator: `tools/parity/generators/f027/generate.R`;
  - input: `tests/fixtures/parity/f027/inputs/input.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f027/expected/r/tidy-attgt.csv`,
    `tests/fixtures/parity/f027/expected/r/glance-attgt.csv`,
    `tests/fixtures/parity/f027/expected/r/tidy-aggte-simple.csv`,
    `tests/fixtures/parity/f027/expected/r/glance-aggte-simple.csv`,
    `tests/fixtures/parity/f027/expected/r/tidy-aggte-group.csv`,
    `tests/fixtures/parity/f027/expected/r/glance-aggte-group.csv`,
    `tests/fixtures/parity/f027/expected/r/tidy-aggte-calendar.csv`,
    `tests/fixtures/parity/f027/expected/r/glance-aggte-calendar.csv`,
    `tests/fixtures/parity/f027/expected/r/tidy-aggte-dynamic.csv`, and
    `tests/fixtures/parity/f027/expected/r/glance-aggte-dynamic.csv`;
  - expected Stata schema:
    `tests/fixtures/parity/f027/expected/new-stata/export-schema.json`;
  - manifest: `tests/fixtures/parity/f027/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f027.do`;
  - status: F027 `parity-verified` for ATT(g,t) tidy/glance exports and
    simple, group, calendar, and dynamic aggregation tidy/glance exports.
    Table schemas, statistics, p-values, confidence intervals, and glance
    metadata are verified; inherited tidy/glance stress is covered by RT014,
    RT026, PY011, and PY022 rows.
- R `test-glance.R` inheritance fixture:
  - generator: `tools/parity/generators/rt014/generate.R`;
  - input: `tests/fixtures/parity/rt014/inputs/sim-glance.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt014/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/rt014/expected/contract/upstream-test-map.json`,
    `tests/fixtures/parity/rt014/expected/contract/approved-divergence.csv`,
    and
    `tests/fixtures/parity/rt014/expected/contract/approved-divergence.json`;
  - R expected outputs:
    `tests/fixtures/parity/rt014/expected/r/glance-metadata.csv` and
    `tests/fixtures/parity/rt014/expected/r/glance-relations.csv`;
  - manifest: `tests/fixtures/parity/rt014/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-glance.do`;
  - status: RT014 `approved-divergence`. The gate maps 12 public
    `glance.MP` and `glance.AGGTEobj` metadata tests from R did
    `tests/testthat/test-glance.R`, covering `csdid_estat glance` metadata
    for MP and simple/dynamic/group/calendar aggregation objects in slow and
    fast-request paths. The five approved divergences are R-only DIDparams
    slot-mutation and arbitrary custom-estimator callback tests, which do not
    map to the public Stata command surface.
- R `test-tidy.R` inheritance fixture:
  - generator: `tools/parity/generators/rt026/generate.R`;
  - input: `tests/fixtures/parity/rt026/inputs/mpdta.csv`;
  - R expected outputs:
    `tests/fixtures/parity/rt026/expected/r/tidy-attgt.csv`,
    `tests/fixtures/parity/rt026/expected/r/tidy-aggte-simple.csv`,
    `tests/fixtures/parity/rt026/expected/r/tidy-aggte-group.csv`,
    `tests/fixtures/parity/rt026/expected/r/tidy-aggte-calendar.csv`,
    `tests/fixtures/parity/rt026/expected/r/tidy-aggte-dynamic.csv`,
    `tests/fixtures/parity/rt026/expected/r/nobs.csv`, and
    `tests/fixtures/parity/rt026/expected/contract/upstream-test-map.csv`;
  - manifest: `tests/fixtures/parity/rt026/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-tidy.do`;
  - status: RT026 `parity-verified`. The mpdta-based gate maps all source
    tests from R `tests/testthat/test-tidy.R`, covering expected
    Stata-normalized tidy columns, statistic and p-value formulas, p-value
    bounds, and unique-unit `nobs` metadata for MP and simple/group/calendar/
    dynamic aggregation exports.
- Python `test_glance.py` inheritance fixture:
  - generator: `tools/parity/generators/py011/generate.py`;
  - input: `tests/fixtures/parity/py011/inputs/sim-glance.csv`;
  - contract outputs:
    `tests/fixtures/parity/py011/expected/contract/glance-metadata.csv` and
    `tests/fixtures/parity/py011/expected/contract/upstream-test-map.csv`;
  - manifest: `tests/fixtures/parity/py011/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_glance.do`;
  - status: PY011 `parity-verified`. The gate maps all 19 tests and
    parameterizations from DrSquare/csdid `csdid/test_csdid/test_glance.py`,
    covering DIDparams/glance keys and positive values, nobs/ngroup/ntime
    consistency, aggregation DIDparams for simple/dynamic/group/calendar,
    fast-request optimized metadata plus ATT agreement, and `dr`/`reg`/`ipw`
    method metadata on the Python helper-style simulation fixture.
- Python `test_tidy.py` inheritance fixture:
  - generator: `tools/parity/generators/py022/generate.py`;
  - inputs:
    `tests/fixtures/parity/py022/inputs/mpdta.csv` and
    `tests/fixtures/parity/py022/inputs/sim-tidy.csv`;
  - contract outputs:
    `tests/fixtures/parity/py022/expected/contract/tidy-structure.csv` and
    `tests/fixtures/parity/py022/expected/contract/upstream-test-map.csv`;
  - manifest: `tests/fixtures/parity/py022/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_tidy.do`;
  - status: PY022 `parity-verified`. The gate maps all 16 tests and
    parameterizations from DrSquare/csdid `csdid/test_csdid/test_tidy.py`,
    covering nonempty ATT(g,t) tidy output with group/time/estimate columns,
    finite ATT and positive SE values, aggregation result keys and egt values
    for simple/dynamic/group/calendar, nobs metadata, and `dr`/`reg`/`ipw`
    cross-method tidy output.
- Python `test_validation.py` inheritance fixture:
  - generator: `tools/parity/generators/py024/generate.py`;
  - inputs:
    `tests/fixtures/parity/py024/inputs/sample.csv`,
    `tests/fixtures/parity/py024/inputs/negative-weight.csv`, and
    `tests/fixtures/parity/py024/inputs/duplicate.csv`;
  - contract outputs:
    `tests/fixtures/parity/py024/expected/contract/valid-scenarios.csv` and
    `tests/fixtures/parity/py024/expected/contract/upstream-test-map.csv`;
  - manifest: `tests/fixtures/parity/py024/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_validation.do`;
  - status: PY024 `approved-divergence`. The gate maps 20 of 22 tests and
    parameterizations from DrSquare/csdid
    `csdid/test_csdid/test_validation.py`, covering missing-variable
    diagnostics, type checks, negative treatment timing, duplicate id-time
    rows, invalid levels, invalid bootstrap reps, negative anticipation,
    unsupported `control_group`, negative weights, and a valid fit.
    The two approved divergences are Python-only reserved internal column
    names `w` and `rowid`, which do not map to the public Stata command
    surface.
- Plot-data smoke fixture:
  - generator: `tools/parity/generators/f028/generate.R`;
  - input: `tests/fixtures/parity/f028/inputs/input.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f028/expected/r/plot-data-attgt.csv`,
    `tests/fixtures/parity/f028/expected/r/plot-data-attgt-group3.csv`,
    `tests/fixtures/parity/f028/expected/r/plot-data-aggte-dynamic.csv`,
    `tests/fixtures/parity/f028/expected/r/plot-data-aggte-group.csv`,
    `tests/fixtures/parity/f028/expected/r/plot-data-aggte-calendar.csv`, and
    `tests/fixtures/parity/f028/expected/r/events.json`;
  - expected Stata schema:
    `tests/fixtures/parity/f028/expected/new-stata/plot-schema.json`;
  - manifest: `tests/fixtures/parity/f028/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f028.do`;
  - status: F028 `parity-verified` for `csdid_plot, saving()` plot-data export
    for ATT(g,t), ATT(g,t) group filtering, and dynamic/group/calendar
    aggregation, plus simple-aggregation rejection. Plot data columns, labels,
    confidence intervals, significance flags, and save behavior are verified.
    Rendered graphs, graph styling, and JEL figure artifacts remain tracked by
    RT013/PY010/JEL rows.
- R `test-ggdid.R` inheritance fixture:
  - generator: `tools/parity/generators/rt013/generate.R`;
  - input: `tests/fixtures/parity/rt013/inputs/sim-ggdid.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt013/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/rt013/expected/contract/approved-divergence.csv`,
    and `tests/fixtures/parity/rt013/expected/contract/events.csv`;
  - R expected outputs:
    `tests/fixtures/parity/rt013/expected/r/plot-data-attgt.csv`,
    `tests/fixtures/parity/rt013/expected/r/plot-data-attgt-first-group.csv`,
    `tests/fixtures/parity/rt013/expected/r/plot-data-aggte-dynamic.csv`,
    `tests/fixtures/parity/rt013/expected/r/plot-data-aggte-group.csv`, and
    `tests/fixtures/parity/rt013/expected/r/plot-data-aggte-calendar.csv`;
  - manifest: `tests/fixtures/parity/rt013/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-ggdid.do`;
  - status: RT013 `approved-divergence`. The gate maps R `did`
    `tests/testthat/test-ggdid.R` to Stata `csdid_plot` plot-data exports for
    ATT(g,t), group filtering, invalid-group diagnostics,
    dynamic/group/calendar aggregation, and simple-aggregation rejection.
    Approved divergence RT013-DIV001 records that R ggplot label/theme/
    ref_line controls are rendered-graph styling outside the frozen Stata
    plot-data contract.
- Python `test_ggdid.py` inheritance fixture:
  - generator: `tools/parity/generators/py010/generate.py`;
  - input: `tests/fixtures/parity/py010/inputs/sim-ggdid.csv`;
  - contract outputs:
    `tests/fixtures/parity/py010/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py010/expected/contract/approved-divergence.csv`,
    and `tests/fixtures/parity/py010/expected/contract/plot-scenarios.csv`;
  - manifest: `tests/fixtures/parity/py010/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_ggdid.do`;
  - status: PY010 `approved-divergence`. The gate maps Python plotting object
    creation to Stata plot-data exports for ATT(g,t), single-group filtering,
    and dynamic/group/calendar aggregation. Approved divergences record
    Python matplotlib styling APIs and Python's invalid-group raising behavior
    because the Stata port follows R did plot-data and invalid-group warning
    semantics.
- Validation-event smoke fixture:
  - generator: `tools/parity/generators/f029/generate.R`;
  - inputs:
    `tests/fixtures/parity/f029/inputs/input.csv`,
    `tests/fixtures/parity/f029/inputs/negative-weight.csv`,
    `tests/fixtures/parity/f029/inputs/duplicate-input.csv`, and
    `tests/fixtures/parity/f029/inputs/empty-after-markout.csv`;
  - R/contract expected outputs:
    `tests/fixtures/parity/f029/expected/r/events.csv` and
    `tests/fixtures/parity/f029/expected/r/events.json`;
  - manifest: `tests/fixtures/parity/f029/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f029.do`;
  - status: F029 `parity-verified` for current `csdid`, `csdid_stats`,
    `csdid_estat`, and `csdid_plot` validation events, including return codes
    and normalized diagnostic messages. Inherited Python error-handling is
    covered by PY008 and the inherited R error-handling suite is covered by
    RT011 with approved R-only divergences.
- R `test-error-handling.R` inheritance fixture:
  - generator: `tools/parity/generators/rt011/generate.R`;
  - inputs:
    `tests/fixtures/parity/rt011/inputs/sim-error-handling.csv`,
    `tests/fixtures/parity/rt011/inputs/no-never-treated.csv`,
    `tests/fixtures/parity/rt011/inputs/small-groups.csv`,
    `tests/fixtures/parity/rt011/inputs/missing-inputs.csv`, and
    `tests/fixtures/parity/rt011/inputs/treatment-reversal.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt011/expected/contract/upstream-test-map.csv`
    and
    `tests/fixtures/parity/rt011/expected/contract/approved-divergence.csv`;
  - manifest: `tests/fixtures/parity/rt011/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-error-handling.do`;
  - status: RT011 `approved-divergence`. The gate maps all 49 R
    `tests/testthat/test-error-handling.R` blocks, with 29 public
    command-surface diagnostics or success checks executed in Stata. Approved
    divergences RT011-DIV001 through RT011-DIV003 record R-only helper APIs,
    mutable S3 internals, unrepresentable argument shapes, graph helper scalar
    controls, Wald-pretest messaging, extra-dot warning behavior, and
    owner-directed unbalanced-panel handling.
- R `test-conditional-did-pretest.R` inheritance fixture:
  - generator: `tools/parity/generators/rt009/generate.R`;
  - contract outputs:
    `tests/fixtures/parity/rt009/expected/contract/upstream-test-map.csv`
    and
    `tests/fixtures/parity/rt009/expected/contract/approved-divergence.csv`;
  - manifest: `tests/fixtures/parity/rt009/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-conditional-did-pretest.do`;
  - status: RT009 `approved-divergence`. All three R source blocks directly
    test the standalone `conditional_did_pretest()`/`MP.TEST` helper surface
    and its internal precompute/bootstrap-scale paths. The frozen Stata public
    command profile has no standalone conditional-pretest command or MP.TEST
    object; public bootstrap and pre-period behavior remains verified through
    `csdid`, `csdid_stats`, `csdid_estat`, and inference rows.
- R `test-compute-inffunc.R` inheritance fixture:
  - generator: `tools/parity/generators/rt008/generate.R`;
  - input: `tests/fixtures/parity/rt008/inputs/input.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt008/expected/contract/upstream-test-map.csv`
    and
    `tests/fixtures/parity/rt008/expected/contract/approved-divergence.csv`;
  - manifest: `tests/fixtures/parity/rt008/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-compute-inffunc.do`;
  - status: RT008 `approved-divergence`. All eight R source blocks directly
    test `compute_inffunc=FALSE` point-estimates-only MP object behavior and
    custom-estimator callbacks. The frozen Stata public command profile keeps
    influence functions available for standard errors, saved RIF artifacts,
    and postestimation; `compute_inffunc()` is explicitly rejected as an
    unsupported option.
- R `test-overlap-guard-cache.R` inheritance fixture:
  - generator: `tools/parity/generators/rt022/generate.R`;
  - input: `tests/fixtures/parity/rt022/inputs/overlap-cache.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt022/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/rt022/expected/contract/approved-divergence.csv`,
    and `tests/fixtures/parity/rt022/expected/contract/events.csv`;
  - manifest: `tests/fixtures/parity/rt022/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-overlap-guard-cache.do`;
  - status: RT022 `approved-divergence`. The gate maps the public
    overlap-warning count/text assertion from R `did`
    `tests/testthat/test-overlap-guard-cache.R` to Stata diagnostics on the
    separated-design shape and verifies no internal 2x2 error leaks. Approved
    divergences RT022-DIV001 and RT022-DIV002 record direct calls to
    non-exported R overlap/rcond guard helpers and the R-only
    `did.disable_check_cache` toggle.
- R `test-pretest-vectorization.R` inheritance fixture:
  - generator: `tools/parity/generators/rt023/generate.R`;
  - contract outputs:
    `tests/fixtures/parity/rt023/expected/contract/upstream-test-map.csv`
    and
    `tests/fixtures/parity/rt023/expected/contract/approved-divergence.csv`;
  - manifest: `tests/fixtures/parity/rt023/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-pretest-vectorization.do`;
  - status: RT023 `approved-divergence`. All four source blocks directly test
    R conditional-pretest helper internals, `indicator()` and `test.mboot()`,
    including an R skipped large-array tiling path. The Stata port has no
    public `conditional_did_pretest` or `MP.TEST` surface; public bootstrap
    behavior remains verified through `csdid`/`csdid_stats` inference rows.
- R `test-robustness-guards.R` inheritance fixture:
  - generator: `tools/parity/generators/rt024/generate.R`;
  - inputs:
    `tests/fixtures/parity/rt024/inputs/duplicate-id-period.csv`,
    `tests/fixtures/parity/rt024/inputs/negative-weights.csv`,
    `tests/fixtures/parity/rt024/inputs/zero-weights.csv`,
    `tests/fixtures/parity/rt024/inputs/positive-weights.csv`,
    `tests/fixtures/parity/rt024/inputs/rc-missing-treated-post.csv`,
    `tests/fixtures/parity/rt024/inputs/small-never-treated.csv`,
    `tests/fixtures/parity/rt024/inputs/fractional-unbalanced.csv`,
    `tests/fixtures/parity/rt024/inputs/column-named-weights.csv`,
    `tests/fixtures/parity/rt024/inputs/transformed-nonfinite.csv`, and
    `tests/fixtures/parity/rt024/inputs/panel-nan-cells.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt024/expected/contract/upstream-test-map.csv`
    and
    `tests/fixtures/parity/rt024/expected/contract/approved-divergence.csv`;
  - manifest: `tests/fixtures/parity/rt024/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-robustness-guards.do`;
  - status: RT024 `approved-divergence`. Stata maps nine public robustness
    guard blocks from R `tests/testthat/test-robustness-guards.R`, covering
    duplicate id-time rejection, negative and zero-mean weight rejection,
    positive-weight acceptance, no-treated-cell warnings and missing cells,
    never-treated-small-control rejection, fractional unbalanced id baseline/
    fast equality, user columns named `weights`, transformed non-finite
    covariate dropping, and NaN-to-missing cell behavior. RT024-DIV001 through
    RT024-DIV003 record R-only helper internals and R `Inf` treatment-timing
    semantics that have no Stata numeric analogue.
- R `test-audit-fixes.R` inheritance fixture:
  - generator: `tools/parity/generators/rt006/generate.R`;
  - inputs:
    `tests/fixtures/parity/rt006/inputs/balanced-seed1.csv`,
    `tests/fixtures/parity/rt006/inputs/balanced-seed2.csv`,
    `tests/fixtures/parity/rt006/inputs/balanced-seed3.csv`,
    `tests/fixtures/parity/rt006/inputs/mpdta.csv`, and
    `tests/fixtures/parity/rt006/inputs/negative-g.csv`;
  - R expected outputs:
    `tests/fixtures/parity/rt006/expected/r/fixweights-attgt.csv`,
    `tests/fixtures/parity/rt006/expected/r/fixweights-aggte.csv`,
    `tests/fixtures/parity/rt006/expected/r/normal-aggte.csv`, and
    `tests/fixtures/parity/rt006/expected/r/calendar-ignored.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt006/expected/contract/upstream-test-map.csv`
    and
    `tests/fixtures/parity/rt006/expected/contract/approved-divergence.csv`;
  - manifest: `tests/fixtures/parity/rt006/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-audit-fixes.do`;
  - status: RT006 `approved-divergence`. The gate maps public R audit-fix
    behavior for no-weight `fix_weights(varying)` ATT(g,t) and simple
    aggregation SE normalization, ordinary simple/dynamic/group/calendar
    aggregation on `mpdta`, all-NA calendar-period dropping under `na_rm`,
    clean empty-window aggregation errors, negative `gvar()` rejection before
    baseline or fast computation, and calendar `min_e()`/`max_e()`/
    `balance_e()` ignored-window warnings. The implementation fix keeps the
    no-weight `fix_weights(varying)` path on the ordinary panel influence
    function, avoiding the exact doubled-SE audit regression. The
    `fix_weights(varying)` `method(dr)` fast request now uses the optimized
    path and matches explicit `nofast`; RT006-DIV002 records R-only
    non-exported parallel multiplier-bootstrap helper internals.
- Python `test_error_handling.py` inheritance fixture:
  - generator: `tools/parity/generators/py008/generate.py`;
  - inputs:
    `tests/fixtures/parity/py008/inputs/sim-data.csv`,
    `tests/fixtures/parity/py008/inputs/no-never-treated.csv`,
    `tests/fixtures/parity/py008/inputs/small-groups.csv`,
    `tests/fixtures/parity/py008/inputs/first-period-treated.csv`,
    `tests/fixtures/parity/py008/inputs/missing-outcome.csv`, and
    `tests/fixtures/parity/py008/inputs/treatment-reversal.csv`;
  - contract outputs:
    `tests/fixtures/parity/py008/expected/contract/upstream-test-map.csv` and
    `tests/fixtures/parity/py008/expected/contract/upstream-test-map.json`;
  - manifest: `tests/fixtures/parity/py008/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_error_handling.do`;
  - status: PY008 `parity-verified`. The gate maps all 12 tests in
    DrSquare/csdid `csdid/test_csdid/test_error_handling.py`, covering
    missing-variable diagnostics, no-never-treated latest-cohort fallback
    warning, small-group warning, first-period-treated drop warning,
    missing-outcome drop diagnostic, `na_rm` aggregation after missing ATT
    injection, `fix_weights` validation, fast-request missing-column
    validation, invalid method validation, and irreversible treatment timing
    rejection.
- Mutation/state-hygiene fixture:
  - generator: `tools/parity/generators/f031/generate.R`;
  - input: `tests/fixtures/parity/f031/inputs/input.csv`;
  - expected Stata schema:
    `tests/fixtures/parity/f031/expected/new-stata/mutation-safety.json`;
  - manifest: `tests/fixtures/parity/f031/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f031.do`;
  - status: F031 `parity-verified` for supported estimation, saved-RIF
    estimation, saved-RIF postestimation, current-frame preservation when
    frames are available, auxiliary-frame preservation when frames are
    available, absence of package global macro writes in source files,
    `csdid_estat` display/tidy/glance, `csdid_stats`
    simple/group/calendar/dynamic, `csdid_plot` supported plot-data exports,
    invalid-option rejection, and preservation of data values, order, variable
    order, labels, characteristics, and user matrices.
- R `test-mutation-safety.R` inheritance fixture:
  - generator: `tools/parity/generators/rt020/generate.R`;
  - inputs:
    `tests/fixtures/parity/rt020/inputs/panel.csv` and
    `tests/fixtures/parity/rt020/inputs/repeated-cross-section.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt020/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/rt020/expected/contract/upstream-test-map.json`,
    `tests/fixtures/parity/rt020/expected/contract/approved-divergence.csv`,
    `tests/fixtures/parity/rt020/expected/contract/approved-divergence.json`, and
    `tests/fixtures/parity/rt020/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/rt020/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-mutation-safety.do`;
  - status: RT020 `approved-divergence`. Stata verifies that active dataset
    variable names, values, and row order are unchanged for panel and
    repeated-cross-section inputs with and without requested fast mode.
    RT020-DIV001 records that R's data.frame/data.table object-class split has
    no separate Stata command-surface analogue.
- R `test-output-methods-coverage.R` inheritance fixture:
  - generator: `tools/parity/generators/rt021/generate.R`;
  - input: `tests/fixtures/parity/rt021/inputs/output-methods.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt021/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/rt021/expected/contract/upstream-test-map.json`,
    `tests/fixtures/parity/rt021/expected/contract/approved-divergence.csv`,
    `tests/fixtures/parity/rt021/expected/contract/approved-divergence.json`, and
    `tests/fixtures/parity/rt021/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/rt021/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-output-methods-coverage.do`;
  - status: RT021 `approved-divergence`. Stata verifies
    `csdid_stats`/`csdid_estat` output surfaces for all aggregation types and
    pointwise not-yet-treated `dr`/`ipw`/`reg` branches. RT021-DIV001 through
    RT021-DIV003 record R-only `conditional_did_pretest`/`MP.TEST`,
    `trimmer`, and `get_wide_data` helper APIs with no public Stata command
    analogue.
- Direct DRDID-boundary smoke fixture:
  - generator: `tools/parity/generators/f033/generate.R`;
  - input: `tests/fixtures/parity/f033/inputs/input.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f033/expected/r/drdid-direct-grid.csv` and
    `tests/fixtures/parity/f033/expected/r/drdid-alternative-grid.csv`;
  - manifest: `tests/fixtures/parity/f033/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f033.do`;
  - approved divergence:
    `tests/fixtures/parity/f033/expected/contract/approved-divergence.csv`;
  - status: F033 `approved-divergence` evidence against direct R `DRDID`
    1.3.0 functions for one two-period design across weighted and unweighted
    panel/repeated-cross-section, intercept/covariate,
    `dr`/`reg`/normalized-`ipw` cells, and nondefault `pscoretrim(.7)`
    trimming for weighted covariate DR/IPW cells. The fixture now also includes
    diagnostic contrasts that prove Stata matches the R `did` target functions
    rather than improved DRDID, RC1, or unnormalized IPW alternatives.
    F033-DIV001 records raw DRDID helper internals that are not public Stata
    command surfaces.
- Saved-RIF artifact smoke fixture:
  - generator: `tools/parity/generators/f034/generate.R`;
  - input: `tests/fixtures/parity/f034/inputs/input.csv`;
  - R expected output:
    `tests/fixtures/parity/f034/expected/r/rif-summary.csv`;
  - expected Stata schema:
    `tests/fixtures/parity/f034/expected/new-stata/saverif-schema.json`;
  - manifest: `tests/fixtures/parity/f034/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f034.do`;
  - approved divergence:
    `tests/fixtures/parity/f034/expected/contract/approved-divergence.csv`;
  - status: F034 `approved-divergence` evidence for `saverif()` artifacts in panel and true
    repeated-cross-section no-covariate `method(reg)` slices, including the
    saved unit aggregation `weight` column and `csdid_stats using` reload parity
    for simple, group, calendar, and dynamic aggregation. F034-DIV001 records
    persisted RIF datasets as a Stata extension that must preserve R
    influence-function content rather than byte-match an R object format.
- Clean-install release fixture:
  - generator: `tools/parity/generators/f050/generate.R`;
  - input: `tests/fixtures/parity/f050/inputs/input.csv`;
  - expected Stata schema:
    `tests/fixtures/parity/f050/expected/new-stata/install-schema.json`;
  - manifest: `tests/fixtures/parity/f050/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f050.do`;
  - status: F050 `parity-verified` for local build, local `net install`,
    temporary PLUS/PERSONAL isolation, installed file resolution, and installed
    smoke commands, including the saved RIF `weight` column.
- Release-defaults and UX fixture:
  - generator: `tools/parity/generators/f051/generate.R`;
  - input: `tests/fixtures/parity/f051/inputs/default-panel.csv`;
  - R expected output:
    `tests/fixtures/parity/f051/expected/r/default-attgt.csv`;
  - default/UX contract:
    `tests/fixtures/parity/f051/expected/contract/default-surface.json`;
  - manifest: `tests/fixtures/parity/f051/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f051.do`;
  - status: F051 `parity-verified` for the release-facing omitted-option
    defaults and user workflow surface. The gate verifies Stata default
    ATT(g,t) output against the R-generated default-equivalent oracle and
    freezes `method(dr)`, never-treated controls, `baseperiod(varying)`,
    `anticipation(0)`, `level(95)`, `pscoretrim(.995)`, optimized default
    computation/storage metadata, Stata-style aliases (`baseperiod()`,
    bare `universal`/`varying`, `id()`, `fixweights(base|first)`,
    `notyettreated`/`nevertreated`, `vce(cluster ...)`, `allowunbalanced`,
    `storeall`, bootstrap shorthand, `window()`, `balance()`, `dropmissing`,
    `csdid_stats event`, `csdid_stats, type(event)`, `estat event`, and
    `estat dynamic/simple/group/calendar`), `storeall` full-storage
    compatibility, default `csdid_stats` group aggregation, dynamic/event
    replay, `csdid_plot, saving()` plot-data handoff, and explicit diagnostics
    for missing `saving()` and unsupported `csdid_estat` subcommands.
- Base-period parity fixture:
  - generator: `tools/parity/generators/f007/generate.R`;
  - input: `tests/fixtures/parity/f007/inputs/input.csv`;
  - R expected output: `tests/fixtures/parity/f007/expected/r/base-period-grid.csv`;
  - manifest: `tests/fixtures/parity/f007/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f007.do`;
  - status: F007 `parity-verified`.
- Control-group parity fixture:
  - generator: `tools/parity/generators/f008/generate.R`;
  - input: `tests/fixtures/parity/f008/inputs/input.csv`;
  - R expected output: `tests/fixtures/parity/f008/expected/r/control-group-grid.csv`;
  - manifest: `tests/fixtures/parity/f008/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f008.do`;
  - status: F008 `parity-verified`.
- Anticipation parity fixture:
  - generator: `tools/parity/generators/f009/generate.R`;
  - input: `tests/fixtures/parity/f009/inputs/input.csv`;
  - R expected output: `tests/fixtures/parity/f009/expected/r/anticipation-grid.csv`;
  - manifest: `tests/fixtures/parity/f009/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f009.do`;
  - status: F009 `parity-verified`.
- Duplicate unit-time validation fixture:
  - generator: `tools/parity/generators/f024/generate.R`;
  - input: `tests/fixtures/parity/f024/inputs/duplicate-input.csv`;
  - R expected event output: `tests/fixtures/parity/f024/expected/r/events.json`;
  - manifest: `tests/fixtures/parity/f024/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f024.do`;
  - status: F024 `parity-verified`.
- Method-boundary smoke fixture:
  - generator: `tools/parity/generators/f010/generate.R`;
  - inputs: `tests/fixtures/parity/f010/inputs/input.csv` and
    `tests/fixtures/parity/f010/inputs/input-staggered.csv`;
  - R expected outputs: `tests/fixtures/parity/f010/expected/r/method-grid.csv`
    `tests/fixtures/parity/f010/expected/r/covariate-method-grid.csv`,
    `tests/fixtures/parity/f010/expected/r/rc-method-grid.csv`,
    `tests/fixtures/parity/f010/expected/r/rc-covariate-method-grid.csv`,
    and `tests/fixtures/parity/f010/expected/r/control-method-grid.csv`;
  - manifest: `tests/fixtures/parity/f010/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f010.do`;
  - status: F010 `parity-verified` for panel and true repeated-cross-section
    `dr`/`reg`/`ipw`
    point-estimate and analytical-SE parity for no-covariate and
    numeric-covariate cells, plus a staggered all-method
    nevertreated/notyettreated control-group grid for panel and repeated-
    cross-section paths. The fixture covers the repeated-cross-section
    no-covariate notyettreated SE path exposed by the F010/PY016-style grid,
    and includes soft-deprecated legacy alias checks for `dripw -> dr` and
    `stdipw -> ipw`. Deeper native DRDID dependency-boundary parity remains
    tracked by F033.
- Covariate timing smoke fixture:
  - generator: `tools/parity/generators/f011/generate.R`;
  - inputs:
    `tests/fixtures/parity/f011/inputs/input.csv` and
    `tests/fixtures/parity/f011/inputs/sparse-factor.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f011/expected/r/covariate-grid.csv`,
    `tests/fixtures/parity/f011/expected/r/dense-factor-dummy-grid.csv`,
    `tests/fixtures/parity/f011/expected/r/sparse-factor-grid.csv`, and
    `tests/fixtures/parity/f011/expected/r/sparse-factor-events.csv`;
  - manifest: `tests/fixtures/parity/f011/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f011.do`;
  - status: F011 `parity-verified` for panel and true repeated-cross-section
    `dr`/`reg`/`ipw`
    covariate parity for numeric time-varying covariates, factor expansion,
    numeric interactions (`~ x1 * x2` / `c.x1##c.x2`), and squared transformed
    covariate terms (`~ I(x1^2) + x2` / `c.x1#c.x1 x2`). Broader nuisance
    stress remains tracked by RT/PY inheritance rows and F033.
- R model-matrix hoist fixture:
  - generator: `tools/parity/generators/rt019/generate.R`;
  - inputs: `tests/fixtures/parity/rt019/inputs/input.csv` and
    `tests/fixtures/parity/rt019/inputs/sparse-factor.csv`;
  - expected outputs:
    `tests/fixtures/parity/rt019/expected/r/covariate-grid.csv`,
    `tests/fixtures/parity/rt019/expected/r/dense-factor-dummy-grid.csv`,
    `tests/fixtures/parity/rt019/expected/r/sparse-factor-grid.csv`,
    `tests/fixtures/parity/rt019/expected/r/sparse-factor-events.csv`,
    `tests/fixtures/parity/rt019/expected/contract/upstream-test-map.csv`,
    and `tests/fixtures/parity/rt019/expected/contract/approved-divergence.csv`;
  - manifest: `tests/fixtures/parity/rt019/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-modelmatrix-hoist.do`;
  - status: RT019 `approved-divergence`. The gate maps five public
    covariate/factor assertions from R
    `tests/testthat/test-modelmatrix-hoist.R`: panel and
    repeated-cross-section numeric/interaction/squared covariate ATT(g,t)/SE
    parity, dense factor/manual-dummy equivalence, and panel/RC sparse-factor
    missing-pattern plus singular-warning parity. `RT019-DIV001` through
    `RT019-DIV006` record R-only `model.matrix`, `faster_mode`, `poly()`,
    formula-time non-finite transform, matrix-valued formula, and retained
    empty-factor-level internals that have no separate public Stata command
    surface.
- Balanced-panel and allow_unbalanced weight smoke fixture:
  - generator: `tools/parity/generators/f012/generate.R`;
  - inputs: `tests/fixtures/parity/f012/inputs/input.csv` and
    `tests/fixtures/parity/f012/inputs/input-unbalanced.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f012/expected/r/weighted-grid.csv`,
    `tests/fixtures/parity/f012/expected/r/time-invariant-fixweights.csv`,
    `tests/fixtures/parity/f012/expected/r/weighted-aggte.csv`, and
    `tests/fixtures/parity/f012/expected/r/events.csv`;
  - manifest: `tests/fixtures/parity/f012/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f012.do`;
  - status: F012 `parity-verified` for `iweight`/R `weightsname` parity on
    balanced-panel
    default/varying/base-period/first-period `dr`/`reg`/`ipw` cells with and
    without numeric covariates, plus true repeated-cross-section default/varying
    weighted cells with and without numeric covariates, scaled-weight invariance,
    time-invariant unit-weight default/varying/base-period/first-period
    ATT(g,t) parity and point-estimate invariance across `dr`/`reg`/`ipw`
    with no and numeric covariates,
    negative-weight validation, R-style time-varying-weight messaging,
    time-invariant no-message behavior, fixed-reference unbalanced drop
    warnings, and weighted simple/group/calendar/dynamic aggregation for
    `dr`/`reg`/`ipw`, no and numeric covariates, `wt`/`wt_scaled`, panel
    default/varying/base-period/first-period, repeated-cross-section
    default/varying, plus allow_unbalanced default/varying/base-period/first-period;
    inherited IF consistency and custom-estimator diagnostics remain tracked by
    RT/PY rows.
- Analytical-inference fixture:
  - generator: `tools/parity/generators/f013/generate.R`;
  - input: `tests/fixtures/parity/f013/inputs/input.csv`;
  - R expected outputs: `tests/fixtures/parity/f013/expected/r/attgt.csv`
    and `tests/fixtures/parity/f013/expected/r/inffunc-summary.csv`;
  - manifest: `tests/fixtures/parity/f013/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f013.do`;
  - status: F013 `parity-verified` for analytical ATT(g,t) SEs and
    influence-function dimensions/summaries. Bootstrap and clustered inference
    remain F014/F015.
- R `test-inference.R` inheritance fixture:
  - generator: `tools/parity/generators/rt015/generate.R`;
  - inputs:
    `tests/fixtures/parity/rt015/inputs/panel.csv` and
    `tests/fixtures/parity/rt015/inputs/repeated-cross-section.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt015/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/rt015/expected/contract/upstream-test-map.json`,
    `tests/fixtures/parity/rt015/expected/contract/approved-divergence.csv`,
    `tests/fixtures/parity/rt015/expected/contract/approved-divergence.json`,
    and `tests/fixtures/parity/rt015/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/rt015/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-inference.do`;
  - status: RT015 `approved-divergence`. The gate maps current public
    inference surfaces from R `tests/testthat/test-inference.R` at sha256
    `3a39714114bb5157f619f3184d2e21011c49c1a1a828405ee35b24c027eb131f`:
    panel, clustered panel, repeated-cross-section, and clustered
    repeated-cross-section ATT(g,t) SEs, influence-function dimensions,
    cluster metadata, and dynamic/group/calendar aggregation SEs.
    `RT015-DIV001` records the R `did` 2.1.2 temporary-library historical
    object comparison, which has no public Stata command analogue.
- R legacy point-estimate script fixtures:
  - generators:
    `tools/parity/generators/rt029/generate.R` and
    `tools/parity/generators/rt030/generate.R`;
  - Stata comparisons:
    `tests/stata/r/att_gt_point_estimate_tests.do` and
    `tests/stata/r/att_gt_point_estimate_tests_rmd.do`;
  - status: RT029 and RT030 `approved-divergence`. The gates map public
    point-estimate scenarios from R
    `tests/testthat/att_gt_point_estimate_tests.R` and
    `tests/testthat/att_gt_point_estimate_tests.Rmd`: panel methods,
    two-period aggregations, no-covariate fits, repeated cross-sections,
    allow_unbalanced, and not-yet-treated/no-never controls. `RT029-DIV001`
    and `RT030-DIV001` record that the source files are legacy script/Rmd
    artifacts with printed output rather than formal `testthat` expectations.
- Bootstrap/simultaneous-band smoke fixture:
  - generator: `tools/parity/generators/f014/generate.R`;
  - input: `tests/fixtures/parity/f014/inputs/input.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f014/expected/r/bootstrap-attgt.csv`,
    `tests/fixtures/parity/f014/expected/r/bootstrap-cluster-attgt.csv`,
    `tests/fixtures/parity/f014/expected/r/events.csv`, and
    `tests/fixtures/parity/f014/expected/r/events.json`;
  - manifest: `tests/fixtures/parity/f014/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f014.do`;
  - status: F014 `approved-divergence` for ATT(g,t)
    multiplier-bootstrap support on one balanced-panel `method(reg)` slice,
    covering both unclustered and cluster-summed influence-function paths.
    Stata records bootstrap reps, seed, multiplier distribution, cluster
    metadata, simultaneous critical value, pointwise critical value, and
    `e(boot_attgt)`. The `pointwise` switch maps to non-cband intervals. The
    seeded simultaneous-band bootstrap keeps the BMisc/R rademacher stream,
    while pointwise bootstrap uses the faster vectorized Rademacher path and
    advances the BMisc state for postestimation continuity. F035 guards the
    BMisc stream probe; F014 continues to smoke-check stochastic bootstrap SEs while enforcing
    deterministic ATT, analytical SEs, clustered analytical SEs, metadata, and
    CI algebra. PY005/PY015 cover inherited Python clustered bootstrap smoke,
    RT017 covers inherited R ATT(g,t) cluster-sum bootstrap stress, and
    aggregation bootstrap plus inherited RT018 postprocess stress remain
    tracked separately.
- Bootstrap option-surface fixture:
  - generator: `tools/parity/generators/f035/generate.R`;
  - input: `tests/fixtures/parity/f035/inputs/input.csv`;
  - expected Stata option contract:
    `tests/fixtures/parity/f035/expected/new-stata/bootstrap-options.json`;
  - expected validation events:
    `tests/fixtures/parity/f035/expected/new-stata/events.csv` and
    `tests/fixtures/parity/f035/expected/new-stata/events.json`;
  - approved divergence:
    `tests/fixtures/parity/f035/expected/contract/approved-divergence.csv`;
  - manifest: `tests/fixtures/parity/f035/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f035.do`;
  - status: F035 `approved-divergence` evidence for `wboot(reps())`,
    `wboot(biters())`, nested `rseed()`/`seed()`, shorthand
    `wboot reps(#) seed(#)` / `wboot reps(#) rseed(#)`, top-level `rseed()`
    with `wboot()`, `pointwise` metadata inherited from F014, and legacy
    `wtype()`/`wbtype()` values `normal`, `gaussian`, `rademacher`, and
    `mammen` mapped to the R-compatible rademacher multiplier path with
    `e(boot_dist_requested)` preserved. ATT(g,t) clustered bootstrap is
    supported through either `cluster()` or `wboot(cluster())`, and mismatched
    cluster declarations return an explicit diagnostic. Invalid reps, seeds,
    distribution names, and `reps()`, `biters()`, `seed()`, or `rseed()`
    without `wboot` return explicit diagnostics. PY005/PY015 cover inherited
    Python clustered bootstrap smoke,
    RT017 covers inherited R ATT(g,t) cluster-sum bootstrap stress, and RT018
    records R's direct internal `mboot()` post-processing helper tests as an
    approved divergence. F035 now guards seed/reps metadata, deterministic
    alias equality, and the exact seeded BMisc/R rademacher stream probe, while F035-DIV002 records
    aggregation-bootstrap postprocessing as covered by F014/RT018-style evidence
    rather than this option-surface row.
- Clustered-inference smoke fixture:
  - generator: `tools/parity/generators/f015/generate.R`;
  - input: `tests/fixtures/parity/f015/inputs/input.csv`;
  - R expected outputs: `tests/fixtures/parity/f015/expected/r/cluster-grid.csv`,
    `tests/fixtures/parity/f015/expected/r/cluster-aggte.csv`, and
    `tests/fixtures/parity/f015/expected/r/events.json`;
  - manifest: `tests/fixtures/parity/f015/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f015.do`;
  - status: F015 `parity-verified` for analytical cluster-sum SE parity for
    ATT(g,t) and
    simple/group/calendar/dynamic aggregation across balanced panel
    no-covariate, balanced panel numeric-covariate `dr`, and true
    repeated-cross-section no-covariate slices. Materialized runs store
    `e(cluster_vec)` for postestimation aggregation, while large lean runs keep
    the same vector in the Mata cache; both paths reject time-varying panel
    clusters. ATT(g,t) clustered multiplier bootstrap smoke is covered by
    PY002/PY004/PY005/PY015 plus F014/F035, RT007 covers inherited R
    cluster-analytic stress, and RT017 covers inherited R ATT(g,t)
    cluster-sum bootstrap stress.
- R `test-cluster-analytic.R` inheritance fixture:
  - generator: `tools/parity/generators/rt007/generate.R`;
  - inputs:
    `tests/fixtures/parity/rt007/inputs/clustered-shocks-404.csv`,
    `tests/fixtures/parity/rt007/inputs/clustered-shocks-505.csv`,
    `tests/fixtures/parity/rt007/inputs/panel-between-11.csv`,
    `tests/fixtures/parity/rt007/inputs/panel-within-11.csv`,
    `tests/fixtures/parity/rt007/inputs/rcs-909.csv`,
    `tests/fixtures/parity/rt007/inputs/rcs-909-id.csv`, and
    `tests/fixtures/parity/rt007/inputs/rcs-910.csv`;
  - R expected outputs:
    `tests/fixtures/parity/rt007/expected/r/analytical-targets.csv`,
    `tests/fixtures/parity/rt007/expected/r/cluster-iid-contrast.csv`, and
    `tests/fixtures/parity/rt007/expected/r/aggte-overall.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt007/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/rt007/expected/contract/upstream-test-map.json`,
    and `tests/fixtures/parity/rt007/expected/contract/bootstrap-scenarios.csv`;
  - manifest: `tests/fixtures/parity/rt007/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-cluster-analytic.do`;
  - status: RT007 `parity-verified`. The gate maps R `did`
    `tests/testthat/test-cluster-analytic.R`, covering analytical ATT(g,t)
    clustered SEs equal to cluster-sum targets in regular/requested-fast panel
    and repeated-cross-section modes, clustered-vs-iid SE differences when
    clusters share shocks, clustered bootstrap IQR/raw-draw SD agreement with
    analytical SEs for panel DGPs, repeated-cross-section clustered
    bootstrap-vs-analytical agreement, and simple/group/dynamic aggregation
    propagation. F035 guards the exact seeded BMisc/R rademacher stream probe;
    RT007 remains a cluster-analytic and bootstrap-scale inheritance
    fixture rather than a raw-draw export fixture.
- R `test-mboot-postprocess.R` inheritance fixture:
  - generator: `tools/parity/generators/rt018/generate.R`;
  - contract outputs:
    `tests/fixtures/parity/rt018/expected/contract/upstream-test-map.csv`
    and
    `tests/fixtures/parity/rt018/expected/contract/approved-divergence.csv`;
  - manifest: `tests/fixtures/parity/rt018/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-mboot-postprocess.do`;
  - status: RT018 `approved-divergence`. Both R source blocks directly test
    R's internal `mboot()` helper on synthetic influence-function matrices and
    DIDparams-like lists, including the all-degenerate post-processing branch.
    The frozen Stata public command profile has no standalone `mboot` helper;
    public multiplier-bootstrap behavior remains verified through
    `csdid`/`csdid_stats` bootstrap, simultaneous-band, cluster-bootstrap, and
    inference rows.
- Python `test_aggte_comprehensive.py` inheritance fixture:
  - generator: `tools/parity/generators/py001/generate.py`;
  - input: `tests/fixtures/parity/py001/inputs/aggte-data.csv`;
  - contract outputs:
    `tests/fixtures/parity/py001/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py001/expected/contract/upstream-test-map.json`,
    and `tests/fixtures/parity/py001/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/py001/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_aggte_comprehensive.do`;
  - status: PY001 `parity-verified`. The gate maps all 46 public
    parameterizations in DrSquare/csdid
    `csdid/test_csdid/test_aggte_comprehensive.py` at sha256
    `0b8e87470662850acd90d96c449dfb1f51f7bd48393ad0864aa082ad693701df`.
    Stata verifies simple/dynamic/group/calendar aggregation validity,
    event-time sorting and windows, `balance_e` filtering, positive SEs,
    `na_rm` behavior, public aggregation metadata, level preservation, and
    `dr`/`reg`/`ipw` cross-method aggregation checks through `csdid_stats`.
- Python `test_analytical_cluster_se.py` inheritance fixture:
  - generator: `tools/parity/generators/py002/generate.py`;
  - input: `tests/fixtures/parity/py002/inputs/clustered-data.csv`;
  - contract outputs:
    `tests/fixtures/parity/py002/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py002/expected/contract/upstream-test-map.json`,
    and `tests/fixtures/parity/py002/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/py002/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_analytical_cluster_se.do`;
  - status: PY002 `parity-verified`. The gate maps all three assertions in
    DrSquare/csdid `csdid/test_csdid/test_analytical_cluster_se.py`, covering
    positive analytical clustered ATT(g,t) SEs without bootstrap, broad
    clustered bootstrap-vs-analytical SE agreement under the recorded
    stochastic tolerance, and positive simple-aggregation analytical clustered
    SEs.
- Python `test_att_gt.py` inheritance fixture:
  - generator: `tools/parity/generators/py003/generate.py`;
  - inputs:
    `tests/fixtures/parity/py003/inputs/sim-data.csv`,
    `tests/fixtures/parity/py003/inputs/two-period.csv`,
    `tests/fixtures/parity/py003/inputs/dynamic.csv`,
    `tests/fixtures/parity/py003/inputs/dynamic-rc.csv`,
    `tests/fixtures/parity/py003/inputs/unequal-periods.csv`,
    `tests/fixtures/parity/py003/inputs/anticipation.csv`,
    `tests/fixtures/parity/py003/inputs/unbalanced.csv`,
    `tests/fixtures/parity/py003/inputs/no-never.csv`,
    `tests/fixtures/parity/py003/inputs/small-groups.csv`,
    `tests/fixtures/parity/py003/inputs/fixweights.csv`,
    `tests/fixtures/parity/py003/inputs/fixweights-constant.csv`,
    `tests/fixtures/parity/py003/inputs/fixweights-unbalanced.csv`, and
    `tests/fixtures/parity/py003/inputs/nonconsecutive.csv`;
  - contract outputs:
    `tests/fixtures/parity/py003/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py003/expected/contract/upstream-test-map.json`,
    `tests/fixtures/parity/py003/expected/contract/approved-divergence.csv`,
    `tests/fixtures/parity/py003/expected/contract/approved-divergence.json`,
    and `tests/fixtures/parity/py003/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/py003/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_att_gt.do`;
  - status: PY003 `approved-divergence`. The gate maps 93 public assertions
    from DrSquare/csdid `csdid/test_csdid/test_att_gt.py` at sha256
    `65d153387ad39131aa5a9f5f87abf9ae8081bf562cc26ff3bf390b953ea154fe`.
    Stata verifies core `dr`/`reg`/`ipw` ATT(g,t), repeated cross-sections,
    allow_unbalanced routing, not-yet-treated controls, no-never fallback,
    dynamic aggregation, exposure windows, anticipation, level/cband metadata,
    validation failures, base-period modes, small-group warnings, unit weights,
    clustered analytical SEs, requested-fast/baseline equality, `fix_weights`
    behavior, influence-function summaries, and user column-name variations.
    `PY003-DIV001` records Python callable `est_method`, which has no public
    Stata command analogue.
- Python `test_cluster_analytic.py` inheritance fixture:
  - generator: `tools/parity/generators/py004/generate.py`;
  - inputs:
    `tests/fixtures/parity/py004/inputs/clustered-shocks-404.csv`,
    `tests/fixtures/parity/py004/inputs/clustered-shocks-505.csv`,
    `tests/fixtures/parity/py004/inputs/clustered-shocks-606.csv`,
    `tests/fixtures/parity/py004/inputs/clustered-shocks-707.csv`, and
    `tests/fixtures/parity/py004/inputs/clustered-shocks-808.csv`;
  - contract outputs:
    `tests/fixtures/parity/py004/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py004/expected/contract/upstream-test-map.json`,
    and `tests/fixtures/parity/py004/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/py004/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_cluster_analytic.do`;
  - status: PY004 `parity-verified`. The gate maps all public assertions and
    parameterizations in DrSquare/csdid
    `csdid/test_csdid/test_cluster_analytic.py`, covering clustered-vs-iid
    analytical SE differences, clustered analytical runs, simple/group/dynamic
    aggregation propagation, panel and repeated-cross-section
    bootstrap-vs-analytical broad agreement, repeated-cross-section
    requested-fast optimized equivalence, and all-method clustered analytical
    aggregation smoke.
- Python `test_clustered.py` inheritance fixture:
  - generator: `tools/parity/generators/py005/generate.py`;
  - inputs:
    `tests/fixtures/parity/py005/inputs/clustered-data.csv` and
    `tests/fixtures/parity/py005/inputs/time-varying-cluster.csv`;
  - contract outputs:
    `tests/fixtures/parity/py005/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py005/expected/contract/upstream-test-map.json`,
    and `tests/fixtures/parity/py005/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/py005/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_clustered.do`;
  - status: PY005 `parity-verified`. The gate maps all five assertions in
    DrSquare/csdid `csdid/test_csdid/test_clustered.py`, covering clustered
    multiplier-bootstrap positive valid SEs, clustered versus unclustered
    bootstrap SE contrasts, unit-level clustering close to no-cluster
    bootstrap SEs, and time-varying cluster rejection.
- R `test-mboot-cluster.R` inheritance fixture:
  - generator: `tools/parity/generators/rt017/generate.R`;
  - inputs:
    `tests/fixtures/parity/rt017/inputs/clustered-unbalanced.csv`,
    `tests/fixtures/parity/rt017/inputs/clustered-balanced.csv`, and
    `tests/fixtures/parity/rt017/inputs/clustered-invalid.csv`;
  - R expected outputs:
    `tests/fixtures/parity/rt017/expected/r/cluster-targets.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt017/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/rt017/expected/contract/upstream-test-map.json`,
    and `tests/fixtures/parity/rt017/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/rt017/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-mboot-cluster.do`;
  - status: RT017 `parity-verified`. The gate maps all three public
    assertions in R `did` `tests/testthat/test-mboot-cluster.R`, covering
    cluster-vector/influence-function alignment, unbalanced cluster-sum versus
    cluster-mean separation, balanced cluster-sum equals cluster-mean,
    clustered bootstrap SEs tracking the cluster-sum target for ATT(2,2), and
    rejection of multiple non-id cluster declarations. F035 guards the exact
    seeded BMisc/R rademacher stream probe; RT017 remains focused on the
    cluster-summed inheritance behavior.
- R `test-aggte-clustervars-override.R` analytical inheritance:
  - generator: `tools/parity/generators/rt001/generate.R`;
  - input: `tests/fixtures/parity/rt001/inputs/two-cluster.csv`;
  - R expected outputs:
    `tests/fixtures/parity/rt001/expected/r/analytic-overrides.csv`,
    `tests/fixtures/parity/rt001/expected/r/relations.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt001/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/rt001/expected/contract/upstream-test-map.json`,
    `tests/fixtures/parity/rt001/expected/contract/approved-divergence.csv`,
    and
    `tests/fixtures/parity/rt001/expected/contract/approved-divergence.json`;
  - manifest: `tests/fixtures/parity/rt001/metadata/manifest.json`;
  - Stata comparison:
    `tests/stata/r/test-aggte-clustervars-override.do`;
  - status: RT001 `approved-divergence`. `csdid_stats` accepts
    `cluster()`/`clustervars()` postestimation overrides only when they match
    the cluster variable used by `csdid`; same-variable overrides are honored
    without warning, while missing or different cluster variables now fail
    loudly instead of falling back to non-clustered analytical standard errors.
    The upstream aggregation-bootstrap override subtest is recorded as
    `RT001-DIV001` because aggregation bootstrap remains outside the current
    public Stata aggregation contract.
- First unbalanced-panel smoke fixture:
  - generator: `tools/parity/generators/f016/generate.R`;
  - inputs: `tests/fixtures/parity/f016/inputs/input.csv`,
    `tests/fixtures/parity/f016/inputs/input-uniform-count.csv`, and
    `tests/fixtures/parity/f016/inputs/rt027-unbalanced-cluster.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f016/expected/r/attgt.csv`,
    `tests/fixtures/parity/f016/expected/r/cluster-grid.csv`,
    `tests/fixtures/parity/f016/expected/r/uniform-count-attgt.csv`,
    `tests/fixtures/parity/f016/expected/r/rt027-cluster-attgt.csv`,
    `tests/fixtures/parity/f016/expected/r/rt027-cluster-aggte.csv`, and
    `tests/fixtures/parity/f016/expected/r/events.json`;
  - manifest: `tests/fixtures/parity/f016/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f016.do`;
  - status: F016 `parity-verified` for owner-directed D003 unbalanced-panel
    default behavior: unbalanced `ivar()` routes to the repeated-cross-section
    estimator and matches R `did` 2.5.1 for `dr`/`reg`/`ipw` point estimates,
    analytical SEs, and cell counts with no covariates and `x1 + x2`
    covariates, each with and without `iweight`s. Clustered SE parity for the same grid and
    time-varying cluster rejection also pass, and unbalanced `ivar()` calls
    store `e(panel_mode) = "allow_unbalanced"`. The inherited equal-row-count
    but missing-periods edge case is also routed to `allow_unbalanced` and
    matches R missingness and finite ATT/SE values. A partial RT027-style
    shuffled unbalanced clustered universal-base slice now matches R for
    ATT(g,t), simple/group/calendar/dynamic aggregation, cluster-vector
    alignment, and R's missing-SE base-period behavior. Broader inherited
    unbalanced-panel stress beyond the RT027 source file remains tracked by
    PY rows.
- R `test-unbalanced-faster-cluster-se.R` inheritance fixture:
  - generator: `tools/parity/generators/rt027/generate.R`;
  - inputs:
    `tests/fixtures/parity/rt027/inputs/unbalanced-clustered.csv` and
    `tests/fixtures/parity/rt027/inputs/balanced-clustered.csv`;
  - R expected outputs:
    `tests/fixtures/parity/rt027/expected/r/attgt.csv` and
    `tests/fixtures/parity/rt027/expected/r/aggte.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt027/expected/contract/upstream-test-map.csv`
    and
    `tests/fixtures/parity/rt027/expected/contract/approved-divergence.csv`;
  - manifest: `tests/fixtures/parity/rt027/metadata/manifest.json`;
  - Stata comparison:
    `tests/stata/r/test-unbalanced-faster-cluster-se.do`;
  - status: RT027 `approved-divergence`. The gate maps all three upstream R
    source tests. The balanced clustered `method(reg)` fast path is verified
    against R `did` 2.5.1 and the baseline path for ATT(g,t) and
    simple/group/dynamic/calendar aggregations. The unbalanced clustered and
    iid public-result checks match R for ATT(g,t), aggregation, cluster-vector
    alignment, cluster-sum analytical SEs, and clustered-vs-iid SE
    separation, but RT027-DIV001 records that Stata `fast` requests on
    unbalanced panels intentionally fall back to the baseline path instead of
    running R's unbalanced `faster_mode` implementation.
- Legacy balance-mode compatibility fixture:
  - generator: `tools/parity/generators/f017/generate.R`;
  - input: `tests/fixtures/parity/f017/inputs/input.csv`;
  - expected outputs: `tests/fixtures/parity/f017/expected/r/events.csv`
    and `tests/fixtures/parity/f017/expected/r/events.json`;
  - manifest: `tests/fixtures/parity/f017/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f017.do`;
  - status: F017 `soft-deprecated-alias`. Legacy `bal(full)`,
    `balance(full)`, and `bal(unbal)` are accepted with a warning and map to
    the default `allow_unbalanced` path without restoring legacy unit
    dropping; `long`/`long2` emit strong deprecation warnings and use
    `baseperiod(universal)` when omitted, and `asinr` is verified as a no-op
    warning.
- Legacy/current option-inventory fixture:
  - generator: `tools/parity/generators/f036/generate.R`;
  - input: `tests/fixtures/parity/f036/inputs/input.csv`;
  - expected inventory:
    `tests/fixtures/parity/f036/expected/new-stata/option-inventory.csv` and
    `tests/fixtures/parity/f036/expected/new-stata/option-inventory.json`;
  - expected validation events:
    `tests/fixtures/parity/f036/expected/new-stata/events.csv` and
    `tests/fixtures/parity/f036/expected/new-stata/events.json`;
  - approved divergence:
    `tests/fixtures/parity/f036/expected/contract/approved-divergence.csv`;
  - manifest: `tests/fixtures/parity/f036/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f036.do`;
  - status: F036 `approved-divergence` evidence for the current public option surface across
    `csdid`, `csdid_stats`, `csdid_estat`, and `csdid_plot`. Accepted core
    options, `pscoretrim()`, and soft-deprecated aliases are checked, and
    `dryrun`, `agg()`, invalid `pscoretrim()`, `from()`, and unsupported style
    options return explicit diagnostics. F036-DIV001 records legacy Stata
    option classifications that are frozen as explicit retained,
    soft-deprecated, not-yet, or unsupported behavior rather than silent
    legacy no-ops.
- Python parametric-combination feature-slice fixture:
  - generator: `tools/parity/generators/f037/generate.R`;
  - input: `tests/fixtures/parity/f037/inputs/input.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f037/expected/r/scenarios.csv`,
    `tests/fixtures/parity/f037/expected/r/attgt.csv`, and
    `tests/fixtures/parity/f037/expected/r/aggte.csv`;
  - approved divergence:
    `tests/fixtures/parity/f037/expected/contract/approved-divergence.csv`;
  - manifest: `tests/fixtures/parity/f037/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f037.do`;
  - status: F037 `approved-divergence` feature-slice evidence for the Python deeper parametric grid,
    anchored to R `did` 2.5.1 expected values. The verified slice covers
    method by control group by base period, method by panel/repeated-cross
    section, method by anticipation, and method by aggregation type with one
    numeric covariate and analytical SEs. This fixed the Stata not-yet-treated
    control threshold for universal-base placebo cells to use
    `max(current period, base period) + anticipation`, matching R. F037-DIV001
    records Python-only stochastic bootstrap combinations and exhaustive
    integration-grid residuals as inherited surfaces covered by dedicated
    Python gates.
- Python inherited parametric-combination source-map fixture:
  - generator: `tools/parity/generators/py017/generate.py`;
  - inputs:
    `tests/fixtures/parity/py017/inputs/panel-data.csv`,
    `tests/fixtures/parity/py017/inputs/dynamic-data.csv`, and
    `tests/fixtures/parity/py017/inputs/anticipation-data.csv`;
  - expected source maps:
    `tests/fixtures/parity/py017/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py017/expected/contract/upstream-test-map.json`,
    and `tests/fixtures/parity/py017/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/py017/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_parametric_combinations.do`;
  - status: PY017 `parity-verified`. The fixture maps all 120 parameterized
    assertions from Python `csdid/test_csdid/test_parametric_combinations.py`
    at sha256 `ce505335fe16f7ed98196daffa628b25852474b0fd1fe948167c32f8e2502936`
    to public Stata behavior: method/control/base-period grids, panel and
    repeated-cross-section paths, anticipation 0/1/2, bootstrap and
    non-bootstrap finite SE/ATT checks, full simple-aggregation integration,
    all aggregation types by method, and repeated-cross-section dynamic-effect
    checks.
- Python user-regression fixture:
  - generator: `tools/parity/generators/f038/generate.R`;
  - inputs:
    `tests/fixtures/parity/f038/inputs/t1.csv`,
    `tests/fixtures/parity/f038/inputs/missing-cov.csv`,
    `tests/fixtures/parity/f038/inputs/fewer-periods.csv`,
    `tests/fixtures/parity/f038/inputs/zero-pre.csv`, and
    `tests/fixtures/parity/f038/inputs/anticipation.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f038/expected/r/attgt.csv`,
    `tests/fixtures/parity/f038/expected/r/aggte.csv`,
    `tests/fixtures/parity/f038/expected/r/events.csv`, and
    `tests/fixtures/parity/f038/expected/r/events.json`;
  - approved divergence:
    `tests/fixtures/parity/f038/expected/contract/approved-divergence.csv`;
  - manifest: `tests/fixtures/parity/f038/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f038.do`;
  - status: F038 `approved-divergence` evidence for Python/R user bug-fix
    regressions, anchored to R `did` 2.5.1 expected values. The verified slice
    covers harmless `t1` columns, missing-covariate complete-case panel unit
    dropping, fewer observed periods than treatment groups with dynamic,
    group, and calendar aggregations, zero pre-treatment outcomes, missing
    formula variables, and anticipation-window treatment-group coercion. This
    corrected Stata sample marking so panel covariate missingness is detected
    before row-wise `marksample` dropping and removes the full panel unit,
    matching R. RT028 and PY023 now map the inherited R/Python user-bug files
    through dedicated gates. PY020 now maps the separate Python review-fix file
    with approved divergences for Python-only helper/object-model internals.
    F038-DIV001 records those inherited residuals as covered by RT028, PY020,
    and PY023 rather than duplicated in this feature row.
- R `test-user_bug_fixes.R` inheritance fixture:
  - generator: `tools/parity/generators/rt028/generate.R`;
  - inputs:
    `tests/fixtures/parity/rt028/inputs/mpdta.csv`,
    `tests/fixtures/parity/rt028/inputs/fewer-periods.csv`,
    `tests/fixtures/parity/rt028/inputs/zero-pre.csv`,
    `tests/fixtures/parity/rt028/inputs/missing-var.csv`, and
    `tests/fixtures/parity/rt028/inputs/anticipation.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt028/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/rt028/expected/contract/approved-divergence.csv`,
    and `tests/fixtures/parity/rt028/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/rt028/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-user_bug_fixes.do`;
  - status: RT028 `approved-divergence`. The gate maps six public R user-bug
    blocks, covering mpdta not-yet-treated regressions before and after adding
    a harmless `t1` column, missing-covariate complete-case preprocessing,
    fewer observed periods than treatment groups with dynamic/group/calendar
    aggregation, zero pre-treatment ATT under universal/varying bases, unknown
    covariate rejection, and anticipation-window treatment-group coercion with
    fast-requested equality. RT028-DIV001 records the skipped R
    `DRDID::drdid_rc1` custom-estimator repeated-cross-section small-group
    branch, which has no public Stata custom-estimator callback analogue.
- Python `test_user_bug_fixes.py` inheritance fixture:
  - generator: `tools/parity/generators/py023/generate.py`;
  - inputs:
    `tests/fixtures/parity/py023/inputs/mpdta.csv`,
    `tests/fixtures/parity/py023/inputs/fewer_periods.csv`,
    `tests/fixtures/parity/py023/inputs/zero_pretreat.csv`,
    `tests/fixtures/parity/py023/inputs/missing_var.csv`, and
    `tests/fixtures/parity/py023/inputs/anticipation.csv`;
  - contract outputs:
    `tests/fixtures/parity/py023/expected/contract/upstream-test-map.csv`
    and `tests/fixtures/parity/py023/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/py023/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_user_bug_fixes.do`;
  - status: PY023 `parity-verified`. The gate maps all nine inherited
    Python user-bug tests, covering mpdta not-yet-treated regressions before
    and after adding a harmless `t1` column, missing-covariate complete-case
    preprocessing, fewer observed periods than treatment groups with
    dynamic/group/calendar aggregation and `dr`/`reg`/`ipw` method grid,
    zero pre-treatment ATT under universal/varying bases, unknown covariate
    rejection, and anticipation-window treatment-group coercion.
- Python inference fixture:
  - generator: `tools/parity/generators/f039/generate.R`;
  - input: `tests/fixtures/parity/f039/inputs/input.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f039/expected/r/scenarios.csv`,
    `tests/fixtures/parity/f039/expected/r/attgt.csv`,
    `tests/fixtures/parity/f039/expected/r/aggte.csv`, and
    `tests/fixtures/parity/f039/expected/r/inference-dimensions.csv`;
  - manifest: `tests/fixtures/parity/f039/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f039.do`;
  - status: F039 `parity-verified`. The original F039 analytical fixture
    remains as R-anchored evidence for panel and true repeated-cross-section
    inference across `dr`/`reg`/`ipw` with one numeric covariate, finite
    positive ATT(g,t) SEs, influence-function dimensions, and simple/dynamic/
    group/calendar aggregation SE parity. The row is closed by the stronger
    PY012 inheritance gate, which maps all 43 parameterized assertions in
    DrSquare/csdid `csdid/test_csdid/test_inference.py`, including
    unclustered bootstrap-vs-analytical rough agreement, bootstrap/analytical
    ATT equality, overall ATT near the true effect, and DR/REG cross-method
    ATT agreement.
- Python/R JEL inheritance audit fixture:
  - generator: `tools/parity/generators/f040/generate.R`;
  - expected contract outputs:
    `tests/fixtures/parity/f040/expected/contract/scenario-coverage.csv`,
    `tests/fixtures/parity/f040/expected/contract/source-audit.csv`,
    `tests/fixtures/parity/rt016/expected/contract/scenario-coverage.csv`,
    and `tests/fixtures/parity/py014/expected/contract/scenario-coverage.csv`;
  - manifests:
    `tests/fixtures/parity/f040/metadata/manifest.json`,
    `tests/fixtures/parity/rt016/metadata/manifest.json`, and
    `tests/fixtures/parity/py014/metadata/manifest.json`;
  - Stata comparisons:
    `tests/stata/test-f040.do`,
    `tests/stata/r/test-jel_replication.do`, and
    `tests/stata/python/test_jel_replication.do`;
  - JEL harness: `tests/run-jel-smoke.sh`;
  - status: F040/PY014 approved-divergence evidence and RT016
    parity-verified evidence for the inherited JEL test map. F041-F043 cover
    Table 7, 2xT, and GxT analytical JEL scenarios on actual JEL data, and
    F040 verifies the Table 7 weighted DR covariate `fast` request uses the
    optimized path and matches explicit `nofast` for ATT(g,t) and simple
    aggregation matrices. The
    approved divergence records that the frozen Python source path
    `csdid/test_csdid/test_jel_replication.py` is absent in the available local
    Python checkout; unavailable Python-specific source contents are therefore
    not certified.
- JEL Table 7 smoke fixture:
  - generator: `tools/parity/generators/f041/generate.R`;
  - input: `tests/fixtures/parity/f041/inputs/table7-input.csv`;
  - R expected output:
    `tests/fixtures/parity/f041/expected/r/table7-analytical.csv`;
  - committed JEL artifact context:
    `tests/fixtures/parity/f041/expected/jel/table7-committed.csv`;
  - manifest: `tests/fixtures/parity/f041/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f041.do`;
  - status: partial F041 evidence for the actual JEL Table 7 empirical
    sample. The verified slice reconstructs the two-period covariate-adjusted
    JEL analysis input from `JEL-DiD`, then compares Stata `csdid`
    analytical simple aggregation against R `did` 2.5.1 for `reg`/`ipw`/`dr`,
    weighted and unweighted. Committed R/Stata Table 7 display values are
    recorded as context, and the verified point estimates round to the
    committed R table. Full JEL replication still requires the 25,000-rep
    bootstrap/table-rendering wrapper and comparison against committed or
    regenerated JEL artifacts.
- JEL 2xT event-study smoke fixture:
  - generator: `tools/parity/generators/f042/generate.R`;
  - input: `tests/fixtures/parity/f042/inputs/event-study-input.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f042/expected/r/trends.csv`,
    `tests/fixtures/parity/f042/expected/r/attgt.csv`,
    `tests/fixtures/parity/f042/expected/r/dynamic.csv`, and
    `tests/fixtures/parity/f042/expected/r/post-window.csv`;
  - manifest: `tests/fixtures/parity/f042/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f042.do`;
  - JEL harness: `tests/run-jel-smoke.sh`;
  - status: partial F042 evidence for the actual JEL 2xT empirical sample.
    The verified slice reconstructs the JEL 2xT input from `JEL-DiD`, checks
    weighted trend data for Figure 2, and compares Stata `csdid` raw ATT(g,t),
    analytical dynamic aggregation, and post-window dynamic summaries against
    R `did` 2.5.1 for the weighted no-covariate regression event study and the
    weighted covariate-adjusted `reg`/`ipw`/`dr` event studies. Full Figure 3/4
    replication still requires the 25,000-rep bootstrap confidence intervals,
    plotting wrapper, rendered artifact comparison, and runtime/performance
    hardening.
- JEL GxT smoke fixture:
  - generator: `tools/parity/generators/f043/generate.R`;
  - input: `tests/fixtures/parity/f043/inputs/gxt-input.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f043/expected/r/trends.csv`,
    `tests/fixtures/parity/f043/expected/r/attgt.csv`,
    `tests/fixtures/parity/f043/expected/r/dynamic.csv`, and
    `tests/fixtures/parity/f043/expected/r/post-window.csv`;
  - Stata actual exports:
    `tests/fixtures/parity/f043/expected/new-stata/trends.csv`,
    `tests/fixtures/parity/f043/expected/new-stata/attgt.csv`,
    `tests/fixtures/parity/f043/expected/new-stata/dynamic.csv`, and
    `tests/fixtures/parity/f043/expected/new-stata/post-window.csv`;
  - manifest: `tests/fixtures/parity/f043/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f043.do`;
  - JEL harness: `tests/run-jel-smoke.sh`;
  - status: partial F043 evidence for the actual JEL staggered-adoption
    empirical sample. The verified slice reconstructs the GxT input from
    `JEL-DiD`, checks weighted timing-group trend data for Figure 5, and
    compares Stata `csdid` analytical ATT(g,t), dynamic aggregation, and
    post-window aggregation against R `did` 2.5.1 for weighted no-covariate and
    covariate-adjusted DR event-study designs with not-yet-treated controls and
    universal base periods. Raw ATT/SE vector comparisons use the recorded
    F043 numerical-tolerance exception for JEL-scale cross-runtime solver
    drift; dynamic/post-window summaries remain tightly aligned. Full Figure
    5-9 replication still requires 25,000-rep bootstrap confidence intervals,
    plotting wrappers, rendered artifact comparison, and performance hardening.
- JEL all-artifact inventory and artifact-audit fixture:
  - generator: `tools/parity/generators/f044/generate.R`;
  - artifact-audit generator: `tools/parity/generators/jel/generate.py`;
  - contract outputs:
    `tests/fixtures/parity/f044/expected/contract/jel-artifact-inventory.csv`
    and
    `tests/fixtures/parity/f044/expected/contract/full-reproduction-evidence.csv`;
  - JEL artifact rollup:
    `tests/fixtures/jel/expected/contract/jel-artifact-rollup.csv`;
  - manifest: `tests/fixtures/parity/f044/metadata/manifest.json`;
  - per-artifact manifests:
    `tests/fixtures/jel/jel001/metadata/manifest.json` through
    `tests/fixtures/jel/jel018/metadata/manifest.json`;
  - Stata audits:
    `tests/stata/test-f044.do` and
    `tests/stata/jel/test-artifact-contract.do`;
  - report: `reports/jel-replication-summary.md`;
  - full reproduction report: `reports/jel-full-reproduction-result.md`;
  - status: F044 and JEL001-JEL018 are mapped and smoke-verified for
    conformance profile v1. The audit confirms JEL001-JEL018 scripts, tables,
    and figures are mapped, present in the local reference checkout, hashed,
    and linked to per-artifact full-reproduction evidence. The latest opt-in
    full R/Stata master gate completes with both masters exiting 0, failure
    markers 0, `status=pass`, `oracle_parity_status=pass`, zero Figure 3/8/9
    label-audit failures, and zero Table 7 display-audit failures. Historical
    R artifact drift under the R `did` 2.5.1 oracle repin is recorded
    separately for release-owner evidence disposition.
- Legacy default-divergence fixture:
  - generator: `tools/parity/generators/f045/generate.R`;
  - inputs:
    `tests/fixtures/parity/f045/inputs/balanced.csv` and
    `tests/fixtures/parity/f045/inputs/unbalanced.csv`;
  - expected Stata contracts:
    `tests/fixtures/parity/f045/expected/new-stata/defaults.csv`,
    `tests/fixtures/parity/f045/expected/new-stata/defaults.json`,
    `tests/fixtures/parity/f045/expected/new-stata/events.csv`, and
    `tests/fixtures/parity/f045/expected/new-stata/events.json`;
  - manifest: `tests/fixtures/parity/f045/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f045.do`;
  - status: F045 `unsupported-by-design` evidence for legacy defaults that
    must not silently govern v1 behavior. The verified slice confirms balanced
    estimator/sample defaults match explicit R-compatible defaults, unbalanced
    `ivar()` defaults to the D003 `allowunbalanced` path, omitted `ivar()`
    defaults to repeated cross sections, `asinr` is an opt-in no-op warning,
    `method(dripw)` and `method(stdipw)` are opt-in canonical aliases,
    soft-deprecated `bal()`/`balance()` aliases warn without changing
    R-compatible unbalanced-panel routing, `long`/`long2` warn and select
    `baseperiod(universal)` when omitted, and `dryrun` returns an explicit
    unsupported-by-design error.
- Legacy deprecation-warning fixture:
  - generator: `tools/parity/generators/f046/generate.R`;
  - input: `tests/fixtures/parity/f046/inputs/input.csv`;
  - expected Stata warning contract:
    `tests/fixtures/parity/f046/expected/new-stata/events.csv` and
    `tests/fixtures/parity/f046/expected/new-stata/events.json`;
  - migration contract:
    `docs/legacy-migration-guide.md`,
    `tests/fixtures/parity/f046/expected/new-stata/migration-checklist.csv`,
    and
    `tests/fixtures/parity/f046/expected/new-stata/migration-checklist.json`;
  - manifest: `tests/fixtures/parity/f046/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f046.do`;
  - meta comparison: `tests/meta/test-legacy-migration-guide.sh`;
  - status: F046 `parity-verified`. The fixture freezes stable
    soft-deprecation warnings and canonical behavior for retained legacy
    aliases: `method(dripw)` maps to `dr`, `method(stdipw)` maps to `ipw`,
    `asinr` remains a no-op, and `wboot(wtype(rademacher))` /
    `wboot(wbtype(mammen))` record the requested legacy distribution while
    using the R-compatible rademacher multiplier path. The generated checklist
    links the migration guide to F045 old-default divergence evidence,
    F016/F017 unbalanced and unsupported-mode evidence, F035 bootstrap option
    evidence, and F040-F044/JEL release blockers.
- Seeded randomized differential fixture:
  - generator: `tools/parity/generators/f047/generate.R`;
  - inputs:
    `tests/fixtures/parity/f047/inputs/all-inputs.csv` plus five
    scenario-specific input CSVs;
  - R expected outputs:
    `tests/fixtures/parity/f047/expected/r/scenarios.csv`,
    `tests/fixtures/parity/f047/expected/r/attgt.csv`, and
    `tests/fixtures/parity/f047/expected/r/aggte.csv`;
  - exported Stata actuals:
    `tests/fixtures/parity/f047/expected/new-stata/attgt.csv` and
    `tests/fixtures/parity/f047/expected/new-stata/aggte.csv`;
  - manifest: `tests/fixtures/parity/f047/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f047.do`;
  - status: F047 `parity-verified` release smoke evidence for seeded
    small-panel randomized differential testing. The verified slice covers
    balanced panel, true repeated-cross-section, and unbalanced `ivar()` as
    R-compatible unbalanced-panel/RC paths across selected `dr`/`reg`/`ipw`,
    nevertreated/notyettreated, varying/universal base-period,
    covariate/no-covariate, and weighted/unweighted cells. ATT(g,t) and
    simple/dynamic aggregation match R `did` 2.5.1 under TOL002. This is not a
    replacement for F048 Monte Carlo sanity, F049 performance budgets, or F044
    all-JEL artifact replication.
- Monte Carlo sanity fixture:
  - generator: `tools/parity/generators/f048/generate.R`;
  - input: `tests/fixtures/parity/f048/inputs/sim-input.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f048/expected/r/per-rep.csv` and
    `tests/fixtures/parity/f048/expected/r/summary.csv`;
  - exported Stata actuals:
    `tests/fixtures/parity/f048/expected/new-stata/per-rep.csv` and
    `tests/fixtures/parity/f048/expected/new-stata/summary.csv`;
  - manifest: `tests/fixtures/parity/f048/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f048.do`;
  - status: F048 `parity-verified` release sanity evidence for a known
    two-period balanced-panel DGP with true ATT 1.0, one treated cohort,
    never-treated controls, `method(reg)`, analytical SEs, and 200 fixed
    simulations. Stata matches R `did` 2.5.1 per-rep ATT/SE under TOL002 and
    satisfies TOL008 with absolute mean bias about 0.0051 and empirical 95%
    coverage error 0.01. Broader stochastic inference coverage remains in
    F014/F035/RT007/RT017/PY002/PY004/PY005/PY015; performance budgets remain
    F049.
- Performance pathology fixture:
  - generator: `tools/parity/generators/f049/generate.R`;
  - inputs:
    `tests/fixtures/parity/f049/inputs/small-smoke.csv`,
    `tests/fixtures/parity/f049/inputs/medium-panel.csv`, and
    `tests/fixtures/parity/f049/inputs/aggregation-medium.csv`;
  - frozen budget contract:
    `tests/fixtures/parity/f049/expected/contract/budgets.csv`;
  - exported Stata benchmark results:
    `build/f049/results.csv` (ignored because wall-clock timings are
    environment-volatile);
  - manifest: `tests/fixtures/parity/f049/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f049.do`;
  - status: F049 `parity-verified` release performance evidence for the
    default frozen budgets and opt-in cache-backed storage candidates. The
    verified slice runs a 1,000-row small smoke benchmark; a 50,000-row
    balanced-panel default `fast(auto)` benchmark using the large-job
    `performance(auto)` storage resolver; 50,000-row `method(reg) fast lean`
    and explicit `performance(auto)` benchmarks; default 50,000-row
    option-surface budgets for covariate `method(dr)`, weighted `method(ipw)`,
    clustered `method(reg)`, and bootstrap-smoke `method(reg)`;
    a 48,886-row allow_unbalanced covariate/weighted
    `method(dr)` budget; all simple/group/calendar/dynamic aggregation
    postestimation budgets; and supported ATT(g,t), dynamic, group, and
    calendar `csdid_plot, saving()` plot-data export budgets. All default
    option-surface rows now require
    `e(fast_used)=1`, with `e(compute_path)` equal to `fast-balanced-panel`,
    `fast-repeated-cross-section`, or `fast-allow-unbalanced` as appropriate.
    The large rows verify cache-backed dynamic aggregation, absence of
    full `e(inffunc)`/`e(unit_group)`/large clustered `e(cluster_vec)`
    where `e(large_store)=0`, and a 5s absolute budget. The paired R-relative harness
    `tools/bench/run-f049-ratio.py` now times the same F049 scenarios in R and
    Stata and writes `build/f049/r-stata-ratio.csv`. The frozen R-relative
    budgets require <=1.8x R for non-bootstrap rows and for the literal
    omitted-option default bootstrap row, plus <=3x R for expanded seeded
    bootstrap/cband rows. The 2026-07-09 Stata 17 MP run records 0.036s for the
    50,000-row panel, 0.075s for covariate DR, 0.051s averaged for weighted IPW,
    0.049s for clustered REG, 0.134s for the literal default
    DR/bootstrap/cband command, 0.125s for seeded pointwise REG bootstrap,
    0.123s for seeded cband REG, 0.163s for covariate DR bootstrap, 0.142s for
    weighted IPW bootstrap, 0.072s for clustered REG bootstrap, 0.403s for
    unbalanced covariate/weighted DR bootstrap, and 0.316s for its analytical
    counterpart. The corresponding ratios are 0.17x, 1.12x, 1.21x, 0.89x,
    1.60x, 1.76x, 1.71x, 1.52x, 1.63x, 1.36x, 1.12x, and 1.34x R. Dynamic
    aggregation bootstrap is 1.84x R; non-bootstrap aggregation and plot-data
    rows remain well below their 1.8x budgets.
    `CSDID_RUN_OPTIN_PERF=1 tests/run-optin-performance.sh` now runs generated
    scale, paired R/Stata, and measured-RSS gates. The current scale run passes
    `large_panel` at 3.983s for 500,000 rows and `bootstrap_medium` at 0.341s
    for 25,000 rows and 999 seeded pointwise reps. Peak RSS is 380.094 MB for
    default cband, 230.516 MB for compiled balanced bootstrap, 233.859 MB for
    unbalanced weighted DR bootstrap, 166.969 MB for aggregation bootstrap,
    and 278.906 MB for `large_panel`. The
    passing result required replacing O(units x rows) row-index and
    cluster-alignment setup in `src/mata/csdid.mata` with sorted balanced-panel
    reshaping, vectorized sorted-layout detection, single-pass indexed setup,
    conditional balanced-panel
    outcome/weight/covariate blocks, cached row-to-unit and cluster mappings,
    vectorized balanced-panel cell extraction, compressed row-map
    allow_unbalanced extraction, Mata-native panel validation and time-varying-weight warning
    detection, cached covariate DR nuisance layouts and influence-adjustment
    directions, scalarized influence-function adjustment products,
    intercept-only weighted IPW special cases, cache-only large cluster-vector
    storage, compressed cluster-sum accumulation, vectorized IF assignment,
    skipped quiet display work, exact vectorized unseeded cband draws,
    one-sort bootstrap scales, and an optional compiled BMisc-compatible
    multiplier kernel with automatic fail-closed Mata fallback.
    `e(profile)`, `e(bootstrap_profile)`, and
    `e(agg_bootstrap_profile)` report phase seconds, calls, and work counts for
    performance audits.
- Engineering contract meta tests:
  - tests:
    `tests/meta/test-engineering-inventory.sh`,
    `tests/meta/test-engineering-architecture.sh`,
    `tests/meta/test-dependency-policy.sh`,
    `tests/meta/test-performance-plan.sh`, and
    `tests/meta/test-engineering-audit.sh`;
  - report: `reports/engineering-audit.md`;
  - status: ENG001-ENG004 are `parity-verified` contract/style gates for the
    frozen Mauricio Caceres Bravo and Sergio Correia engineering-reference
    inventory, ado/Mata architecture, dependency policy, and performance plan.
    ENG005 is `parity-verified` for conformance profile v1: the engineering
    audit is present and meta-tested, default benchmark budgets and isolated
    install evidence are recorded, and the full JEL reproduction gate now
    supplies the release-scale empirical evidence that was previously a
    residual risk.
- Python per-cell failure fixture:
  - generator: `tools/parity/generators/py018/generate.R`;
  - inputs:
    `tests/fixtures/parity/py018/inputs/zero-weight-failure.csv`,
    `tests/fixtures/parity/py018/inputs/normal.csv`,
    `tests/fixtures/parity/py018/inputs/tiny-group.csv`,
    `tests/fixtures/parity/py018/inputs/collinear-covariates.csv`,
    `tests/fixtures/parity/py018/inputs/overlap-failure.csv`,
    `tests/fixtures/parity/py018/inputs/singular-control.csv`, and
    `tests/fixtures/parity/py018/inputs/small-comparison-upstream.csv`;
  - R expected outputs:
    `tests/fixtures/parity/py018/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py018/expected/contract/upstream-test-map.json`,
    `tests/fixtures/parity/py018/expected/r/failure-pattern.csv`,
    `tests/fixtures/parity/py018/expected/r/events.csv`, and
    `tests/fixtures/parity/py018/expected/r/events.json`;
  - manifest: `tests/fixtures/parity/py018/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_percell_failure.do`;
  - status: PY018 `parity-verified`. The upstream-test map covers all four
    tests in DrSquare/csdid
    `csdid/test_csdid/test_percell_failure.py` at sha256
    `e15c0c8cde82b8d035fa285f344be7735b775e15d5b0b9fc4dd2159c5f05fe8e`.
    The Stata gate verifies collinear-covariate no-crash behavior,
    tiny-group no-crash and viable-group finite-cell behavior, failed-cell
    missingness expectations, and normal-data no-regression behavior. It also
    keeps stricter R-backed zero-weight, overlap, singular-control, and
    small-comparison-group cases with exact missing-pattern and warning-count
    checks plus TOL002 finite ATT/SE parity.
- Python R-parity inheritance fixture:
  - generator: `tools/parity/generators/py019/generate.py`;
  - inputs:
    `tests/fixtures/parity/py019/inputs/mpdta.csv`,
    `tests/fixtures/parity/py019/inputs/sim_data.csv`,
    `tests/fixtures/parity/py019/inputs/mpdta_tvw.csv`,
    `tests/fixtures/parity/py019/inputs/factor_cov.csv`, and
    `tests/fixtures/parity/py019/inputs/mpdta_extra.csv`;
  - R/Python reference outputs:
    `tests/fixtures/parity/py019/expected/r/ref_attgt.csv`,
    `tests/fixtures/parity/py019/expected/r/ref_aggte.csv`,
    `tests/fixtures/parity/py019/expected/r/ref_fixweights.csv`,
    `tests/fixtures/parity/py019/expected/r/sim/ref_factor.csv`, and
    `tests/fixtures/parity/py019/expected/r/sim/ref_gaps.csv`;
  - contract outputs:
    `tests/fixtures/parity/py019/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py019/expected/contract/upstream-test-map.json`,
    and `tests/fixtures/parity/py019/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/py019/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_r_parity.do`;
  - status: PY019 `parity-verified`. The gate maps all 36 public
    parameterizations in DrSquare/csdid
    `csdid/test_csdid/test_r_parity.py` at sha256
    `59eda1cbb9b794dc8bfdd3b15d3695ab2fa9d05e67174feee11e6b026f7f95bd`.
    Stata verifies ATT(g,t), simple/group/dynamic/calendar overall
    aggregation, group/dynamic/calendar event-level aggregation, time-varying
    `fix_weights` ATT(g,t), factor-covariate parity with standard and
    requested-fast optimized paths, and repeated-cross-section, universal-base,
    anticipation, weighted, and clustered gap scenarios against the frozen R
    reference CSVs under the source Python tolerances.
- Python review-fix inheritance fixture:
  - generator: `tools/parity/generators/py020/generate.py`;
  - inputs:
    `tests/fixtures/parity/py020/inputs/review-panel.csv`,
    `tests/fixtures/parity/py020/inputs/clustered-panel.csv`,
    `tests/fixtures/parity/py020/inputs/boolean-outcome.csv`,
    `tests/fixtures/parity/py020/inputs/uniform-missing-periods.csv`,
    `tests/fixtures/parity/py020/inputs/no-never.csv`,
    `tests/fixtures/parity/py020/inputs/late-cohort.csv`,
    `tests/fixtures/parity/py020/inputs/first-period-treated.csv`,
    `tests/fixtures/parity/py020/inputs/universal-base.csv`,
    `tests/fixtures/parity/py020/inputs/universal-stochastic.csv`, and
    `tests/fixtures/parity/py020/inputs/id-validation.csv`;
  - contract outputs:
    `tests/fixtures/parity/py020/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py020/expected/contract/upstream-test-map.json`,
    `tests/fixtures/parity/py020/expected/contract/scenarios.csv`,
    `tests/fixtures/parity/py020/expected/contract/approved-divergence.csv`,
    and
    `tests/fixtures/parity/py020/expected/contract/approved-divergence.json`;
  - manifest: `tests/fixtures/parity/py020/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_review_fixes.do`;
  - status: PY020 `approved-divergence`. The gate maps all 31 tests and
    parameterizations from DrSquare/csdid
    `csdid/test_csdid/test_review_fixes.py` at sha256
    `e0206e8d37d5577d9616449dda9d1d0e74ffce4adb0f608cf36aa9f02b816711`.
    Stata verifies the 20 public command-surface behaviors: factor covariates
    are not silently dropped, requested-fast results match standard results
    for factor-covariate panel and repeated-cross-section paths, mixed
    factor/numeric covariates run, clustered bootstrap and analytical SEs are
    finite and reasonable, anticipation and no-never-treated coercion work,
    numeric 0/1 outcomes are accepted, missing covariates fail clearly,
    balanced/unbalanced panel routing follows the frozen contract, universal
    base-period missing-SE behavior is preserved, and numeric/string id
    validation matches the public Stata surface. Eleven Python helper,
    object-model, logical-dtype, non-Stata-option, or R-incompatible
    deterministic zero-IF tests are recorded in `PY020-DIV001` through
    `PY020-DIV005`.
- Python simulation parity fixture:
  - generator: `tools/parity/generators/py021/generate.py`;
  - inputs:
    `tests/fixtures/parity/py021/inputs/tp2_const.csv`,
    `tests/fixtures/parity/py021/inputs/tp4_const.csv`,
    `tests/fixtures/parity/py021/inputs/tp4_dyn.csv`,
    `tests/fixtures/parity/py021/inputs/tp5_dyn.csv`,
    `tests/fixtures/parity/py021/inputs/tp8_dyn.csv`, and
    `tests/fixtures/parity/py021/inputs/tp10_const.csv`;
  - R/Python expected output: `tests/fixtures/parity/py021/expected/r/ref_sim.csv`;
  - contract outputs:
    `tests/fixtures/parity/py021/expected/contract/scenarios.csv`,
    `tests/fixtures/parity/py021/expected/contract/upstream-test-map.csv`,
    and
    `tests/fixtures/parity/py021/expected/contract/upstream-test-map.json`;
  - manifest: `tests/fixtures/parity/py021/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_sim_parity.do`;
  - status: PY021 `parity-verified`. The gate maps all 24
    parameterizations from DrSquare/csdid
    `csdid/test_csdid/test_sim_parity.py`, covering ATT(g,t) and analytical
    SE parity against frozen R simulation references across six simulated
    datasets, nevertreated/notyettreated controls, and `dr`/`reg`
    estimators under the source Python tolerances.
- True repeated-cross-section fixture:
  - generator: `tools/parity/generators/f018/generate.R`;
  - input: `tests/fixtures/parity/f018/inputs/input.csv`;
  - R expected output: `tests/fixtures/parity/f018/expected/r/attgt.csv`;
  - manifest: `tests/fixtures/parity/f018/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f018.do`;
  - status: F018 `parity-verified`.
- Sample-construction parity fixture:
  - generator: `tools/parity/generators/f019/generate.R`;
  - input: `tests/fixtures/parity/f019/inputs/input.csv`;
  - R expected outputs: `tests/fixtures/parity/f019/expected/r/sample-mask.csv`
    and `tests/fixtures/parity/f019/expected/r/attgt.csv`;
  - manifest: `tests/fixtures/parity/f019/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f019.do`;
  - status: F019 `parity-verified`.
- No-never-treated cohort fixture:
  - generator: `tools/parity/generators/f020/generate.R`;
  - input: `tests/fixtures/parity/f020/inputs/input.csv`;
  - R expected outputs: `tests/fixtures/parity/f020/expected/r/sample-mask.csv`
    and `tests/fixtures/parity/f020/expected/r/control-grid.csv`;
  - manifest: `tests/fixtures/parity/f020/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f020.do`;
  - status: F020 `parity-verified`.
- R `test-always-treated-invariance.R` inheritance fixture:
  - generator: `tools/parity/generators/rt004/generate.R`;
  - inputs:
    `tests/fixtures/parity/rt004/inputs/p1.csv`,
    `tests/fixtures/parity/rt004/inputs/p2.csv`,
    `tests/fixtures/parity/rt004/inputs/p3.csv`,
    `tests/fixtures/parity/rt004/inputs/fastslow.csv`, and
    `tests/fixtures/parity/rt004/inputs/structural.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt004/expected/contract/upstream-test-map.csv`
    and `tests/fixtures/parity/rt004/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/rt004/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-always-treated-invariance.do`;
  - status: RT004 `parity-verified`. The gate maps all seven upstream
    R blocks, covering common-cell ATT(g,t) missingness and finite-value
    invariance after dropping literal and anticipation-induced always-treated
    cohorts, invariance to rescaling always-treated outcomes, fast/baseline
    agreement in the no-never plus always-treated regime, latest-cohort
    retention as controls but not estimated ATT groups, and default
    nevertreated fallback invariance.
- R core `test-att_gt.R` inheritance fixture:
  - generator: `tools/parity/generators/rt005/generate.R`;
  - inputs: RT005 copies the public ATT(g,t) DGP inputs used by the broad
    att_gt gate under `tests/fixtures/parity/rt005/inputs/`;
  - contract outputs:
    `tests/fixtures/parity/rt005/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/rt005/expected/contract/approved-divergence.csv`,
    and `tests/fixtures/parity/rt005/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/rt005/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-att_gt.do`;
  - status: RT005 `approved-divergence`. The gate maps 44 public blocks from
    R `tests/testthat/test-att_gt.R` through the public Stata att_gt command
    suite: `dr`/`reg`/`ipw` estimation, aggregation, allow_unbalanced routing,
    not-yet-treated controls, anticipation, base periods, sampling weights,
    `fix_weights`, influence-function consistency, clustered SEs,
    fast/baseline equality, validation, and reserved column names.
    `RT005-DIV001` and `RT005-DIV002` record R function-valued custom
    estimator callback cases that have no public Stata command analogue.
- R `test-edge-cases.R` inheritance fixture:
  - generator: `tools/parity/generators/rt010/generate.R`;
  - inputs:
    `tests/fixtures/parity/rt010/inputs/single_treated.csv`,
    `tests/fixtures/parity/rt010/inputs/two_period.csv`,
    `tests/fixtures/parity/rt010/inputs/no_never.csv`,
    `tests/fixtures/parity/rt010/inputs/first_period.csv`,
    `tests/fixtures/parity/rt010/inputs/nonconsecutive_time.csv`,
    `tests/fixtures/parity/rt010/inputs/nonconsecutive_group.csv`,
    `tests/fixtures/parity/rt010/inputs/balanced_allow.csv`,
    `tests/fixtures/parity/rt010/inputs/unbalanced_allow.csv`, and
    `tests/fixtures/parity/rt010/inputs/single_post.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt010/expected/contract/upstream-test-map.csv`
    and `tests/fixtures/parity/rt010/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/rt010/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-edge-cases.do`;
  - status: RT010 `parity-verified`. The gate maps all eleven upstream
    R blocks, covering finite ATT(g,t) in single-treated, two-period
    universal-base, nonconsecutive-time, balanced, allow_unbalanced, and
    single-post-treatment designs; nonmissing simple/dynamic/group/calendar
    aggregation for the single-treated design; no-never not-yet success and
    default nevertreated fallback warning; first-period-treated warning/drop
    behavior; and nonconsecutive treatment-group values.
- Python `test_edge_cases.py` inheritance fixture:
  - generator: `tools/parity/generators/py007/generate.py`;
  - inputs:
    `tests/fixtures/parity/py007/inputs/single_group.csv`,
    `tests/fixtures/parity/py007/inputs/no_never.csv`,
    `tests/fixtures/parity/py007/inputs/two_period.csv`,
    `tests/fixtures/parity/py007/inputs/nonconsecutive_time.csv`,
    `tests/fixtures/parity/py007/inputs/nonconsecutive_group.csv`,
    `tests/fixtures/parity/py007/inputs/single_post.csv`,
    `tests/fixtures/parity/py007/inputs/sim_data.csv`,
    `tests/fixtures/parity/py007/inputs/first_period.csv`, and
    `tests/fixtures/parity/py007/inputs/unbalanced.csv`;
  - contract outputs:
    `tests/fixtures/parity/py007/expected/contract/upstream-test-map.csv`
    and `tests/fixtures/parity/py007/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/py007/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_edge_cases.do`;
  - status: PY007 `parity-verified`. The gate maps all 27 Python
    parameterizations, covering `dr`/`reg`/`ipw` finite ATT(g,t) checks for
    single-treated, two-period universal-base, nonconsecutive-time,
    nonconsecutive-group, single-post-treatment, and repeated-cross-section
    unbalanced designs; all four aggregation types; no-never warning/coercion;
    first-period-treated dropping; balanced-panel default; and unbalanced-ivar
    repeated-cross-section behavior.
- Python `test_notyettreated.py` inheritance fixture:
  - generator: `tools/parity/generators/py016/generate.py`;
  - input: `tests/fixtures/parity/py016/inputs/notyettreated.csv`;
  - contract outputs:
    `tests/fixtures/parity/py016/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py016/expected/contract/upstream-test-map.json`,
    and `tests/fixtures/parity/py016/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/py016/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_notyettreated.do`;
  - status: PY016 `parity-verified`. The gate maps all six tests in
    DrSquare/csdid `csdid/test_csdid/test_notyettreated.py`, covering
    not-yet-treated estimation with no never-treated group, latest-cohort
    retention in `e(unit_group)`, latest-cohort exclusion from `e(group_prob)`,
    finite ATT estimates, nevertreated fallback warning/coercion, and positive
    average post-treatment ATT.
- Python `test_integration.py` inheritance fixture:
  - generator: `tools/parity/generators/py013/generate.py`;
  - input: `tests/fixtures/parity/py013/inputs/panel-data.csv`;
  - contract outputs:
    `tests/fixtures/parity/py013/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py013/expected/contract/upstream-test-map.json`,
    `tests/fixtures/parity/py013/expected/contract/approved-divergence.csv`,
    `tests/fixtures/parity/py013/expected/contract/approved-divergence.json`,
    and `tests/fixtures/parity/py013/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/py013/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_integration.do`;
  - status: PY013 `approved-divergence`. The gate maps four public
    command-surface tests in DrSquare/csdid
    `csdid/test_csdid/test_integration.py`, covering the full public
    pipeline, finite ATT(g,t), positive standard errors, populated
    simple/group/dynamic/calendar aggregations, positive simple overall ATT,
    `dr`/`ipw`/`reg` methods, and not-yet-treated controls. The single
    approved divergence, PY013-DIV001, records that the Python
    `compute_inffunc=False` internal construction-path equality test has no
    public Stata command analogue; public fast/requested-fast equivalence
    remains covered by F032 and PY009.
- First-period-treated timing fixture:
  - generator: `tools/parity/generators/f021/generate.R`;
  - input: `tests/fixtures/parity/f021/inputs/input.csv`;
  - R expected outputs: `tests/fixtures/parity/f021/expected/r/sample-mask.csv`
    and `tests/fixtures/parity/f021/expected/r/attgt.csv`;
  - manifest: `tests/fixtures/parity/f021/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f021.do`;
  - status: F021 `parity-verified`.
- Treatment-timing encoding fixture:
  - generator: `tools/parity/generators/f022/generate.R`;
  - inputs:
    `tests/fixtures/parity/f022/inputs/input.csv` and
    `tests/fixtures/parity/f022/inputs/negative-g.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f022/expected/r/sample-mask.csv`,
    `tests/fixtures/parity/f022/expected/r/attgt.csv`,
    `tests/fixtures/parity/f022/expected/r/events.csv`, and
    `tests/fixtures/parity/f022/expected/r/events.json`;
  - manifest: `tests/fixtures/parity/f022/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f022.do`;
  - status: F022 `parity-verified` for future-treated cohorts recoded to
    never-treated when `g > max(time) + anticipation`, ATT/SE parity for that
    recoding, and explicit negative-`gvar()` rejection with an R 2.5.1
    audit-compatible diagnostic.
- Irregular-time-gap fixture:
  - generator: `tools/parity/generators/f023/generate.R`;
  - input: `tests/fixtures/parity/f023/inputs/input.csv`;
  - R expected output: `tests/fixtures/parity/f023/expected/r/attgt.csv`;
  - manifest: `tests/fixtures/parity/f023/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f023.do`;
  - status: F023 `parity-verified`.
- Data-type and name fixture:
  - generator: `tools/parity/generators/f030/generate.R`;
  - inputs:
    `tests/fixtures/parity/f030/inputs/input.csv`,
    `tests/fixtures/parity/f030/inputs/internal-names.csv`,
    `tests/fixtures/parity/f030/inputs/group-time-names.csv`, and
    `tests/fixtures/parity/f030/inputs/output-names.csv`;
  - R expected outputs:
    `tests/fixtures/parity/f030/expected/r/attgt.csv`,
    `tests/fixtures/parity/f030/expected/r/name-collision-attgt.csv`,
    `tests/fixtures/parity/f030/expected/r/events.csv`, and
    `tests/fixtures/parity/f030/expected/r/events.json`;
  - manifest: `tests/fixtures/parity/f030/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f030.do`;
  - status: parity-verified core data-type and name coverage for numeric
    `ivar()`, `time()`, and `gvar()` storage classes, non-default variable names, numeric controls,
    stored-name preservation, R-backed name-collision parity for user variables
    named `idname`/`tname`/`gname` with a harmless `t1` column, R-backed
    name-collision parity for user variables named `group`/`time`/`unit` across
    `dr`/`reg`/`ipw`, and output-name covariates named `att`/`se`/`event_time`/
    `overall_att` across `dr`/`reg`/`ipw` with R-matched finite and missing
    cells. Explicit string outcome, covariate, `ivar()`, `time()`, `gvar()`,
    and `cluster()` rejection also pass. Broader inherited name-normalization
    stress remains tracked by RT/PY rows.
- Optimized-path equivalence fixture:
  - generator: `tools/parity/generators/f032/generate.R`;
  - inputs: `tests/fixtures/parity/f032/inputs/input.csv` and
    `tests/fixtures/parity/f032/inputs/input-shuffled.csv`, plus
    `tests/fixtures/parity/f032/inputs/input-unbalanced.csv` for
    fast-allow-unbalanced coverage;
  - R expected outputs:
    `tests/fixtures/parity/f032/expected/r/attgt.csv`,
    `tests/fixtures/parity/f032/expected/r/aggte.csv`, and
    `tests/fixtures/parity/f032/expected/r/fast-option-grid.csv`;
  - manifest: `tests/fixtures/parity/f032/metadata/manifest.json`;
  - Stata comparison: `tests/stata/test-f032.do` and
    `tests/stata/test-f032-fast-auto-surface.do`;
  - status: F032 `parity-verified` evidence for all-surface fast/nofast
    equivalence. Default `fast(auto)` and explicit `fast` now report
    `e(fast_used)=1` across `dr`/`reg`/`ipw`, covariates, weights,
    `fix_weights()`, repeated cross sections, allow_unbalanced routing,
    clustered analytical inference, bootstrap smoke cases,
    and aggregation; explicit `nofast` is the baseline/debug path. ATT(g,t),
    analytical SEs, clustered analytical SEs, influence-function summaries,
    Gram matrix, and simple/group/calendar/dynamic aggregations match the
    nofast path and R fixtures on sorted and shuffled row orders. PY009 covers
    the inherited Python covariate fast grid, RT025 covers repeated-
    cross-section and unbalanced precompute public invariants, and RT027 now
    maps inherited unbalanced clustered fast-mode stress after retiring the
    previous unbalanced fast-request divergence. RT012 still records the R-only
    custom-estimator IF callback case as an approved divergence.
- R `test-slowpath-precompute.R` inheritance fixture:
  - generator: `tools/parity/generators/rt025/generate.R`;
  - inputs:
    `tests/fixtures/parity/rt025/inputs/input.csv`,
    `tests/fixtures/parity/rt025/inputs/input-shuffled.csv`, and
    `tests/fixtures/parity/rt025/inputs/input-unbalanced.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt025/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/rt025/expected/contract/approved-divergence.csv`,
    and `tests/fixtures/parity/rt025/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/rt025/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-slowpath-precompute.do`;
  - status: RT025 `approved-divergence`. Stata maps the two public
    invariants in R `tests/testthat/test-slowpath-precompute.R`: requested-fast
    optimized equality for repeated-cross-section and unbalanced inputs, and
    input-row-order invariance. RT025-DIV001 records six R-only
    `did.disable_precompute`/`get_wide_data` legacy-path comparisons, which
    have no public Stata command analogue.
- R `test-faster-mode-consistency.R` inheritance fixture:
  - generator: `tools/parity/generators/rt012/generate.R`;
  - inputs:
    `tests/fixtures/parity/rt012/inputs/input.csv` and
    `tests/fixtures/parity/rt012/inputs/input-unbalanced.csv`;
  - contract outputs:
    `tests/fixtures/parity/rt012/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/rt012/expected/contract/approved-divergence.csv`,
    and `tests/fixtures/parity/rt012/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/rt012/metadata/manifest.json`;
  - Stata comparison: `tests/stata/r/test-faster-mode-consistency.do`;
  - status: RT012 `approved-divergence`. Stata maps all 40 upstream
    R `tests/testthat/test-faster-mode-consistency.R` blocks: 39 public
    faster-mode consistency checks map to requested-fast optimized equality,
    no-covariate `method(reg)` fast-path equality, anticipation coverage,
    and simple/dynamic/group/calendar aggregation equality. RT012-DIV001
    records the one R-only custom-estimator partial-NA influence-function
    callback test, which has no public Stata command analogue.
- Python `test_faster_mode_consistency.py` inheritance fixture:
  - generator: `tools/parity/generators/py009/generate.py`;
  - input: `tests/fixtures/parity/py009/inputs/sim-fast.csv`;
  - contract outputs:
    `tests/fixtures/parity/py009/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py009/expected/contract/upstream-test-map.json`,
    and `tests/fixtures/parity/py009/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/py009/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_faster_mode_consistency.do`;
  - status: PY009 `parity-verified`. The gate maps all 24 parameterizations
    in DrSquare/csdid `csdid/test_csdid/test_faster_mode_consistency.py`.
    Because the Python source uses covariates, Stata verifies requested-fast
    optimized equality (`fast_requested=1`, `fast_used=1`) against explicit
    `nofast` across panel/repeated-cross-section,
    nevertreated/notyettreated, `dr`/`reg`/`ipw`, and varying/universal base
    periods.
- Python `test_compute_inffunc.py` inheritance fixture:
  - generator: `tools/parity/generators/py006/generate.py`;
  - input: `tests/fixtures/parity/py006/inputs/sample-data.csv`;
  - contract outputs:
    `tests/fixtures/parity/py006/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py006/expected/contract/upstream-test-map.json`,
    `tests/fixtures/parity/py006/expected/contract/approved-divergence.csv`,
    and `tests/fixtures/parity/py006/expected/contract/approved-divergence.json`;
  - manifest: `tests/fixtures/parity/py006/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_compute_inffunc.do`;
  - status: PY006 `approved-divergence`. The gate maps the Python
    `test_default_is_true` assertion to Stata's public IF-backed command
    contract by verifying `e(inffunc)`, finite ATT(g,t) standard errors, and
    public aggregation postestimation. The approved divergence,
    PY006-DIV001, covers Python's internal `compute_inffunc=False`
    point-estimates-only path, where SEs/IFs are intentionally absent and
    aggregation is blocked. Stata has no public command option for a no-IF
    object because the port keeps influence functions available for SEs,
    saved RIF artifacts, and `csdid_stats`/`csdid_estat`.
- Python `test_inference.py` inheritance fixture:
  - generator: `tools/parity/generators/py012/generate.py`;
  - input: `tests/fixtures/parity/py012/inputs/inference-data.csv`;
  - contract outputs:
    `tests/fixtures/parity/py012/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py012/expected/contract/upstream-test-map.json`,
    and `tests/fixtures/parity/py012/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/py012/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_inference.do`;
  - status: PY012 `parity-verified`. The gate maps all 43 parameterized
    assertions in DrSquare/csdid `csdid/test_csdid/test_inference.py`,
    covering balanced-panel and repeated-cross-section finite ATT(g,t) SEs,
    influence-function dimensions, simple aggregation SEs, dynamic/group/
    calendar event-level aggregation SEs, unclustered bootstrap-vs-analytical
    broad SE agreement, bootstrap/analytical ATT equality, overall ATT near
    the true effect, and DR/REG cross-method ATT agreement.
- Python `test_mboot_cluster.py` inheritance fixture:
  - generator: `tools/parity/generators/py015/generate.py`;
  - inputs:
    `tests/fixtures/parity/py015/inputs/clustered-unbalanced.csv`,
    `tests/fixtures/parity/py015/inputs/clustered-balanced.csv`, and
    `tests/fixtures/parity/py015/inputs/clustered-invalid.csv`;
  - contract outputs:
    `tests/fixtures/parity/py015/expected/contract/upstream-test-map.csv`,
    `tests/fixtures/parity/py015/expected/contract/upstream-test-map.json`,
    and `tests/fixtures/parity/py015/expected/contract/scenarios.csv`;
  - manifest: `tests/fixtures/parity/py015/metadata/manifest.json`;
  - Stata comparison: `tests/stata/python/test_mboot_cluster.do`;
  - status: PY015 `parity-verified`. The gate maps all three assertions in
    DrSquare/csdid `csdid/test_csdid/test_mboot_cluster.py`, covering
    clustered multiplier-bootstrap finite positive SEs for unbalanced and
    balanced cluster designs plus explicit rejection of multiple/list-valued
    bootstrap cluster declarations through the public `wboot(cluster())`
    option. The exact seeded BMisc/R rademacher stream probe is guarded by
    F035; PY015 remains an inherited Python cluster-bootstrap smoke fixture
    rather than a raw-draw export fixture.

## Verified Locally

- 2026-06-23 PY001 targeted rerun:
  - `python3 tools/parity/generators/py001/generate.py`;
  - `stata-mp -b do tests/stata/python/test_aggte_comprehensive.do`;
  - strict `test_aggte_comprehensive.log` scan found no real Stata failures.
- 2026-06-23 PY003 targeted rerun:
  - `python3 tools/parity/generators/py003/generate.py`;
  - `stata-mp -b do tests/stata/python/test_att_gt.do`;
  - strict `test_att_gt.log` scan found no real Stata failures;
  - `python3 tools/validate-contract.py` returned `contract validation ok`;
  - all `tests/meta/*.sh` checks passed;
  - matrix status counts after PY003 promotion:
    `parity-verified: 64`, `approved-divergence: 28`,
    `contract-frozen: 33`, `unsupported-by-design: 2`.
- 2026-06-23 RT002 targeted rerun:
  - `Rscript tools/parity/generators/rt002/generate.R`;
  - `stata-mp -b do tests/stata/r/test-aggte-comprehensive.do`;
  - strict `test-aggte-comprehensive.log` scan found no real Stata failures;
  - `python3 tools/validate-contract.py` returned `contract validation ok`;
  - all `tests/meta/*.sh` checks passed;
  - matrix status counts after RT002 promotion:
    `parity-verified: 64`, `approved-divergence: 29`,
    `contract-frozen: 32`, `unsupported-by-design: 2`.
- 2026-06-23 RT001 targeted rerun:
  - `Rscript tools/parity/generators/rt001/generate.R`;
  - `stata-mp -b do tests/stata/r/test-aggte-clustervars-override.do`;
  - strict `test-aggte-clustervars-override.log` scan found no real Stata failures;
  - `python3 tools/validate-contract.py` returned `contract validation ok`;
  - all `tests/meta/*.sh` checks passed;
  - matrix status counts after RT001 promotion:
    `parity-verified: 64`, `approved-divergence: 30`,
    `contract-frozen: 31`, `unsupported-by-design: 2`.
- 2026-06-23 RT015 targeted rerun:
  - `Rscript tools/parity/generators/rt015/generate.R`;
  - `stata-mp -b do tests/stata/r/test-inference.do`;
  - strict `test-inference.log` scan found no real Stata failures;
  - `python3 tools/validate-contract.py` returned `contract validation ok`;
  - all `tests/meta/*.sh` checks passed;
  - matrix status counts after RT015 promotion:
    `parity-verified: 64`, `approved-divergence: 31`,
    `contract-frozen: 30`, `unsupported-by-design: 2`.
- 2026-06-23 RT029/RT030 targeted rerun:
  - `Rscript tools/parity/generators/rt029/generate.R`;
  - `stata-mp -b do tests/stata/r/att_gt_point_estimate_tests.do`;
  - `Rscript tools/parity/generators/rt030/generate.R`;
  - `stata-mp -b do tests/stata/r/att_gt_point_estimate_tests_rmd.do`;
  - strict scans of `att_gt_point_estimate_tests.log` and
    `att_gt_point_estimate_tests_rmd.log` found no real Stata failures;
  - `python3 tools/validate-contract.py` returned `contract validation ok`;
  - all `tests/meta/*.sh` checks passed;
  - matrix status counts after RT029/RT030 promotion:
    `parity-verified: 64`, `approved-divergence: 33`,
    `contract-frozen: 28`, `unsupported-by-design: 2`.
- 2026-06-23 RT019 targeted rerun:
  - `Rscript tools/parity/generators/rt019/generate.R`;
  - `stata-mp -b do tests/stata/r/test-modelmatrix-hoist.do`;
  - strict `test-modelmatrix-hoist.log` scan found no real Stata failures;
  - `python3 tools/validate-contract.py` returned `contract validation ok`;
  - all `tests/meta/*.sh` checks passed;
  - matrix status counts after RT019 promotion:
    `parity-verified: 64`, `approved-divergence: 34`,
    `contract-frozen: 27`, `unsupported-by-design: 2`.
- 2026-06-23 RT005 targeted rerun:
  - `Rscript tools/parity/generators/rt005/generate.R`;
  - `stata-mp -b do tests/stata/r/test-att_gt.do`;
  - strict `test-att_gt.log` scan found no real Stata failures;
  - `python3 tools/validate-contract.py` returned `contract validation ok`;
  - all `tests/meta/*.sh` checks passed;
  - matrix status counts after RT005 promotion:
    `parity-verified: 64`, `approved-divergence: 35`,
    `contract-frozen: 26`, `unsupported-by-design: 2`.
- 2026-06-23 F033-F038 targeted rerun:
  - `Rscript tools/parity/generators/f033/generate.R`;
  - `stata-mp -b do tests/stata/test-f033.do`;
  - `Rscript tools/parity/generators/f034/generate.R`;
  - `stata-mp -b do tests/stata/test-f034.do`;
  - `Rscript tools/parity/generators/f035/generate.R`;
  - `stata-mp -b do tests/stata/test-f035.do`;
  - `Rscript tools/parity/generators/f036/generate.R`;
  - `stata-mp -b do tests/stata/test-f036.do`;
  - `Rscript tools/parity/generators/f037/generate.R`;
  - `stata-mp -b do tests/stata/test-f037.do`;
  - `Rscript tools/parity/generators/f038/generate.R`;
  - `stata-mp -b do tests/stata/test-f038.do`;
  - strict scans of `test-f033.log` through `test-f038.log` found no real
    Stata failures;
  - `python3 tools/validate-contract.py` returned `contract validation ok`;
  - all `tests/meta/*.sh` checks passed;
  - matrix status counts after F033-F038 promotion:
    `parity-verified: 64`, `approved-divergence: 41`,
    `contract-frozen: 20`, `unsupported-by-design: 2`.
- 2026-06-23 PY019 targeted rerun:
  - `python3 tools/parity/generators/py019/generate.py`;
  - `stata-mp -b do tests/stata/python/test_r_parity.do`;
  - strict `test_r_parity.log` scan found no real Stata failures;
  - `python3 tools/validate-contract.py` returned `contract validation ok`;
  - all `tests/meta/*.sh` checks passed;
  - matrix status counts after PY019 promotion:
    `parity-verified: 63`, `approved-divergence: 27`,
    `contract-frozen: 35`, `unsupported-by-design: 2`.
- 2026-06-23 full smoke rerun:
  - `date '+smoke start %Y-%m-%d %H:%M:%S %Z' && bash tests/run-smoke.sh`
    started at `2026-06-23 12:20:05 EDT` and exited 0;
  - strict post-smoke Stata log scan found no `r(...)`, failed assertion,
    merge mismatch, syntax/type/conformability, unrecognized-command,
    disallowed-option, or `--Break--` failures;
  - `python3 tools/validate-contract.py` returned `contract validation ok`;
  - all `tests/meta/*.sh` checks passed;
  - matrix status counts after PY017/PY020 promotion:
    `parity-verified: 62`, `approved-divergence: 27`,
    `contract-frozen: 36`, `unsupported-by-design: 2`.
- `tests/run-smoke.sh` with strict Stata log scanning
- `python3 tools/validate-contract.py`
- `stata-mp -b do tests/stata/smoke-basic.do`
- `stata-mp -b do tests/stata/install-isolated.do`
- `Rscript tools/parity/generators/f001/generate.R`
- `stata-mp -b do tests/stata/test-f001.do`
- `Rscript tools/parity/generators/f002/generate.R`
- `stata-mp -b do tests/stata/test-f002.do`
- `Rscript tools/parity/generators/f003/generate.R`
- `stata-mp -b do tests/stata/test-f003.do`
- `Rscript tools/parity/generators/f004/generate.R`
- `stata-mp -b do tests/stata/test-f004.do`
- `Rscript tools/parity/generators/f005/generate.R`
- `stata-mp -b do tests/stata/test-f005.do`
- `Rscript tools/parity/generators/f006/generate.R`
- `stata-mp -b do tests/stata/test-f006.do`
- `Rscript tools/parity/generators/f025/generate.R`
- `stata-mp -b do tests/stata/test-f025.do`
- `Rscript tools/parity/generators/rt001/generate.R`
- `stata-mp -b do tests/stata/r/test-aggte-clustervars-override.do`
- `Rscript tools/parity/generators/rt002/generate.R`
- `stata-mp -b do tests/stata/r/test-aggte-comprehensive.do`
- `Rscript tools/parity/generators/f026/generate.R`
- `stata-mp -b do tests/stata/test-f026.do`
- `Rscript tools/parity/generators/f027/generate.R`
- `stata-mp -b do tests/stata/test-f027.do`
- `Rscript tools/parity/generators/f028/generate.R`
- `stata-mp -b do tests/stata/test-f028.do`
- `Rscript tools/parity/generators/f029/generate.R`
- `stata-mp -b do tests/stata/test-f029.do`
- `Rscript tools/parity/generators/f030/generate.R`
- `stata-mp -b do tests/stata/test-f030.do`
- `Rscript tools/parity/generators/f031/generate.R`
- `stata-mp -b do tests/stata/test-f031.do`
- `Rscript tools/parity/generators/f032/generate.R`
- `stata-mp -b do tests/stata/test-f032.do`
- `Rscript tools/parity/generators/f033/generate.R`
- `stata-mp -b do tests/stata/test-f033.do`
- `Rscript tools/parity/generators/f034/generate.R`
- `stata-mp -b do tests/stata/test-f034.do`
- `Rscript tools/parity/generators/f035/generate.R`
- `stata-mp -b do tests/stata/test-f035.do`
- `Rscript tools/parity/generators/f036/generate.R`
- `stata-mp -b do tests/stata/test-f036.do`
- `Rscript tools/parity/generators/f037/generate.R`
- `stata-mp -b do tests/stata/test-f037.do`
- `Rscript tools/parity/generators/f038/generate.R`
- `stata-mp -b do tests/stata/test-f038.do`
- `Rscript tools/parity/generators/py018/generate.R`
- `stata-mp -b do tests/stata/python/test_percell_failure.do`
- `python3 tools/parity/generators/py019/generate.py`
- `stata-mp -b do tests/stata/python/test_r_parity.do`
- `python3 tools/parity/generators/py020/generate.py`
- `stata-mp -b do tests/stata/python/test_review_fixes.do`
- `python3 tools/parity/generators/py021/generate.py`
- `stata-mp -b do tests/stata/python/test_sim_parity.do`
- `python3 tools/parity/generators/py006/generate.py`
- `stata-mp -b do tests/stata/python/test_compute_inffunc.do`
- `python3 tools/parity/generators/py008/generate.py`
- `stata-mp -b do tests/stata/python/test_error_handling.do`
- `python3 tools/parity/generators/py009/generate.py`
- `stata-mp -b do tests/stata/python/test_faster_mode_consistency.do`
- `python3 tools/parity/generators/py012/generate.py`
- `stata-mp -b do tests/stata/python/test_inference.do`
- `python3 tools/parity/generators/py013/generate.py`
- `stata-mp -b do tests/stata/python/test_integration.do`
- `python3 tools/parity/generators/py016/generate.py`
- `stata-mp -b do tests/stata/python/test_notyettreated.do`
- `python3 tools/parity/generators/py017/generate.py`
- `stata-mp -b do tests/stata/python/test_parametric_combinations.do`
- `Rscript tools/parity/generators/f050/generate.R`
- `stata-mp -b do tests/stata/test-f050.do`
- `Rscript tools/parity/generators/f007/generate.R`
- `stata-mp -b do tests/stata/test-f007.do`
- `Rscript tools/parity/generators/f008/generate.R`
- `stata-mp -b do tests/stata/test-f008.do`
- `Rscript tools/parity/generators/f009/generate.R`
- `stata-mp -b do tests/stata/test-f009.do`
- `Rscript tools/parity/generators/f010/generate.R`
- `stata-mp -b do tests/stata/test-f010.do`
- `Rscript tools/parity/generators/f011/generate.R`
- `stata-mp -b do tests/stata/test-f011.do`
- `Rscript tools/parity/generators/f012/generate.R`
- `stata-mp -b do tests/stata/test-f012.do`
- `python3 tools/parity/generators/py001/generate.py`
- `stata-mp -b do tests/stata/python/test_aggte_comprehensive.do`
- `python3 tools/parity/generators/py003/generate.py`
- `stata-mp -b do tests/stata/python/test_att_gt.do`
- `Rscript tools/parity/generators/f013/generate.R`
- `stata-mp -b do tests/stata/test-f013.do`
- `Rscript tools/parity/generators/rt015/generate.R`
- `stata-mp -b do tests/stata/r/test-inference.do`
- `Rscript tools/parity/generators/rt029/generate.R`
- `stata-mp -b do tests/stata/r/att_gt_point_estimate_tests.do`
- `Rscript tools/parity/generators/rt030/generate.R`
- `stata-mp -b do tests/stata/r/att_gt_point_estimate_tests_rmd.do`
- `Rscript tools/parity/generators/f015/generate.R`
- `stata-mp -b do tests/stata/test-f015.do`
- `Rscript tools/parity/generators/f016/generate.R`
- `stata-mp -b do tests/stata/test-f016.do`
- `Rscript tools/parity/generators/f018/generate.R`
- `stata-mp -b do tests/stata/test-f018.do`
- `Rscript tools/parity/generators/f019/generate.R`
- `stata-mp -b do tests/stata/test-f019.do`
- `Rscript tools/parity/generators/f020/generate.R`
- `stata-mp -b do tests/stata/test-f020.do`
- `Rscript tools/parity/generators/f021/generate.R`
- `stata-mp -b do tests/stata/test-f021.do`
- `Rscript tools/parity/generators/f022/generate.R`
- `stata-mp -b do tests/stata/test-f022.do`
- `Rscript tools/parity/generators/f023/generate.R`
- `stata-mp -b do tests/stata/test-f023.do`
- `Rscript tools/parity/generators/f024/generate.R`
- `stata-mp -b do tests/stata/test-f024.do`

## Current Matrix Summary

- `parity-verified`: 88 rows. These include F001-F013, F015-F016,
  F018-F032, F039, F041-F044, F046-F051, RT003, RT004, RT007, RT010,
  RT016, RT017, RT026, PY001, PY002, PY004, PY005, PY007-PY009,
  PY011, PY012, PY015-PY019, PY021-PY023, JEL001-JEL018, and
  ENG001-ENG005.
- `approved-divergence`: 38 rows. These are F014, F033-F038, F040,
  RT001, RT002, RT005, RT006, RT008, RT009, RT011-RT015, RT018-RT025,
  RT027-RT030, PY003, PY006, PY010, PY013, PY014, PY020, and PY024.
  They remain terminal because each has an explicit decision record and
  executable evidence for an unavailable source path, R/Python-only helper
  surface, non-public Stata analogue, stochastic draw-stream boundary, or
  intentionally unsupported compatibility behavior.
- `unsupported-by-design`: F017 and F045.
- No rows remain `contract-frozen`.

## Residual Scope

The implementation is complete for conformance profile v1 as represented by
`inst/spec/feature-matrix.csv`, the frozen decision registry, and the current
fixtures. The remaining approved divergences are not hidden implementation
work: they are explicit contract decisions where R/Python internals, callable
estimators, historical object comparisons, rendered plotting style, or exact
cross-runtime stochastic histories do not define a public Stata result.

Full JEL reproduction is no longer a residual release blocker for this profile.
`reports/jel-full-reproduction-result.md` records both master scripts exiting
0, failure markers 0, and every committed table/figure artifact hash-matching
or semantically matching. A public Git tag still requires rerunning
`docs/release-checklist.md` on the target release machine.

The pinned legacy-to-candidate performance certification is also closed on the
recorded macOS platform. Seven isolated alternating trials cover 15 analytical,
bootstrap, aggregation, clustering, unbalanced, and large-panel workloads.
Every paired time and process-RSS median is below the public legacy package,
and every bootstrap 95% upper bound remains below `1.0`. The raw runs, summary,
artifact hashes, and policy are recorded under
`build/legacy-candidate-ab/` and in
`reports/legacy-candidate-performance-certification.md`.

## Next Required Milestones

1. Before publishing a public tag, rerun `docs/release-checklist.md` on the
   target release machine and attach the generated logs to the release record.
2. Keep the approved-divergence rows visible in release notes so users can
   distinguish public Stata parity from R/Python-only internal surfaces and
   historical object-model tests.
3. Treat larger optional benchmarks, additional rendered-style audits, and
   future compatibility modes as post-v1 hardening work; they must not change
   R-parity defaults without a new frozen decision record.
