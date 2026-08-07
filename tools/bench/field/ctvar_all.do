*-----------------------------------------------------------------------------
*      ctvar_all.do -- the calendar-time design, every command at every option
*-----------------------------------------------------------------------------
* Covariate trend effects vary with calendar time, identically across
* cohorts: conditional parallel trends holds and every outcome model is
* correctly specified cell by cell. Target ES(e) = 2.0 + 0.5 e.
* Writes one CSV row per (regime, pkg, rep, horizon); summarize with
* mcsum.py. Seeds replication r at 90000 + r. Run from the bench/ folder.
*   Usage: stata-mp -b do ctvar_all.do <nunits> <reps> <outfile>
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
    dgp_ct, n(`nunits') seed(`=90000 + `r'')
    tempfile d
    quietly save "`d'", replace
    foreach pkg in csdid_dr csdid_ipw csdid_reg csdid_dr_nt csdid_ipw_nt csdid_reg_nt jwdid jwdid_uc bjs bjs_wtr dcdh dcdh_tnp lpdid lpdid_rw lpdid_ctl lpdid_rw_ctl sa sa_xt {
        use "`d'", clear
        * the plain lpdid arms run WITHOUT controls: the legacy lpdid branch
        * adds controls(x1 x2) whenever cov is passed, which is the separate
        * lpdid_ctl arm here
        local covopt = cond(inlist("`pkg'", "lpdid", "lpdid_rw"), "", "cov")
        capture sim_est3, pkg(`pkg') regime(balanced) bal(none) `covopt'
        if _rc == 0 & r(ok) == 1 {
            matrix RR = r(R)
            forvalues h = 0/2 {
                local v1 = string(RR[`h'+1,1], "%18.0g")
                local v2 = string(RR[`h'+1,2], "%18.0g")
                file write out "ctvar,`pkg',`r',`h',`v1',`v2'" _n
            }
        }
        else {
            forvalues h = 0/2 {
                file write out "ctvar,`pkg',`r',`h',.,." _n
            }
        }
    }
    if mod(`r', 25) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
