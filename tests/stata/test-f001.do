* ---------------------------------------------------------------------------
* F001, fixture family attgt: the smallest possible ATT(g,t) against R did
* 2.5.1. A 40-row repeated-cross-section two-by-two, method(reg), never-treated
* controls, varying base period -- one cell, and its ATT must match the oracle
* CSV to 1e-10 after a 1:1 merge on (group, time) that asserts every row pairs.
* Standard errors are pinned only by their missingness pattern, since this is
* the cell where R reports none. First line of defense for the ATT kernel
* itself: if this file fails, no other parity result means anything.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f001/inputs/input.csv", clear asdouble
csdid y, time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
matrix A = e(attgt)

preserve
clear
svmat double A, names(col)
rename (group time event_time att se n_treat_t n_treat_pre n_control_t n_control_pre) ///
       (group time event_time att_stata se_stata n_treat_t n_treat_pre n_control_t n_control_pre)
tempfile actual
save "`actual'"
restore

import delimited using "`root'/tests/fixtures/parity/f001/expected/r/attgt.csv", clear asdouble
merge 1:1 group time using "`actual'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert missing(se) == missing(se_stata)
