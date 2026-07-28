version 15
clear all
set more off

local root "`c(pwd)'"

confirm file "`root'/tests/fixtures/parity/rt023/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt023/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt023/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt023/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt023/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt023/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 4
quietly count if coverage_status == "mapped"
assert r(N) == 0
quietly count if coverage_status == "approved-divergence"
assert r(N) == 4
quietly count if divergence_id == "RT023-DIV001"
assert r(N) == 4

import delimited using "`root'/tests/fixtures/parity/rt023/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "RT023-DIV001"
assert strpos(reason[1], "conditional-pretest helper internals") > 0
