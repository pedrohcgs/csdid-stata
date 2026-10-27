* RT082: a visible conservative refusal at the conditioning cutoff.
version 15
clear all
set more off
set linesize 255
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt082"
program define rt082_assert_missing
 version 15
 syntax, TABLE(name) IFMAT(name)
 assert rowsof(`table')==1
 assert missing(`table'[1,4]) & missing(`table'[1,5])
 mata: assert(all(st_matrix("`ifmat'") :>= .))
end
program define rt082_assert_warning
 version 15
 syntax using/
 tempname h
 local found 0
 file open `h' using `"`using'"',read text
 file read `h' line
 while r(eof)==0 {
  if strpos(`"`macval(line)'"',"singular or numerically ill-conditioned for group 2 in time period 2") local found 1
  file read `h' line
 }
 file close `h'
 assert `found'==1
end
* Actual R backend verdicts are data, not an assumption about the host BLAS.
import delimited "`fx'/expected/r/results.csv",clear asdouble bindquote(strict)
assert _N==16
isid scenario
assert inlist(backend,"default","internal")
assert inlist(route,"panel","rc")
foreach v in att se {
 capture confirm string variable `v'
 if !_rc destring `v',replace force
}
assert missing(att)==missing_att
assert missing(se)==missing_att
assert missing(error)
assert !missing(blas)
* The internal-product witness is the one the unchanged Mata guard refuses.
assert missing_att==1 if backend=="internal"
import delimited "`fx'/expected/r/grams.csv",clear asdouble
assert _N==18
assert value<. & rcond>0 & rcond<.
assert rcond<epsilon if backend=="internal"
* The public Stata verdict is independent of whether a reference BLAS accepts.
tempfile runlog
foreach route in panel rc {
 foreach weighted in 0 1 {
  foreach speed in auto off {
   import delimited "`fx'/inputs/panel.csv",clear asdouble
   local structure "ivar(id)"
   if "`route'"=="rc" local structure "ivar(rowid) rcs"
   local weights ""
   if `weighted' local weights "[iw=w]"
   local slow ""
   if "`speed'"=="off" local slow "nofast"
   log using "`runlog'",text replace name(rt082)
   capture noisily csdid y a b `weights', `structure' time(t) gvar(g) method(reg) ///
    nevertreated baseperiod(varying) analytical pointwise storeall `slow'
   local rc=_rc
   log close rt082
   assert `rc'==0
   matrix A=e(attgt)
   matrix I=e(inffunc)
   rt082_assert_missing,table(A) ifmat(I)
   rt082_assert_warning using "`runlog'"
  }
 }
}
* Qualification: a fabricated accepted cell must fail the refusal assertion.
matrix ACCEPTED=A
matrix ACCEPTED[1,4]=1
capture rt082_assert_missing,table(ACCEPTED) ifmat(I)
assert _rc==9
* Qualification: a silent missing cell must fail the disclosure assertion.
tempname blank
tempfile silent
file open `blank' using "`silent'",write text replace
file write `blank' "no condition warning" _n
file close `blank'
capture rt082_assert_warning using "`silent'"
assert _rc==9
display "RT082 PASS: eight visible missing-cell refusals; sixteen genuine R backend fits recorded; accepted-cell and silent-refusal faults rejected"
