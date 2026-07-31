version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt012_assert_matrix_equal
    version 15
    args left right tol

    assert rowsof(`left') == rowsof(`right')
    assert colsof(`left') == colsof(`right')
    forvalues r = 1/`=rowsof(`left')' {
        forvalues c = 1/`=colsof(`left')' {
            scalar lval = `left'[`r', `c']
            scalar rval = `right'[`r', `c']
            assert missing(lval) == missing(rval)
            if !missing(lval) {
                assert abs(lval - rval) <= `tol' + `tol' * abs(lval)
            }
        }
    }
end

program define rt012_save_agg, eclass
    version 15
    syntax , TYPE(string) SAVING(string) [APPEND]

    csdid_stats, type(`type')
    matrix M = e(aggte)
    preserve
    clear
    svmat double M, names(col)
    gen str16 type = "`type'"
    gen seq = _n
    if "`append'" != "" append using "`saving'"
    save "`saving'", replace
    restore
end

program define rt012_collect_aggs
    version 15
    syntax , SAVING(string) [FAST NOFAST]

    tempfile part
    local fastopt ""
    if "`fast'" != "" local fastopt "fast"
    if "`nofast'" != "" local fastopt "nofast"
    local first 1
    foreach agg_type in simple dynamic group calendar {
        import delimited using "`c(pwd)'/tests/fixtures/parity/rt012/inputs/input.csv", clear asdouble
        quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) `fastopt' analytical nevertreated base_period(varying) bal(none)
        rt012_save_agg, type(`agg_type') saving("`part'")
        if `first' {
            use "`part'", clear
            save "`saving'", replace
            local first 0
        }
        else {
            use "`saving'", clear
            append using "`part'"
            save "`saving'", replace
        }
    }
end

confirm file "`root'/tests/fixtures/parity/rt012/inputs/input.csv"
confirm file "`root'/tests/fixtures/parity/rt012/inputs/input-unbalanced.csv"
confirm file "`root'/tests/fixtures/parity/rt012/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt012/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt012/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt012/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt012/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/rt012/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt012/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 40
quietly count if coverage_status == "mapped"
assert r(N) == 39
quietly count if coverage_status == "approved-divergence" & divergence_id == "RT012-DIV001"
assert r(N) == 1

import delimited using "`root'/tests/fixtures/parity/rt012/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "RT012-DIV001"

import delimited using "`root'/tests/fixtures/parity/rt012/inputs/input.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) notyet base_period(universal) nofast analytical bal(none)
matrix BasePanel = e(attgt)
assert e(fast_requested) == 0
assert e(fast_allowed) == 0

import delimited using "`root'/tests/fixtures/parity/rt012/inputs/input.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) notyet base_period(universal) fast analytical bal(none)
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-balanced-panel"
matrix FastPanel = e(attgt)
rt012_assert_matrix_equal BasePanel FastPanel 1e-9

import delimited using "`root'/tests/fixtures/parity/rt012/inputs/input.csv", clear asdouble
quietly csdid y x, time(period) gvar(g) method(ipw) base_period(varying) nofast analytical nevertreated bal(none)
matrix BaseRC = e(attgt)
import delimited using "`root'/tests/fixtures/parity/rt012/inputs/input.csv", clear asdouble
quietly csdid y x, time(period) gvar(g) method(ipw) base_period(varying) fast analytical nevertreated bal(none)
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-repeated-cross-section"
matrix FastRC = e(attgt)
rt012_assert_matrix_equal BaseRC FastRC 1e-9

import delimited using "`root'/tests/fixtures/parity/rt012/inputs/input-unbalanced.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(reg) notyet nofast analytical base_period(varying) bal(none)
matrix BaseUB = e(attgt)
import delimited using "`root'/tests/fixtures/parity/rt012/inputs/input-unbalanced.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(reg) notyet fast analytical base_period(varying) bal(none)
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-allow-unbalanced"
matrix FastUB = e(attgt)
rt012_assert_matrix_equal BaseUB FastUB 1e-9

import delimited using "`root'/tests/fixtures/parity/rt012/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) method(reg) nofast analytical nevertreated base_period(varying) bal(none)
matrix BaseNoCov = e(attgt)
import delimited using "`root'/tests/fixtures/parity/rt012/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) method(reg) fast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 1
assert e(fast_used) == 1
matrix FastNoCov = e(attgt)
rt012_assert_matrix_equal BaseNoCov FastNoCov 1e-10

tempfile base_agg fast_agg
rt012_collect_aggs, saving("`base_agg'") nofast
rt012_collect_aggs, saving("`fast_agg'") fast
use "`base_agg'", clear
rename (egt att se overall_att overall_se) (egt_base att_base se_base overall_att_base overall_se_base)
merge 1:1 type seq using "`fast_agg'", nogen assert(match)
foreach v in egt att se overall_att overall_se {
    assert missing(`v'_base) == missing(`v') if missing(`v'_base) | missing(`v')
    assert abs(`v'_base - `v') <= 1e-9 + 1e-9 * abs(`v'_base) if !missing(`v'_base)
}

* ---------------------------------------------------------------------------
* RT012 R-oracle comparison (added 2026-07-27)
* The assertions above prove the fast and baseline kernels agree with each other.
* Both being wrong in the same way would also satisfy that, so this pins the same
* five configurations against R.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/rt012/expected/r/attgt.csv"
tempfile rt012_actual
quietly {
    clear
    set obs 0
    gen str60 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`rt012_actual'", replace emptyok
}
capture program drop rt012_grab
program define rt012_grab
    args tag store
    tempname A
    matrix `A' = e(attgt)
    local nr = rowsof(`A')
    preserve
    quietly {
        clear
        set obs `nr'
        gen str60 scenario = "`tag'"
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

import delimited using "`root'/tests/fixtures/parity/rt012/inputs/input.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
rt012_grab "dr_panel" "`rt012_actual'"
import delimited using "`root'/tests/fixtures/parity/rt012/inputs/input.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) notyet base_period(universal) analytical bal(none)
rt012_grab "dr_notyet_universal" "`rt012_actual'"
import delimited using "`root'/tests/fixtures/parity/rt012/inputs/input.csv", clear asdouble
quietly csdid y x, time(period) gvar(g) method(ipw) base_period(varying) analytical nevertreated bal(none)
rt012_grab "ipw_rcs_varying" "`rt012_actual'"
import delimited using "`root'/tests/fixtures/parity/rt012/inputs/input-unbalanced.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(reg) notyet analytical base_period(varying) bal(none)
rt012_grab "reg_unbal_notyet" "`rt012_actual'"
import delimited using "`root'/tests/fixtures/parity/rt012/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
rt012_grab "reg_nox" "`rt012_actual'"

import delimited using "`root'/tests/fixtures/parity/rt012/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`rt012_actual'", assert(match) nogen
quietly count
assert r(N) == 63
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "RT012 OK: 63 cells (five fast/nofast configurations) match R to <1e-9"
