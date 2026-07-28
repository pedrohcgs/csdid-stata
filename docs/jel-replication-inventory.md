# JEL Replication Inventory

Status: frozen for conformance profile v1.

## Source

Repository: `https://github.com/pedrohcgs/JEL-DiD`

Observed HEAD on 2026-06-22:
`50f4f183783d2344f85bc4f39bcbcc1b7eba6466`

The JEL `renv.lock` pins R `4.4.2`, R `did` `2.3.0` from GitHub remote SHA
`674a3981810eeacf2367e28d77fc71ca057aaa24`, and R `DRDID` `1.2.3` from GitHub
remote SHA `83a438c9cf8e6c98189291533e64d26ff2e8d178`. This is empirical
replication context and the original artifact target. It does not replace R
`did` 2.5.1 as the package oracle.

The Stata master script sets `global sscdate "2025-11-29"` and installs
`csdid`, `drdid`, `honestdid`, `regsave`, `estout`, `coefplot`, and `grc1leg2`
from a date-pinned SSC mirror. The new package test must override `csdid` with
the local checkout through an isolated ado path.

JEL acceptance has two layers:

- Original-artifact replication: reproduce the committed JEL tables and figure
  data under the JEL dependency context. The opt-in full reproduction wrapper
  now runs both JEL master pipelines and records the release-blocking result in
  `reports/jel-full-reproduction-result.md`.
- Modern-oracle diagnostics: optionally regenerate analogous R outputs under R
  `did` 2.5.1. Differences are diagnostic unless a package-default parity row
  is implicated.

If the two layers disagree, package defaults follow R `did` 2.5.1 and the JEL
result requires a documented empirical compatibility path.

## Scripts

| ID | Script | Command role | Acceptance |
| --- | --- | --- | --- |
| JEL001 | `scripts/R/00_master_did_jel.R` | restore `renv`, run all R analysis scripts | completes and regenerates expected R tables/figures |
| JEL002 | `scripts/Stata/00_stata_master_did_jel.do` | set local ado path, install non-`csdid` dependencies, run all Stata scripts | completes with local new `csdid` first in ado path |
| JEL001a | `scripts/R/0_make_data.R` | construct analysis data | output hashes recorded |
| JEL001b | `scripts/R/1_Adoption_Table.R` | adoption table | table data parity |
| JEL001c | `scripts/R/2_2x2.R` | 2x2 analysis | table/figure data parity |
| JEL001d | `scripts/R/3_2XT.R` | 2xT analysis | table/figure data parity |
| JEL001e | `scripts/R/4_GxT.R` | GxT analysis | table/figure data parity |
| JEL001f | `scripts/R/5_honestdid.R` | sensitivity analysis context | run or explicitly document if test-only dependency unavailable |
| JEL002a | `scripts/Stata/0_stata_Make_data.do` | construct Stata analysis data | output hashes recorded |
| JEL002b | `scripts/Stata/1_stata_adoption_table.do` | adoption table | table data parity |
| JEL002c | `scripts/Stata/2_stata_2x2.do` | 2x2 analysis | table/figure data parity |
| JEL002d | `scripts/Stata/3_stata_2xT.do` | 2xT analysis | table/figure data parity |
| JEL002e | `scripts/Stata/4_stata_GxT.do` | GxT analysis | table/figure data parity |
| JEL002f | `scripts/Stata/5_stata_honestdid.do` | sensitivity analysis context | run or explicitly document if test-only dependency unavailable |

## Tables

Full regenerated parity requires numeric table contents to compare under
TOL004. The full reproduction wrapper records table hash matches or
semantic numeric-token matches in
`build/jel-full-reproduction/outputs/artifact-comparison.csv`.

| ID | R artifact | Stata artifact | Acceptance test |
| --- | --- | --- | --- |
| JEL003 | `tables/table1_R.tex` | `tables/table1_stata.tex` | `tests/stata/jel/test-artifact-contract.do` |
| JEL004 | `tables/table2_R.tex` | `tables/table2_stata.tex` | `tests/stata/jel/test-artifact-contract.do` |
| JEL005 | `tables/table3_R.tex` | `tables/table3_stata.tex` | `tests/stata/jel/test-artifact-contract.do` |
| JEL006 | `tables/table4_R.tex` | `tables/table4_stata.tex` | `tests/stata/jel/test-artifact-contract.do` |
| JEL007 | `tables/table5_R.tex` | `tables/table5_stata.tex` | `tests/stata/jel/test-artifact-contract.do` |
| JEL008 | `tables/table6_R.tex` | `tables/table6_stata.tex` | `tests/stata/jel/test-artifact-contract.do` |
| JEL009 | `tables/table7_R.tex` | `tables/table7_stata.tex` | `tests/stata/jel/test-artifact-contract.do` |

## Figures

Full regenerated parity requires figure semantics to compare before accepting
rendered PDF drift. The full reproduction wrapper compares R/Stata displayed
labels for Figures 3, 8, and 9, preserves text/tick-token semantics for
regenerated Stata figures, and records rendered PDF drift as supporting
evidence rather than as the statistical oracle.

| ID | R artifact | Stata artifact | Acceptance test |
| --- | --- | --- | --- |
| JEL010 | `figures/figure1_R.pdf` | `figures/figure1_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` |
| JEL011 | `figures/figure2_R.pdf` | `figures/figure2_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` |
| JEL012 | `figures/figure3_R.pdf` | `figures/figure3_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` |
| JEL013 | `figures/figure4_R.pdf` | `figures/figure4_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` |
| JEL014 | `figures/figure5_R.pdf` | `figures/figure5_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` |
| JEL015 | `figures/figure6_R.pdf` | `figures/figure6_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` |
| JEL016 | `figures/figure7_R.pdf` | `figures/figure7_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` |
| JEL017 | `figures/figure8_R.pdf` | `figures/figure8_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` |
| JEL018 | `figures/figure9_R.pdf` | `figures/figure9_stata.pdf` | `tests/stata/jel/test-artifact-contract.do` |

## Current Artifact Audit

The default test gate for JEL001-JEL018 is
`tests/stata/jel/test-artifact-contract.do`. It verifies committed JEL script,
table, and PDF availability plus per-artifact links to the full reproduction
evidence under `tests/fixtures/jel/`. The full master-pipeline run remains
opt-in because it restores R dependencies, installs pinned Stata dependencies,
and runs 25,000-rep empirical scripts.

## Wrapper Policy

The implementation must not edit the upstream JEL scripts in place. Instead,
the test harness should run them through a wrapper that:

- sets `rootdir` to the local JEL checkout;
- redirects PLUS/PERSONAL/SITE ado paths to a temporary local tree;
- installs non-`csdid` dependencies only when JEL replication is explicitly
  enabled;
- places the new package before SSC `csdid` in the ado path;
- records generated table, figure, log, and data hashes.

## Highest-Risk JEL Checks

The first JEL smoke checks are Table 7, the 2xT event-study outputs, and GxT
plot data. These are most likely to expose covariate, event-time, aggregation,
and inference mismatches.
