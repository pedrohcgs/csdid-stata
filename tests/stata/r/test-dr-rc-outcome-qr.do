* RT039 -- DR RC outcome coefficients use QR of the weighted design.
* Affine outcomes expose residuals manufactured by solving normal equations;
* the remaining cases pin ordinary ATT, SE and every IF value on all routes
* that reach this kernel, including balanced-panel fixweights(varying).
version 15
clear all
set more off
set linesize 200
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt039"
scalar rt039_maxatt = 0
scalar rt039_maxse = 0
scalar rt039_maxif = 0
scalar rt039_natt = 0
scalar rt039_nif = 0

import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1)
isid scenario group time
assert _N == 14
import delimited using "`fx'/expected/r/inffunc.csv", clear asdouble varnames(1)
isid scenario unit_index group time
assert _N == 800

mata:
void rt039_compare_if()
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
    st_numscalar("rt039_maxif", max((st_numscalar("rt039_maxif"), worst)))
    st_numscalar("rt039_nif", st_numscalar("rt039_nif") + rows(ref))
}
end

foreach s in affine_rc affine_rc_weighted affine_unbalanced affine_unbalanced_weighted regular_rc regular_unbalanced regular_balanced_varying {
    import delimited using "`fx'/inputs/`s'.csv", clear asdouble varnames(1)
    local structure "rcs"
    if strpos("`s'", "unbalanced") local structure "ivar(id) bal(none)"
    if "`s'" == "regular_balanced_varying" local structure "ivar(id) bal(full) fixweights(varying)"
    local weight ""
    if strpos("`s'", "weighted") | strpos("`s'", "regular") local weight "[iw=w]"
    local cluster ""
    if "`s'" == "affine_unbalanced_weighted" | strpos("`s'", "regular") local cluster "cluster(cl)"
    quietly csdid y x1 x2 `weight', time(time) gvar(g) `structure' `cluster' ///
        method(dr) nevertreated base_period(universal) analytical pointwise storeall
    matrix A = e(attgt)
    matrix IF = e(inffunc)
    assert rowsof(A) == 2
    assert colsof(IF) == rowsof(A)
    local nobs = e(N)
    local nunits = e(N_units)
    preserve
    import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1)
    keep if scenario == "`s'"
    assert _N == 2
    forvalues i = 1/2 {
        assert A[`i', 1] == group[`i']
        assert A[`i', 2] == time[`i']
        assert `nobs' == sample_n[`i']
        assert `nunits' == n_units[`i']
        assert missing(A[`i', 4]) == missing(att[`i'])
        assert missing(A[`i', 5]) == missing(se[`i'])
        if !missing(att[`i']) {
            assert abs(A[`i', 4] - att[`i']) <= 1e-10 + 1e-10 * abs(att[`i'])
            scalar rt039_maxatt = max(rt039_maxatt, abs(A[`i', 4] - att[`i']))
        }
        if !missing(se[`i']) {
            assert abs(A[`i', 5] - se[`i']) <= 1e-10 + 1e-10 * abs(se[`i'])
            scalar rt039_maxse = max(rt039_maxse, abs(A[`i', 5] - se[`i']))
        }
        scalar rt039_natt = rt039_natt + 1
    }
    restore
    preserve
    import delimited using "`fx'/expected/r/inffunc.csv", clear asdouble varnames(1)
    keep if scenario == "`s'"
    isid unit_index group time
    mata: rt039_compare_if()
    restore
}
assert rt039_natt == 14
assert rt039_nif == 800
display as text "RT039 max |dATT| = " %12.5g rt039_maxatt " max |dSE| = " %12.5g rt039_maxse " max |dIF| = " %12.5g rt039_maxif
display as text "test-dr-rc-outcome-qr: all 14 cells and 800 influence values match"
