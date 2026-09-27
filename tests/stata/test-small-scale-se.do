* A standard error of 1.49e-7 or less (ten times the square root of machine
* epsilon) is reported as missing, as R did 2.5.1 does (att_gt.R:570/593,
* compute.aggte.R:312). An outcome on a small enough scale therefore loses
* every standard error -- R blanks the same cells on mpdta with lemp * 1e-6 --
* and the note csdid_stats prints must name that cause and its remedy rather
* than an overflowing variance. Above the floor, rescaling the outcome scales
* every estimate and standard error with it.
version 15
clear all
set more off
set linesize 250
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local mpdta "`root'/examples/data/mpdta.csv"

import delimited using "`mpdta'", clear asdouble varnames(1)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
matrix A0 = e(attgt)
local c_se = colnumb(A0, "se")

* above the floor: every standard error scales with the outcome
import delimited using "`mpdta'", clear asdouble varnames(1)
quietly replace lemp = lemp * 1e-4
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
matrix A4 = e(attgt)
forvalues i = 1/`=rowsof(A0)' {
    if !missing(A0[`i', `c_se']) assert reldif(A4[`i', `c_se'], 1e-4 * A0[`i', `c_se']) < 1e-8
}

* below it: every standard error is missing, and the note says why
import delimited using "`mpdta'", clear asdouble varnames(1)
quietly replace lemp = lemp * 1e-6
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
matrix A6 = e(attgt)
forvalues i = 1/`=rowsof(A6)' {
    assert missing(A6[`i', `c_se'])
}
tempfile lg
log using "`lg'", text replace name(smallscale)
csdid_stats event
log close smallscale
tempname fh
local body ""
file open `fh' using "`lg'", read text
file read `fh' line
while r(eof) == 0 {
    * a long line wraps in the log as "> " continuations; rejoin it
    if substr(`"`line'"', 1, 2) == "> " local body `"`body'`=substr(`"`line'"', 3, .)'"'
    else local body `"`body' `line'"'
    file read `fh' line
}
file close `fh'
assert strpos(`"`body'"', "note: every standard error in this type(dynamic) aggregation is missing") > 0
assert strpos(`"`body'"', "a standard error of 1.49e-7 or less is reported as missing, so rescale the outcome") > 0

display as text "test-small-scale-se: the standard-error floor and its note"
