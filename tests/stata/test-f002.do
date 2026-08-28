* ---------------------------------------------------------------------------
* F002, fixture family attgt-balanced-staggered: the same reg/never-treated/
* varying-base configuration as F001 on a 192-row BALANCED PANEL with staggered
* adoption, so the (g,t) grid is six cells rather than one. ATT is pinned to R
* did 2.5.1 at 1e-10 and the analytical standard errors at 1e-8, with the row
* count asserted at exactly 6 -- a grid that silently gains or loses a cell is
* the failure this catches, and it would otherwise hide inside a merge.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f002/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
matrix A = e(attgt)

preserve
clear
svmat double A, names(col)
rename (group time event_time att se n_treat_t n_treat_pre n_control_t n_control_pre) ///
       (group time event_time att_stata se_stata n_treat_t n_treat_pre n_control_t n_control_pre)
tempfile actual
save "`actual'"
restore

import delimited using "`root'/tests/fixtures/parity/f002/expected/r/attgt.csv", clear asdouble
merge 1:1 group time using "`actual'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
assert abs(se - se_stata) < 1e-8 if !missing(se) & !missing(se_stata)
assert _N == 6
