* RT083: common sampling-weight scale preserves aggregation ratio derivatives.
version 15
clear all
set more off
set linesize 200
args engine_source
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt083"
if `"`engine_source'"'!="" quietly do "`engine_source'"
foreach m in att se if agg crit wald pvalue derivative {
    scalar RT083_max_`m'=0
}
quietly _csdid_engine_load
mata:
void rt083_compare(real matrix a,real matrix e,string scalar metric)
{
    real colvector d
    real scalar worst
    if(rows(a)!=rows(e) | cols(a)!=cols(e)) _error(9)
    if(any((a:>=.):!=(e:>=.))) {
        errprintf("RT083 %s missingness differs\n",metric)
        _error(9)
    }
    d=select(vec(abs(a-e)),vec(e:<.))
    worst=rows(d)?max(d):0
    st_numscalar("RT083_max_"+metric,max((st_numscalar("RT083_max_"+metric),worst)))
    if(worst>1e-8) {
        errprintf("RT083 %s max absolute discrepancy %21.15g\n",metric,worst)
        _error(9)
    }
}
real matrix rt083_old(real colvector w,real colvector g,real rowvector keep,
    real colvector pg,real colvector group)
{
    real matrix centered
    real colvector rs
    real scalar spg,k
    spg=0
    for(k=1;k<=cols(keep);k++)spg=spg+pg[keep[k]]
    centered=J(rows(w),cols(keep),.)
    for(k=1;k<=cols(keep);k++)centered[.,k]=w:*(g:==group[keep[k]]):-pg[keep[k]]
    rs=rowsum(centered)
    for(k=1;k<=cols(keep);k++)centered[.,k]=centered[.,k]/spg:-rs*(pg[keep[k]]/(spg^2))
    return(centered)
}
end
* The saver is ado-local. Compile its unchanged body under a test name so
* the legacy artifact uses the current production metadata/signature writer.
tempfile production_writer
mata:
rt083_writer=cat(st_local("root")+"/src/ado/csdid.ado")
rt083_start=select((1::rows(rt083_writer)),strpos(rt083_writer,"program define _csdid_save_rif"):==1)
assert(rows(rt083_start)==1)
rt083_writer=rt083_writer[rt083_start[1]..rows(rt083_writer)]
rt083_writer[1]="program define rt083_production_rif_writer"
rt083_fh=fopen(st_local("production_writer"),"w")
for(rt083_j=1;rt083_j<=rows(rt083_writer);rt083_j++)fput(rt083_fh,rt083_writer[rt083_j])
fclose(rt083_fh)
end
quietly do "`production_writer'"
* Independent finite-difference derivatives and repeated selected cohort masses.
import delimited using "`fx'/inputs/ratio-units.csv",clear asdouble varnames(1)
mata: rt083_ag=csdid__Agg();rt083_ag.unit_group=st_data(.,"g");rt083_w=st_data(.,"w")
mata: rt083_group=(2\2\3\3\4);rt083_keep=(1,3,4,5)
local scales "1 1e-200 1e-160 1e160 1e200 1e307"
local i=0
foreach scale of local scales {
    local ++i
    mata: rt083_ag.unit_weight=rt083_w*`scale';rt083_pg=J(5,1,.)
    mata: for(rt083_j=1;rt083_j<=5;rt083_j++)rt083_pg[rt083_j]=mean(rt083_ag.unit_weight:*(rt083_ag.unit_group:==rt083_group[rt083_j]))
    mata: st_matrix("RT083_WIF",rt083_ag.weight_if(rt083_keep,rt083_pg,rt083_group))
    import delimited using "`fx'/expected/r/ratio-`i'.csv",clear asdouble varnames(1)
    mata: rt083_compare(st_matrix("RT083_WIF"),st_data(.,("x1","x2","x3","x4")),"if")
}
import delimited using "`fx'/expected/r/ratio-derivatives.csv",clear asdouble varnames(1)
mata: rt083_compare(st_matrix("RT083_WIF"),st_data(.,("d1","d2","d3","d4")),"if")
mata: rt083_compare(st_matrix("RT083_WIF"),st_data(.,("fd1","fd2","fd3","fd4")),"derivative")
* Preserve the established arithmetic exactly whenever its intermediate values
* are representable, including the original invalid-input all-missing result.
import delimited using "`fx'/inputs/ordinary-units.csv",clear asdouble varnames(1)
mata: rt083_ag.unit_group=st_data(.,"g");rt083_w=st_data(.,"w");rt083_group=(2\2\3);rt083_keep=(1,2,3)
local i=0
foreach scale in 1e-100 1 1e100 {
    local ++i
    mata: rt083_ag.unit_weight=rt083_w*`scale';rt083_pg=J(3,1,.)
    mata: for(rt083_j=1;rt083_j<=3;rt083_j++)rt083_pg[rt083_j]=mean(rt083_ag.unit_weight:*(rt083_ag.unit_group:==rt083_group[rt083_j]))
    mata: rt083_actual=rt083_ag.weight_if(rt083_keep,rt083_pg,rt083_group)
    mata: assert(rt083_actual==rt083_old(rt083_ag.unit_weight,rt083_ag.unit_group,rt083_keep,rt083_pg,rt083_group))
    mata: st_matrix("RT083_WIF",rt083_actual)
    import delimited using "`fx'/expected/r/ordinary-`i'.csv",clear asdouble varnames(1)
    mata: rt083_compare(st_matrix("RT083_WIF"),st_data(.,("x1","x2","x3")),"if")
}
forvalues i=1/3 {
    mata: rt083_ag.unit_weight=J(12,1,1);rt083_pg=(`i'==1?(0\0\0):(`i'==2?(.\1\1):(-1\-1\2)))
    mata: rt083_actual=rt083_ag.weight_if(rt083_keep,rt083_pg,rt083_group)
    mata: assert(rt083_actual==rt083_old(rt083_ag.unit_weight,rt083_ag.unit_group,rt083_keep,rt083_pg,rt083_group))
    mata: st_matrix("RT083_WIF",rt083_actual)
    import delimited using "`fx'/expected/r/invalid-`i'.csv",clear asdouble varnames(1)
    mata: rt083_compare(st_matrix("RT083_WIF"),st_data(.,("x1","x2","x3")),"if")
}
import delimited using "`fx'/inputs/overflow-units.csv",clear asdouble varnames(1)
mata: rt083_ag.unit_group=st_data(.,"g");rt083_ag.unit_weight=J(24,1,1e307);rt083_group=2:+mod((1::80):+1,2);rt083_keep=1..80
mata: st_matrix("RT083_WIF",rt083_ag.weight_if(rt083_keep,J(80,1,1e307/3),rt083_group))
import delimited using "`fx'/expected/r/repeated-mass-overflow.csv",clear asdouble varnames(1)
local vars ""
forvalues j=1/80 {
    local vars "`vars' x`j'"
}
mata: rt083_compare(st_matrix("RT083_WIF"),st_data(.,tokens("`vars'")),"if")
program define rt083_matrix
    version 15
    syntax using/, MATRIX(name) METRIC(string) SCENARIO(string) [KEYS(name) TYPE(string)]
    preserve
    use "`using'",clear
    keep if scenario=="`scenario'"
    if "`type'"!="" keep if type=="`type'"
    if "`keys'"!="" mata: assert(st_matrix("`keys'")[.,1]==st_data(.,"unit"))
    local vars ""
    forvalues j=1/`=colsof(`matrix')' {
        local vars "`vars' v`j'"
    }
    mata: rt083_compare(st_matrix("`matrix'"),st_data(.,tokens("`vars'")),"`metric'")
    restore
end
program define rt083_write_legacy_raw_rif, eclass
    version 15
    syntax using/
    * Reconstruct the valid balanced-panel weight fields the previous writer
    * received. The production writer signs this artifact; nothing is edited
    * after writing, and no integrity check is bypassed.
    tempname UG GP
    matrix `UG'=e(unit_group)
    matrix `GP'=e(group_prob)
    mata: rt083_raw_id=select(st_data(.,"id"),st_data(.,"time"):==1)
    mata: rt083_raw_weight=select(st_data(.,"w"),st_data(.,"time"):==1)
    mata: assert(rt083_raw_id==st_matrix("`UG'")[.,1])
    mata: assert(min(rt083_raw_weight)>0 & max(rt083_raw_weight)<2.2250738585072014e-308)
    mata: rt083_legacy_ug=st_matrix("`UG'");rt083_legacy_ug[.,3]=rt083_raw_weight
    mata: rt083_legacy_gp=st_matrix("`GP'")
    mata: for(rt083_j=1;rt083_j<=rows(rt083_legacy_gp);rt083_j++)rt083_legacy_gp[rt083_j,2]=sum(rt083_raw_weight:*(rt083_legacy_ug[.,2]:==rt083_legacy_gp[rt083_j,1]))/rows(rt083_legacy_ug)
    mata: st_matrix("`UG'",rt083_legacy_ug);st_matrix("`GP'",rt083_legacy_gp)
    ereturn matrix unit_group=`UG'
    ereturn matrix group_prob=`GP'
    quietly rt083_production_rif_writer using "`using'",replace
end
tempfile cells ifs aggs aggifs criticals diagnostics specs
foreach table in cells ifs aggs aggifs criticals diagnostics {
    import delimited using "`fx'/expected/r/`table'.csv",clear asdouble varnames(1)
    save ``table''
}
import delimited using "`fx'/inputs/scenarios.csv",clear asdouble varnames(1)
save `specs'
local n=_N
forvalues i=1/`n' {
    use `specs',clear
    local scenario=scenario[`i']
    local route=route[`i']
    local method=method[`i']
    local scale : display %21.17g scale[`i']
    local subnormal=subnormal[`i']
    local boot=bootstrap[`i']
    local pan ""
    if "`route'"!="rc" local pan "ivar(id)"
    if "`route'"=="unbalanced" local pan "ivar(id) bal(none) fix_weights(varying)"
    local inf "analytical pointwise"
    if `boot' local inf "rseed(20261029) reps(99)"
    local input "`route'"
    if `subnormal' local input "`route'-subnormal"
    import delimited using "`fx'/inputs/`input'.csv",clear asdouble varnames(1)
    if !`subnormal' replace w=w*`scale'
    tempfile rif
    quietly csdid y x [iw=w],time(time) gvar(g) method(`method') `pan' `inf' storeall saverif(`rif') replace
    estimates store rt083_fit
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
    mata: assert(st_matrix("`A'")[.,(1,2)]==st_data(.,("group","time")))
    mata: rt083_compare(st_matrix("`A'")[.,4],st_data(.,"att"),"att")
    mata: rt083_compare(st_matrix("`A'")[.,5],st_data(.,"se"),"se")
    restore
    rt083_matrix using "`ifs'",matrix(`IF') metric(if) keys(`UG') scenario(`scenario')
    preserve
    use `diagnostics',clear
    keep if scenario=="`scenario'"
    mata: rt083_compare(`crit',st_data(.,"crit"),"crit")
    mata: rt083_compare(`wald',st_data(.,"wald"),"wald")
    mata: rt083_compare(`pvalue',st_data(.,"pvalue"),"pvalue")
    restore
    foreach type in dynamic group calendar simple {
        quietly csdid_stats,type(`type')
        matrix `A'=e(aggte)
        matrix `IF'=e(agg_inffunc)
        local crit=e(crit_val)
        preserve
        use `aggs',clear
        keep if scenario=="`scenario'" & type=="`type'"
        mata: rt083_compare(st_matrix("`A'"),st_data(.,("v1","v2","v3","v4","v5")),"agg")
        restore
        rt083_matrix using "`aggifs'",matrix(`IF') metric(if) keys(`UG') scenario(`scenario') type(`type')
        preserve
        use `criticals',clear
        keep if scenario=="`scenario'" & type=="`type'"
        mata: rt083_compare(`crit',st_data(.,"crit"),"crit")
        restore
    }
    * Saved RIFs carry analytical inference; bootstrap chains use the direct fit.
    if !`boot' {
        foreach type in dynamic group calendar simple {
            quietly csdid_stats using "`rif'",type(`type')
            matrix `A'=e(aggte)
            matrix `IF'=e(agg_inffunc)
            preserve
            use `aggs',clear
            keep if scenario=="`scenario'" & type=="`type'"
            mata: rt083_compare(st_matrix("`A'"),st_data(.,("v1","v2","v3","v4","v5")),"agg")
            restore
            rt083_matrix using "`aggifs'",matrix(`IF') metric(if) keys(`UG') scenario(`scenario') type(`type')
        }
    }
    if `subnormal' & "`route'"=="panel" & !`boot' {
        quietly estimates restore rt083_fit
        tempfile legacy_rif
        quietly rt083_write_legacy_raw_rif using "`legacy_rif'"
        foreach type in dynamic group calendar simple {
            quietly csdid_stats using "`legacy_rif'",type(`type')
            matrix `A'=e(aggte)
            matrix `IF'=e(agg_inffunc)
            preserve
            use `aggs',clear
            keep if scenario=="`scenario'" & type=="`type'"
            mata: rt083_compare(st_matrix("`A'"),st_data(.,("v1","v2","v3","v4","v5")),"agg")
            restore
            rt083_matrix using "`aggifs'",matrix(`IF') metric(if) keys(`UG') scenario(`scenario') type(`type')
        }
        display as text "RT083 `scenario': valid legacy raw-weight RIF matches all four aggregations"
    }
    display as text "RT083 `scenario': `route' `method' scale `scale' bootstrap `boot' matches"
}
* Repeated post-treatment cohort masses can overflow the raw share denominator
* on a public long-calendar fit, before the weight-IF calculation is entered.
foreach periods in 23 40 {
foreach huge in 0 1 {
    local scale "1"
    if `huge' local scale "1e307"
    import delimited using "`fx'/inputs/repeated-public.csv",clear asdouble varnames(1)
    keep if time<=`periods'
    generate double w=basew*`scale'
    tempfile rif
    quietly csdid y [iw=w],ivar(id) time(time) gvar(g) method(reg) nevertreated ///
        analytical pointwise storeall saverif(`rif') replace
    tempname A IF
    matrix `A'=e(attgt)
    preserve
    import delimited using "`fx'/expected/r/repeated-public-cells.csv",clear asdouble varnames(1)
    keep if periods==`periods' & huge==`huge'
    mata: assert(st_matrix("`A'")[.,(1,2)]==st_data(.,("group","time")))
    mata: rt083_compare(st_matrix("`A'")[.,4],st_data(.,"att"),"att")
    mata: rt083_compare(st_matrix("`A'")[.,5],st_data(.,"se"),"se")
    restore
    foreach route in direct saved {
        if "`route'"=="direct" quietly csdid_stats simple
        else quietly csdid_stats using "`rif'",type(simple)
        matrix `A'=e(aggte)
        matrix `IF'=e(agg_inffunc)
        preserve
        import delimited using "`fx'/expected/r/repeated-public-aggregate.csv",clear asdouble varnames(1)
        keep if periods==`periods' & huge==`huge'
        mata: rt083_compare(st_matrix("`A'")[.,(2,3)],st_data(.,("att","se")),"agg")
        restore
        preserve
        import delimited using "`fx'/expected/r/repeated-public-inffunc.csv",clear asdouble varnames(1)
        keep if periods==`periods' & huge==`huge'
        mata: rt083_compare(st_matrix("`IF'"),st_data(.,("value","value")),"if")
        restore
    }
    display as text "RT083 repeated public masses: `periods' periods scale `scale' direct/saved match"
}
}
foreach m in att se if agg crit wald pvalue derivative {
    display as text "RT083 max |d`m'| = " %21.15g scalar(RT083_max_`m')
}
display as text "test-aggregation-weight-scale: complete ratio, cell and aggregate influence functions match"
