* ---------------------------------------------------------------------------
* A cohort the shortened horizon can no longer reach must leave the group list.
*
* Dropping the units already treated in the first period can move the first
* period forward. A cohort whose value is at or before the NEW first period has
* no base period, so no ATT(g,t) cell is emitted for it -- but it was still
* kept in the cohort list, which is what the aggregation iterates over. The
* estimation therefore succeeded and the AGGREGATION failed: `estat group'
* exited 498 with "no valid ATT(g,t) estimates found for group aggregation" on
* results that had just printed.
*
* R re-trims its cohort list against the post-drop first period on both of its
* preprocessing paths, so it aggregates this design without complaint.
*
* The design: unit 1 is treated at t == 1 and is the only unit observed there,
* so the drop moves the first period to t == 2 -- which is exactly cohort
* g == 2's value. Cohort 4 is the one that survives and must be reported.
*
* This is another whether-it-runs difference, invisible to the numeric parity
* fixtures: every ATT(g,t) both trees report is identical, and the broken one
* simply cannot aggregate them.
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
1 5 1
2 2 2
2 3 2
2 4 2
2 5 2
3 2 2
3 3 2
3 4 2
3 5 2
4 2 4
4 3 4
4 4 4
4 5 4
5 2 4
5 3 4
5 4 4
5 5 4
6 2 0
6 3 0
6 4 0
6 5 0
7 2 0
7 3 0
7 4 0
7 5 0
end
set seed 31337
generate double y = rnormal()

* -- the estimation reports cohort 4 and nothing for cohort 2 -----------
capture noisily csdid y, ivar(id) time(t) gvar(g) bal(none) rseed(31337)
assert _rc == 0
matrix A = e(attgt)
assert rowsof(A) == 4
forvalues i = 1/4 {
    assert A[`i', 1] == 4
}

* -- and the aggregation over those cells RUNS ---------------------------
capture noisily estat group
local rc_group = _rc
assert `rc_group' == 0

matrix G = e(aggte)
assert rowsof(G) == 1
assert G[1, 1] == 4
assert !missing(G[1, 2])

* -- the other aggregations too: none of them may trip over the cohort ---
foreach a in simple dynamic calendar {
    capture noisily estat `a'
    assert _rc == 0
}

display as text "test-cohort-trim-after-drop: a cohort with no base period leaves the group list"
