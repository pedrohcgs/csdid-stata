# Reference Locks

Status: frozen for conformance profile v1.

This directory records the source references used by the frozen contract. These
locks are behavioral and provenance inputs; generated parity artifacts will add
fixture-specific hashes during implementation.

| Lock file | Purpose |
| --- | --- |
| `r-did-lock.json` | R `did` 2.5.1 source and observed package metadata |
| `python-csdid-lock.json` | Python `csdid` source, test inventory, and license metadata |
| `legacy-stata-lock.json` | Existing Stata source and command surface |
| `jel-did-lock.json` | JEL empirical suite source, scripts, tables, figures, and dependency notes |
| `stata-engineering-lock.json` | Mauricio Caceres Bravo and Sergio Correia engineering references |
| `workflow-lock.json` | Goal-workflow reference source |
| `../source-test-inventory.csv` | R/Python source test file hashes mapped to RT/PY rows |

The implementation goal must extend these locks with fixture-specific
environment versions, generator commands, generator hashes, output hashes, RNG
seeds, RNG kinds, and Stata executable metadata for each generated parity
artifact.

## Fixture Manifest Minimum Schema

Every generated fixture must include `metadata/manifest.json` with:

- `matrix_id`, `fixture_family`, `normative_source`, and `decision_refs`;
- input artifact paths and SHA-256 hashes;
- generator commands and generator file SHA-256 hashes;
- R/Python/Stata executable versions and package versions used;
- RNG seed, RNG kind, bootstrap draw count, and draw distribution when
  stochastic inference is involved;
- expected-output artifact paths and SHA-256 hashes;
- tolerance IDs used for each comparison class;
- explicit notes for approved divergences.
