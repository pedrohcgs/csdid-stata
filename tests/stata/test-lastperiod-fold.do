* ---------------------------------------------------------------------------
* Dropping the first-period-treated units must not re-fold the cohort list.
*
* A cohort whose value lies beyond the last observed period is folded to
* never-treated once, off the period list of the FULL sample. When the units
* that are dropped for being already treated in the first period are also the
* only units observed in the last period, the remaining sample has a shorter
* horizon -- and re-applying the fold against that shorter horizon would
* reclassify every later cohort as never-treated, empty the group list, and
* turn a run that estimates into a "No valid groups" refusal.
*
* The design below is the smallest one that separates the two: unit 1 is
* first-period treated AND is the only unit present at t == 4, so the reduced
* sample runs to t == 3 while cohort g == 4 must survive as a treated cohort
* with three pre-treatment cells.
*
* This is a REFUSAL-vs-RESULT difference, which the numeric parity fixtures
* cannot see: both trees agree on every number they both report, and the
* broken one simply reports nothing at all.
* ---------------------------------------------------------------------------
version 15
clear all
set more off
set linesize 200

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

clear
input long id int t int g
1 1 1
1 2 1
1 3 1
1 4 1
2 1 0
2 2 0
2 3 0
3 1 0
3 2 0
3 3 0
4 1 4
4 2 4
4 3 4
5 1 4
5 2 4
5 3 4
end
set seed 4242
generate double y = rnormal()

* -- the run must succeed, not refuse -----------------------------------
capture noisily csdid y, ivar(id) time(t) gvar(g) bal(none) rseed(4242)
local rc = _rc
assert `rc' == 0

* -- cohort 4 must survive the fold, with its three cells ---------------
matrix A = e(attgt)
assert rowsof(A) == 3
forvalues i = 1/3 {
    assert A[`i', 1] == 4
}
* the three periods of the reduced horizon, in order
assert A[1, 2] == 1
assert A[2, 2] == 2
assert A[3, 2] == 3

* -- the universal base cell is the normalised one ----------------------
assert A[3, 4] == 0
assert missing(A[3, 5])

* -- and the two pre-treatment cells carry real estimates ---------------
assert !missing(A[1, 4]) & !missing(A[1, 5]) & A[1, 5] > 0
assert !missing(A[2, 4]) & !missing(A[2, 5]) & A[2, 5] > 0

* -- the drop itself still happened, and is still announced -------------
assert e(N_units) == 4

display as text "test-lastperiod-fold: the fold is applied once, on the full sample"
