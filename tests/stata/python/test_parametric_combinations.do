version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py017_assert_any_finite_att
    version 15
    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    quietly count if !missing(att)
    assert r(N) > 0
    quietly count if !missing(att) & abs(att) < .
    assert r(N) > 0
    restore
end

program define py017_assert_any_positive_se
    version 15
    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    quietly count if !missing(se) & se > 0
    assert r(N) > 0
    restore
end

program define py017_assert_simple
    version 15
    quietly csdid_stats, type(simple) na_rm
    matrix G = e(aggte)
    assert rowsof(G) == 1
    assert !missing(G[1, 4])
end

program define py017_assert_agg
    version 15
    syntax, TYPE(string) [POSITIVESE]

    quietly csdid_stats, type(`type') na_rm
    matrix G = e(aggte)
    assert rowsof(G) > 0
    preserve
    clear
    svmat double G, names(col)
    capture confirm variable overall_att
    if !_rc {
        quietly count if !missing(overall_att)
    }
    else {
        quietly count if !missing(att)
    }
    assert r(N) > 0
    if "`positivese'" != "" {
        capture confirm variable overall_se
        if !_rc {
            quietly count if !missing(overall_se) & overall_se > 0
        }
        else {
            quietly count if !missing(se) & se > 0
        }
        assert r(N) > 0
    }
    restore
end

program define py017_run_fit
    version 15
    syntax, INPUT(string) METHOD(string) CONTROL(string) BASE(string) PANEL(integer) ANTICIPation(integer) [WBOOT]

    import delimited using "`input'", clear asdouble
    local panelopt ""
    if `panel' local panelopt "ivar(id)"
    * States the never-treated arm explicitly; the omitted-option default is now not-yet-treated.
    local controlopt "nevertreated"
    if "`control'" == "notyettreated" local controlopt "notyet"
    local bootopt ""
    if "`wboot'" != "" local bootopt "wboot(reps(31) rseed(202617))"
    local inferopt "analytical"
    if "`wboot'" != "" local inferopt ""

    quietly csdid y x, `panelopt' time(period) gvar(g) method(`method') `inferopt' ///
        `controlopt' base_period(`base') anticipation(`anticipation') `bootopt' bal(none)
    if `panel' {
        assert "`e(panel_mode)'" == "panel"
    }
    else {
        assert "`e(panel_mode)'" == "repeated-cross-section"
    }
    assert "`e(method)'" == "`method'"
    assert "`e(control_group)'" == "`control'"
    assert "`e(base_period)'" == "`base'"
    assert e(anticipation) == `anticipation'
    if "`wboot'" != "" {
        assert e(bstrap) == 1
        assert e(biters) == 31
        matrix B = e(boot_attgt)
        preserve
        clear
        svmat double B, names(col)
        quietly count if !missing(se_boot) & se_boot > 0
        assert r(N) > 0
        restore
    }
end

confirm file "`root'/tests/fixtures/parity/py017/inputs/panel-data.csv"
confirm file "`root'/tests/fixtures/parity/py017/inputs/dynamic-data.csv"
confirm file "`root'/tests/fixtures/parity/py017/inputs/anticipation-data.csv"
confirm file "`root'/tests/fixtures/parity/py017/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py017/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py017/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py017/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py017/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 120
quietly count if coverage_status == "mapped"
assert r(N) == 120

local panel_input "`root'/tests/fixtures/parity/py017/inputs/panel-data.csv"
local dynamic_input "`root'/tests/fixtures/parity/py017/inputs/dynamic-data.csv"
local anticipation_input "`root'/tests/fixtures/parity/py017/inputs/anticipation-data.csv"

foreach method in dr reg ipw {
    foreach control in nevertreated notyettreated {
        foreach base in varying universal {
            py017_run_fit, input("`panel_input'") method(`method') control(`control') base(`base') panel(1) anticipation(0)
            py017_assert_any_finite_att
            py017_assert_any_positive_se
            py017_assert_simple
        }
    }
}

foreach method in dr reg ipw {
    foreach panel in 1 0 {
        py017_run_fit, input("`panel_input'") method(`method') control(nevertreated) base(varying) panel(`panel') anticipation(0)
        py017_assert_any_finite_att
        py017_assert_agg, type(dynamic)
    }
}

foreach ant in 0 1 2 {
    foreach method in dr reg ipw {
        py017_run_fit, input("`anticipation_input'") method(`method') control(nevertreated) base(varying) panel(1) anticipation(`ant')
        py017_assert_any_finite_att
        py017_assert_any_positive_se
    }
}

foreach method in dr reg ipw {
    py017_run_fit, input("`panel_input'") method(`method') control(nevertreated) base(varying) panel(1) anticipation(0)
    py017_assert_any_positive_se
    py017_assert_any_finite_att

    py017_run_fit, input("`panel_input'") method(`method') control(nevertreated) base(varying) panel(1) anticipation(0) wboot
    py017_assert_any_positive_se
    py017_assert_any_finite_att
}

foreach method in dr reg ipw {
    foreach control in nevertreated notyettreated {
        foreach base in varying universal {
            foreach panel in 1 0 {
                py017_run_fit, input("`panel_input'") method(`method') control(`control') base(`base') panel(`panel') anticipation(0)
                py017_assert_simple
            }
        }
    }
}

foreach aggtype in simple dynamic group calendar {
    foreach method in dr reg ipw {
        py017_run_fit, input("`panel_input'") method(`method') control(nevertreated) base(varying) panel(1) anticipation(0)
        py017_assert_agg, type(`aggtype') positivese
    }
}

foreach method in dr reg ipw {
    py017_run_fit, input("`dynamic_input'") method(`method') control(nevertreated) base(varying) panel(0) anticipation(0)
    quietly csdid_stats, type(dynamic) na_rm
    matrix D = e(aggte)
    preserve
    clear
    svmat double D, names(col)
    quietly count if egt >= 0 & !missing(att) & att > 0
    assert r(N) > 0
    restore

    py017_run_fit, input("`panel_input'") method(`method') control(nevertreated) base(varying) panel(1) anticipation(0)
    py017_assert_any_finite_att
    py017_run_fit, input("`panel_input'") method(`method') control(nevertreated) base(varying) panel(0) anticipation(0)
    py017_assert_any_finite_att
}

* ---------------------------------------------------------------------------
* PY017 R-oracle comparison (added 2026-07-27)
* The assertions above are "at least one ATT is finite" and "at least one SE is
* positive", which almost any implementation satisfies. This pins all three
* parametric grids against R: method x control x base, method x panel/RCS, and
* anticipation x method.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py017/expected/r/attgt.csv"
tempfile py017_actual
quietly {
    clear
    set obs 0
    gen str60 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`py017_actual'", replace emptyok
}
capture program drop py017_grab
program define py017_grab
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

local py017_panel "`root'/tests/fixtures/parity/py017/inputs/panel-data.csv"
local py017_ant   "`root'/tests/fixtures/parity/py017/inputs/anticipation-data.csv"
foreach method in dr reg ipw {
    foreach control in nevertreated notyettreated {
        foreach base in varying universal {
            * States the never-treated arm explicitly; the omitted-option default is now not-yet-treated.
            local cgopt "nevertreated"
            if "`control'" == "notyettreated" local cgopt "notyet"
            import delimited using "`py017_panel'", clear asdouble
            quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') `cgopt' base_period(`base') anticipation(0) analytical bal(none)
            py017_grab "g1_`method'_`control'_`base'" "`py017_actual'"
        }
    }
}
foreach method in dr reg ipw {
    import delimited using "`py017_panel'", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') base_period(varying) anticipation(0) analytical nevertreated bal(none)
    py017_grab "g2_`method'_panel" "`py017_actual'"
    import delimited using "`py017_panel'", clear asdouble
    quietly csdid y x, time(period) gvar(g) method(`method') base_period(varying) anticipation(0) analytical nevertreated bal(none)
    py017_grab "g2_`method'_rcs" "`py017_actual'"
}
foreach ant in 0 1 2 {
    foreach method in dr reg ipw {
        import delimited using "`py017_ant'", clear asdouble
        quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') base_period(varying) anticipation(`ant') analytical nevertreated bal(none)
        py017_grab "g3_`method'_`ant'" "`py017_actual'"
    }
}

import delimited using "`root'/tests/fixtures/parity/py017/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`py017_actual'", assert(match) nogen
quietly count
assert r(N) == 360
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "PY017 OK: 360 cells (27 scenarios across three parametric grids) match R to <1e-9"
