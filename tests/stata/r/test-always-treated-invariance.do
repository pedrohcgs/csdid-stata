version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt004_save_att
    version 15
    syntax using/, SAVING(string) [DROPGROUP(real -999999) SCALEGROUP(real -999999) SCALEFACTOR(real 1) NOTYET ANTICIPATION(integer 0) FAST METHOD(string)]

    if "`method'" == "" local method "dr"
    import delimited using "`using'", clear asdouble
    if `dropgroup' != -999999 {
        drop if g == `dropgroup'
    }
    if `scalegroup' != -999999 {
        replace y = y * `scalefactor' if g == `scalegroup'
    }

    quietly csdid y, ivar(uid) time(t) gvar(g) method(`method') `notyet' analytical ///
        anticipation(`anticipation') `fast' bal(none)
    matrix ATT = e(attgt)
    clear
    svmat double ATT, names(col)
    keep group time att
    save "`saving'", replace
end

program define rt004_assert_common_att_equal
    version 15
    syntax, BASE(string) USING(string) TOL(real)

    use "`base'", clear
    keep group time att
    rename att att_base
    merge 1:1 group time using "`using'", keep(match) nogen
    assert _N > 0
    assert missing(att_base) == missing(att)
    assert abs(att_base - att) <= `tol' + `tol' * abs(att_base) if !missing(att_base)
end

confirm file "`root'/tests/fixtures/parity/rt004/inputs/p1.csv"
confirm file "`root'/tests/fixtures/parity/rt004/inputs/p2.csv"
confirm file "`root'/tests/fixtures/parity/rt004/inputs/p3.csv"
confirm file "`root'/tests/fixtures/parity/rt004/inputs/fastslow.csv"
confirm file "`root'/tests/fixtures/parity/rt004/inputs/structural.csv"
confirm file "`root'/tests/fixtures/parity/rt004/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt004/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt004/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/rt004/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt004/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 10
quietly count if coverage_status == "mapped"
assert r(N) == 10

import delimited using "`root'/tests/fixtures/parity/rt004/expected/contract/scenarios.csv", clear varnames(1) stringcols(_all)
assert _N == 7

foreach method in dr reg ipw {
    foreach mode in baseline fast {
        tempfile full drop
        local fastopt ""
        if "`mode'" == "fast" local fastopt "fast"
        rt004_save_att using "`root'/tests/fixtures/parity/rt004/inputs/p1.csv", ///
            saving("`full'") method(`method') notyet `fastopt'
        rt004_save_att using "`root'/tests/fixtures/parity/rt004/inputs/p1.csv", ///
            saving("`drop'") method(`method') notyet dropgroup(1) `fastopt'
        rt004_assert_common_att_equal, base("`full'") using("`drop'") tol(1e-8)
    }
}

foreach mode in baseline fast {
    tempfile full drop
    local fastopt ""
    if "`mode'" == "fast" local fastopt "fast"
    rt004_save_att using "`root'/tests/fixtures/parity/rt004/inputs/p2.csv", ///
        saving("`full'") notyet anticipation(1) `fastopt'
    rt004_save_att using "`root'/tests/fixtures/parity/rt004/inputs/p2.csv", ///
        saving("`drop'") notyet anticipation(1) dropgroup(2) `fastopt'
    rt004_assert_common_att_equal, base("`full'") using("`drop'") tol(1e-8)
}

foreach mode in baseline fast {
    tempfile full drop
    local fastopt ""
    if "`mode'" == "fast" local fastopt "fast"
    rt004_save_att using "`root'/tests/fixtures/parity/rt004/inputs/p3.csv", ///
        saving("`full'") notyet anticipation(1) `fastopt'
    rt004_save_att using "`root'/tests/fixtures/parity/rt004/inputs/p3.csv", ///
        saving("`drop'") notyet anticipation(1) dropgroup(2) `fastopt'
    rt004_assert_common_att_equal, base("`full'") using("`drop'") tol(1e-8)
}

tempfile base scaled
rt004_save_att using "`root'/tests/fixtures/parity/rt004/inputs/p1.csv", ///
    saving("`base'") notyet
rt004_save_att using "`root'/tests/fixtures/parity/rt004/inputs/p1.csv", ///
    saving("`scaled'") notyet scalegroup(1) scalefactor(1000000)
rt004_assert_common_att_equal, base("`base'") using("`scaled'") tol(1e-8)

tempfile slow fast
rt004_save_att using "`root'/tests/fixtures/parity/rt004/inputs/fastslow.csv", ///
    saving("`slow'") notyet
rt004_save_att using "`root'/tests/fixtures/parity/rt004/inputs/fastslow.csv", ///
    saving("`fast'") notyet fast
rt004_assert_common_att_equal, base("`slow'") using("`fast'") tol(1e-10)

import delimited using "`root'/tests/fixtures/parity/rt004/inputs/structural.csv", clear asdouble
quietly csdid y, ivar(uid) time(t) gvar(g) method(dr) notyet analytical base_period(varying) bal(none)
matrix ATT = e(attgt)
matrix GP = e(group_prob)
matrix UG = e(unit_group)

preserve
clear
svmat double UG, names(col)
quietly count if group == 5
assert r(N) > 0
quietly count if group == 1
assert r(N) == 0
restore

preserve
clear
svmat double GP, names(col)
quietly count if group == 5
assert r(N) == 0
quietly count if group == 1
assert r(N) == 0
restore

preserve
clear
svmat double ATT, names(col)
quietly count if group == 5
assert r(N) == 0
quietly count if group == 1
assert r(N) == 0
quietly count if !missing(att)
assert r(N) > 0
restore

tempfile nt_full nt_drop
rt004_save_att using "`root'/tests/fixtures/parity/rt004/inputs/p1.csv", ///
    saving("`nt_full'")
rt004_save_att using "`root'/tests/fixtures/parity/rt004/inputs/p1.csv", ///
    saving("`nt_drop'") dropgroup(1)
rt004_assert_common_att_equal, base("`nt_full'") using("`nt_drop'") tol(1e-8)

* ---------------------------------------------------------------------------
* RT004 R-oracle comparison (added 2026-07-27)
* The assertions above check an INVARIANCE -- rescaling one cohort's outcome must
* leave the other cohorts' ATT unchanged -- which is self-referential and holds
* even if every value is wrong. This pins the base runs against R.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/rt004/expected/r/attgt.csv"
tempfile rt004_actual
quietly {
    clear
    set obs 0
    gen str60 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`rt004_actual'", replace emptyok
}
capture program drop rt004_grab
program define rt004_grab
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

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/rt004/inputs/p1.csv", clear asdouble
    quietly csdid y, ivar(uid) time(t) gvar(g) method(`method') analytical nevertreated base_period(varying) bal(none)
    rt004_grab "p1_`method'" "`rt004_actual'"
    import delimited using "`root'/tests/fixtures/parity/rt004/inputs/structural.csv", clear asdouble
    quietly csdid y, ivar(uid) time(t) gvar(g) method(`method') analytical nevertreated base_period(varying) bal(none)
    rt004_grab "structural_`method'" "`rt004_actual'"
}
import delimited using "`root'/tests/fixtures/parity/rt004/inputs/structural.csv", clear asdouble
quietly csdid y, ivar(uid) time(t) gvar(g) method(dr) notyet analytical base_period(varying) bal(none)
rt004_grab "structural_notyet_dr" "`rt004_actual'"
import delimited using "`root'/tests/fixtures/parity/rt004/inputs/fastslow.csv", clear asdouble
quietly csdid y, ivar(uid) time(t) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
rt004_grab "fastslow_dr" "`rt004_actual'"

import delimited using "`root'/tests/fixtures/parity/rt004/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`rt004_actual'", assert(match) nogen
quietly count
assert r(N) == 57
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "RT004 OK: 57 cells (always-treated-invariance designs) match R to <1e-9"
