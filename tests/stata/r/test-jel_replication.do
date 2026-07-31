version 15
clear all
set more off

local root "`c(pwd)'"

confirm file "`root'/tests/fixtures/parity/rt016/expected/contract/scenario-coverage.csv"
confirm file "`root'/tests/fixtures/parity/rt016/expected/contract/source-audit.csv"
confirm file "`root'/tests/fixtures/parity/rt016/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt016/expected/contract/scenario-coverage.csv", clear varnames(1) stringcols(_all)
assert _N == 6
assert matrix_id == "RT016"
assert source_kind == "r-test-map"
assert source_test_path == "tests/testthat/test-jel_replication.R"
assert coverage_status == "covered"
assert inlist(stata_gate, "F040", "F041", "F042", "F043")
quietly count if scenario_id == "jel_2xt_attgt_no_covariates" & stata_gate == "F042"
assert r(N) == 1
quietly count if scenario_id == "jel_faster_mode_table7_dr_weighted" & stata_gate == "F040"
assert r(N) == 1

import delimited using "`root'/tests/fixtures/parity/rt016/expected/contract/source-audit.csv", clear varnames(1) stringcols(_all)
quietly count if source == "r-did" & status == "available"
assert r(N) == 1
