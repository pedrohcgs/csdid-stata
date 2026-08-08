*-----------------------------------------------------------------------------
*      smallnt.do -- comparison groups with a five percent never-treated share
*-----------------------------------------------------------------------------
* Never-treated share ~5 percent; three equal treated cohorts, so the
* target stays ES(e) = 2.0 + 0.5 e.
* Writes one CSV row per (regime, pkg, rep, horizon); summarize with
* mcsum.py. Seeds replication r at 90000 + r. Run from the bench/ folder.
*   Usage: stata-mp -b do smallnt.do <nunits> <reps> <outfile>
*-----------------------------------------------------------------------------
clear all
set more off
args nunits reps outfile
* replication-package layout puts src/ beside bench/; in the repo checkout it
* sits three levels up -- probe for it
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"
quietly do "simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {
    dgp_snt, n(`nunits') seed(`=90000 + `r'')
    tempfile d
    quietly save "`d'", replace
    foreach pkg in csdid_dr csdid_dr_nt sa {
        use "`d'", clear
        capture sim_est3, pkg(`pkg') regime(balanced) bal(none) 
        if _rc == 0 & r(ok) == 1 {
            matrix RR = r(R)
            forvalues h = 0/2 {
                local v1 = string(RR[`h'+1,1], "%18.0g")
                local v2 = string(RR[`h'+1,2], "%18.0g")
                file write out "smallnt,`pkg',`r',`h',`v1',`v2'" _n
            }
        }
        else {
            forvalues h = 0/2 {
                file write out "smallnt,`pkg',`r',`h',.,." _n
            }
        }
    }
    if mod(`r', 25) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
