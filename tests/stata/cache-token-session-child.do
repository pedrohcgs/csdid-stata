* One of the two Stata processes test-cache-token-session.do launches. The
* defect this pair guards against is only reachable ACROSS sessions, so it
* cannot be staged inside one: the cache token used to be a per-session
* counter, and the collision it produced was between the first lean estimation
* of one session and the first lean estimation of another. Both arms below
* therefore have to be the first lean csdid of their own process.
*
* Nothing is judged here. Every observation goes to a csv the parent reads
* back, return codes included, so that a refusal arrives at the judge as a
* number rather than as a missing file.
*
*   argument 1  repository root (src/ado and src/mata go on the adopath)
*   argument 2  arm: A (the run that is saved) or B (the run that restores it)
*   argument 3  estimation input csv
*   argument 4  scratch directory: the .ster files and the csv live here

version 15
clear all
set more off

local root  "`1'"
local arm   "`2'"
local data  "`3'"
local scratch "`4'"

adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local lean_ster "`scratch'/lean.ster"
local full_ster "`scratch'/full.ster"

* Did the run say the thing it is required to say? The message is the other
* half of the requirement -- a refusal that arrives as a bare return code is
* not the "re-run the estimation that produced these results" the user needs --
* so the arm's own log is scanned here, where the message is, and the parent
* judges the flag.
program define ct_log_says
    version 15
    syntax using/, MESSAGE(string)

    tempname lh
    local body ""
    file open `lh' using `"`using'"', read text
    file read `lh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body'`clean' "'
        file read `lh' line
    }
    file close `lh'
    local hay = subinstr(`"`body'"', " ", "", .)
    local needle = subinstr(`"`message'"', " ", "", .)
    c_local ct_said = (strpos(`"`hay'"', `"`needle'"') > 0)
end

* r(table) is read into a matrix on the line after the command that built it
* everywhere below, because -log close- and -file write- both replace r().

tempname fh
file open `fh' using "`scratch'/`arm'.csv", write replace text

if "`arm'" == "A" {
    * The estimation the second session will restore, saved both ways. Lean is
    * the default and keeps the influence functions in the Mata engine; storeall
    * puts them in e(), which is what makes it the control: whatever the token
    * does, the storeall artifact carries its own inference across the process
    * boundary and must go on reproducing these figures exactly.
    import delimited using "`data'", clear asdouble
    capture noisily csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical notyet
    local lean_rc = _rc
    file write `fh' "lean_est_rc," (`lean_rc') _n
    estimates save "`lean_ster'", replace

    capture noisily csdid_estat event
    local agg_rc = _rc
    tempname TA
    if `agg_rc' == 0 matrix `TA' = r(table)
    file write `fh' "truth_agg_rc," (`agg_rc') _n
    if `agg_rc' == 0 {
        file write `fh' "truth_k," (colsof(`TA')) _n
        forvalues j = 1/`=colsof(`TA')' {
            file write `fh' "truth_b_`j'," %21.17e (`TA'[1, `j']) _n
            file write `fh' "truth_se_`j'," %21.17e (`TA'[2, `j']) _n
        }
    }

    import delimited using "`data'", clear asdouble
    capture noisily csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical notyet storeall
    file write `fh' "full_est_rc," (_rc) _n
    estimates save "`full_ster'", replace
}
else {
    * A different estimation of the same SHAPE -- same units, same (g,t) grid,
    * a tenfold outcome -- run first, exactly as an ordinary second day of work
    * would. Under the counter this run took the token the saved run had, and
    * the aggregation below reported this run's standard errors under the saved
    * run's point estimates.
    import delimited using "`data'", clear asdouble
    quietly replace y = y * 10
    capture noisily csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical notyet
    file write `fh' "own_est_rc," (_rc) _n

    import delimited using "`data'", clear asdouble
    estimates use "`lean_ster'"
    file write `fh' "lean_restore_n_units," (e(N_units)) _n
    file write `fh' "lean_restore_n_attgt," (e(N_attgt)) _n

    tempname TB
    tempfile leanlog
    log using "`leanlog'", replace text name(ctlean)
    capture noisily csdid_estat event
    local lean_rc = _rc
    if `lean_rc' == 0 matrix `TB' = r(table)
    log close ctlean
    file write `fh' "lean_agg_rc," (`lean_rc') _n
    ct_log_says using "`leanlog'", ///
        message("the stored results do not match the last csdid run")
    file write `fh' "lean_agg_said," (`ct_said') _n
    * Whatever it produced when it did not refuse. The parent needs the figures
    * to say WHICH estimation answered, not merely that something did.
    if `lean_rc' == 0 {
        file write `fh' "lean_k," (colsof(`TB')) _n
        forvalues j = 1/`=colsof(`TB')' {
            file write `fh' "lean_b_`j'," %21.17e (`TB'[1, `j']) _n
            file write `fh' "lean_se_`j'," %21.17e (`TB'[2, `j']) _n
        }
    }

    * The control. storeall's influence functions travel inside the .ster, so
    * this arm never reaches the engine cache and must reproduce the saved
    * session's aggregation figure for figure.
    import delimited using "`data'", clear asdouble
    estimates use "`full_ster'"
    capture noisily csdid_estat event
    local full_rc = _rc
    tempname TF
    if `full_rc' == 0 matrix `TF' = r(table)
    file write `fh' "full_agg_rc," (`full_rc') _n
    if `full_rc' == 0 {
        file write `fh' "full_k," (colsof(`TF')) _n
        forvalues j = 1/`=colsof(`TF')' {
            file write `fh' "full_b_`j'," %21.17e (`TF'[1, `j']) _n
            file write `fh' "full_se_`j'," %21.17e (`TF'[2, `j']) _n
        }
    }
}

file close `fh'
display as text "cache-token-session-child: arm `arm' wrote `scratch'/`arm'.csv"
