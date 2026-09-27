# Provenance

What csdid 2.0.0 was built and checked against, and the license facts that
follow from it.

## References

| Reference | What it was used for | Version |
| --- | --- | --- |
| `bcallaway11/did` | the reference implementation: estimators, samples, inference, aggregation and plot data are checked against it | 2.5.1, commit `9aba07d054a798558ac9b551887f5cb592d8db10` |
| `DrSquare/csdid`, a fork of the Python package `d2cml-ai/csdid` | additional test cases | commit `555f28bc12fcafa9c099e6e5503a30a4c22fc89f` |
| `pedrohcgs/csdid-stata` | Stata `csdid` Version 1.82, for the migration comparisons and speed benchmarks | commit `fdbae25521a941314af8d84ec0c93fb0596daa8e` |
| `pedrohcgs/JEL-DiD` | empirical replication targets | commit `50f4f183783d2344f85bc4f39bcbcc1b7eba6466` |
| `mcaceresb/stata-gtools` | Stata engineering reference | commit `f8e303d90be1ac7fb469b9ed7caf202957139b69` |
| `mcaceresb/stata-honestdid` | Stata engineering reference | commit `f56934c399d357fac9f3036fc15ce3adf8968597` |
| `gphk-metrics/stata-multe` | Stata engineering reference | commit `89656e373f83ef8d69292549ab4a8155129b83e4` |
| `mcaceresb/stata-staggered` | Stata engineering reference | commit `088605931fdb93e78ba1c6c578584ee263d23232` |
| `mcaceresb/stata-pretrends` | Stata engineering reference | commit `5dc09d0c6c55d157fe3babc5ab68cb9fbc46a0fb` |
| `sergiocorreia/reghdfe` | Stata engineering reference | commit `4c1744df2c3bc474d0ee7ee5efa1bb54760067e5` |
| `sergiocorreia/ftools` | Stata engineering reference | commit `7b3663e49ea5c5b81638c55be29edf416e68e8b7` |
| `sergiocorreia/ivreghdfe` | Stata engineering reference | commit `bfb5577a6dbdfb029ab4ab6a7e93f7257a827b42` |
| `sergiocorreia/ppmlhdfe` | Stata engineering reference | commit `b85665d8f674e93c1e07446a9a2b29be7f797910` |
| `sergiocorreia/stata-misc` | Stata engineering reference | commit `bb10fd8ccb1fafa03c58019dcb2f4dea17ef813c` |
| `reisportela/xhdfe-xfe` | reference for shipping a platform plugin | commit `04041e0e9bf952fd4d3e7ef2e40ce72ccbe80dbe` |

## Code

The estimation engine -- `csdid`, `csdid_stats`, `csdid_estat`, `csdid_plot`,
the Mata library and the bootstrap plugin's C source -- is new code. No
implementation code was copied into it from the references above: their code
was read to understand behavior and design, and their numerical output was
used as test targets. The deprecated utilities documented in
`help csdid_legacy` come from Version 1.82 of this package. The plugin is built against Stata's official
`stplugin.h` and `stplugin.c` interface files, whose SHA256 values are checked
at build time (`0d32086bfb7a621e30ed7fefa41b351b6733bb4561da28a4c581580d62c64e8b`
and `ab694f53e30a404bbfbe59d301a81b8bc59eeecf84bc5427eb65cbf0c5020d6d`); those
files are not in the repository. The compiled macOS plugin ships inside the
package; other platforms use the Mata implementation.

## Licenses

- csdid 2.0.0 is released under the MIT license; see `LICENSE`.
- R `did` 2.5.1 reports `License: GPL-3` in its `DESCRIPTION`.
- Python `csdid` ships an MIT `LICENSE` file, and its `setup.py` declares
  `license="MIT"`.
- Stata `csdid` Version 1.82 carried no top-level license file.
