* ---------------------------------------------------------------------------
* balance() with dropmissing: an event time that lost every cell is announced.
*
* Owner decision 2026-09-26. Under dropmissing, an event time of the balanced
* window whose every cell failed is not reported, and the post-treatment
* average then covers only the event times left -- the reference drops it in
* silence. csdid warns and carries on. A single missing cell at an event time
* that is still reported keeps the older composition warning.
* ---------------------------------------------------------------------------
version 15
clear all
set more off
set linesize 255

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define bv_log_has, rclass
    version 15
    syntax using/, MESSAGE(string)
    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " local clean = strtrim(substr(`"`clean'"', 3, .))
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    return scalar has = strpos(`"`body'"', `"`message'"') > 0
end

* one e = 1 cell missing: still reported, the composition warning names it
use "`root'/src/data/mpdta.dta", clear
drop if first_treat == 2006 & year == 2007
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(reg) ///
    nevertreated base_period(universal) bal(none) analytical pointwise
tempfile lg
log using "`lg'", text replace name(bv)
csdid_stats event, balance(1) dropmissing
log close bv
bv_log_has using "`lg'", message("cohort 2006 at event time 1")
assert r(has) == 1
bv_log_has using "`lg'", message("no estimated cell is left at event time")
assert r(has) == 0

* both e = 1 cells missing: event time 1 vanishes, is named, and nothing stops
drop if first_treat == 2004 & year == 2005
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(reg) ///
    nevertreated base_period(universal) bal(none) analytical pointwise
log using "`lg'", text replace name(bv)
csdid_stats event, balance(1) dropmissing
log close bv
bv_log_has using "`lg'", message("no estimated cell is left at event time(s) 1 of the balance(1) window")
assert r(has) == 1
tempname AG
matrix `AG' = e(aggte)
mata: st_local("has_e1", strofreal(any(st_matrix("`AG'")[., 1] :== 1)))
assert `has_e1' == 0

display as text "test-balance-vanished-event-time: a vanished balanced event time is announced, not refused"
