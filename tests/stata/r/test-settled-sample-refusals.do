* RT045 -- refusals decided on the settled sample, named and without frames.
* With no never-treated units the latest cohort becomes the comparison group
* and the periods from its date on are removed. Only then can R tell that the
* coerced group is too small, that no treated cohort is left, or that no
* (g,t) cell can be formed. csdid estimated the first where R refuses, crashed
* with r(3202) or exited a bare r(111) on the second and third, and printed
* internal Mata frames under the kernel's refusals. Each verdict must be R's,
* with rc 459, the named reason, and no frames.
version 15
clear all
set more off
set linesize 200
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt045"

program define rt045_log_has, rclass
    version 15
    syntax using/, MESSAGE(string)
    tempname fh
    local found 0
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        if strpos(`"`macval(line)'"', `"`message'"') local found 1
        file read `fh' line
    }
    file close `fh'
    return scalar found = `found'
end

import delimited using "`fx'/expected/r/estimation_status.csv", clear varnames(1) bindquote(strict)
isid scenario
tempfile status
save `status'
import delimited using "`fx'/inputs/scenarios.csv", clear varnames(1) bindquote(strict)
assert _N == 12
merge 1:1 scenario using `status'
assert _merge == 3
drop _merge
* R's reason, by kind: R's own text carries backquotes, so it is classified
* here rather than carried through a macro
generate byte kind = 1 * (strpos(message, "never-treated group is too small") > 0) + ///
    2 * (strpos(message, "No valid groups") > 0) + 3 * (strpos(message, "No valid (g, t) cells") > 0)
assert (kind > 0) == refused
tempfile specs runlog
save `specs'
local nrefused 0
forvalues k = 1/12 {
    use `specs', clear
    local s = scenario[`k']
    local design = design[`k']
    local opts = stata_options[`k']
    local refused = refused[`k']
    local kind = kind[`k']
    import delimited using "`fx'/inputs/`design'.csv", clear asdouble varnames(1)
    log using "`runlog'", text replace name(rt045log)
    capture noisily csdid y, `opts' method(reg) analytical
    local rc = _rc
    log close rt045log
    rt045_log_has using "`runlog'", message("returned error")
    assert !r(found)
    if `refused' {
        assert `rc' == 459
        if `kind' == 1 {
            rt045_log_has using "`runlog'", message("The never-treated group is too small to serve as a reliable comparison group")
            assert r(found)
            rt045_log_has using "`runlog'", message("Check groups: 0.")
            assert r(found)
        }
        else if `kind' == 2 {
            rt045_log_has using "`runlog'", message("No valid groups.")
            assert r(found)
        }
        else {
            rt045_log_has using "`runlog'", message("No valid (g, t) cells found for estimation.")
            assert r(found)
        }
        local ++nrefused
        display as text "RT045 `s': refused as R refuses"
    }
    else {
        assert `rc' == 0
        matrix A = e(attgt)
        preserve
        import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1)
        keep if scenario == "`s'"
        assert _N == rowsof(A)
        forvalues i = 1/`=_N' {
            assert A[`i', 1] == group[`i'] & A[`i', 2] == time[`i']
            assert reldif(A[`i', 4], att[`i']) < 1e-8
            assert missing(A[`i', 5]) == missing(se[`i'])
        }
        restore
        display as text "RT045 `s': estimated as R estimates"
    }
}
assert `nrefused' == 11

* The first-period drop can leave a single unit after the scan counted two;
* the kernel's one-unit refusal then carries no internal frames either.
clear
input id t g y
2 2 6 -1
1 6 3 5
4 2 3 3
4 3 3 4
3 3 0 2
2 3 6 0
2 6 6 2
1 4 3 2
end
log using "`runlog'", text replace name(rt045log)
capture noisily csdid y, ivar(id) time(t) gvar(g) method(ipw) analytical anticipation(1)
local rc = _rc
log close rt045log
assert `rc' == 459
rt045_log_has using "`runlog'", message("ivar() identifies only one unit")
assert r(found)
rt045_log_has using "`runlog'", message("returned error")
assert !r(found)

display as text "test-settled-sample-refusals: 11 settled-sample refusals match R, named and without frames"
