*-----------------------------------------------------------------------------
*      ymiss.do -- two representations of an unbalanced panel
*-----------------------------------------------------------------------------
* Period-varying missingness applied the same way at the same seeds, either
* by deleting rows or by setting only the outcome to missing (cohort and X
* stay on the roster). Target ES(e) = 2.0 + 0.5 e. All three commands drop
* missing-Y rows internally, so the two representations coincide.
* Writes one CSV row per (regime, pkg, rep, horizon); summarize with
* mcsum.py. Seeds replication r at 90000 + r. Run from the bench/ folder.
*   Usage: stata-mp -b do ymiss.do <nunits> <reps> <outfile>
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

foreach mode in drop ymiss {
    forvalues r = 1/`reps' {
        dgp_ym, n(`nunits') seed(`=90000 + `r'') mode(`mode')
        tempfile d
        quietly save "`d'", replace
        foreach pkg in csdid_dr jwdid bjs {
            use "`d'", clear
            capture sim_est3, pkg(`pkg') regime(unbalanced) bal(none)
            if _rc == 0 & r(ok) == 1 {
                matrix RR = r(R)
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "ymiss_`mode',`pkg',`r',`h',`v1',`v2'" _n
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "ymiss_`mode',`pkg',`r',`h',.,." _n
                }
            }
        }
        if mod(`r', 25) == 0 display "MCPROG mode `mode' rep `r' of `reps' done"
    }
}
file close out
display "MCDONE `outfile'"
