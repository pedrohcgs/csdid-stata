* ---------------------------------------------------------------------------
* balance() requires complete original post-treatment event-time support.
* A missing cell removes its cohort from every balanced event time. An event
* time missing for every eligible cohort makes the balanced profile unavailable.
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

* One e=1 cell missing: its cohort is removed from the whole balanced profile.
use "`root'/src/data/mpdta.dta", clear
drop if first_treat == 2006 & year == 2007
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(reg) ///
    nevertreated base_period(universal) bal(none) analytical pointwise
tempfile lg
matrix AT=e(attgt)
log using "`lg'", text replace name(bv)
csdid_stats event, balance(1) dropmissing
log close bv
matrix AG=e(aggte)
mata: bv_k=selectindex((st_matrix("AT")[.,1]:==2004):&(st_matrix("AT")[.,2]:==2004))
mata: assert(abs(st_matrix("AG")[selectindex(st_matrix("AG")[.,1]:==0),2]-st_matrix("AT")[bv_k,4])<1e-10)
bv_log_has using "`lg'", message("cohort composition differs")
assert r(has) == 0
bv_log_has using "`lg'", message("no estimated cell is left at event time")
assert r(has) == 0

* Both e=1 cells missing: no cohort has complete support, so refuse by name.
drop if first_treat == 2004 & year == 2005
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) method(reg) ///
    nevertreated base_period(universal) bal(none) analytical pointwise
log using "`lg'", text replace name(bv)
capture noisily csdid_stats event, balance(1) dropmissing
local rc=_rc
log close bv
assert `rc'==498
bv_log_has using "`lg'", message("every observed post-treatment event time through balance()")
assert r(has) == 1

display as text "test-balance-vanished-event-time: incomplete cohorts leave the balanced profile"
