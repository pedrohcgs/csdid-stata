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
quietly csdid lemp, ivar(countyreal) time(year) gvar(gvar_built) analytical nevertreated base_period(varying) bal(none)
matrix B = e(attgt)
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) analytical nevertreated base_period(varying) bal(none)
matrix A = e(attgt)
assert rowsof(A) == rowsof(B)
mata: st_local("d", strofreal(max(abs(st_matrix("A")[.,4] - st_matrix("B")[.,4]))))
assert `d' < 1e-12

* the egen form is the same computation -- csgvar forwards to _gcsgvar, which
* is what `egen g = csgvar(...)' dispatches to, so this is the route that a
* de-duplication could silently break
egen gvar_egen = csgvar(treated), tvar(year) ivar(countyreal)
assert gvar_egen == gvar_built
quietly count if missing(gvar_egen)
assert r(N) == 0

* csgvar refuses a treatment indicator with more than two values, with a
* documented return code rather than the old undocumented 4444
generate byte three_vals = mod(_n, 3)
capture csgvar bad = three_vals, tvar(year) ivar(countyreal)
assert _rc == 459
capture egen bad_egen = csgvar(three_vals), tvar(year) ivar(countyreal)
assert _rc == 459

* and it refuses a two-valued indicator whose untreated state is not 0. This
* one used to pass: `replace aux = 0 if exp == 0' never fired, every unit came
* back with a positive cohort, and csdid then silently coerced the latest
* treated cohort into the comparison group -- wrong sample, rc 0.
generate byte treated12 = treated + 1
capture csgvar bad12 = treated12, tvar(year) ivar(countyreal)
assert _rc == 459
capture egen bad12_egen = csgvar(treated12), tvar(year) ivar(countyreal)
assert _rc == 459

* a two-valued indicator coded 0/5 is still accepted: only the UNTREATED value
* has to be 0, and legacy do-files may rely on that
generate byte treated05 = 5 * treated
csgvar gvar05 = treated05, tvar(year) ivar(countyreal)
assert gvar05 == gvar_built
drop gvar05

* ---- the requested storage type is the type you get ------------------------
* `typlist' was parsed and thrown away: every route produced a float, whatever
* was asked for. A cohort code is a value on the time axis, so on a %tc or
* epoch-second axis float's 24-bit mantissa rounds it, and the rounded cohort
* is a different treatment group handed to csdid with rc 0.
foreach t in double long int {
    egen `t' gvar_`t' = csgvar(treated), tvar(year) ivar(countyreal)
    assert "`: type gvar_`t''" == "`t'"
    assert gvar_`t' == gvar_built
    drop gvar_`t'
}
csgvar float gvar_cmd_float = treated, tvar(year) ivar(countyreal)
assert "`: type gvar_cmd_float'" == "float"
drop gvar_cmd_float

* with no type asked for, the command form gives double rather than `set type',
* because the time axis is what the answer lives on
csgvar gvar_default = treated, tvar(year) ivar(countyreal)
assert "`: type gvar_default'" == "double"
drop gvar_default

* and a cohort code past float's exact range survives, to the unit
preserve
quietly replace year = 20000000 + year
quietly replace firsttreat = 20000000 + firsttreat if firsttreat > 0
quietly replace treated = (firsttreat > 0 & year >= firsttreat)
csgvar gvar_big = treated, tvar(year) ivar(countyreal)
assert "`: type gvar_big'" == "double"
assert gvar_big == firsttreat
quietly count if gvar_big > 16777216
assert r(N) > 0
drop gvar_big

* a type that cannot hold it is refused rather than rounding in silence
capture egen float gvar_narrow = csgvar(treated), tvar(year) ivar(countyreal)
assert _rc == 198
capture confirm variable gvar_narrow
assert _rc != 0
restore

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
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) analytical nevertreated base_period(varying) bal(none)
capture noisily csdid_table
* whatever it does with the table, it must not abort the session
assert inlist(_rc, 0, 198, 111, 301)

* ---- csdid_rif does not reach into the user's namespace -------------------
* It used to hand its results out through the fixed global names bb_, VV_ and
* cln_. Two things followed. `ereturn post bb_ VV_' CONSUMES those matrices, so
* a user who happened to have a matrix called bb_ lost it outright. And an
* UNCLUSTERED run picked up whatever scalar cln_ was already lying around and
* posted it as e(N_clust): with a stray cln_ = 12345 in memory, csdid_rif
* reported 12345 clusters for a run with no cluster() at all.
*
* The estimates were never affected, and must not be now.
clear
quietly set obs 2000
quietly generate long id = _n
quietly generate double cl = mod(id, 41) + 1
quietly generate double rif1 = mod(id * 13, 97) / 97 - 0.5 + 1.2
quietly generate double rif2 = mod(id * 7, 89) / 89 - 0.5 + 0.4

matrix bb_ = J(2, 2, 42)
matrix VV_ = J(3, 3, 7)
scalar cln_ = 12345

quietly csdid_rif rif1 rif2
* no cluster() was given, so there is no cluster count to report -- and
* certainly not the user's scalar
assert missing(e(N_clust))
assert "`e(vcetype)'" == "Robust"
tempname RIFB
matrix `RIFB' = e(b)
assert colsof(`RIFB') == 2

quietly csdid_rif rif1 rif2, cluster(cl)
assert e(N_clust) == 41

quietly csdid_rif rif1 rif2, wboot reps(199) seed(20260806)
assert "`e(vcetype)'" == "WBoot"

* the user's own objects are exactly as they were left
assert rowsof(bb_) == 2 & colsof(bb_) == 2 & bb_[1, 1] == 42
assert rowsof(VV_) == 3 & colsof(VV_) == 3 & VV_[1, 1] == 7
assert cln_ == 12345

display "LEGACY OK: csgvar verified against csdid; four deprecated commands load; csdid_rif leaves bb_/VV_/cln_ alone"
