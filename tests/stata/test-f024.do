* ---------------------------------------------------------------------------
* F024 pins the refusal of a repeated unit-period. A panel identified by
* ivar() and time() cannot carry two rows for the same unit and period; R did
* 2.5.1 stops rather than estimating on whichever row it reaches, and csdid
* must stop too, with rc 459.
*
* The clean fixture is estimated first so the refusal is attributable to the
* single duplicated row and not to the design: the same data, plus one repeat,
* must go from a fit with the expected sample size to an error.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f024/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
assert e(N) == 40

import delimited using "`root'/tests/fixtures/parity/f024/inputs/duplicate-input.csv", clear asdouble
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
assert _rc == 459
