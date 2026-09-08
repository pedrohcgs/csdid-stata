# Tests

The repository includes numerical fixtures, Stata tests, installation checks,
and static checks for package and documentation consistency. Run commands from
the repository root.

| Directory | Contents |
| --- | --- |
| `stata/` | Estimation, inference, aggregation, sample, export, and session-state tests; `r/` and `python/` contain inherited regression cases. |
| `fixtures/` | Inputs, expected results, and metadata naming the reference and regeneration command. |
| `meta/` | Static and structural checks, including manifest, version, and documentation consistency. |
| `installation/` | Checks that an extracted distribution installs into an isolated Stata profile and runs. |

## Run the checks

```sh
bash tests/run-smoke.sh                   # Stata suite and its prerequisites
bash tools/release/preflight.sh --fast    # static consistency checks
bash tools/release/preflight.sh           # full verification
bash tools/release/preflight.sh --release # includes release-scale reproductions
bash tools/release/preflight.sh --list    # check inventory and prerequisites
```

The runners discover tests from the tree; a fixed count is not a guarantee that
all current tests ran. The fast run covers only the static tier. Some meta-gates
also inspect built artifacts, so build the package before checking an edited
source tree.

Stata batch jobs can return shell status zero after a do-file fails. Inspect
the log for errors and normal completion. The runners reject failures and
missing completion; do not interpret a truncated log as a successful test.

## References and prerequisites

Full verification needs more than Stata. Static checks require shell tools and
Python 3 with NumPy and pandas. Install the Python dependencies in the test
environment with `python3 -m pip install numpy pandas`. The numerical and
performance comparisons also need the following:

| Comparison | Prerequisite |
| --- | --- |
| Package rebuild | Licensed Stata 17, selected by `CSDID_BUILD_STATA_CMD` when the consumer uses another runtime |
| Prepared website comparison | Jekyll with `kramdown-parser-gfm`, and `CSDID_SITE_ROOT` pointing to a checkout of `pedrohcgs/pedrohcgs.github.io` with the prepared `csdid/` site |
| R oracle checks and regeneration | R with pinned `did` 2.5.1, `DRDID` 1.3.0, and `digest`; the oracle gate verifies loaded code as well as versions |
| R source and adversarial cases | `CSDID_DID_UPSTREAM` pointing to the source checkout pinned by the reference lock |
| Version 1.82 comparison | `CSDID_LEGACY_ROOT` pointing to the legacy source commit pinned by the harness |
| JEL reproduction | `JEL_DID_REFERENCE` pointing to the pinned JEL-DiD replication materials and their dependencies |

Set `STATA_CMD` to the licensed Stata executable being tested and
`CSDID_BUILD_STATA_CMD` to the Stata 17 executable that builds the release
library. For example, a Stata 19.5 consumer still uses Stata 17 for compilation.
When the build setting is omitted, it defaults to `STATA_CMD`; the build
refuses a compiler other than Stata 17. Record the consumer's actual version
and platform. A missing prerequisite is reported as `BLOCKED` or a failure,
not a pass.

The website comparison checks the local checkout against freshly built files.
Deployment and the pages served over HTTP require separate verification.

The JEL smoke check can pass artifact contracts before the full reproduction
has run. It explicitly reports full reproduction `UNVERIFIED` in that case
and records `parity_verified=0`. Failed or inconsistent recorded reproduction
results fail the check. Both smoke runners write their local artifact
observations to a fresh directory under `build/`, preserving the committed
JEL snapshot. The full reproduction remains a separate required check in the
`--release` run.

## Fixtures

Each fixture's `metadata/manifest.json` records its source, generator, and
comparison. Most statistical references come from R `did`; a fixture for a
feature it does not expose records its independent derivation. Expected
outputs are regenerated, never edited by hand. A regenerated value that changes
requires investigation before it can replace an expected result.

Identifiers such as `f001`, `rt001`, and `py001` connect fixture metadata to
its tests and reference inventory. Preserve those connections when working
with the suite. Numerical tests should compare the reported values and their
influence functions where relevant, including failures and missing values.
