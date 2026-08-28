* Temporary: which estat path burns the time at n=100k -- not part of suite.
clear all
set more off
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"
mkpanel, n(100000)
tempfile d
quietly save "`d'", replace

capture file close out
file open out using "aggdiag.csv", write replace text
file write out "fit,storage,fit_seconds,estat_seconds" _n

foreach fit in analytical wboot {
    foreach stor in default lean {
        use "`d'", clear
        local sopt = cond("`stor'" == "lean", "storage(lean)", "")
        local fopt = cond("`fit'" == "wboot", "wboot(reps(999) rseed(20260729))", "analytical pointwise")
        timer clear 8
        timer on 8
        capture quietly csdid y, ivar(id) time(time) gvar(gvar) `fopt' `sopt'
        timer off 8
        if _rc {
            file write out "`fit',`stor',rc`=_rc',." _n
            continue
        }
        timer clear 9
        timer on 9
        capture quietly estat event
        timer off 9
        local erc = _rc
        quietly timer list 8
        local vf = string(r(t8), "%12.0g")
        quietly timer list 9
        local ve = cond(`erc', "rc`erc'", string(r(t9), "%12.0g"))
        file write out "`fit',`stor',`vf',`ve'" _n
    }
}
file close out
display "MCDONE"
