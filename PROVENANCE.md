# Provenance

Status: frozen for conformance profile v1.

## Workflow Source

This repository adapts the goal-driven workflow structure from
`meleantonio/didbjs-codex-goal` at observed HEAD
`1c8f472ee896d1a13d049b458e2eedc7c59c1de9`.

Reused conceptually: contract freeze before implementation, oracle review
before implementation, numbered fixtures, feature matrix, tolerance registry,
reference locks, and final-report discipline.

Not reused: BJS-specific econometric content, R package implementation content,
or parity fixtures from `didbjs`.

## Reference Roles

| Reference | Role | Observed ref |
| --- | --- | --- |
| `bcallaway11/did` | primary statistical and API oracle | GitHub HEAD `9aba07d054a798558ac9b551887f5cb592d8db10`; version 2.5.1 |
| CRAN `did` 2.5.1 | optional archive if found | not visible in initial current/archive checks on 2026-06-22 |
| `DrSquare/csdid` | Python deeper-test source | HEAD `555f28bc12fcafa9c099e6e5503a30a4c22fc89f` |
| `pedrohcgs/csdid-stata` | legacy Stata behavior source | HEAD `fdbae25521a941314af8d84ec0c93fb0596daa8e` |
| `pedrohcgs/JEL-DiD` | empirical acceptance suite | HEAD `50f4f183783d2344f85bc4f39bcbcc1b7eba6466` |
| `mcaceresb/stata-gtools` | Stata engineering reference | HEAD `f8e303d90be1ac7fb469b9ed7caf202957139b69` |
| `mcaceresb/stata-honestdid` | Stata engineering reference | HEAD `f56934c399d357fac9f3036fc15ce3adf8968597` |
| `gphk-metrics/stata-multe` | Stata engineering reference | HEAD `89656e373f83ef8d69292549ab4a8155129b83e4` |
| `mcaceresb/stata-staggered` | Stata engineering reference | HEAD `088605931fdb93e78ba1c6c578584ee263d23232` |
| `mcaceresb/stata-pretrends` | Stata engineering reference | HEAD `5dc09d0c6c55d157fe3babc5ab68cb9fbc46a0fb` |
| `sergiocorreia/reghdfe` | Stata engineering reference | HEAD `4c1744df2c3bc474d0ee7ee5efa1bb54760067e5` |
| `sergiocorreia/ftools` | Stata engineering reference | HEAD `7b3663e49ea5c5b81638c55be29edf416e68e8b7` |
| `sergiocorreia/ivreghdfe` | Stata engineering reference | HEAD `bfb5577a6dbdfb029ab4ab6a7e93f7257a827b42` |
| `sergiocorreia/ppmlhdfe` | Stata engineering reference | HEAD `b85665d8f674e93c1e07446a9a2b29be7f797910` |
| `sergiocorreia/stata-misc` | Stata engineering reference | HEAD `bb10fd8ccb1fafa03c58019dcb2f4dea17ef813c` |
| `reisportela/xhdfe-xfe` | platform plugin architecture/release reference | HEAD `04041e0e9bf952fd4d3e7ef2e40ce72ccbe80dbe`; reviewed 2026-07-09 |

## License Notes

- R `did` 2.5.1 reports `License: GPL-3` in `DESCRIPTION`.
- Python `csdid` includes an MIT `LICENSE` and `setup.py` uses `license="MIT"`;
  `setup.py` classifiers mention Apache, so upstream metadata is inconsistent.
  Treat MIT as binding until clarified.
- Current Stata `csdid-stata` has no observed top-level license file in the
  checkout.
- JEL-DiD is an empirical replication source; its generated artifacts are used
  as acceptance targets.
- The optional bootstrap plugin is original clean-room C code. No source was
  copied from the engineering references. Its build uses Stata's official
  `stplugin.h` and `stplugin.c` interface files after verifying SHA256 values
  `0d32086bfb7a621e30ed7fefa41b351b6733bb4561da28a4c581580d62c64e8b` and
  `ab694f53e30a404bbfbe59d301a81b8bc59eeecf84bc5427eb65cbf0c5020d6d`.

## Clean-Room Boundary

Implementation code remains clean-room by default:

- R, Python, legacy Stata, and engineering-reference implementation code may be
  read to understand public behavior, tests, architecture, and style.
- Do not copy implementation code unless a future provenance entry records
  source path, commit, license, copied/adapted lines, justification, and a
  license-compatible package decision.
- Generated numerical outputs, manifests, behavioral descriptions, and public
  docs may be used as test oracles.
- Engineering-reference patterns may be adopted at the design level, but code
  snippets are subject to the same provenance rules.

## Artifact Ledger

| Artifact class | Source allowed | Copy policy |
| --- | --- | --- |
| Contract documents | Original synthesis from reference behavior | owned by this repo |
| Reference locks | Commit/version metadata from public repos | owned by this repo |
| Fixture inputs | Generated during implementation | owned by this repo; generator logged |
| R expected outputs | Generated from pinned R `did` | allowed as test oracle |
| Python expected outputs | Generated from pinned Python `csdid` | allowed as deeper-test evidence |
| Legacy Stata outputs | Generated from current Stata `csdid` | allowed as compatibility evidence |
| JEL tables/figures | Generated or compared from JEL-DiD | release acceptance evidence |
| Implementation code | New clean-room Stata ado/Mata | no source copying unless ledger updated |
| Bootstrap plugin | New clean-room C implementation plus official Stata plugin SDK at build time | SDK files are checksum-pinned and excluded from the repository/bundle; compiled platform artifacts are release outputs |

## Future Ledger Entries

Every copied/adapted implementation fragment must add:

- source repository, commit, path, and line range;
- destination path and line range;
- license basis;
- reason clean-room reimplementation was not used;
- reviewer approval before release.
