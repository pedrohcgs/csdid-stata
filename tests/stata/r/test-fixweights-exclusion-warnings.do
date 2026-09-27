* RT061 -- under fix_weights(base_period|first_period), csdid raises R's
* exclusion and empty-cell warnings, in R's order.
* R judges a cell's validity on its rows before the exclusion, then drops the
* units the target period does not observe and says so, then raises the four
* corner warnings on the rows that are left. A cell with an empty corner before
* the exclusion still gets the exclusion line and every corner the exclusion
* empties; a cell the exclusion empties on one side warns for both periods.
* The unset scenario is the unchanged control.
version 15
clear all
set more off
set linesize 255
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt061"

* The exclusion and corner warnings in a log, in order, without "warning: ".
program define rt061_warnings, rclass
    version 15
    syntax using/
    tempname fh
    local n 0
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local l = strtrim(`"`macval(line)'"')
        if substr(`"`l'"', 1, 9) == "warning: " {
            local m = substr(`"`l'"', 10, .)
            if strpos(`"`m'"', "No units in group") == 1 | ///
               strpos(`"`m'"', "No available control units") == 1 | ///
               strpos(`"`m'"', "Some units not observed in") == 1 {
                local ++n
                return local w`n' `"`m'"'
            }
        }
        file read `fh' line
    }
    file close `fh'
    return scalar n = `n'
end

import delimited using "`fx'/expected/r/warnings.csv", clear varnames(1) stringcols(3)
tempfile expected
save `expected'
import delimited using "`fx'/expected/r/attgt.csv", clear varnames(1) asdouble
tempfile expected_att
save `expected_att'
import delimited using "`fx'/inputs/scenarios.csv", clear varnames(1) stringcols(_all)
local n_scen = _N
forvalues k = 1/`n_scen' {
    local scen`k' = scenario[`k']
    local data`k' = data[`k']
    local fw`k' = fix_weights[`k']
    local meth`k' = method[`k']
}

local total 0
forvalues k = 1/`n_scen' {
    local scenario "`scen`k''"
    local fwopt = cond("`fw`k''" == "", "", "fix_weights(`fw`k'')")
    import delimited using "`fx'/inputs/`data`k''.csv", clear asdouble varnames(1)
    tempfile lg
    log using "`lg'", text replace name(rt061)
    quietly csdid y, ivar(id) time(t) gvar(g) bal(none) method(`meth`k'') ///
        nevertreated base_period(universal) `fwopt' analytical
    log close rt061
    tempname A
    matrix `A' = e(attgt)

    rt061_warnings using "`lg'"
    local got = r(n)
    forvalues i = 1/`got' {
        local got`i' `"`r(w`i')'"'
    }
    use `expected' if scenario == "`scenario'", clear
    sort seq
    if `got' != _N {
        display as error "RT061 `scenario': csdid printed `got' warnings, R prints `=_N'"
        forvalues i = 1/`got' {
            display as error `"  csdid `i': `got`i''"'
        }
    }
    assert `got' == _N
    forvalues i = 1/`got' {
        if `"`got`i''"' != message[`i'] {
            display as error `"RT061 `scenario' #`i': csdid "`got`i''" vs R "`=message[`i']'""'
        }
        assert `"`got`i''"' == message[`i']
    }

    * the numbers and the blanks are R's
    use `expected_att' if scenario == "`scenario'", clear
    assert rowsof(`A') == _N
    forvalues i = 1/`=_N' {
        local hit 0
        forvalues j = 1/`=rowsof(`A')' {
            if `A'[`j', 1] == group[`i'] & `A'[`j', 2] == time[`i'] local hit `j'
        }
        assert `hit' > 0
        if missing(att[`i']) assert missing(`A'[`hit', 4])
        else assert abs(`A'[`hit', 4] - att[`i']) <= 1e-10 + 1e-10 * abs(att[`i'])
        if missing(se[`i']) assert missing(`A'[`hit', 5])
        else assert abs(`A'[`hit', 5] - se[`i']) <= 1e-10 + 1e-10 * abs(se[`i'])
    }
    local total = `total' + `got'
    display as text "RT061 `scenario': `got' warnings, R's, in R's order"
}
assert `total' == 76

display as text "test-fixweights-exclusion-warnings: csdid raises R's fix_weights exclusion and corner warnings in R's order"
