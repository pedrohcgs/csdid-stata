# Conformance Profile v1

Status: frozen for implementation-goal v1.

This profile defines what counts as complete for the first parity-first Stata
`csdid` rewrite.

## Activation Rule

This profile is active because the repository records:

- primary R `did` 2.5.1 reference commit
  `9aba07d054a798558ac9b551887f5cb592d8db10`;
- Python `csdid` reference commit
  `555f28bc12fcafa9c099e6e5503a30a4c22fc89f`;
- legacy Stata `csdid` reference commit
  `fdbae25521a941314af8d84ec0c93fb0596daa8e`;
- JEL-DiD empirical reference commit
  `50f4f183783d2344f85bc4f39bcbcc1b7eba6466`;
- workflow model commit
  `1c8f472ee896d1a13d049b458e2eedc7c59c1de9`;
- pinned Stata engineering references in
  `docs/stata-engineering-references.md`;
- accepted decision records D001-D017;
- frozen fixture and feature matrix in `inst/spec/feature-matrix.csv`;
- frozen fixture schemas in `inst/spec/fixture-schemas.md`;
- frozen tolerance registry in `docs/tolerance-registry-v1.md`;
- frozen JEL and legacy inventories.

Initial checks on 2026-06-22 did not find `did_2.5.1.tar.gz` in CRAN current
or archive paths. The GitHub commit above is the R `did` 2.5.1 source unless a
future decision records a separate release archive.

## Terminal Status Rules

Before implementation starts, every mandatory row in
`inst/spec/feature-matrix.csv` has status `contract-frozen`.

Mandatory features may finish only as:

- `parity-verified`
- `approved-divergence`

Mandatory features may not finish as:

- `implemented-only`
- `unsupported-by-design`
- `blocked`

Nonmandatory legacy rows may finish as `unsupported-by-design` only when
`docs/legacy-stata-compatibility.md` preapproves removal or rejection. They may
finish as `soft-deprecated-alias` when an old spelling is retained with a
warning and mapped to canonical R-parity behavior.
`blocked` always means implementation is incomplete.

## Mandatory Scope

The mandatory v1 scope includes:

- R `did` 2.5.1 public `att_gt`, `aggte`, `ggdid`, output, validation,
  inference, and example behavior that maps to a Stata package;
- 30 R test artifacts mapped as RT001-RT030;
- 24 Python deeper-test files mapped as PY001-PY024;
- 50 fixture families F001-F050;
- JEL-DiD scripts, seven tables, and nine figures mapped as JEL001-JEL018;
- Stata engineering requirements ENG001-ENG005;
- source-test hashes in `tools/parity/source-test-inventory.csv`;
- clean install, isolated ado path, offline default tests, and opt-in full
  parity regeneration.

## Stata Version Profile

The v1 Stata floor is Stata 15. Primary CI and manual verification should run
on Stata 17. Release checks should also run on Stata 18 or newer when
available. Runtime commands may use frames only behind version guards; otherwise
they must use `preserve`/`restore`, tempfiles, or tempnames compatible with
Stata 15.

Default tests must not require internet access or the user's global ado tree.
JEL replication and optional dependency checks are opt-in.

## Source Hierarchy

| Domain | Governing source |
| --- | --- |
| Estimator behavior, defaults, samples, inference, aggregation, plotting data | R `did` 2.5.1 |
| Deeper regression and stress tests | Python `csdid`, subordinate to R |
| Legacy command behavior | Existing Stata `csdid`, compatibility only |
| Empirical release acceptance | JEL-DiD |
| Ado/Mata architecture and performance style | Pinned Stata engineering references |
| Sanity checks beyond software references | Algebraic and simulation invariants |

When sources disagree, R `did` 2.5.1 wins unless an approved divergence is
recorded before implementation.

## Preapproved Exclusions

No mandatory R-parity behavior is preapproved for exclusion.

The following nonmandatory legacy behaviors are preapproved for removal or
rejection with a clear user-facing message:

- current Stata pair-balanced unbalanced-panel default;
- current Stata `ipw` fallback behavior that maps to `stdipw`;
- old graph styling syntax that cannot be represented as stable plot-data
  parity;
- hidden or undocumented options that have no R-parity analogue and no JEL use.

Each removal must be recorded in `docs/legacy-stata-compatibility.md` and tested
as `unsupported-by-design`.

## Required First Milestones

Implementation must proceed in this order:

1. Engineering baseline: package layout, dependency checks, and fixture harness.
2. F001 static 2x2 ATT(g,t) parity.
3. F016 unbalanced-panel repeated-cross-section default parity.
4. F003-F006 aggregation parity.
5. JEL smoke tests for Table 7 and 2xT event-study outputs.
6. Full R test inheritance, Python deeper-test inheritance, JEL replication,
   benchmarks, and release hygiene.

## Completion Gate For Implementation

`codex-goals/implementation-goal.md` completes only if:

- every mandatory matrix row has status `parity-verified` or
  `approved-divergence`;
- zero mandatory matrix rows are `blocked`, `implemented-only`, or
  `unsupported-by-design`;
- all default tests pass without internet, Python, R, or licensed Stata beyond
  the local Stata runtime needed to run the package;
- opt-in R, Python, and legacy-Stata parity regeneration jobs pass in the
  prepared environments, and the opt-in JEL parity job either passes or has
  explicit release-owner disposition for each `needs-review` item;
- every JEL table and plot-data artifact is reproduced or has an explicit
  release-owner disposition tied to R `did` 2.5.1 evidence;
- benchmark budgets in `inst/spec/bench-budgets.yml` pass or have an approved
  release note;
- the engineering audit against `docs/stata-engineering-references.md` passes;
- provenance and license records are complete;
- the implementation final report records reference commits, versions,
  artifact hashes, tolerance exceptions, divergences, benchmark results, and
  regeneration commands.
