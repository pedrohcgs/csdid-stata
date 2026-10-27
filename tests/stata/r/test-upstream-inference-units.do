* RT078: preserve positive inference under outcome rescaling and anticipation.
version 15
clear all
set more off
set linesize 200
args engine_source
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
if `"`engine_source'"' != "" quietly do "`engine_source'"
local fx "`root'/tests/fixtures/parity/rt078"
foreach m in att se if agg crit wald {
    scalar RT078_max_`m' = 0
}
mata:
void rt078_compare(real matrix a, real matrix e, real scalar scale, string scalar metric)
{
    real colvector d, keep
    real scalar worst
    if (rows(a)!=rows(e) | cols(a)!=cols(e)) _error(9)
    if (any((a:>=.):!=(e:>=.))) {
        errprintf("RT078 %s missingness differs\n",metric)
        _error(9)
    }
    keep=vec(e:<.)
    d=select(vec(abs(a-e)),keep)
    worst=rows(d) ? max(d) : 0
    st_numscalar("RT078_max_"+metric,max((st_numscalar("RT078_max_"+metric),worst)))
    d=select(vec(abs(a/scale-e/scale):/(1:+abs(e/scale))),keep)
    if (rows(d) & max(d)>1e-8) {
        errprintf("RT078 %s scaled max difference %21.15g\n",metric,max(d))
        _error(9)
    }
}
end
program define rt078_matrix
    version 15
    syntax using/, MATRIX(name) SCALE(real) METRIC(string) SCENARIO(string) [KEYS(name) TYPE(string)]
    preserve
    use "`using'",clear
    keep if scenario=="`scenario'"
    if "`type'"!="" keep if type=="`type'"
    if "`keys'"!="" {
        mata: assert(st_matrix("`keys'")[.,1] == st_data(.,"unit"))
    }
    local vars ""
    forvalues j=1/`=colsof(`matrix')' {
        local vars "`vars' v`j'"
    }
    mata: rt078_compare(st_matrix("`matrix'"),st_data(.,tokens("`vars'")),`scale',"`metric'")
    restore
end
tempfile cells ifs diagnostics aggs aggifs criticals
foreach table in cells inffunc diagnostics aggregates agg-inffunc criticals {
    import delimited using "`fx'/expected/r/`table'.csv",clear asdouble varnames(1)
    if "`table'"=="cells" save `cells'
    if "`table'"=="inffunc" save `ifs'
    if "`table'"=="diagnostics" save `diagnostics'
    if "`table'"=="aggregates" save `aggs'
    if "`table'"=="agg-inffunc" save `aggifs'
    if "`table'"=="criticals" save `criticals'
}
import delimited using "`fx'/inputs/scenarios.csv", clear asdouble varnames(1)
tempfile specs
save `specs'
local n = _N
forvalues i=1/`n' {
    use `specs',clear
    local scenario = scenario[`i']
    local route = route[`i']
    local method = method[`i']
    local base = base[`i']
    local ant = anticipation[`i']
    local scale = scale[`i']
    local boot = bootstrap[`i']
    local cl ""
    if cluster[`i'] local cl "cluster(cl)"
    local pan ""
    if "`route'"=="panel" local pan "ivar(id)"
    local inf "analytical pointwise"
    if `boot' local inf "rseed(20261026) reps(199)"
    import delimited using "`fx'/inputs/`route'.csv",clear asdouble varnames(1)
    replace y=y*`scale'
    quietly csdid y, time(time) gvar(g) method(`method') base_period(`base') ///
        anticipation(`ant') `pan' `cl' `inf' storeall
    tempname A IF UG
    matrix `A'=e(attgt)
    matrix `IF'=e(inffunc)
    matrix `UG'=e(unit_group)
    local crit=e(crit_val)
    local wald=.
    local pvalue=.
    capture local wald=e(wald_stat)
    capture local pvalue=e(wald_pvalue)
    preserve
    use `cells',clear
    keep if scenario=="`scenario'"
    mata: assert(st_matrix("`A'")[.,(1,2)]==st_data(.,("group","time")))
    mata: rt078_compare(st_matrix("`A'")[.,4],st_data(.,"att"),`scale',"att")
    mata: rt078_compare(st_matrix("`A'")[.,5],st_data(.,"se"),`scale',"se")
    restore
    rt078_matrix using "`ifs'",matrix(`IF') scale(`scale') metric(if) keys(`UG') scenario(`scenario')
    preserve
    use `diagnostics',clear
    keep if scenario=="`scenario'"
    assert _N==1
    mata: rt078_compare(`crit',st_data(.,"crit"),1,"crit")
    if !missing(wald) {
        mata: rt078_compare(`wald',st_data(.,"wald"),1,"wald")
        assert `pvalue'==pvalue
    }
    restore
    foreach type in dynamic group calendar simple {
        quietly csdid_stats,type(`type')
        matrix `A'=e(aggte)
        matrix `IF'=e(agg_inffunc)
        local crit=e(crit_val)
        * The event/group/calendar keys are calendar labels, not outcomes.
        preserve
        use `aggs',clear
        keep if scenario=="`scenario'" & type=="`type'"
        mata: rt078_compare(st_matrix("`A'")[.,1],st_data(.,"v1"),1,"agg")
        mata: rt078_compare(st_matrix("`A'")[.,2..5],st_data(.,("v2","v3","v4","v5")),`scale',"agg")
        restore
        rt078_matrix using "`aggifs'",matrix(`IF') scale(`scale') metric(if) scenario(`scenario') type(`type')
        preserve
        use `criticals',clear
        keep if scenario=="`scenario'" & type=="`type'"
        mata: rt078_compare(`crit',st_data(.,"crit"),1,"crit")
        restore
    }
    display as text "RT078 `scenario': `route' `method' `base' anticipation(`ant') scale `scale' boot `boot' matches"
}
* The mboot support rule must not square tiny but nonzero draws.
preserve
import delimited using "`fx'/expected/r/tiny-sigma.csv",clear asdouble varnames(1)
forvalues i=1/`=_N' {
    local sc : display %21.17g scale[`i']
    local sigma : display %21.17g sigma[`i']
    mata: assert(abs(csdid__bootstrap_sigma((-2\-1\0\1\2)*`sc',invnormal(.75)-invnormal(.25))/`sigma'-1)<1e-14)
}
restore
mata: assert(csdid__bootstrap_sigma(J(5,1,0),invnormal(.75)-invnormal(.25))>=.)
mata: assert(csdid__bootstrap_sigma((1\2\.\4\5),invnormal(.75)-invnormal(.25))>=.)
mata: assert(csdid__se_from_if((1\.\3))>=.)
* Missing or overflowed cluster columns cannot borrow another column's scale.
import delimited using "`fx'/inputs/cluster-probes.csv",clear asdouble varnames(1)
mata:
rt078_cluster = csdid__Agg()
rt078_cluster.cluster_vec=st_data(.,"cl")
csdid__cluster_layout(rt078_cluster.cluster_vec,rt078_cluster.cl_ord,rt078_cluster.cl_info)
rt078_cluster_if=st_data(.,("missing","overflow","healthy","zero"))
rt078_cluster_se=J(4,1,.)
for(rt078_j=1;rt078_j<=4;rt078_j++) rt078_cluster_se[rt078_j]=rt078_cluster.cluster_se(rt078_cluster_if[.,rt078_j])
st_matrix("RT078_CLUSTER_AGG",rt078_cluster_se)
st_matrix("RT078_CLUSTER_IF",rt078_cluster_if)
st_matrix("RT078_CLUSTER_ATT",J(4,10,1))
st_matrix("RT078_CLUSTER_UNIT",((1::4),J(4,1,0),J(4,1,1)))
csdid_cluster_attgt("cl","","","RT078_CLUSTER_ATT","RT078_CLUSTER_IF","RT078_CLUSTER_UNIT","RT078_CLUSTER_N",1,"RT078_CLUSTER_VEC")
end
import delimited using "`fx'/expected/r/cluster-se.csv",clear asdouble varnames(1)
mata: rt078_compare(st_matrix("RT078_CLUSTER_AGG"),st_data(.,"se"),1,"se")
mata: rt078_compare(st_matrix("RT078_CLUSTER_ATT")[.,5],st_data(.,"se"),1,"se")
import delimited using "`fx'/inputs/overflow-draws.csv",clear asdouble varnames(1)
mata: rt078_overflow=st_data(.,("v1","v2"))
import delimited using "`fx'/expected/r/overflow-crit.csv",clear asdouble varnames(1)
mata: assert(abs(csdid__bootstrap_cband_crit(rt078_overflow,.05,invnormal(.975))-st_data(.,"crit"))<1e-12)
mata: rt078_overflow_att=(1,2,0,1,1\1,3,1,1,1);rt078_c=.;rt078_pc=.
mata: rt078_overflow_out=csdid__boot_table(rt078_overflow_att,rt078_overflow,5,5,0,5,.05,1,rt078_c,rt078_pc)
mata: assert(abs(rt078_c-st_data(.,"crit"))<1e-12)
foreach route in panel rc {
    import delimited using "`fx'/inputs/`route'.csv",clear asdouble varnames(1)
    keep if inlist(time,1,2)
    replace g=cond(g==4,2,0)
    local pan ""
    if "`route'"=="panel" local pan "ivar(id)"
    quietly csdid y,`pan' time(time) gvar(g) method(reg) rseed(20261026) reps(199) storeall
    matrix TWO=e(attgt)
    assert e(cband)==0
    assert e(cband_fallback)==0
    assert e(crit_val)==e(point_crit_val)
    preserve
    import delimited using "`fx'/expected/r/two-period.csv",clear asdouble varnames(1)
    keep if route=="`route'"
    mata: rt078_compare(st_matrix("TWO")[.,4],st_data(.,"att"),1,"att")
    mata: rt078_compare(st_matrix("TWO")[.,5],st_data(.,"se"),1,"se")
    restore
}
* Changing an anticipation outcome moves that cell, while all clean-period
* comparisons and the Wald pretest use the same pre-anticipation base.
foreach base in varying universal {
    import delimited using "`fx'/inputs/panel.csv",clear asdouble varnames(1)
    quietly csdid y,ivar(id) time(time) gvar(g) anticipation(1) base_period(`base') ///
        method(reg) analytical pointwise storeall
    matrix BEFORE=e(attgt)
    local wald_before=e(wald_stat)
    replace y=y+9 if g==4 & time==3
    quietly csdid y,ivar(id) time(time) gvar(g) anticipation(1) base_period(`base') ///
        method(reg) analytical pointwise storeall
    matrix AFTER=e(attgt)
    mata: rt078_changed=(st_matrix("BEFORE")[.,1]:==4):&(st_matrix("BEFORE")[.,2]:==3)
    mata: assert(max(abs(st_matrix("AFTER")[.,4]-st_matrix("BEFORE")[.,4]-9*rt078_changed))<1e-10)
    assert abs(e(wald_stat)-`wald_before')<1e-8
}
foreach m in att se if agg crit wald {
    display as text "RT078 max |d`m'| = " %21.15g scalar(RT078_max_`m')
}
display as text "test-upstream-inference-units: every inference configuration matches"
