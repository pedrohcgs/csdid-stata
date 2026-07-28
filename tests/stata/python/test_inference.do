version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py012_assert_public_inference
    version 15
    syntax , METHOD(string) PANELMODE(string) TARGET(real) ATTTOL(real)

    local panelopt ""
    if "`panelmode'" == "panel" local panelopt "ivar(id)"

    import delimited using "`c(pwd)'/tests/fixtures/parity/py012/inputs/inference-data.csv", clear asdouble
    quietly csdid y x, `panelopt' time(period) gvar(g) method(`method') analytical
    assert "`e(method)'" == "`method'"
    assert "`e(panel_mode)'" == "`panelmode'"
    matrix A = e(attgt)
    matrix IF = e(inffunc)
    assert colsof(IF) == rowsof(A)
    if "`panelmode'" == "panel" {
        assert rowsof(IF) == e(N_units)
    }
    else {
        assert rowsof(IF) == e(N)
    }

    preserve
    clear
    svmat double A, names(col)
    quietly count if !missing(att) & !missing(se) & se > 0
    assert r(N) > 0
    restore

    quietly csdid_stats, type(simple) na_rm
    matrix S = e(aggte)
    assert rowsof(S) > 0
    assert S[1,5] > 0
    if "`panelmode'" == "panel" {
        assert abs(S[1,4] - `target') < `atttol'
    }

    if "`panelmode'" == "panel" {
        foreach agg_type in dynamic group calendar {
            quietly csdid_stats, type(`agg_type') na_rm
            matrix G = e(aggte)
            preserve
            clear
            svmat double G, names(col)
            quietly count if !missing(att) & !missing(se)
            assert r(N) > 0
            quietly count if !missing(att) & !missing(se) & se > 0
            assert r(N) > 0
            restore
        }
    }
end

program define py012_assert_bootstrap
    version 15
    syntax , METHOD(string) REPS(integer) RATIOMIN(real) RATIOMAX(real)

    import delimited using "`c(pwd)'/tests/fixtures/parity/py012/inputs/inference-data.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') analytical
    matrix A = e(attgt)

    import delimited using "`c(pwd)'/tests/fixtures/parity/py012/inputs/inference-data.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') wboot(reps(`reps') rseed(9012)) pointwise
    assert e(bstrap) == 1
    assert e(biters) == `reps'
    matrix B = e(boot_attgt)
    assert rowsof(B) == rowsof(A)
    forvalues i = 1/`=rowsof(A)' {
        assert abs(A[`i',4] - B[`i',4]) < 1e-10
    }

    preserve
    clear
    set obs `=rowsof(B)'
    generate double ratio = .
    forvalues i = 1/`=rowsof(B)' {
        replace ratio = B[`i',5] / B[`i',6] in `i' if B[`i',5] < . & B[`i',6] < . & B[`i',5] > 0 & B[`i',6] > 0
    }
    quietly count if !missing(ratio)
    assert r(N) > 0
    quietly summarize ratio, detail
    assert r(p50) > `ratiomin'
    assert r(p50) < `ratiomax'
    restore
end

confirm file "`root'/tests/fixtures/parity/py012/inputs/inference-data.csv"
confirm file "`root'/tests/fixtures/parity/py012/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py012/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py012/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py012/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py012/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 43
quietly count if coverage_status == "mapped"
assert r(N) == 43

import delimited using "`root'/tests/fixtures/parity/py012/expected/contract/scenarios.csv", clear varnames(1)
assert _N == 1
local reps = bootstrap_reps[1]
local ratio_min = bootstrap_ratio_min[1]
local ratio_max = bootstrap_ratio_max[1]
local target = overall_att_target[1]
local att_tol = overall_att_abs_tol[1]
local method_tol = method_att_abs_tol[1]

foreach method in dr reg ipw {
    py012_assert_public_inference, method(`method') panelmode(panel) target(`target') atttol(`att_tol')
    py012_assert_public_inference, method(`method') panelmode(repeated-cross-section) target(`target') atttol(`att_tol')
    py012_assert_bootstrap, method(`method') reps(`reps') ratiomin(`ratio_min') ratiomax(`ratio_max')
}

import delimited using "`root'/tests/fixtures/parity/py012/inputs/inference-data.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical
matrix DR = e(attgt)
import delimited using "`root'/tests/fixtures/parity/py012/inputs/inference-data.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(reg) analytical
matrix REG = e(attgt)
assert rowsof(DR) == rowsof(REG)
forvalues i = 1/`=rowsof(DR)' {
    assert abs(DR[`i',4] - REG[`i',4]) < `method_tol' if !missing(DR[`i',4]) & !missing(REG[`i',4])
}

* ---------------------------------------------------------------------------
* PY012 R-oracle comparison (added 2026-07-27)
* The assertions above compare against DGP-implied targets with loose tolerances
* and check dr-versus-reg agreement; they never compared against R. This pins
* the six analytical scenarios cell by cell.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py012/expected/r/attgt.csv"
tempfile py012_actual
quietly {
    clear
    set obs 0
    gen str32 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`py012_actual'", replace emptyok
}
capture program drop py012_grab
program define py012_grab
    args tag store
    tempname A
    matrix `A' = e(attgt)
    local nr = rowsof(`A')
    preserve
    quietly {
        clear
        set obs `nr'
        gen str32 scenario = "`tag'"
        gen double group = .
        gen double time = .
        gen double att_stata = .
        gen double se_stata = .
        forvalues i = 1/`nr' {
            replace group     = `A'[`i',1] in `i'
            replace time      = `A'[`i',2] in `i'
            replace att_stata = `A'[`i',4] in `i'
            replace se_stata  = `A'[`i',5] in `i'
        }
        append using "`store'"
        save "`store'", replace
    }
    restore
end

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/py012/inputs/inference-data.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') analytical
    py012_grab "panel_`method'" "`py012_actual'"
    import delimited using "`root'/tests/fixtures/parity/py012/inputs/inference-data.csv", clear asdouble
    quietly csdid y x, time(period) gvar(g) method(`method') analytical
    py012_grab "rcs_`method'" "`py012_actual'"
}

import delimited using "`root'/tests/fixtures/parity/py012/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`py012_actual'", assert(match) nogen
quietly count
assert r(N) == 54
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "PY012 OK: 54 cells (panel and RCS x three methods, analytical) match R to <1e-9"
