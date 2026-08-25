* The engine loader's teardown is TARGETED. When the resolved library path
* changes mid-session -- two installations, a shadowing copy, a stale build --
* the loader must drop and reload csdid's own Mata namespace (csdid_*) and
* nothing else. It used to run `mata clear', which destroyed the caller's
* variables, their functions, and every other package's loaded Mata state; the
* cold audit measured a user sentinel vanishing across an internal refresh the
* user never asked for.
*
* The test plants three kinds of foreign Mata state -- a variable, a function,
* and state whose name merely RESEMBLES the engine's prefix -- forces the
* changed-library route by pointing $CSDID_ENGINE_LIBRARY somewhere else, runs
* an estimation (which must still succeed off the real library), and asserts
* all three survived.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

import delimited using "`root'/tests/fixtures/parity/f034/inputs/input.csv", ///
    clear asdouble
quietly csdid y x1, ivar(id) time(time) gvar(g) method(dr) analytical notyet
tempname LB0
matrix `LB0' = e(b)

mata: reviewer_sentinel = 42
mata:
real scalar reviewer_helper() return(7)
end
* csdidx_ is NOT csdid_'s namespace: the pattern csdid_*() must not reach it
mata: csdidx_lookalike = 9

local loader_lib_saved `"$CSDID_ENGINE_LIBRARY"'
global CSDID_ENGINE_LIBRARY "/nonexistent/somewhere/lcsdid_v2.mlib"
quietly csdid y x1, ivar(id) time(time) gvar(g) method(dr) analytical notyet
global CSDID_ENGINE_LIBRARY `"`loader_lib_saved'"'

* the estimation off the reloaded engine reproduces the same numbers
tempname LB1
matrix `LB1' = e(b)
assert mreldif(`LB0', `LB1') == 0

* and every piece of foreign state survived the refresh
mata: st_local("t1", strofreal(reviewer_sentinel == 42))
assert `t1' == 1
mata: st_local("t2", strofreal(reviewer_helper() == 7))
assert `t2' == 1
mata: st_local("t3", strofreal(csdidx_lookalike == 9))
assert `t3' == 1
capture mata: mata drop reviewer_sentinel reviewer_helper() csdidx_lookalike

display as text "engine loader teardown: a changed library path reloads csdid's namespace and touches nothing else"
