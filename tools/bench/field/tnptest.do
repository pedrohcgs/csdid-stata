* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do tnptest.do
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
capture file close out
file open out using "`B'/tnptest.csv", write replace text
file write out "variant,rep,h,est" _n
forvalues r = 1/100 {
    quietly sim_dgp, n(1000) seed(`=90000+`r'') regime(balanced) cov
    foreach v in tnp_x1 tnp_both {
        local opt = cond("`v'"=="tnp_x1", "trends_nonparam(x1)", "trends_nonparam(x1 x2)")
        capture quietly did_multiplegt_dyn y id time treated, effects(3) `opt' graphoptions(nodraw)
        if _rc == 0 {
            forvalues h = 0/2 {
                local e = string(e(Effect_`=`h'+1'), "%18.0g")
                file write out "`v',`r',`h',`e'" _n
            }
        }
        else file write out "`v',`r',0,FAILRC`=_rc'" _n
    }
}
file close out
display "TNP done"
