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
