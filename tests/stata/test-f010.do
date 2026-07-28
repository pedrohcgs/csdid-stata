version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

tempfile actual allactual
local first 1
foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/f010/inputs/input.csv", clear asdouble
    csdid y, ivar(id) time(time) gvar(g) method(`method') analytical
    matrix A = e(attgt)
    clear
    svmat double A, names(col)
    gen str8 method = "`method'"
    rename (att se) (att_stata se_stata)
    keep method group time event_time att_stata se_stata
    if `first' {
        save "`allactual'", replace
        local first 0
    }
    else {
        append using "`allactual'"
        save "`allactual'", replace
    }
}

import delimited using "`root'/tests/fixtures/parity/f010/expected/r/method-grid.csv", clear asdouble
merge 1:1 method group time using "`allactual'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert !missing(se)
assert abs(se - se_stata) < 1e-8

tempfile allactual_cov
local first 1
foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/f010/inputs/input.csv", clear asdouble
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(`method') analytical
    matrix A = e(attgt)
    clear
    svmat double A, names(col)
    gen str8 method = "`method'"
    rename (att se) (att_stata se_stata)
    keep method group time event_time att_stata se_stata
    if `first' {
        save "`allactual_cov'", replace
        local first 0
    }
    else {
        append using "`allactual_cov'"
        save "`allactual_cov'", replace
    }
}

import delimited using "`root'/tests/fixtures/parity/f010/expected/r/covariate-method-grid.csv", clear asdouble
merge 1:1 method group time using "`allactual_cov'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert !missing(se)
assert abs(se - se_stata) < 1e-8

tempfile allactual_rc
local first 1
foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/f010/inputs/input.csv", clear asdouble
    csdid y, time(time) gvar(g) method(`method') analytical
    assert "`e(idvar)'" == ""
    assert "`e(panel_mode)'" == "repeated-cross-section"
    matrix A = e(attgt)
    clear
    svmat double A, names(col)
    gen str8 method = "`method'"
    gen str24 panel_mode_stata = "repeated-cross-section"
    rename (att se) (att_stata se_stata)
    keep method group time event_time att_stata se_stata panel_mode_stata
    if `first' {
        save "`allactual_rc'", replace
        local first 0
    }
    else {
        append using "`allactual_rc'"
        save "`allactual_rc'", replace
    }
}

import delimited using "`root'/tests/fixtures/parity/f010/expected/r/rc-method-grid.csv", clear asdouble
merge 1:1 method group time using "`allactual_rc'", nogen assert(match)
assert panel_mode == panel_mode_stata
assert abs(att - att_stata) < 1e-10
assert !missing(se)
assert abs(se - se_stata) < 1e-8

tempfile allactual_rc_cov
local first 1
foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/f010/inputs/input.csv", clear asdouble
    csdid y x1 x2, time(time) gvar(g) method(`method') analytical
    assert "`e(idvar)'" == ""
    assert "`e(panel_mode)'" == "repeated-cross-section"
    matrix A = e(attgt)
    clear
    svmat double A, names(col)
    gen str8 method = "`method'"
    gen str24 panel_mode_stata = "repeated-cross-section"
    rename (att se) (att_stata se_stata)
    keep method group time event_time att_stata se_stata panel_mode_stata
    if `first' {
        save "`allactual_rc_cov'", replace
        local first 0
    }
    else {
        append using "`allactual_rc_cov'"
        save "`allactual_rc_cov'", replace
    }
}

import delimited using "`root'/tests/fixtures/parity/f010/expected/r/rc-covariate-method-grid.csv", clear asdouble
merge 1:1 method group time using "`allactual_rc_cov'", nogen assert(match)
assert panel_mode == panel_mode_stata
assert abs(att - att_stata) < 1e-10
assert !missing(se)
assert abs(se - se_stata) < 1e-8

tempfile allactual_control
local first_control 1
foreach panel_mode in panel repeated-cross-section {
    foreach covariates in none numeric {
        foreach control_group in nevertreated notyettreated {
            local cgopt ""
            if "`control_group'" == "notyettreated" local cgopt "notyet"
            foreach method in dr reg ipw {
                import delimited using "`root'/tests/fixtures/parity/f010/inputs/input-staggered.csv", clear asdouble
                if "`panel_mode'" == "panel" & "`covariates'" == "numeric" {
                    csdid y x1 x2, ivar(id) time(time) gvar(g) method(`method') `cgopt' analytical
                }
                else if "`panel_mode'" == "panel" {
                    csdid y, ivar(id) time(time) gvar(g) method(`method') `cgopt' analytical
                }
                else if "`covariates'" == "numeric" {
                    csdid y x1 x2, time(time) gvar(g) method(`method') `cgopt' analytical
                }
                else {
                    csdid y, time(time) gvar(g) method(`method') `cgopt' analytical
                }
                assert "`e(panel_mode)'" == "`panel_mode'"
                assert "`e(control_group)'" == "`control_group'"
                assert "`e(method)'" == "`method'"
                matrix A = e(attgt)
                clear
                svmat double A, names(col)
                gen str24 panel_mode = "`panel_mode'"
                gen str12 covariates = "`covariates'"
                gen str16 control_group = "`control_group'"
                gen str8 method = "`method'"
                rename (event_time att se) (event_time_stata att_stata se_stata)
                keep panel_mode covariates control_group method group time event_time_stata att_stata se_stata
                if `first_control' {
                    save "`allactual_control'", replace
                    local first_control 0
                }
                else {
                    append using "`allactual_control'"
                    save "`allactual_control'", replace
                }
            }
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/f010/expected/r/control-method-grid.csv", clear asdouble
merge 1:1 panel_mode covariates control_group method group time using "`allactual_control'", nogen assert(match)
assert event_time == event_time_stata
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
assert abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att) if !missing(att)
assert abs(se - se_stata) <= 1e-8 + 1e-8 * abs(se) if !missing(se)

import delimited using "`root'/tests/fixtures/parity/f010/inputs/input.csv", clear asdouble
capture noisily csdid y, time(time) gvar(g) method(bad) analytical
assert _rc == 198

foreach badmethod in drimp aipw {
    import delimited using "`root'/tests/fixtures/parity/f010/inputs/input.csv", clear asdouble
    capture noisily csdid y, time(time) gvar(g) method(`badmethod') analytical
    assert _rc == 198
}

foreach alias in dripw stdipw {
    if "`alias'" == "dripw" {
        local canonical "dr"
    }
    else {
        local canonical "ipw"
    }

    import delimited using "`root'/tests/fixtures/parity/f010/inputs/input.csv", clear asdouble
    quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(`canonical') analytical
    matrix C = e(attgt)

    import delimited using "`root'/tests/fixtures/parity/f010/inputs/input.csv", clear asdouble
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(`alias') analytical
    assert "`e(method)'" == "`canonical'"
    assert "`e(method_requested)'" == "`alias'"
    matrix A = e(attgt)
    assert mreldif(A, C) < 1e-14
}
