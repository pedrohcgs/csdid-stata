version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f011_count_log_contains, rclass
    version 15
    syntax using/, MESSAGE(string)

    tempname fh
    local body ""
    local count 0
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    local compact_body = subinstr(`"`body'"', " ", "", .)
    local compact_message = subinstr(`"`message'"', " ", "", .)
    local pos = strpos(`"`compact_body'"', `"`compact_message'"')
    while `pos' > 0 {
        local ++count
        local compact_body = substr(`"`compact_body'"', `pos' + strlen(`"`compact_message'"'), .)
        local pos = strpos(`"`compact_body'"', `"`compact_message'"')
    }
    return scalar count = `count'
end

tempfile allactual
local first 1

foreach scenario in numeric factor factor_dr factor_ipw interaction interaction_dr interaction_ipw square square_dr square_ipw rc_numeric rc_numeric_dr rc_numeric_ipw rc_factor rc_factor_dr rc_factor_ipw rc_interaction rc_interaction_dr rc_interaction_ipw rc_square rc_square_dr rc_square_ipw {
    import delimited using "`root'/tests/fixtures/parity/f011/inputs/input.csv", clear asdouble
    local method "reg"
    if strpos("`scenario'", "_dr") {
        local method "dr"
    }
    else if strpos("`scenario'", "_ipw") {
        local method "ipw"
    }

    local xspec "x1 x2"
    if "`scenario'" == "numeric" {
        local xspec "x1 x2"
    }
    else if strpos("`scenario'", "factor") == 1 {
        local xspec "i.f x1"
    }
    else if strpos("`scenario'", "interaction") == 1 {
        local xspec "c.x1##c.x2"
    }
    else if strpos("`scenario'", "square") == 1 {
        local xspec "c.x1#c.x1 x2"
    }
    else if strpos("`scenario'", "rc_numeric") {
        local xspec "x1 x2"
    }
    else if strpos("`scenario'", "rc_factor") {
        local xspec "i.f x1"
    }
    else if strpos("`scenario'", "rc_interaction") {
        local xspec "c.x1##c.x2"
    }
    else {
        local xspec "c.x1#c.x1 x2"
    }

    if strpos("`scenario'", "rc_") == 1 {
        csdid y `xspec', time(time) gvar(g) method(`method') analytical
    }
    else {
        csdid y `xspec', ivar(id) time(time) gvar(g) method(`method') analytical
    }
    if strpos("`scenario'", "rc_") == 1 {
        assert "`e(idvar)'" == ""
        assert "`e(panel_mode)'" == "repeated-cross-section"
    }
    else {
        assert e(idvar) == "id"
        assert "`e(panel_mode)'" == "panel"
    }
    assert "`e(method)'" == "`method'"
    matrix A = e(attgt)
    clear
    svmat double A, names(col)
    gen str24 scenario = "`scenario'"
    gen str8 est_method = "`method'"
    rename (att se) (att_stata se_stata)
    keep scenario est_method group time event_time att_stata se_stata
    if `first' {
        save "`allactual'", replace
        local first 0
    }
    else {
        append using "`allactual'"
        save "`allactual'", replace
    }
}

import delimited using "`root'/tests/fixtures/parity/f011/expected/r/covariate-grid.csv", clear asdouble
merge 1:1 scenario est_method group time using "`allactual'", nogen assert(match)
assert abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att)
assert !missing(se)
assert abs(se - se_stata) <= 1e-10 + 1e-10 * abs(se)

tempfile denseactual
local first 1
foreach panel_mode in panel repeated-cross-section {
    foreach covariate_spec in factor dummy {
        foreach method in dr reg ipw {
            import delimited using "`root'/tests/fixtures/parity/f011/inputs/input.csv", clear asdouble
            if "`covariate_spec'" == "factor" {
                local xspec "i.f x1"
            }
            else {
                local xspec "f_2 f_3 x1"
            }

            if "`panel_mode'" == "panel" {
                csdid y `xspec', ivar(id) time(time) gvar(g) method(`method') analytical
                assert "`e(panel_mode)'" == "panel"
            }
            else {
                csdid y `xspec', time(time) gvar(g) method(`method') analytical
                assert "`e(panel_mode)'" == "repeated-cross-section"
            }
            assert "`e(method)'" == "`method'"
            matrix A = e(attgt)
            clear
            svmat double A, names(col)
            generate str24 panel_mode = "`panel_mode'"
            generate str8 covariate_spec = "`covariate_spec'"
            generate str8 method = "`method'"
            rename (event_time att se) (event_time_stata att_stata se_stata)
            keep panel_mode covariate_spec method group time event_time_stata att_stata se_stata
            if `first' {
                save "`denseactual'", replace
                local first 0
            }
            else {
                append using "`denseactual'"
                save "`denseactual'", replace
            }
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/f011/expected/r/dense-factor-dummy-grid.csv", clear asdouble
merge 1:1 panel_mode covariate_spec method group time using "`denseactual'", nogen assert(match)
assert event_time == event_time_stata
assert abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att)
assert !missing(se)
assert abs(se - se_stata) <= 1e-10 + 1e-10 * abs(se)

preserve
keep panel_mode method group time covariate_spec att_stata se_stata
keep if covariate_spec == "factor"
rename (att_stata se_stata) (att_factor se_factor)
drop covariate_spec
tempfile densefactor
save "`densefactor'", replace
restore
keep panel_mode method group time covariate_spec att_stata se_stata
keep if covariate_spec == "dummy"
merge 1:1 panel_mode method group time using "`densefactor'", nogen assert(match)
assert abs(att_stata - att_factor) <= 1e-12 + 1e-12 * abs(att_factor)
assert abs(se_stata - se_factor) <= 1e-12 + 1e-12 * abs(se_factor)

tempfile sparseactual sparseevents sparselog
local first 1
local firstevent 1
foreach panel_mode in panel repeated-cross-section {
    foreach covariate_spec in factor dummy {
        import delimited using "`root'/tests/fixtures/parity/f011/inputs/sparse-factor.csv", clear asdouble
        if "`covariate_spec'" == "factor" {
            local xspec "i.fac"
        }
        else {
            local xspec "f_b"
        }

        capture log close f011sparse
        log using "`sparselog'", text replace name(f011sparse)
        if "`panel_mode'" == "panel" {
            capture noisily csdid y `xspec', ivar(id) time(period) gvar(g) method(reg) analytical
        }
        else {
            capture noisily csdid y `xspec', time(period) gvar(g) method(reg) analytical
        }
        local actual_rc = _rc
        log close f011sparse
        assert `actual_rc' == 0
        assert "`e(method)'" == "reg"
        if "`panel_mode'" == "panel" {
            assert "`e(panel_mode)'" == "panel"
        }
        else {
            assert "`e(panel_mode)'" == "repeated-cross-section"
        }

        f011_count_log_contains using "`sparselog'", message("singular or numerically ill-conditioned")
        local singular_count = r(count)
        f011_count_log_contains using "`sparselog'", message("Error computing internal 2x2 DiD")
        assert r(count) == 0

        matrix A = e(attgt)
        clear
        svmat double A, names(col)
        generate str24 panel_mode = "`panel_mode'"
        generate str8 covariate_spec = "`covariate_spec'"
        generate byte att_missing_stata = missing(att)
        generate byte se_missing_stata = missing(se)
        rename (event_time att se) (event_time_stata att_stata se_stata)
        keep panel_mode covariate_spec group time event_time_stata att_stata se_stata att_missing_stata se_missing_stata
        if `first' {
            save "`sparseactual'", replace
            local first 0
        }
        else {
            append using "`sparseactual'"
            save "`sparseactual'", replace
        }

        clear
        set obs 1
        generate str24 panel_mode = "`panel_mode'"
        generate str8 covariate_spec = "`covariate_spec'"
        generate str32 event_key = "singular_control_matrix"
        generate double singular_count_stata = `singular_count'
        if `firstevent' {
            save "`sparseevents'", replace
            local firstevent 0
        }
        else {
            append using "`sparseevents'"
            save "`sparseevents'", replace
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/f011/expected/r/sparse-factor-grid.csv", clear asdouble
merge 1:1 panel_mode covariate_spec group time using "`sparseactual'", nogen assert(match)
assert event_time == event_time_stata
assert att_missing == att_missing_stata
assert se_missing == se_missing_stata
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
assert missing(att) | abs(att - att_stata) <= 1e-10 + 1e-10 * abs(att)
assert missing(se) | abs(se - se_stata) <= 1e-10 + 1e-10 * abs(se)

import delimited using "`root'/tests/fixtures/parity/f011/expected/r/sparse-factor-events.csv", clear varnames(1)
merge 1:1 panel_mode covariate_spec event_key using "`sparseevents'", nogen assert(match)
assert expected_count == singular_count_stata
