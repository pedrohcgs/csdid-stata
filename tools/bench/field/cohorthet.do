*-----------------------------------------------------------------------------
*      cohorthet.do -- cohort-specific treatment-effect heterogeneity in X
*-----------------------------------------------------------------------------
* tau(g,t,X) has cohort-specific coefficients on X and X-by-event-time;
* conditional parallel trends holds. Target ES(e) = 2.516667 + 0.633333 e.
* The appended _nt and sa arms are the pooled-gamma contamination test.
* Writes one CSV row per (regime, pkg, rep, horizon); summarize with
* mcsum.py. Seeds replication r at 90000 + r. Run from the bench/ folder.
*   Usage: stata-mp -b do cohorthet.do <nunits> <reps> <outfile>
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
    dgp_ch, n(`nunits') seed(`=90000 + `r'')
    tempfile d
    quietly save "`d'", replace
    foreach pkg in csdid_dr csdid_reg jwdid bjs lpdid_rw_ctl dcdh sa csdid_reg_nt csdid_dr_nt sa_xt {
        use "`d'", clear
        capture sim_est3, pkg(`pkg') regime(balanced) bal(none) cov
        if _rc == 0 & r(ok) == 1 {
            matrix RR = r(R)
            forvalues h = 0/2 {
                local v1 = string(RR[`h'+1,1], "%18.0g")
                local v2 = string(RR[`h'+1,2], "%18.0g")
                file write out "cohorthet,`pkg',`r',`h',`v1',`v2'" _n
            }
        }
        else {
            forvalues h = 0/2 {
                file write out "cohorthet,`pkg',`r',`h',.,." _n
            }
        }
    }
    if mod(`r', 25) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
