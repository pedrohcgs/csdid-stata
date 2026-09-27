* RT062 -- the warning csdid prints when it declines the Wald pre-test on a
* singular covariance matrix is R's, word for word. The two pre-treatment
* cells are each other's comparison, so their estimates are exact negatives.
version 15
clear all
set more off
set linesize 255
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt062"

import delimited using "`fx'/expected/r/warnings.csv", clear varnames(1) stringcols(1)
assert _N == 1
local want = "warning: " + message[1]

import delimited using "`fx'/inputs/singular-pretest.csv", clear asdouble varnames(1)
tempfile lg
log using "`lg'", text replace name(rt062)
csdid y, time(t) gvar(g) method(reg) notyet base_period(varying) analytical
log close rt062
assert missing(e(wald_stat)) & missing(e(wald_pvalue))

* the whole line, so a character R does not print is caught
tempname fh
local n 0
local hit 0
file open `fh' using "`lg'", read text
file read `fh' line
while r(eof) == 0 {
    local l = strtrim(`"`macval(line)'"')
    if strpos(`"`l'"', "warning: Not returning pre-test Wald") == 1 {
        local ++n
        if `"`l'"' == `"`want'"' local ++hit
        else display as error `"csdid: [`l']"' _n `"R:     [`want']"'
    }
    file read `fh' line
}
file close `fh'
assert `n' == 1 & `hit' == 1

display as text "test-wald-pretest-warning: the singular pre-test warning is R's, word for word"
