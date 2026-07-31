version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

confirm file "`root'/tests/fixtures/parity/rt005/inputs/sim-data.csv"
confirm file "`root'/tests/fixtures/parity/rt005/inputs/two-period.csv"
confirm file "`root'/tests/fixtures/parity/rt005/inputs/dynamic.csv"
confirm file "`root'/tests/fixtures/parity/rt005/inputs/dynamic-rc.csv"
confirm file "`root'/tests/fixtures/parity/rt005/inputs/unequal-periods.csv"
confirm file "`root'/tests/fixtures/parity/rt005/inputs/anticipation.csv"
confirm file "`root'/tests/fixtures/parity/rt005/inputs/unbalanced.csv"
confirm file "`root'/tests/fixtures/parity/rt005/inputs/no-never.csv"
confirm file "`root'/tests/fixtures/parity/rt005/inputs/small-groups.csv"
confirm file "`root'/tests/fixtures/parity/rt005/inputs/fixweights.csv"
confirm file "`root'/tests/fixtures/parity/rt005/inputs/fixweights-constant.csv"
confirm file "`root'/tests/fixtures/parity/rt005/inputs/fixweights-unbalanced.csv"
confirm file "`root'/tests/fixtures/parity/rt005/inputs/nonconsecutive.csv"
confirm file "`root'/tests/fixtures/parity/rt005/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt005/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt005/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt005/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt005/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/rt005/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt005/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 46
quietly count if coverage_status == "mapped"
assert r(N) == 44
quietly count if coverage_status == "approved-divergence"
assert r(N) == 2
quietly count if divergence_id == "RT005-DIV001"
assert r(N) == 1
quietly count if divergence_id == "RT005-DIV002"
assert r(N) == 1

import delimited using "`root'/tests/fixtures/parity/rt005/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 2
quietly count if strpos(reason, "function-valued est_method") > 0
assert r(N) == 1
quietly count if strpos(reason, "custom estimator callback") > 0
assert r(N) >= 1

do "`root'/tests/stata/python/test_att_gt.do"
