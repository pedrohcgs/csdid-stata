# Tests

Everything here is run by `tools/release/preflight.sh`, which is the single
command for "is this mergeable?". Nothing in this directory is expected to be
run by hand as part of normal work.

| Directory | What it holds |
| --- | --- |
| `stata/` | The suite proper: `test-*.do` cover the package's own behaviour, `stata/r/` mirror the tests of the R reference implementation, and `stata/python/` mirror those of the Python one. |
| `fixtures/` | Frozen inputs and expected outputs. Each fixture directory holds `inputs/`, `expected/` and a `metadata/manifest.json` recording how it was generated and what it is compared against. |
| `meta/` | Checks that the project describes itself correctly — that a manifest names files that exist, that versions agree, that a ledger row has the evidence it claims. These fail when documentation and reality drift apart, which no amount of estimator testing would catch. |
| `installation/` | A small check that a distributed copy installs into a clean Stata session and runs. Copied into the release bundle. |

## Fixture identifiers

Fixture directories are named `f001`, `rt001`, `py001` and so on. The prefix
records where the requirement came from — `f` from this package's own feature
matrix, `rt` from a test of the R implementation, `py` from a test of the Python
one — and the identifiers are referenced by `inst/spec/feature-matrix.csv`,
`tools/validate-contract.py` and several `meta/` gates. They are load-bearing,
not decorative: renaming one means updating every consumer.

## Regenerating expected output

Expected outputs are produced by the generators under `tools/parity/generators/`,
never edited by hand. Each fixture's `metadata/manifest.json` names the command
that produces it. Regenerating should be a no-op; a fixture that moves is either
a real change to mirror or a divergence to record and justify.

## Running

```sh
bash tools/release/preflight.sh          # everything
bash tools/release/preflight.sh --fast   # the cheap consistency checks only
bash tools/release/preflight.sh --list   # what would run, and why
```

`--fast` is a pre-commit convenience and never a merge verdict: it runs the
spec tier only, and a full run is required before merge.

## Reproducing the certification

The Stata suite and every meta gate run from a clone with nothing but Stata:

    bash tools/release/preflight.sh

The deepest tiers compare against external references and report BLOCKED --
never a pass -- when a prerequisite is absent:

| Tier | Needs | Where |
| --- | --- | --- |
| R oracle environment + regeneration | R with the pinned `did` 2.5.1 and `DRDID` 1.3.0 packages (and the `digest` package) | install from CRAN/GitHub; the environment gate verifies both the versions and a content digest of the loaded code before any oracle is trusted |
| Adversarial R differential | `CSDID_DID_UPSTREAM` pointing at a checkout of the `did` 2.5.1 sources | github.com/bcallaway11/did, tag v2.5.1 |
| Legacy A/B certification | `CSDID_LEGACY_ROOT` pointing at the frozen Version 1.82 sources at the pinned commit recorded in the harness | any faithful copy of the Version 1.82 release sources |
| JEL full reproduction | `JEL_DID_REFERENCE` pointing at the JEL-DiD replication materials | github.com/pedrohcgs/JEL-DiD |

`preflight.sh --release` runs everything, including the tiers above and the
timing rows, and writes a digest-bound receipt only when every check passed
and the platform identified itself.
