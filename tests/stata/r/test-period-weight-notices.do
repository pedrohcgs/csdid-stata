* RT084: R notices inspect normalized full screened per-unit ranges.
version 15
clear all
set more off
set linesize 255
args case_filter engine_source
local root "`c(pwd)'"
local fx "`root'/tests/fixtures/parity/rt084"
capture mkdir "`root'/build"
capture mkdir "`root'/build/rt084-notice-isolation"
foreach dir in plus personal oldplace {
    capture mkdir "`root'/build/rt084-notice-isolation/`dir'"
}
sysdir set PLUS "`root'/build/rt084-notice-isolation/plus"
sysdir set PERSONAL "`root'/build/rt084-notice-isolation/personal"
sysdir set OLDPLACE "`root'/build/rt084-notice-isolation/oldplace"
capture adopath - SITE
capture adopath - "."
adopath ++ "`root'/pkg"
if `"`engine_source'"'!="" quietly do "`engine_source'"
quietly _csdid_engine_load
if `"`engine_source'"'=="" assert "$CSDID_ENGINE_LIBRARY"=="`root'/pkg/lcsdid_v2.mlib"
mata:
void rt084_notice_check(string scalar path,real scalar expected,string scalar body,string scalar label)
{
    string colvector lines
    string scalar joined,line
    real scalar hits,j
    lines=cat(path)
    hits=0
    for(j=1;j<=rows(lines);j++)hits=hits+(strpos(lines[j],"Time-varying weights detected.")>0)
    if(hits!=expected) {
        errprintf("RT084 notice %s count %g expected %g\n",label,hits,expected)
        _error(9)
    }
    if(hits) {
        joined=""
        for(j=1;j<=rows(lines);j++) {
            line=strtrim(lines[j])
            if(substr(line,1,1)==">")line=strtrim(substr(line,2,.))
            joined=joined+" "+line
        }
        joined=invtokens(tokens(joined))
        if(!strpos(subinstr(joined," ",""),subinstr(invtokens(tokens(body))," ",""))) {
            errprintf("RT084 notice %s does not preserve the R message body\n",label)
            _error(9)
        }
    }
}
end
tempfile notices
import delimited using "`fx'/expected/r/notice-cases.csv",clear asdouble varnames(1) bindquote(strict)
save `notices'
local count=_N
forvalues i=1/`count' {
    use `notices',clear
    local case=notice_case[`i']
    if `"`case_filter'"'!="" & "`case'"!="constant" & "`case'"!="`case_filter'" continue
    local expected=emit[`i']
    local body=body[`i']
    use "`fx'/inputs/ordinary.dta",clear
    if "`case'"=="range_eps" {
        replace w=1
        replace w=1+1e-8 if time==2
        replace w=1-1e-8 if time==3
    }
    if inlist("`case'","balanced_away","first_treated") replace w=2*w if id==1 & time==2
    if "`case'"=="balanced_away" drop if id==1 & time==4
    if "`case'"=="first_treated" replace g=1 if id==1
    local transcript "`root'/build/rt084-notice-isolation/`case'.log"
    capture log close rt084_notice
    quietly log using "`transcript'",text name(rt084_notice) replace
    quietly csdid y x [iw=w],ivar(id) time(time) gvar(g) method(reg) ///
        notyet base_period(universal) bal(full) analytical pointwise
    quietly log close rt084_notice
    confirm file "`transcript'"
    mata: rt084_notice_check(st_local("transcript"),strtoreal(st_local("expected")),st_local("body"),st_local("case"))
    display as text "RT084 notice `case': R count and path-neutral body match"
}
display as text "RT084 notices complete"
