* RT080: unique RC identities, complete-case boundary, and name invariance.
version 15
clear all
set more off
set linesize 240
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt080"
scalar rt080_att = 0
scalar rt080_se = 0
scalar rt080_if = 0
mata:
void rt080_compare_if()
{
    real matrix a, inf, ref
    real colvector hit
    real scalar worst, j, got
    a=st_matrix("A"); inf=st_matrix("I")
            ref=st_data(.,("unit","group","time","value"))
            worst=0
            for (j=1;j<=rows(ref);j++) {
                hit=selectindex((a[.,1]:==ref[j,2]):&(a[.,2]:==ref[j,3]))
                assert(length(hit)==1)
                got=inf[ref[j,1],hit[1]]
                assert(missing(got)==missing(ref[j,4]))
                assert(reldif(got,ref[j,4])<1e-8)
                worst=max((worst,abs(got-ref[j,4])))
            }
            st_numscalar("rt080_if",max((st_numscalar("rt080_if"),worst)))
}
end

foreach route in panel rc unbalanced {
    foreach method in reg ipw dr {
        foreach speed in auto off {
            import delimited "`fx'/inputs/panel.csv", clear asdouble
            local structure "ivar(id)"
            if "`route'" == "rc" local structure "ivar(obsid) rcs"
            if "`route'" == "unbalanced" {
                drop if mod(id,13) == 0 & time == 2
                local structure "ivar(id) bal(none)"
            }
            local slow ""
            if "`speed'" == "off" local slow "nofast"
            quietly csdid y x [iw=w], `structure' time(time) gvar(g) method(`method') ///
                notyet baseperiod(universal) analytical pointwise storeall `slow'
            matrix A = e(attgt)
            matrix I = e(inffunc)
            preserve
            import delimited "`fx'/expected/r/attgt.csv", clear asdouble
            keep if route == "`route'" & method == "`method'"
            sort group time
            assert _N == rowsof(A)
            forvalues k=1/`=_N' {
                assert group[`k'] == A[`k',1] & time[`k'] == A[`k',2]
                assert missing(att[`k']) == missing(A[`k',4])
                assert missing(se[`k']) == missing(A[`k',5])
                assert reldif(att[`k'], A[`k',4]) < 1e-8
                assert reldif(se[`k'], A[`k',5]) < 1e-8
                scalar rt080_att = max(rt080_att, abs(att[`k']-A[`k',4]))
                scalar rt080_se = max(rt080_se, abs(se[`k']-A[`k',5]))
            }
            restore
            preserve
            import delimited "`fx'/expected/r/inffunc.csv", clear asdouble
            keep if route == "`route'" & method == "`method'"
            assert _N == rowsof(I)*colsof(I)
            mata: rt080_compare_if()
            restore
            foreach alias in args tlist cutoff_t V1 {
                rename x `alias'
                quietly csdid y `alias' [iw=w], `structure' time(time) gvar(g) method(`method') ///
                    notyet baseperiod(universal) analytical pointwise storeall `slow'
                mata: assert(mreldif(st_matrix("A"),st_matrix("e(attgt)"))==0)
                mata: assert(mreldif(st_matrix("I"),st_matrix("e(inffunc)"))==0)
                rename `alias' x
            }
        }
    }
}
foreach shape in across within screened missingids {
    import delimited "`fx'/inputs/panel.csv", clear asdouble
    if "`shape'" == "across" replace obsid=id
    if "`shape'" == "within" expand 2 if _n==1
    if "`shape'" == "screened" {
        replace obsid=obsid[1] in 2
        replace y=. in 2
    }
    if "`shape'" == "missingids" replace obsid=. in 1/2
    quietly regress y x
    capture noisily csdid y x, ivar(obsid) rcs time(time) gvar(g) method(reg) analytical pointwise
    local rc=_rc
    assert `rc'==cond("`shape'"=="missingids",0,459)
    if `rc' assert "`e(cmd)'"=="regress"
}
* if/in defines the raw validation sample; duplicates outside it are irrelevant.
import delimited "`fx'/inputs/panel.csv", clear asdouble
replace obsid=obsid[1] in 2
quietly csdid y x if _n!=2, ivar(obsid) rcs time(time) gvar(g) method(reg) analytical pointwise
assert e(N)==449
* Omitted IDs use observation-level sampling even when a repeated ID column exists.
quietly csdid y x, rcs time(time) gvar(g) method(reg) analytical pointwise
assert e(N_units)==450
* The resolved band policy and the user's explicit pointwise request differ.
import delimited "`fx'/inputs/panel.csv", clear asdouble
keep if time<=2
replace g=cond(id<=30,0,2)
quietly csdid y x, ivar(id) time(time) gvar(g) method(reg) wboot(reps(99) rseed(42))
assert e(cband)==0
assert e(pointwise)==0
quietly csdid y x, ivar(id) time(time) gvar(g) method(reg) wboot(reps(99) rseed(42)) pointwise
assert e(cband)==0
assert e(pointwise)==1
display "RT080 max |dATT|=" rt080_att " max |dSE|=" rt080_se " max |dIF|=" rt080_if
display "test-upstream-settling: complete"
