version 15
clear all
set more off

local root "`c(pwd)'"

confirm file "`root'/tests/fixtures/parity/py014/expected/contract/scenario-coverage.csv"
confirm file "`root'/tests/fixtures/parity/py014/expected/contract/source-audit.csv"
confirm file "`root'/tests/fixtures/parity/py014/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py014/expected/contract/scenario-coverage.csv", clear varnames(1) stringcols(_all)
assert _N == 6
assert matrix_id == "PY014"
assert source_kind == "python-test-map"
assert source_test_path == "csdid/test_csdid/test_jel_replication.py"
assert python_test_path == "csdid/test_csdid/test_jel_replication.py"
assert coverage_status == "covered"
assert inlist(stata_gate, "F040", "F041", "F042", "F043")

import delimited using "`root'/tests/fixtures/parity/py014/expected/contract/source-audit.csv", clear varnames(1) stringcols(_all)
quietly count if source == "python-csdid" & inlist(status, "available", "absent-in-available-checkout")
assert r(N) == 1
