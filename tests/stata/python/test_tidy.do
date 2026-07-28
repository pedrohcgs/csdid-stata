version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py022_append_structure
    version 15
    syntax, Object(string) Outfile(string) [APPEND]

    preserve
    clear
    set obs 1
    gen str24 object = "`object'"
    gen double nobs_stata = e(N_units)
    gen double n_rows_stata = e(N_attgt)
    if "`append'" == "" {
        save "`outfile'", replace
    }
    else {
        append using "`outfile'"
        save "`outfile'", replace
    }
    restore
end

confirm file "`root'/tests/fixtures/parity/py022/inputs/mpdta.csv"
confirm file "`root'/tests/fixtures/parity/py022/inputs/sim-tidy.csv"
confirm file "`root'/tests/fixtures/parity/py022/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py022/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py022/expected/contract/tidy-structure.csv"
confirm file "`root'/tests/fixtures/parity/py022/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py022/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 16
quietly count if coverage_status == "mapped"
assert r(N) == 16

tempfile actual tidy

import delimited using "`root'/tests/fixtures/parity/py022/inputs/mpdta.csv", clear asdouble
egen byte tag_id = tag(countyreal)
quietly count if tag_id
local mp_nobs = r(N)
drop tag_id
csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(reg) analytical
assert e(N_units) == `mp_nobs'
confirm matrix e(attgt)
confirm matrix e(inffunc)
assert e(N_attgt) > 0
csdid_estat tidy, saving("`tidy'") replace
use "`tidy'", clear
assert _N > 0
confirm variable group
confirm variable time
confirm variable estimate
assert !missing(estimate)
assert !missing(std_error)
assert std_error > 0 if !missing(estimate)
py022_append_structure, object(MP) outfile("`actual'")

import delimited using "`root'/tests/fixtures/parity/py022/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(reg) analytical
foreach agg_type in simple dynamic group calendar {
    csdid_stats, type(`agg_type')
    confirm matrix e(aggte)
    matrix A = e(aggte)
    assert rowsof(A) > 0
    assert e(N_units) == `mp_nobs'
    if "`agg_type'" == "dynamic" {
        forvalues i = 1/`=rowsof(A)' {
            assert !missing(A[`i', 1])
        }
    }
    if "`agg_type'" == "group" {
        forvalues i = 1/`=rowsof(A)' {
            assert A[`i', 1] > 0
        }
    }
    if "`agg_type'" == "calendar" {
        forvalues i = 1/`=rowsof(A)' {
            assert A[`i', 1] > 0
        }
    }
    py022_append_structure, object(aggte_`agg_type') outfile("`actual'") append
}

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/py022/inputs/sim-tidy.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') analytical
    csdid_estat tidy, saving("`tidy'") replace
    use "`tidy'", clear
    assert _N > 0
    confirm variable estimate
    assert !missing(estimate)
    py022_append_structure, object(method_`method') outfile("`actual'") append
}

import delimited using "`root'/tests/fixtures/parity/py022/expected/contract/tidy-structure.csv", clear varnames(1) stringcols(_all)
merge 1:1 object using "`actual'", nogen assert(match)
destring expected_min_rows nobs, replace
assert n_rows_stata >= expected_min_rows
assert nobs == nobs_stata
