version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt021_assert_agg_output
    version 15
    syntax, TYPE(string)

    csdid_stats, type(`type')
    matrix G = e(aggte)
    assert rowsof(G) > 0
    csdid_estat attgt
    tempfile tidy glance
    csdid_estat tidy, saving("`tidy'") replace
    confirm file "`tidy'"
    preserve
    use "`tidy'", clear
    assert _N > 0
    restore
    csdid_estat glance, saving("`glance'") replace
    confirm file "`glance'"
    preserve
    use "`glance'", clear
    assert _N == 1
    restore
end

confirm file "`root'/tests/fixtures/parity/rt021/inputs/output-methods.csv"
confirm file "`root'/tests/fixtures/parity/rt021/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt021/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt021/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt021/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt021/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/rt021/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt021/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 5
quietly count if coverage_status == "mapped"
assert r(N) == 2
quietly count if coverage_status == "approved-divergence"
assert r(N) == 3

import delimited using "`root'/tests/fixtures/parity/rt021/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 3
quietly count if divergence_id == "RT021-DIV001"
assert r(N) == 1
quietly count if divergence_id == "RT021-DIV002"
assert r(N) == 1
quietly count if divergence_id == "RT021-DIV003"
assert r(N) == 1

import delimited using "`root'/tests/fixtures/parity/rt021/inputs/output-methods.csv", clear asdouble
csdid y x, ivar(id) time(period) gvar(g) method(dr) wboot(reps(25) rseed(20262101))
assert e(bstrap) == 1
foreach type in simple group dynamic calendar {
    rt021_assert_agg_output, type(`type')
}

foreach method in dr ipw reg {
    import delimited using "`root'/tests/fixtures/parity/rt021/inputs/output-methods.csv", clear asdouble
    csdid y x, ivar(id) time(period) gvar(g) method(`method') notyet analytical
    assert "`e(control_group)'" == "notyettreated"
    csdid_stats, type(dynamic)
    matrix G = e(aggte)
    assert rowsof(G) > 0
    tempfile gl
    csdid_estat glance, saving("`gl'") replace
    confirm file "`gl'"
}

* ---------------------------------------------------------------------------
* RT021 R-oracle comparison (added 2026-07-27)
* The assertions above check structure and loose bounds; they never compared a
* value against R. This pins every cell of the scenarios below.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/rt021/expected/r/attgt.csv"
tempfile rt021_actual
quietly {
    clear
    set obs 0
    gen str32 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`rt021_actual'", replace emptyok
}
capture program drop rt021_grab
program define rt021_grab
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

foreach method in dr ipw reg {
    import delimited using "`root'/tests/fixtures/parity/rt021/inputs/output-methods.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') notyet analytical
    rt021_grab "`method'" "`rt021_actual'"
}

import delimited using "`root'/tests/fixtures/parity/rt021/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`rt021_actual'", assert(match) nogen
quietly count
assert r(N) == 27
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "RT021 OK: 27 cells (three methods, not-yet-treated) match R to <1e-9"
