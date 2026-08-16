* test-ipw-trim-diagnostic.do
* ---------------------------------------------------------------------------
* A propensity-score trim that leaves NO effective comparison mass must say so.
*
* csdid__ipw_panel_fit divides the control moment by mean(trim*w*ps*(1-d)/(1-ps)).
* When the trim removes every control that mean is exactly 0, the division
* returns missing, and the cell used to arrive as a blank ATT with no
* explanation: the guard that classifies it (fit_status 3, "no usable weights")
* was on the intercept-only branch of the same routine, on both repeated
* cross-section twins and on the live doubly-robust panel route, but not on the
* covariate branch.
*
* This is a DELIBERATE divergence from R, of the same kind and in the same
* direction as the doubly-robust panel route's: DRDID::std_ipw_did_panel
* divides by the same zero and returns NaN in silence, which did reports as a
* bare NA. No number moves -- the ATT and the standard error were missing
* before and are missing here -- only the diagnosis is new. See AGENTS.md.
*
* Qualification: both log assertions fail against the pre-guard tree (commit
* 2641902), where the covariate cell blanks silently; the missing-value
* assertions pass on both, which is what makes the log the thing under test.
* ---------------------------------------------------------------------------
version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* Is `message' somewhere in the log? Stata wraps long lines and marks the
* continuation with "> ", so the log is flattened and despaced before the
* search, exactly as test-pair-cell-and-balance-order does it.
program define itd_assert_log
    version 15
    syntax using/, MESSAGE(string) [OMIT]

    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body'`clean' "'
        file read `fh' line
    }
    file close `fh'
    local found = strpos(subinstr(`"`body'"', " ", "", .), subinstr(`"`message'"', " ", "", .)) > 0
    if "`omit'" == "" assert `found'
    else assert !`found'
end

*-----------------------------------------------------------------------------
* 200 treated and 200 never-treated over two periods, with one covariate whose
* distribution is identical in the two groups. The fitted score sits near .5
* for every unit -- far below the .999 overlap cut-off, so the cell reaches the
* trim -- and pscoretrim(.4) is below every control's score, so every control
* is trimmed and the comparison mass is exactly 0. Deterministic: every term is
* a dyadic rational or an integer ratio, so no RNG enters.
*-----------------------------------------------------------------------------
clear
quietly set obs 400
generate long id = _n
generate byte g = cond(id <= 200, 2, 0)
generate byte x = mod(id, 5)
quietly expand 2
quietly bysort id: generate byte t = _n
generate double y = mod(id, 13)/4 + (t == 2)*(mod(id, 7)/8) + 0.5*(g == 2 & t == 2)
sort id t

tempfile trimlog
log using "`trimlog'", replace text
csdid y x, ivar(id) time(t) gvar(g) method(ipw) ///
    base_period(varying) analytical nofast pscoretrim(.4)
log close

tempname A
matrix `A' = e(attgt)
assert rowsof(`A') == 1
assert missing(`A'[1, 4]) & missing(`A'[1, 5])
itd_assert_log using "`trimlog'", ///
    message("no usable weights for group 2 in time period 2")
* and it is the trim that is being reported, not an overlap violation
itd_assert_log using "`trimlog'", message("overlap condition violated") omit

*-----------------------------------------------------------------------------
* The same cell with a trim that binds on nothing estimates normally, so the
* guard refuses a design rather than the route.
*-----------------------------------------------------------------------------
quietly csdid y x, ivar(id) time(t) gvar(g) method(ipw) ///
    base_period(varying) analytical nofast pscoretrim(1)
matrix `A' = e(attgt)
assert !missing(`A'[1, 4]) & !missing(`A'[1, 5])

display as text "test-ipw-trim-diagnostic passed"
