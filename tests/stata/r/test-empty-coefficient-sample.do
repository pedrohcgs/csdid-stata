* RT042: e(sample) describes settled data even when no coefficient can post.
version 15
clear all
set more off
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt042"
tempfile samples
import delimited using "`fx'/expected/r/sample.csv", clear asdouble varnames(1)
isid scenario id t
assert _N == 120
save `samples'

foreach scenario in varying universal screened {
    import delimited using "`fx'/inputs/`scenario'.csv", clear asdouble varnames(1)
    local base = cond("`scenario'" == "universal", "universal", "varying")
    local qualifier ""
    if "`scenario'" == "screened" local qualifier "if id > 2"
    quietly csdid y x `qualifier', ivar(id) time(t) gvar(g) method(reg) ///
        nevertreated base_period(`base') analytical pointwise
    assert "`e(cmd)'" == "csdid"
    capture confirm matrix e(b)
    assert _rc == 111
    capture confirm matrix e(V)
    assert _rc == 111
    assert "`e(datasignaturevars)'" != ""
    matrix A = e(attgt)
    local n = e(N)
    local n_units = e(N_units)
    generate byte actual_used = e(sample)
    quietly count if actual_used
    assert r(N) == `n'
    if "`scenario'" == "screened" {
        assert `n' == 34
        quietly summarize y if actual_used
        local sample_mean = r(mean)
        quietly estat summarize y
        matrix S = r(stats)
        assert S[1, 1] == `sample_mean'

        * A refused saved-RIF call preserves even a b-less posted sample.
        tempfile absent_rif
        local signature "`e(datasignature)'"
        capture csdid_stats simple using "`absent_rif'"
        assert _rc == 601
        assert "`e(cmd)'" == "csdid"
        assert "`e(datasignature)'" == "`signature'"
        assert actual_used == e(sample)
        assert e(N) == `n'
        capture confirm matrix e(b)
        assert _rc == 111

        quietly replace y = y + 100 if actual_used
        capture estat summarize y
        assert _rc == 459
    }
    generate str12 scenario = "`scenario'"
    merge 1:1 scenario id t using `samples', keep(master match)
    assert _merge == 3
    assert actual_used == used
    import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1)
    keep if scenario == "`scenario'"
    assert _N == rowsof(A)
    assert `n' == sample_n
    assert `n_units' == n_units
    forvalues i = 1/`=_N' {
        assert A[`i', 1] == group[`i']
        assert A[`i', 2] == time[`i']
        assert A[`i', 4] == att[`i']
        assert A[`i', 5] == se[`i']
    }
}
display as text "RT042: all cells and 120 sample markers match; b-less samples are signed and survive refused RIF loads"
