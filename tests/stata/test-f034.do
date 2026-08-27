version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

confirm file "`root'/tests/fixtures/parity/f034/expected/new-stata/saverif-schema.json"
confirm file "`root'/tests/fixtures/parity/f034/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/f034/expected/contract/approved-divergence.json"

import delimited using "`root'/tests/fixtures/parity/f034/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "F034-DIV001"

tempfile allactual
local first 1

foreach scenario in panel_reg rc_reg {
    import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", clear asdouble
    tempfile rif
    if "`scenario'" == "panel_reg" {
        csdid y, ivar(id) time(time) gvar(g) method(reg) saverif("`rif'") replace analytical nevertreated base_period(varying) bal(none)
        assert "`e(rif_file)'" == "`rif'"
    }
    else {
        csdid y, time(time) gvar(g) method(reg) saverif("`rif'") replace analytical nevertreated base_period(varying) bal(none)
        assert "`e(rif_file)'" == "`rif'"
    }
    confirm file "`rif'"

    foreach agg_type in simple group calendar dynamic {
        tempname direct reload
        import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", clear asdouble
        if "`scenario'" == "panel_reg" {
            csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
        }
        else {
            csdid y, time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
        }
        csdid_stats, type(`agg_type')
        matrix `direct' = e(aggte)
        ereturn clear
        csdid_stats using "`rif'", type(`agg_type')
        matrix `reload' = e(aggte)
        assert "`e(rif_file)'" == "`rif'"
        assert "`e(agg_type)'" == "`agg_type'"
        assert rowsof(`direct') == rowsof(`reload')
        assert colsof(`direct') == colsof(`reload')
        forvalues rr = 1/`=rowsof(`direct')' {
            forvalues cc = 1/`=colsof(`direct')' {
                if missing(`direct'[`rr', `cc']) | missing(`reload'[`rr', `cc']) {
                    assert missing(`direct'[`rr', `cc']) == missing(`reload'[`rr', `cc'])
                }
                else {
                    assert abs(`direct'[`rr', `cc'] - `reload'[`rr', `cc']) <= 1e-10
                }
            }
        }
    }

    capture noisily csdid y, time(time) gvar(g) method(reg) saverif("`rif'") analytical nevertreated base_period(varying) bal(none)
    assert _rc == 602

    use "`rif'", clear
    unab vars : _all
    assert "`vars'" == "rif_row id group weight rif1 rif2 rif3 rif4 rif5 rif6 __csdid_meta"
    assert weight == 1
    assert "`: char _dta[csdid_artifact]'" == "rif"
    assert "`: char _dta[csdid_control_group]'" == "nevertreated"
    assert "`: char _dta[csdid_base_period]'" == "varying"
    assert "`: char _dta[csdid_method]'" == "reg"
    assert "`: char _dta[csdid_N_attgt]'" == "6"
    assert "`: char _dta[csdid_N_groups]'" == "2"
    assert "`: char _dta[csdid_N_time]'" == "4"
    if "`scenario'" == "panel_reg" {
        assert "`: char _dta[csdid_panel_mode]'" == "panel"
        assert _N == 36
    }
    else {
        assert "`: char _dta[csdid_panel_mode]'" == "repeated-cross-section"
        assert _N == 144
    }
    assert rif_row == _n

    matrix S = J(6, 11, .)
    forvalues j = 1/6 {
        local lab : variable label rif`j'
        assert regexm(`"`lab'"', "^RIF group=([-+0-9.eE]+) time=([-+0-9.eE]+) event_time=([-+0-9.eE]+)$")
        local meta : char rif`j'[csdid_attgt]
        assert wordcount(`"`meta'"') == 10
        local g = regexs(1)
        local t = regexs(2)
        local ev = regexs(3)
        quietly count if abs(rif`j') > 1e-12
        local nonzero = r(N)
        quietly summarize rif`j', meanonly
        local rsum = r(sum)
        local rmin = r(min)
        local rmax = r(max)
        tempvar sq
        quietly generate double `sq' = rif`j'^2
        quietly summarize `sq', meanonly
        local sumsq = r(sum)
        drop `sq'
        matrix S[`j', 1] = `g'
        matrix S[`j', 2] = `t'
        matrix S[`j', 3] = `ev'
        matrix S[`j', 4] = `j'
        matrix S[`j', 5] = _N
        matrix S[`j', 6] = `rsum'
        matrix S[`j', 7] = `sumsq'
        matrix S[`j', 8] = `rmin'
        matrix S[`j', 9] = `rmax'
        matrix S[`j', 10] = `nonzero'
        matrix S[`j', 11] = sqrt(`sumsq') / _N
    }
    matrix colnames S = group time event_time inffunc_col n_rows sum sumsq min max nonzero_count se_from_if
    clear
    svmat double S, names(col)
    gen str24 scenario = "`scenario'"
    rename (n_rows sum sumsq min max nonzero_count se_from_if) ///
           (n_rows_stata sum_stata sumsq_stata min_stata max_stata nonzero_count_stata se_from_if_stata)
    if `first' {
        save "`allactual'", replace
        local first 0
    }
    else {
        append using "`allactual'"
        save "`allactual'", replace
    }
}

import delimited using "`root'/tests/fixtures/parity/f034/expected/r/rif-summary.csv", clear asdouble
merge 1:1 scenario group time inffunc_col using "`allactual'", nogen assert(match)
foreach v in n_rows nonzero_count {
    assert `v' == `v'_stata
}
foreach v in sum sumsq min max se_from_if {
    assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v')
}
