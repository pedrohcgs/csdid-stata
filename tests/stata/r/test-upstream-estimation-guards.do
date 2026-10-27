* RT077 -- weighted feasibility and exact locally normalized RC support.
version 15
clear all
set more off
set linesize 255
args engine_source
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
if `"`engine_source'"' != "" quietly do "`engine_source'"
else _csdid_engine_load
local fx "`root'/tests/fixtures/parity/rt077"

import delimited using "`fx'/inputs/scenarios.csv", clear asdouble varnames(1)
assert _N == 52
tempfile scenarios expected expected_if
save `scenarios'
import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1)
isid scenario fast group time
save `expected'
import delimited using "`fx'/expected/r/inffunc.csv", clear asdouble varnames(1)
isid scenario fast group time unit
save `expected_if'
scalar rt077_maxatt = 0
scalar rt077_maxse = 0
scalar rt077_maxif = 0
forvalues k = 1/52 {
    use `scenarios', clear
    local scenario = scenario[`k']
    local route = route[`k']
    local method = method[`k']
    local weighted = weighted[`k']
    local weight ""
    if `weighted' local weight "[iw=w]"
    local structure "ivar(id)"
    if "`route'" == "rc" local structure "rcs"
    if "`route'" == "unbalanced" local structure "ivar(id) bal(none)"
    if "`route'" == "varying" local structure "ivar(id) fix_weights(varying)"
    use `expected' if scenario == "`scenario'" & fast == 1, clear
    sort group time
    mkmat group time att se, matrix(R_A)
    use `expected' if scenario == "`scenario'" & fast == 0, clear
    sort group time
    mkmat group time att se, matrix(R_B)
    mata: assert(all(abs(st_matrix("R_A")[.,1..3] :- st_matrix("R_B")[.,1..3]) :< 1e-10))
    mata: assert(all((st_matrix("R_A")[.,4] :>= .) :== (st_matrix("R_B")[.,4] :>= .)))
    mata: assert(max(abs(st_matrix("R_A")[.,4] :- st_matrix("R_B")[.,4])) < 1e-10)
    import delimited using "`fx'/inputs/`scenario'.csv", clear asdouble varnames(1)
    quietly csdid y x `weight', time(t) gvar(g) `structure' method(`method') ///
        nevertreated base_period(universal) analytical pointwise storeall
    matrix A = e(attgt)
    matrix IF = e(inffunc)
    matrix U = e(unit_group)
    display as text "RT077 `scenario'"
    mata: assert(rows(st_matrix("A")) == rows(st_matrix("R_A")))
    mata: assert(all(st_matrix("A")[.,1..2] :== st_matrix("R_A")[.,1..2]))
    mata: assert(all((st_matrix("A")[.,4] :>= .) :== (st_matrix("R_A")[.,3] :>= .)))
    mata: assert(all((st_matrix("A")[.,5] :>= .) :== (st_matrix("R_A")[.,4] :>= .)))
    mata: assert(max(abs(st_matrix("A")[.,4] :- st_matrix("R_A")[.,3])) < 1e-10)
    mata: assert(max(abs(st_matrix("A")[.,5] :- st_matrix("R_A")[.,4])) < 1e-10)
    mata: st_numscalar("rt077_maxatt", max((st_numscalar("rt077_maxatt"), max(abs(st_matrix("A")[.,4] :- st_matrix("R_A")[.,3])))))
    mata: st_numscalar("rt077_maxse", max((st_numscalar("rt077_maxse"), max(abs(st_matrix("A")[.,5] :- st_matrix("R_A")[.,4])))))
    forvalues j = 1/10 {
        local group = A[`j',1]
        local time = A[`j',2]
        use `expected_if' if scenario == "`scenario'" & fast == 1 & group == `group' & time == `time', clear
        sort unit
        mkmat unit value, matrix(R_IF)
        mata: assert(rows(st_matrix("IF")) == rows(st_matrix("R_IF")))
        mata: assert(all(st_matrix("U")[.,1] :== st_matrix("R_IF")[.,1]))
        mata: assert(max(abs(st_matrix("IF")[.,`j'] :- st_matrix("R_IF")[.,2])) < 1e-8)
        mata: st_numscalar("rt077_maxif", max((st_numscalar("rt077_maxif"),max(abs(st_matrix("IF")[.,`j'] :- st_matrix("R_IF")[.,2])))))
    }
}

* Every support boundary is computed by did before a nuisance fit is entered.
import delimited using "`fx'/inputs/support.csv", clear asdouble varnames(1)
tempfile support
save `support'
import delimited using "`fx'/expected/r/support.csv", clear asdouble varnames(1)
assert _N == 40
tempfile support_expected
save `support_expected'
forvalues k = 1/40 {
    use `support_expected', clear
    local scenario = scenario[`k']
    local want_dr = dr[`k']
    local want_reg = reg[`k']
    use `support' if scenario == "`scenario'", clear
    mata: z = st_data(., ("d","post","w","k")); w = csdid__normalize_weights(z[.,3]); assert(csdid__rc_outcome_too_few(z[.,1],z[.,2],w,z[1,4],1) == `want_dr'); assert(csdid__rc_outcome_too_few(z[.,1],z[.,2],w,z[1,4],0) == `want_reg')
}
mata:
// Positive raw weights can vanish locally. An exact positive subnormal counts.
d = (0\0\1\1)
p = (0\1\0\1)
x = J(4,1,1), (-1\1\-1\1)
w = (1\0\1\1)
assert(csdid__rcond_fail(x,d) == 0)
assert(csdid__rcond_fail(x,d,w) == 1)
assert(csdid__rcond_fail(x,d,w,0) == 0)
assert(csdid__overlap_status(J(3,1,1),(0\1\1),(0\1\1)) == 1)
assert(csdid__overlap_status(J(3,1,1),(0\1\1),(0\1\1),0) == 0)
// The pooled control design is well conditioned; its weighted design is not.
x = J(6,1,1), (-1\1\-1\1\0\0)
d = (0\0\0\0\1\1)
w = (1\1e-20\1\1e-20\1\1)
assert(csdid__rcond_fail(x,d) == 0)
for (k=1;k<=3;k++) {
    scale = (1e-100,1,1e100)[k]
    assert(csdid__rcond_fail(x,d,w*scale) == 1)
    assert(csdid__rcond_fail(x,d,J(6,1,scale)) == 0)
}
end

* Observe the actual guard contract at every public route. A raw vector of
* unit weights is internal plumbing; it must not turn an omitted user weight
* into the weighted Gram algorithm or trigger support scans. These healthy
* designs pass each real guard above, so the probes preserve their decisions.
mata: mata drop csdid__overlap_status()
mata: mata drop csdid__rcond_fail()
mata:
RT077_GUARD_CALLS = 0
real scalar csdid__overlap_status(real matrix x, real colvector d,
    | real colvector wraw, real scalar has_weights)
{
    external real scalar RT077_GUARD_CALLS
    if (args() >= 3) assert(args() >= 4 & has_weights == 0)
    RT077_GUARD_CALLS = RT077_GUARD_CALLS + 1
    return(0)
}
real scalar csdid__rcond_fail(real matrix x, real colvector d,
    | real colvector wraw, real scalar has_weights)
{
    external real scalar RT077_GUARD_CALLS
    if (args() >= 3) assert(args() >= 4 & has_weights == 0)
    RT077_GUARD_CALLS = RT077_GUARD_CALLS + 1
    return(0)
}
end
foreach route in panel rc unbalanced varying {
    local structure "ivar(id)"
    if "`route'" == "rc" local structure "rcs"
    if "`route'" == "unbalanced" local structure "ivar(id) bal(none)"
    if "`route'" == "varying" local structure "ivar(id) fix_weights(varying)"
    foreach method in reg dr ipw {
        import delimited using "`fx'/inputs/`route'_reg_unweighted.csv", clear asdouble varnames(1)
        local covariates "x"
        if "`method'" == "ipw" local covariates ""
        mata: rt077_before = RT077_GUARD_CALLS
        quietly csdid y `covariates', time(t) gvar(g) `structure' method(`method') ///
            nevertreated base_period(universal) analytical pointwise
        mata: assert(RT077_GUARD_CALLS > rt077_before)
    }
}
display as result "RT077 PASS: max |dATT|=" %12.5g rt077_maxatt " max |dSE|=" %12.5g rt077_maxse " max |dIF|=" %12.5g rt077_maxif
