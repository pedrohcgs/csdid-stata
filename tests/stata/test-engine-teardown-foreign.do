* ---------------------------------------------------------------------------
* csdid's engine teardown does not depend on anyone else's Mata.
*
* It dropped csdid_*(), which also matches other packages' names -- csdid2
* defines a class csdid_estat -- and Mata refuses a pattern drop as a whole
* when any match is a class with a live instance. So with such an object
* alive, csdid reset reported success and kept the whole old engine, and the
* loader's source fallback then stopped at "already exists" (r(3000)).
* ---------------------------------------------------------------------------
version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* another package's class whose name csdid_*() matches, with a live instance
* whose own name does not (as csdid2's csdid_estat and csdidstat), and a
* user variable that merely carries the prefix
mata:
class csdid_foreignpkg {
    real scalar v
}
foreignstat = csdid_foreignpkg()
foreignstat.v = 41
csdid_userval = 43
end

use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
* the engine's internal functions are in memory now
capture mata: mata describe csdid__selidx()
assert _rc == 0

csdid reset
* ... and gone after reset, although the foreign object is alive
capture mata: mata describe csdid__selidx()
assert _rc != 0
capture mata: mata describe csdid_basic_attgt()
assert _rc != 0
mata: assert(foreignstat.v == 41)
mata: assert(csdid_userval == 43)

* the next estimation brings the engine back
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
assert "`e(cmd)'" == "csdid"

display as text "test-engine-teardown-foreign: the teardown leaves other packages' Mata alone and still clears the engine"
