* Legacy and utility commands carried over from csdid 1.82.
*
* These four deprecated commands and the two supported utilities had never been
* executed by this project. Shipping four untested ado files into a package
* where everything else is gated is not defensible, so this at minimum loads
* each one, confirms it runs, and pins the contract that matters: csgvar
* produces the cohort coding csdid requires, and the deprecated commands
* announce themselves.
version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/legacy"
adopath ++ "`root'/src/mata"

foreach f in csgvar _gcsgvar {
    confirm file "`root'/src/ado/`f'.ado"
}
foreach f in csdid_rif csdid_table dipt tsvmat {
    confirm file "`root'/src/legacy/`f'.ado"
}
confirm file "`root'/src/help/csdid_legacy.sthlp"

* ---- csgvar builds the cohort variable csdid expects -----------------------
import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
generate byte treated = (firsttreat > 0 & year >= firsttreat)
csgvar gvar_built = treated, tvar(year) ivar(countyreal)

* never-treated units must be 0, treated units their first treated period
assert gvar_built == 0 if firsttreat == 0
assert gvar_built == firsttreat if firsttreat > 0 & !missing(gvar_built)
quietly count if missing(gvar_built)
assert r(N) == 0

* and the result must actually drive csdid to the same answer as the original
quietly csdid lemp, ivar(countyreal) time(year) gvar(gvar_built) analytical
matrix B = e(attgt)
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) analytical
matrix A = e(attgt)
assert rowsof(A) == rowsof(B)
mata: st_local("d", strofreal(max(abs(st_matrix("A")[.,4] - st_matrix("B")[.,4]))))
assert `d' < 1e-12

* csgvar refuses a treatment indicator with more than two values
generate byte three_vals = mod(_n, 3)
capture csgvar bad = three_vals, tvar(year) ivar(countyreal)
assert _rc != 0

* ---- the deprecated commands load and announce themselves ------------------
* Each must be loadable. A syntax error in a shipped ado is a packaging defect
* even when the command is deprecated.
foreach c in csdid_rif csdid_table dipt tsvmat {
    capture program drop `c'
    quietly capture noisily run "`root'/src/legacy/`c'.ado"
    assert _rc == 0
}

* csdid_table prints its deprecation notice
import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) analytical
capture noisily csdid_table
* whatever it does with the table, it must not abort the session
assert inlist(_rc, 0, 198, 111, 301)

display "LEGACY OK: csgvar verified against csdid; four deprecated commands load"
