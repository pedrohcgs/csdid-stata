# Stata Engineering References

Status: frozen for implementation-goal v1.

These repositories are engineering references for a fast, reliable, idiomatic
Stata `csdid` implementation. They are not statistical sources of truth. R
`did` 2.5.1 remains the econometric oracle.

## Reference Inventory

| Repository | Observed HEAD on 2026-06-22 | Inspected surfaces | Adopted lessons |
| --- | --- | --- | --- |
| `mcaceresb/stata-gtools` | `f8e303d90be1ac7fb469b9ed7caf202957139b69` | `build/*.ado`, `_gtools_internal.mata`, `gtools_tests.do`, docs examples, `Makefile`, `build.py` | high-performance grouping should be isolated behind tested kernels; benchmarks and examples are first-class artifacts |
| `mcaceresb/stata-honestdid` | `f56934c399d357fac9f3036fc15ce3adf8968597` | `src/ado`, `src/mata`, `standalone`, tests, replication scripts | Stata UX can wrap compiled/Mata internals while preserving reproducible examples and cross-language checks |
| `gphk-metrics/stata-multe` | `89656e373f83ef8d69292549ab4a8155129b83e4` | `src/ado`, `src/mata`, `src/build.do`, unit/speed/weight tests | multi-command estimators should separate command parsing from Mata computation and include speed tests |
| `mcaceresb/stata-staggered` | `088605931fdb93e78ba1c6c578584ee263d23232` | `src/ado`, `src/mata`, unit and R-compare tests | staggered-adoption commands need direct cross-language comparison tests and compact help examples |
| `mcaceresb/stata-pretrends` | `5dc09d0c6c55d157fe3babc5ab68cb9fbc46a0fb` | `src/ado`, `src/mata`, mvnormal and unit tests | diagnostic commands should expose clear user-facing workflows and numerical subtests |
| `sergiocorreia/reghdfe` | `4c1744df2c3bc474d0ee7ee5efa1bb54760067e5` | `current-code/*.ado`, `current-code/*.mata`, programming help, benchmark folders | complex Stata estimators need explicit Mata APIs, postestimation commands, programming docs, and benchmark suites |
| `sergiocorreia/ftools` | `7b3663e49ea5c5b81638c55be29edf416e68e8b7` | `src/*.ado`, `src/*.mata`, test and benchmark do-files | factor/grouping utilities should be optional-fast-path candidates with base-Stata fallback tests |
| `sergiocorreia/ivreghdfe` | `bfb5577a6dbdfb029ab4ab6a7e93f7257a827b42` | `src/ivreghdfe.ado`, examples, tests | integration commands should validate dependency availability and keep examples minimal |
| `sergiocorreia/ppmlhdfe` | `b85665d8f674e93c1e07446a9a2b29be7f797910` | `src/*.ado`, `src/*.mata`, guides, many edge-case tests | hard numerical estimators need explicit convergence diagnostics, separation/failure checks, and many small regression tests |
| `sergiocorreia/stata-misc` | `bb10fd8ccb1fafa03c58019dcb2f4dea17ef813c` | dependency scripts, utility ado files, tests | package utilities should keep dependency installs explicit and testable |
| `reisportela/xhdfe-xfe` | `04041e0e9bf952fd4d3e7ef2e40ce72ccbe80dbe` (reviewed 2026-07-09) | plugin dispatch in `xhdfe.ado`, C++ plugin boundary, platform build/staging scripts, package metadata | bind a plugin beside the active ado file, ship platform-specific artifacts, expose failures clearly, and keep release binaries reproducible |

## Architecture Contract

The implementation must use this split:

- ado wrappers own syntax parsing, `marksample`, validation, error/warning
  messages, user-facing options, `ereturn`, postestimation dispatch, and help
  examples;
- Mata kernels own group/time indexing, 2x2 cell construction, influence
  function storage, covariance and bootstrap accumulation, aggregation weights,
  and performance-critical loops;
- generated fixtures and benchmarks live outside runtime ado files;
- postestimation commands consume stored matrices, scalars, and metadata rather
  than reparsing user data when possible;
- the public command surface keeps `csdid`, `csdid_estat`, `csdid_stats`, and
  `csdid_plot` unless a legacy decision explicitly removes a behavior.

## Stata Version Contract

The v1 runtime floor is Stata 15. Primary CI/manual verification should use
Stata 17, with release checks on Stata 18 or newer when available. Runtime ado
commands may not require frames unless guarded with a Stata-version fallback.
Use `preserve`/`restore`, tempfiles, tempvars, tempnames, and Mata objects in a
Stata 15-compatible way for user-facing commands.

## Dependency Policy

Runtime dependencies for v1:

- `drdid`: required only if the implementation delegates 2x2 estimators to the
  Stata `drdid` package. If delegated, version checks and clear install guidance
  are mandatory.
- `gtools`: optional-fast-path candidate for grouping/collapse operations.
  Base-Stata/Mata fallback is mandatory.
- `ftools`: optional-fast-path candidate for factor/grouping operations.
  Base-Stata/Mata fallback is mandatory.
- `reghdfe`: forbidden as a required v1 runtime dependency. It may inform
  architecture and benchmarks but should not be required for installability.
- `honestdid`: test-only/JEL-only unless a future feature explicitly exposes
  sensitivity analysis.
- JEL plotting/export packages: test-only for JEL replication unless the final
  package command needs them.

Optional-fast-path behavior must be tested against fallback behavior on every
fixture it affects. Default offline tests must not install packages from the
network.

## Compiled Accelerator Contract

The optional `csdid` bootstrap plugin follows these additional rules:

- the complete Mata implementation remains mandatory and is the correctness
  fallback on every platform;
- the plugin boundary is limited to multiplier generation and influence-function
  multiplication; estimator, sample, cluster, confidence-band, and result
  logic remain in Mata;
- seeded plugin output must match Mata draws within the frozen numerical
  tolerance and must advance the 625-word BMisc-compatible RNG state exactly;
- plugin input is passed through temporary numeric variables rather than large
  Stata matrices, and all temporary variables are dropped before return;
- the runtime binds only to a platform-named plugin beside the active
  `csdid.ado`, with a canonical local-development fallback;
- missing, stale, incompatible, or failed plugins must fall back to Mata and
  report diagnostic status without changing estimates;
- official Stata plugin SDK inputs are checksum-pinned, platform binaries are
  built in CI, and runtime certification still requires licensed-Stata rows on
  macOS, Linux, and Windows.

No source was copied from the engineering-reference repositories for this
accelerator. Their architecture and release patterns were used as design
references only.

## Style Rules

- Use `version` statements in ado entry points.
- Use `syntax`/parsing blocks that reject unknown options clearly.
- Use `tempvar`, `tempname`, and `preserve`/`restore` or frames so user data is
  not silently mutated.
- Never leave globals, matrices, frames, or characteristics behind unless they
  are documented stored results.
- Store row and cell identity explicitly for sample masks, RIFs, weights, and
  postestimation.
- Error messages must say what failed and how to fix it.
- Warnings for legacy behavior must be classifiable in logs and tested.
- Help files must include syntax, defaults, R-parity notes, legacy migration
  notes, examples, and stored results.

## Test And Benchmark Rules

- Use small deterministic `.do` tests for every fixture.
- Keep R/Python/JEL regeneration opt-in; default tests consume committed
  artifacts.
- Include cross-language comparison tests where references exist.
- Include fast-path versus fallback tests for optional dependencies.
- Include performance tests for grouping, cell construction, influence-function
  matrix size, aggregation, bootstrap, and JEL-scale runs.
- Include an opt-in scale gate for `large_panel` and `bootstrap_medium` through
  `CSDID_RUN_OPTIN_PERF=1 tests/run-optin-performance.sh`; default smoke tests
  keep the smaller deterministic F049 budget gate.
- Prefer base-Mata compressed row maps and cached factor-like layouts for
  core `csdid` paths. `gtools`/`ftools` may be added only as optional fast-path
  candidates with executable fallback parity tests; they must not become hidden
  runtime dependencies.
- Use `fast(auto)` for parity-proven base-Mata computation paths by default,
  while retaining `nofast` as the explicit baseline/debug path in parity tests.
- For large Stata-only storage costs, prefer documented Mata-cache fast paths
  with explicit e-class flags and postestimation parity tests over silently
  changing default stored-result matrices.
- Storage is unified on lean: influence-function objects live in the engine
  cache at every sample size, and only explicit `storeall` materializes them
  in `e()`. No object with one row per unit crosses Stata's classic-matrix
  layer (quadratic in the longest dimension) on a default run. Clustered,
  bootstrap, replay, aggregation, and estimates-store workflows must remain
  covered by parity and performance gates.
- Record benchmark machine metadata and Stata version.

## Release Rules

- Build and test from an isolated ado path.
- Provide `.pkg`, `stata.toc`, help files, and examples.
- Do not depend on the user's global ado tree.
- Do not require internet access in default tests.
- Before release, produce `reports/engineering-audit.md` documenting:
  architecture, dependency checks, state-mutation audit, benchmark results,
  optional-fast-path parity, and any deviations from this plan.
