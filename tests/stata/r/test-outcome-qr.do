* RT041 -- REG panel/RC and DR panel coefficients use weighted pivoted QR.
* Exact affine outcomes qualify all three kernels. Ordinary cases pin full IFs
* with clustering, panel cache reuse, unbalanced rows and varying weights.
version 15
clear all
set more off
set linesize 200
args only
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt041"
scalar rt041_maxatt = 0
scalar rt041_maxse = 0
scalar rt041_maxif = 0
scalar rt041_natt = 0
scalar rt041_nif = 0

import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1)
isid scenario group time
assert _N == 30
import delimited using "`fx'/expected/r/inffunc.csv", clear asdouble varnames(1)
isid scenario unit_index group time
assert _N == 1440

mata:
void rt041_compare_if()
{
    real matrix a, inf, ref
    real scalar i, j, unit, want, got, gap, worst
    real colvector hit
    a = st_matrix("A")
    inf = st_matrix("IF")
    ref = st_data(., ("unit_index", "group", "time", "value"))
    assert(rows(ref) == rows(inf) * cols(inf))
    worst = 0
    for (i = 1; i <= rows(ref); i++) {
        unit = ref[i, 1]
        hit = selectindex((a[., 1] :== ref[i, 2]) :& (a[., 2] :== ref[i, 3]))
        assert(rows(hit) == 1)
        j = hit[1]
        assert(unit >= 1 & unit <= rows(inf))
        want = ref[i, 4]
        got = inf[unit, j]
        assert((want >= .) == (got >= .))
        if (want >= .) continue
        gap = abs(got - want)
        assert(gap <= 1e-8 + 1e-8 * abs(want))
        worst = max((worst, gap))
    }
    st_numscalar("rt041_maxif", max((st_numscalar("rt041_maxif"), worst)))
    st_numscalar("rt041_nif", st_numscalar("rt041_nif") + rows(ref))
}
end

import delimited using "`fx'/inputs/scenarios.csv", clear asdouble varnames(1)
local ncases = _N
tempfile specs
save `specs'
forvalues k = 1/`ncases' {
    use `specs', clear
    local s = scenario[`k']
    if "`only'" != "" & "`only'" != "`s'" continue
    local method = method[`k']
    local panel = panel[`k']
    local unbalanced = unbalanced[`k']
    local weighted = weighted[`k']
    local clustered = cluster[`k']
    local fix = fix_weights[`k']
    local structure "rcs"
    if "`panel'" == "TRUE" local structure "ivar(id)"
    if "`unbalanced'" == "TRUE" local structure "ivar(id) bal(none)"
    if "`fix'" != "" local structure "`structure' fixweights(`fix')"
    local weight ""
    if "`weighted'" == "TRUE" local weight "[iw=w]"
    local cluster ""
    if "`clustered'" == "TRUE" local cluster "cluster(cl)"
    local ncells = cond("`panel'" == "TRUE", 3, 2)
    import delimited using "`fx'/inputs/`s'.csv", clear asdouble varnames(1)
    quietly csdid y x1 x2 `weight', time(time) gvar(g) `structure' `cluster' ///
        method(`method') nevertreated base_period(universal) analytical pointwise storeall
    matrix A = e(attgt)
    matrix IF = e(inffunc)
    assert rowsof(A) == `ncells'
    assert colsof(IF) == rowsof(A)
    local nobs = e(N)
    local nunits = e(N_units)
    preserve
    import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1)
    keep if scenario == "`s'"
    assert _N == `ncells'
    forvalues i = 1/`ncells' {
        assert A[`i', 1] == group[`i']
        assert A[`i', 2] == time[`i']
        assert `nobs' == sample_n[`i']
        assert `nunits' == n_units[`i']
        assert missing(A[`i', 4]) == missing(att[`i'])
        assert missing(A[`i', 5]) == missing(se[`i'])
        if !missing(att[`i']) {
            assert abs(A[`i', 4] - att[`i']) <= 1e-10 + 1e-10 * abs(att[`i'])
            scalar rt041_maxatt = max(rt041_maxatt, abs(A[`i', 4] - att[`i']))
        }
        if !missing(se[`i']) {
            assert abs(A[`i', 5] - se[`i']) <= 1e-10 + 1e-10 * abs(se[`i'])
            scalar rt041_maxse = max(rt041_maxse, abs(A[`i', 5] - se[`i']))
        }
        scalar rt041_natt = rt041_natt + 1
    }
    restore
    preserve
    import delimited using "`fx'/expected/r/inffunc.csv", clear asdouble varnames(1)
    keep if scenario == "`s'"
    isid unit_index group time
    mata: rt041_compare_if()
    restore
}
if "`only'" == "" {
    assert rt041_natt == 30
    assert rt041_nif == 1440
}
assert rt041_natt > 0
display as text "RT041 max |dATT| = " %12.5g rt041_maxatt " max |dSE| = " %12.5g rt041_maxse " max |dIF| = " %12.5g rt041_maxif
display as text "test-outcome-qr: requested cells and full influence values match"
