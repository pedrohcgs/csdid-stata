# Development and contract workflow

This document holds the internal engineering material that previously lived in
the repository `README.md`. `README.md` is now the user-facing front page for
the `csdid` Stata package; everything about how the port is built, governed,
and verified lives here.

Audience: maintainers and contributors. Users of the `csdid` command should
read `README.md` and `help csdid` instead.

## Mission

This repository is a clean, parity-first rebuild of the Stata `csdid` package.
The mission is narrow and strict: the Stata implementation must match the R
`did` package, including defaults, numerical results, inference, sample
handling, aggregation, plotting data, and empirical replication outputs.
Legacy Stata behavior is legacy behavior unless the frozen contract explicitly
keeps it.

The workflow structure is adapted from the Codex `/goal` workflow in
`meleantonio/didbjs-codex-goal`.

Current public handoff version: `2.0.0-rc1`. Final `v2.0.0` is gated on the
release checklist, platform matrix, and independent review packet documented in
`docs/release-checklist.md`, `docs/platform-matrix.md`, and
`docs/independent-review-packet.md`.

Release-blocking status for this RC: estimator, sample, and omitted-inference
defaults are aligned to R `did` 2.5.1. By default, `csdid` uses multiplier
bootstrap inference with simultaneous confidence bands and 1000 bootstrap
iterations. Use `analytical` or `vce(analytical)` only when analytical standard
errors are deliberately requested.

## Non-negotiables

- R `did` version 2.5.1 is the primary source of truth.
- Every R unit test that applies to public `did` behavior must have a Stata
  equivalent.
- If Python `csdid` has deeper tests than R, Stata must inherit the deeper test.
- Stata defaults must match R defaults.
- Every Stata result must match R, or have an approved divergence recorded in
  `docs/behavior-decisions.md` before implementation.
- Unbalanced panels must follow R semantics by default: use the repeated
  cross-section path while preserving the correct standard-error behavior.
- All empirical results in `pedrohcgs/JEL-DiD` must be reproducible.
- Legacy Stata options that only reproduce legacy behavior may exist as
  soft-deprecated compatibility modes, never as defaults.

## Reference repositories

Orientation pins gathered on 2026-06-22:

| Role | Repository | Reference |
| --- | --- | --- |
| Primary statistical oracle | `bcallaway11/did` | `DESCRIPTION` reports version 2.5.1 at GitHub HEAD `9aba07d054a798558ac9b551887f5cb592d8db10` |
| Python parity and deeper tests | `DrSquare/csdid` | HEAD `555f28bc12fcafa9c099e6e5503a30a4c22fc89f` |
| Legacy Stata behavior | `pedrohcgs/csdid-stata` | HEAD `fdbae25521a941314af8d84ec0c93fb0596daa8e` |
| Empirical acceptance suite | `pedrohcgs/JEL-DiD` | HEAD `50f4f183783d2344f85bc4f39bcbcc1b7eba6466` |
| Workflow model | `meleantonio/didbjs-codex-goal` | HEAD `1c8f472ee896d1a13d049b458e2eedc7c59c1de9` |

The contract-freeze goal must pin the exact source for R `did` 2.5.1. Initial
checks on 2026-06-22 did not find `did_2.5.1.tar.gz` in CRAN current or archive
paths, so the known source is the GitHub commit above unless a separate release
archive is provided.

## Stata engineering references

The Stata implementation should be fast, reliable, and idiomatic. The following
repositories are engineering references for ado/Mata architecture, performance,
testing, packaging, and style. They do not override R `did` as the statistical
oracle.

Engineering-reference pins gathered on 2026-06-22:

| Role | Repository | Reference |
| --- | --- | --- |
| Optimized Stata/Mata patterns | `mcaceresb/stata-gtools` | HEAD `f8e303d90be1ac7fb469b9ed7caf202957139b69` |
| HonestDiD Stata integration and UX | `mcaceresb/stata-honestdid` | HEAD `f56934c399d357fac9f3036fc15ce3adf8968597` |
| Multi-treatment Stata package architecture | `gphk-metrics/stata-multe` | HEAD `89656e373f83ef8d69292549ab4a8155129b83e4` |
| Staggered-adoption Stata workflow patterns | `mcaceresb/stata-staggered` | HEAD `088605931fdb93e78ba1c6c578584ee263d23232` |
| Pre-trends Stata workflow and diagnostics | `mcaceresb/stata-pretrends` | HEAD `5dc09d0c6c55d157fe3babc5ab68cb9fbc46a0fb` |
| High-dimensional FE Stata architecture | `sergiocorreia/reghdfe` | HEAD `4c1744df2c3bc474d0ee7ee5efa1bb54760067e5` |
| Fast grouping/collapse utilities | `sergiocorreia/ftools` | HEAD `7b3663e49ea5c5b81638c55be29edf416e68e8b7` |
| IV with high-dimensional FE integration | `sergiocorreia/ivreghdfe` | HEAD `bfb5577a6dbdfb029ab4ab6a7e93f7257a827b42` |
| Optimized nonlinear Stata workflows | `sergiocorreia/ppmlhdfe` | HEAD `b85665d8f674e93c1e07446a9a2b29be7f797910` |
| Miscellaneous Stata utilities and conventions | `sergiocorreia/stata-misc` | HEAD `bb10fd8ccb1fafa03c58019dcb2f4dea17ef813c` |
| Platform plugin architecture and release staging | `reisportela/xhdfe-xfe` | HEAD `04041e0e9bf952fd4d3e7ef2e40ce72ccbe80dbe`, reviewed 2026-07-09 |

The contract-freeze goal must read these repositories and produce an
engineering-style plan before implementation. The implementation goal must use
that plan for ado/Mata organization, dependency policy, performance budgets,
error handling, test harnesses, and release hygiene.

The implementation has no required runtime dependency on those packages. An
optional platform bootstrap plugin accelerates explicitly seeded multiplier
draws; the complete Mata path remains mandatory and is tested as a fail-closed
fallback. See `docs/platform-matrix.md` for what is and is not certified.

## Legacy performance certification

The release has a pinned old-vs-new certification against
`pedrohcgs/csdid-stata@fdbae25521a941314af8d84ec0c93fb0596daa8e`. Seven
isolated trials per implementation cover analytical and bootstrap DR/IPW/REG,
covariates, weights, clusters, R-compatible unbalanced handling, event
aggregation, simultaneous bands, and a 250,000-row weighted DR panel. Every
frozen row requires both the paired time ratio and process-RSS ratio,
including their bootstrap 95 percent upper bounds, to remain at or below
legacy. Current local evidence passes all 15 rows; see
`reports/legacy-candidate-performance-certification.md`.

## Goal workflow

Run these goals in order:

1. `codex-goals/contract-freeze-goal.md`
   - Read all reference repos.
   - Read the Stata engineering-reference repos.
   - Freeze the feature matrix, fixture catalogue, tolerance registry, and
     behavior decisions.
   - Freeze the ado/Mata architecture and dependency policy.
   - Write no Stata implementation code.

2. `codex-goals/oracle-review-prompt.md`
   - Review the frozen playbook and conformance profile with a frontier model
     before implementation.
   - Incorporate critical feedback.
   - Record the review and incorporated fixes in `reports/oracle-review.md`.

3. `codex-goals/implementation-goal.md`
   - Build the Stata package against the frozen contract.
   - Drive development through fixtures and parity gates.
   - Use the frozen Stata engineering plan for performance and package style.

4. `codex-goals/hardening-goal.md`
   - Harden release quality, documentation, legacy migration, and JEL
     replication.

The files under `docs/`, `inst/spec/`, `tools/parity/reference-lock/`, and
`reports/oracle-review.md` are the frozen conformance-profile v1 contract.
Implementation must not add or remove behavior outside that contract without a
new decision record and feature matrix update.

## Building and installing from source

From the repository root, in Stata:

```stata
do src/build.do
cap ado uninstall csdid
net install csdid, from("`c(pwd)'") replace
```

`src/build.do` compiles `src/mata/csdid.mata` under `matastrict on` to surface
compile errors, then stages the installable payload that `csdid.pkg` lists.

## Where things live

| Path | Contents |
| --- | --- |
| `src/ado/` | `csdid`, `csdid_stats`, `csdid_estat`, `csdid_plot`, `_csdid_post` |
| `src/mata/csdid.mata` | numeric engine |
| `src/help/` | the five shipped help files |
| `examples/` | runnable example do-files and `examples/data/mpdta.csv` |
| `docs/` | frozen contract, behavior decisions, migration and support docs |
| `tests/` | fixtures, Stata gates, meta-tests |
| `tools/` | parity, benchmark, JEL reproduction, plugin, and release tooling |
| `reports/` | audit, certification, and status reports |

## Contract and policy documents

- `PROVENANCE.md` — reference roles, license notes, clean-room boundary, and
  the artifact ledger. Read this before copying anything from any reference.
- `docs/behavior-decisions.md` — every approved divergence from R `did` 2.5.1.
- `docs/conformance-profile-v1.md` — the frozen contract.
- `docs/tolerance-registry-v1.md` — per-fixture numerical tolerances.
- `docs/legacy-stata-compatibility.md`, `docs/legacy-migration-guide.md` —
  legacy Stata `csdid` 1.82 surface and how it maps onto this port.
- `docs/public-api-freeze-v2.md`, `docs/stored-results-api.md` — the public
  command and `e()` surface, and its stability guarantees.
- `docs/versioning-and-release-policy.md`, `docs/release-checklist.md`,
  `docs/release-engineering.md` — release process.
- `docs/platform-matrix.md` — what is certified on which platform.
- `docs/support-runbook.md` — triage process for user reports.
- `LICENSE-DECISION.md` — licensing analysis and the pending owner decision.
