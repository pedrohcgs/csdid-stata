version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f024/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
assert e(N) == 40

import delimited using "`root'/tests/fixtures/parity/f024/inputs/duplicate-input.csv", clear asdouble
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
assert _rc == 459
