* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do simtruth.do
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
set linesize 160
foreach reg in balanced unbalanced rcs {
    sim_dgp, n(40000) seed(11) regime(`reg')
    quietly count
    local rows = r(N)
    preserve
    quietly bysort id: keep if _n == 1
    quietly count
    local nu = r(N)
    local sh ""
    foreach g in 0 3 4 5 {
        quietly count if gvar == `g'
        local one : display %5.3f r(N)/`nu'
        local sh "`sh' `one'"
    }
    restore
    quietly generate double te_ = (gvar - 2) + 0.5 * (time - gvar) if treated
    local tr ""
    forvalues h = 0/2 {
        quietly summarize te_ if treated & time == gvar + `h', meanonly
        local one : display %5.3f r(mean)
        local tr "`tr' `one'"
    }
    drop te_
    di "TRUTH `reg' rows=`rows' units=`nu' shares:`sh' | sample-truth h0/h1/h2:`tr'"
}
