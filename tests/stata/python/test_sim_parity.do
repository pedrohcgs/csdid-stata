version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

foreach dataset in tp2_const tp4_const tp4_dyn tp5_dyn tp8_dyn tp10_const {
    confirm file "`root'/tests/fixtures/parity/py021/inputs/`dataset'.csv"
}
confirm file "`root'/tests/fixtures/parity/py021/expected/r/ref_sim.csv"
confirm file "`root'/tests/fixtures/parity/py021/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py021/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py021/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py021/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py021/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 24
quietly count if coverage_status == "mapped"
assert r(N) == 24
quietly count if divergence_id != ""
assert r(N) == 0

tempfile actual
local first 1
foreach dataset in tp2_const tp4_const tp4_dyn tp5_dyn tp8_dyn tp10_const {
    foreach control in nevertreated notyettreated {
        local ctrlopt ""
        if "`control'" == "notyettreated" local ctrlopt "notyet"
        foreach est in dr reg {
            import delimited using "`root'/tests/fixtures/parity/py021/inputs/`dataset'.csv", clear asdouble
            quietly csdid y x, ivar(id) time(period) gvar(g) method(`est') `ctrlopt' analytical
            matrix A = e(attgt)
            preserve
            clear
            svmat double A, names(col)
            gen str16 dataset = "`dataset'"
            gen str16 control = "`control'"
            gen str8 est = "`est'"
            rename time t
            rename (att se) (att_stata se_stata)
            keep dataset control est group t att_stata se_stata
            if `first' {
                save "`actual'", replace
                local first 0
            }
            else {
                append using "`actual'"
                save "`actual'", replace
            }
            restore
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/py021/expected/r/ref_sim.csv", clear asdouble
merge 1:1 dataset control est group t using "`actual'", nogen assert(match)

assert abs(att - att_stata) <= 1e-6
assert abs(se - se_stata) <= 1e-3 + 0.05 * abs(se)

egen scenario = group(dataset control est)
levelsof scenario, local(scenarios)
foreach s of local scenarios {
    quietly count if scenario == `s'
    assert r(N) > 0
}
