* PY025: behaviours inherited from the Python csdid test_unit_* suite.
*
* Those six files (106 tests) were first excluded from the inheritance record as
* "Python internals with no Stata surface". That was too sweeping: most assert
* behaviour a csdid user can observe. tests/fixtures/parity/py025 classifies all
* 106, naming for each the assertion that covers it. This file carries the ones
* that no other test asserted, and validates the record itself.
version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

confirm file "`root'/tests/fixtures/parity/py025/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py025/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/py025/metadata/manifest.json"

* ---- the record itself ------------------------------------------------------
import delimited using "`root'/tests/fixtures/parity/py025/expected/contract/upstream-test-map.csv", ///
    clear varnames(1) stringcols(_all)
assert _N == 106
quietly count if coverage_status == "mapped"
assert r(N) == 98
quietly count if coverage_status == "approved-divergence" & divergence_id == "PY025-DIV001"
assert r(N) == 8
* nothing may be left blank: every row states where the behaviour is asserted
assert mapped_scenario != ""
assert assertion_family != ""

import delimited using "`root'/tests/fixtures/parity/py025/expected/contract/approved-divergence.csv", ///
    clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id == "PY025-DIV001"

* ---- influence functions are mean-zero, panel and repeated cross section ----
* test_panel_if_mean_zero, test_rc_if_mean_zero, test_inffunc_overall_mean_zero
import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(dr) analytical nevertreated base_period(varying) bal(none)
matrix IF = e(inffunc)
mata: st_local("mx", strofreal(max(abs(mean(st_matrix("IF"))))))
assert `mx' < 1e-12

import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta_extra.csv", clear asdouble
quietly csdid lemp, time(year) gvar(firsttreat) method(dr) analytical nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" == "repeated-cross-section"
matrix IFRC = e(inffunc)
mata: st_local("mxrc", strofreal(max(abs(mean(st_matrix("IFRC"))))))
assert `mxrc' < 1e-12

* ---- dr equals ipw when there are no covariates ----------------------------
* test_panel_dr_equals_ipw_intercept_only, test_rc_dr_equals_ipw_intercept_only
import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(dr) analytical nevertreated base_period(varying) bal(none)
matrix DRP = e(attgt)
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(ipw) analytical nevertreated base_period(varying) bal(none)
matrix IPP = e(attgt)
mata: st_local("dp", strofreal(max(abs(st_matrix("DRP")[.,4] - st_matrix("IPP")[.,4]))))
assert `dp' < 1e-12

import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta_extra.csv", clear asdouble
quietly csdid lemp, time(year) gvar(firsttreat) method(dr) analytical nevertreated base_period(varying) bal(none)
matrix DRR = e(attgt)
quietly csdid lemp, time(year) gvar(firsttreat) method(ipw) analytical nevertreated base_period(varying) bal(none)
matrix IPR = e(attgt)
mata: st_local("dr", strofreal(max(abs(st_matrix("DRR")[.,4] - st_matrix("IPR")[.,4]))))
assert `dr' < 1e-12

* ---- rescaling the weights leaves ATT(g,t) unchanged -----------------------
* test_panel_weight_scale_invariance
import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta_extra.csv", clear asdouble
quietly csdid lemp [iw=wt], ivar(countyreal) time(year) gvar(firsttreat) method(reg) analytical nevertreated base_period(varying) bal(none)
matrix W1 = e(attgt)
replace wt = wt * 7.5
quietly csdid lemp [iw=wt], ivar(countyreal) time(year) gvar(firsttreat) method(reg) analytical nevertreated base_period(varying) bal(none)
matrix W2 = e(attgt)
mata: st_local("dw", strofreal(max(abs(st_matrix("W1")[.,4] - st_matrix("W2")[.,4]))))
assert `dw' < 1e-12

* ---- base-period selection --------------------------------------------------
* test_lpi_basic and the plan_cell_* pre/post cases: with a universal base
* period every cell is measured against g-1, so the POST-treatment cells are
* identical to the varying-base run and the PRE-treatment cells are not.
* Universal also emits the g-1 normalization row, so the two runs have
* different row counts and must be compared on (group, time), not by position.
import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(reg) base_period(varying) analytical nevertreated bal(none)
matrix BV = e(attgt)
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(reg) base_period(universal) analytical nevertreated bal(none)
matrix BU = e(attgt)
mata {
    V = st_matrix("BV"); U = st_matrix("BU")
    dpost = 0; dpre = 0; nmatch = 0
    for (i = 1; i <= rows(V); i++) {
        for (j = 1; j <= rows(U); j++) {
            if (V[i,1] == U[j,1] & V[i,2] == U[j,2]) {
                nmatch++
                d = abs(V[i,4] - U[j,4])
                if (V[i,2] >= V[i,1]) dpost = max((dpost, d))
                else                  dpre  = max((dpre, d))
            }
        }
    }
    st_local("nmatch", strofreal(nmatch))
    st_local("dpost", strofreal(dpost))
    st_local("dpre", strofreal(dpre))
}
assert `nmatch' == 12
assert `dpost' < 1e-12
assert `dpre' > 1e-6

* ---- a cohort treated in the first period has no pre-treatment cell --------
* test_lpi_no_pretreatment_returns_none, test_plan_cell_universal_no_pretreatment_breaks,
* test_plan_cell_post_no_pretreatment_breaks
import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
quietly summarize year, meanonly
local t1 = r(min)
replace firsttreat = `t1' if firsttreat == 2004
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(reg) analytical nevertreated base_period(varying) bal(none)
matrix FP = e(attgt)
mata: st_local("has", strofreal(sum(st_matrix("FP")[.,1] :== `t1') > 0))
assert `has' == 0

* ---- the panel path requires ivar() ----------------------------------------
* test_validate_panel_requires_idname: without ivar() csdid does not silently
* estimate a panel, it takes the repeated-cross-section path.
import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, time(year) gvar(firsttreat) method(dr) analytical nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" == "repeated-cross-section"

* ---- a string time() is rejected -------------------------------------------
* test_validate_rejects_nonnumeric_time
import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
tostring year, gen(yearstr)
capture csdid lemp, ivar(countyreal) time(yearstr) gvar(firsttreat) method(dr) analytical nevertreated base_period(varying) bal(none)
assert _rc == 198

display "PY025 OK: 106 unit tests classified; 98 mapped, 8 inapplicable"
