* RT084/D029: ordinary raw R and the explicitly approved stable boundary.
version 15
clear all
set more off
set linesize 255
args engine_source artifact_dir
local root "`c(pwd)'"
local fx "`root'/tests/fixtures/parity/rt084"
capture mkdir "`root'/build"
capture mkdir "`root'/build/rt084-isolation"
foreach dir in plus personal oldplace {
    capture mkdir "`root'/build/rt084-isolation/`dir'"
}
sysdir set PLUS "`root'/build/rt084-isolation/plus"
sysdir set PERSONAL "`root'/build/rt084-isolation/personal"
sysdir set OLDPLACE "`root'/build/rt084-isolation/oldplace"
capture adopath - SITE
capture adopath - "."
adopath ++ "`root'/pkg"
quietly findfile csdid.ado
assert `"`r(fn)'"'==`"`root'/pkg/csdid.ado"'
if `"`engine_source'"'!="" quietly do "`engine_source'"
quietly _csdid_engine_load
if `"`engine_source'"'=="" assert "$CSDID_ENGINE_LIBRARY"=="`root'/pkg/lcsdid_v2.mlib"
if `"`artifact_dir'"'=="" local artifact_dir "`root'/build/rt084-artifacts"
capture mkdir "`artifact_dir'"
foreach metric in att se if agg crit wald pvalue {
    scalar RT084_max_`metric'=0
}
mata:
real colvector rt084_order(real matrix expected,real matrix actual)
{
    real scalar i
    real colvector index,found
    assert(cols(expected)==cols(actual) & rows(expected)==rows(actual))
    index=J(rows(actual),1,.)
    for(i=1;i<=rows(actual);i++) {
        found=select((1::rows(expected)),rowsum(expected:==J(rows(expected),1,1)*actual[i,.]):==cols(expected))
        assert(rows(found)==1)
        index[i]=found[1]
    }
    assert(rows(uniqrows(sort(index,1)))==rows(index))
    return(index)
}
void rt084_compare(real matrix actual,real matrix expected,string scalar metric,string scalar scenario)
{
    real colvector difference
    real scalar worst,tolerance
    assert(rows(actual)==rows(expected) & cols(actual)==cols(expected))
    if(any((actual:>=.):!=(expected:>=.))) {
        errprintf("RT084 %s %s missingness differs\n",scenario,metric)
        _error(9)
    }
    difference=select(vec(abs(actual-expected)),vec(expected:<.))
    worst=rows(difference)?max(difference):0
    st_numscalar("RT084_max_"+metric,max((st_numscalar("RT084_max_"+metric),worst)))
    tolerance=metric=="if"?1e-8:1e-10
    if(worst>tolerance) {
        errprintf("RT084 %s %s discrepancy %21.15g exceeds %g\n",scenario,metric,worst,tolerance)
        _error(9)
    }
}
end
import delimited using "`fx'/expected/contract/approved-divergence.csv",clear varnames(1)
assert _N==1
assert divergence_id=="RT084-DIV001" & decision_ref=="D029" & status=="approved-divergence"
tempfile cells ifs aggs aggifs criticals diagnostics specs
foreach table in cells ifs aggs aggifs criticals diagnostics {
    import delimited using "`fx'/expected/contract/stata/`table'.csv",clear asdouble varnames(1)
    save ``table''
}
import delimited using "`fx'/expected/contract/stata/scenarios.csv",clear asdouble varnames(1)
save `specs'
local count=_N
forvalues i=1/`count' {
    use `specs',clear
    local scenario=scenario[`i']
    local case=case[`i']
    local method=method[`i']
    local boot=bootstrap[`i']
    local inference "analytical pointwise"
    if `boot' local inference "reps(99) rseed(20261030)"
    use "`fx'/inputs/`case'.dta",clear
    isid id time
    assert _N==640
    local rif "`artifact_dir'/`scenario'-rif.dta"
    quietly csdid y x [iw=w],ivar(id) time(time) gvar(g) method(`method') ///
        notyet base_period(universal) bal(full) `inference' storeall saverif(`rif') replace
    estimates store rt084_fit
    tempname A IF UG
    matrix `A'=e(attgt)
    matrix `IF'=e(inffunc)
    matrix `UG'=e(unit_group)
    local crit=e(crit_val)
    local wald=e(wald_stat)
    local pvalue=e(wald_pvalue)
    preserve
    use `cells',clear
    keep if scenario=="`scenario'"
    if "`case'"=="ordinary" assert reference=="raw-input"
    else assert reference=="period-normalized-input-diagnostic"
    mata: rt084_cell_order=rt084_order(st_data(.,("group","time")),st_matrix("`A'")[.,(1,2)])
    mata: rt084_compare(st_matrix("`A'")[.,4],st_data(.,"att")[rt084_cell_order],"att","`scenario'")
    mata: rt084_compare(st_matrix("`A'")[.,5],st_data(.,"se")[rt084_cell_order],"se","`scenario'")
    restore
    preserve
    use `ifs',clear
    keep if scenario=="`scenario'"
    local vars ""
    forvalues j=1/`=colsof(`IF')' {
        local vars "`vars' v`j'"
    }
    mata: rt084_unit_order=rt084_order(st_data(.,"unit"),st_matrix("`UG'")[.,1])
    mata: rt084_expected=st_data(.,tokens("`vars'"))[rt084_unit_order,rt084_cell_order]
    mata: rt084_compare(st_matrix("`IF'"),rt084_expected,"if","`scenario'")
    restore
    preserve
    use `diagnostics',clear
    keep if scenario=="`scenario'"
    mata: rt084_compare(`crit',st_data(.,"crit"),"crit","`scenario'")
    mata: rt084_compare(`wald',st_data(.,"wald"),"wald","`scenario'")
    mata: rt084_compare(`pvalue',st_data(.,"pvalue"),"pvalue","`scenario'")
    restore
    foreach type in dynamic group calendar simple {
        quietly csdid_stats,type(`type')
        matrix `A'=e(aggte)
        matrix `IF'=e(agg_inffunc)
        local crit=e(crit_val)
        preserve
        use `aggs',clear
        keep if scenario=="`scenario'" & type=="`type'"
        mata: rt084_agg_order=rt084_order(st_data(.,"v1"),st_matrix("`A'")[.,1])
        mata: rt084_compare(st_matrix("`A'"),st_data(.,("v1","v2","v3","v4","v5"))[rt084_agg_order,.],"agg","`scenario' `type'")
        restore
        preserve
        use `aggifs',clear
        keep if scenario=="`scenario'" & type=="`type'"
        local vars ""
        forvalues j=1/`=colsof(`IF')' {
            local vars "`vars' v`j'"
        }
        mata: rt084_unit_order=rt084_order(st_data(.,"unit"),st_matrix("`UG'")[.,1])
        mata: rt084_expected=st_data(.,tokens("`vars'"))[rt084_unit_order,(rt084_agg_order\rows(rt084_agg_order)+1)]
        mata: rt084_compare(st_matrix("`IF'"),rt084_expected,"if","`scenario' `type'")
        restore
        preserve
        use `criticals',clear
        keep if scenario=="`scenario'" & type=="`type'"
        mata: rt084_compare(`crit',st_data(.,"crit"),"crit","`scenario' `type'")
        restore
    }
    if !`boot' {
        foreach type in dynamic group calendar simple {
            quietly csdid_stats using "`rif'",type(`type')
            matrix `A'=e(aggte)
            matrix `IF'=e(agg_inffunc)
            preserve
            use `aggs',clear
            keep if scenario=="`scenario'" & type=="`type'"
            mata: rt084_agg_order=rt084_order(st_data(.,"v1"),st_matrix("`A'")[.,1])
            mata: rt084_compare(st_matrix("`A'"),st_data(.,("v1","v2","v3","v4","v5"))[rt084_agg_order,.],"agg","`scenario' saved `type'")
            restore
            preserve
            use `aggifs',clear
            keep if scenario=="`scenario'" & type=="`type'"
            local vars ""
            forvalues j=1/`=colsof(`IF')' {
                local vars "`vars' v`j'"
            }
            mata: rt084_unit_order=rt084_order(st_data(.,"unit"),st_matrix("`UG'")[.,1])
            mata: rt084_expected=st_data(.,tokens("`vars'"))[rt084_unit_order,(rt084_agg_order\rows(rt084_agg_order)+1)]
            mata: rt084_compare(st_matrix("`IF'"),rt084_expected,"if","`scenario' saved `type'")
            restore
        }
    }
    display as text "RT084 `scenario': approved contract cells, all four aggregations and full influence functions match"
}
display as text "RT084 complete: 12 actual configurations match the scoped D029 contract; genuine raw R retained separately"
