# Project Context

Status: frozen context note for conformance profile v1.

## Background

The R package `did` is the mature, trusted source. The checked out reference
reports version 2.5.1 in `DESCRIPTION` at commit
`9aba07d054a798558ac9b551887f5cb592d8db10`.

Python `csdid` is a parity-oriented implementation with deeper tests under
`csdid/test_csdid`. It is used to inherit stress cases and regression tests
after R behavior is established.

Existing Stata `csdid` is legacy evidence. Its ado header reports version 1.82,
and its help file documents a material unbalanced-panel divergence from R.

JEL-DiD is the empirical release gate. Its R and Stata pipelines, tables,
figures, and dependency locks must be reproducible with the new package.

The implementation should learn engineering patterns from Mauricio Caceres
Bravo's and Sergio Correia's strongest Stata packages. Those references guide
ado/Mata architecture, performance, testing, dependency policy, help files, and
release hygiene, but they do not change the econometric oracle.

## Product Direction

The v1 direction is a new Stata codebase with retained public command names
where compatible: `csdid`, `csdid_estat`, `csdid_stats`, and `csdid_plot`.
Legacy behavior is opt-in, documented, warned, and tested. R-parity behavior is
the default.

## Core Risk

The largest known divergence is unbalanced panel handling. R `did` uses
repeated-cross-section computations for unbalanced panels while preserving
correct standard errors. Current Stata uses pair-balanced or fully balanced
subsamples unless users select alternative balance behavior. This is frozen as
decision D003 and fixture F016.

## Frozen Reference Inventory

| Source | Role |
| --- | --- |
| `bcallaway11/did` | R `did` 2.5.1 statistical oracle |
| `DrSquare/csdid` | Python deeper-test source |
| `pedrohcgs/csdid-stata` | legacy Stata compatibility source |
| `pedrohcgs/JEL-DiD` | empirical acceptance suite |
| `meleantonio/didbjs-codex-goal` | workflow model |
| Mauricio Caceres Bravo Stata repos | ado/Mata, testing, and performance references |
| Sergio Correia Stata repos | ado/Mata, dependency, and benchmark references |

## Frozen Answers

- R `did` 2.5.1 is pinned to the GitHub commit above because CRAN current and
  archive checks did not expose `did_2.5.1.tar.gz` on 2026-06-22.
- v1 supports Stata 15+ syntax, with primary CI on Stata 17 and preferred
  release checks on Stata 18 or newer.
- Implementation remains clean-room unless a future provenance entry explicitly
  records copied/adapted code and a license-compatible package decision.
- Current Stata options are classified in `docs/legacy-stata-compatibility.md`.
- Optional dependencies `gtools` and `ftools` may be fast paths only with
  fallback parity tests. `reghdfe` is not a required v1 runtime dependency.
