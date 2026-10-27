* RT079: preserve common original support before missing-cell/display filters.
version 15
clear all
set more off
set linesize 200
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt079"
scalar RT079_max_att=0
scalar RT079_max_se=0
scalar RT079_max_if=0
mata:
void rt079_compare(real matrix a, real matrix e, string scalar metric)
{
    real colvector d
    real scalar worst
    if(rows(a)!=rows(e) | cols(a)!=cols(e)) _error(9)
    if(any((a:>=.):!=(e:>=.))) _error(9)
    d=select(vec(abs(a-e)),vec(e:<.))
    worst=rows(d)?max(d):0
    if(metric!="") st_numscalar("RT079_max_"+metric,max((st_numscalar("RT079_max_"+metric),worst)))
    if(worst>1e-8) {
        errprintf("RT079 %s max absolute discrepancy %21.15g\n",metric,worst)
        _error(9)
    }
}
end
tempfile specs aggs ifs statuses
import delimited using "`fx'/inputs/scenarios.csv",clear asdouble varnames(1)
save `specs'
local cases=_N
import delimited using "`fx'/expected/r/aggregates.csv",clear asdouble varnames(1)
save `aggs'
import delimited using "`fx'/expected/r/inffunc.csv",clear asdouble varnames(1)
save `ifs'
import delimited using "`fx'/expected/r/status.csv",clear asdouble varnames(1)
save `statuses'
local prior_input ""
forvalues i=1/`cases' {
    use `specs',clear
    local input=input[`i']
    local scenario=scenario[`i']
    local type=type[`i']
    local lo=mine[`i']
    local hi=maxe[`i']
    if missing(`lo') local lo=-1e300
    if missing(`hi') local hi=1e300
    local balance=balance[`i']
    local bal ""
    if `balance'>=0 local bal "balance(`balance')"
    use `statuses',clear
    keep if scenario=="`scenario'"
    assert _N==1
    local refused=refused[1]
    local ignored=ignored[1]
    if "`input'"!="`prior_input'" {
        import delimited using "`fx'/inputs/`input'.csv",clear asdouble varnames(1)
        tempfile rif
        quietly csdid y,ivar(id) time(time) gvar(g) method(reg) nevertreated ///
            bal(none) base_period(universal) analytical pointwise storeall saverif(`rif') replace
        estimates store rt079_fit
        local prior_input "`input'"
    }
    local routes "direct saved"
    if `balance'<0 local routes "direct estat saved"
    foreach route of local routes {
        quietly estimates restore rt079_fit
        local cmd "csdid_stats `type'"
        if "`route'"=="estat" local cmd "estat `type'"
        if "`route'"=="saved" local cmd `"csdid_stats using "`rif'", type(`type')"'
        else local cmd "`cmd',"
        tempfile lg
        quietly log using "`lg'",text replace name(rt079)
        capture noisily `cmd' window(`lo' `hi') `bal' dropmissing
        local rc=_rc
        quietly log close rt079
        if `refused' {
            assert `rc'==498
            assert strpos(fileread("`lg'"),"window()")>0 | strpos(fileread("`lg'"),"balance()")>0
            if `balance'>=0 & `balance'!=10 {
                assert strpos(fileread("`lg'"),"balance()")>0
            }
        }
        else {
            assert `rc'==0
            if `ignored' assert strpos(fileread("`lg'"),"ignored")>0
            tempname A IF
            matrix `A'=e(aggte)
            matrix `IF'=e(agg_inffunc)
            preserve
            use `aggs',clear
            keep if scenario=="`scenario'"
            mata: rt079_compare(st_matrix("`A'")[.,1],st_data(.,"event"),"")
            mata: rt079_compare(st_matrix("`A'")[.,(2,4)],st_data(.,("att","overall")),"att")
            mata: rt079_compare(st_matrix("`A'")[.,(3,5)],st_data(.,("se","overall_se")),"se")
            restore
            preserve
            use `ifs',clear
            keep if scenario=="`scenario'"
            local vlist ""
            forvalues j=1/`=colsof(`IF')' {
                local vlist "`vlist' v`j'"
            }
            mata: rt079_compare(st_matrix("`IF'"),st_data(.,tokens("`vlist'")),"if")
            restore
        }
    }
    display as text "RT079 `scenario' `input' `type': direct/estat/saved-RIF match"
}
* A full original grid with only pre-treatment cells refuses every type by name.
program define rt079_onlypre, eclass
    version 15
    tempname A
    matrix `A'=e(attgt)
    mata: st_matrix("`A'",(st_matrix("`A'")[.,1]:+100,st_matrix("`A'")[.,2..10]))
    ereturn matrix attgt=`A'
end
quietly estimates restore rt079_fit
rt079_onlypre
foreach type in simple group dynamic calendar {
    tempfile lg
    quietly log using "`lg'",text replace name(rt079)
    capture noisily csdid_stats `type'
    local rc=_rc
    quietly log close rt079
    assert `rc'==498
    assert strpos(fileread("`lg'"),"no post-treatment ATT(g,t)")>0
}
foreach m in att se if {
    display as text "RT079 max |d`m'| = " %21.15g scalar(RT079_max_`m')
}
display as text "test-upstream-aggregation-support: calendar windows and common original support match"
