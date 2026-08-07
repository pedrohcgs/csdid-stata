* Runs the Sun and Abraham arm (eventstudyinteract) via simrun3.do on the main designs.
* Same DGP, same seeds (90000 + rep) as simmc.do / simmc_dr.do / simmc_ps2.do,
* so the default-lpdid rows reproduce the published numbers and the rw rows
* drop straight into the same tables.
*   Usage: stata-mp -b do lpdidrw.do <nunits> <reps> <outfile>
args nunits reps outfile
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {

    * ---- Reliability I sampling regimes (no covariates) ----
    foreach reg in balanced varmiss unbalanced {
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(`reg')
        tempfile d
        quietly save "`d'", replace
        foreach pkg in sa {
            use "`d'", clear
            capture sim_est3, pkg(`pkg') regime(`reg') bal(none)
            if _rc == 0 & r(ok) == 1 {
                matrix RR = r(R)
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',`h',`v1',`v2'" _n
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "`reg',`pkg',`r',`h',.,." _n
                }
            }
        }
    }

    * ---- covariate cells: both models right, outcome wrong, pscore wrong ----
    foreach cell in ok owrong pwrong2 {
        local msp = cond("`cell'" == "ok", "", ///
            cond("`cell'" == "owrong", "misspec(outcome)", "misspec(pscore2)"))
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(balanced) cov `msp'
        tempfile dc
        quietly save "`dc'", replace
        foreach pkg in sa {
            use "`dc'", clear
            capture sim_est3, pkg(`pkg') regime(balanced) bal(none) cov
            if _rc == 0 & r(ok) == 1 {
                matrix RR = r(R)
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "bal_`cell',`pkg',`r',`h',`v1',`v2'" _n
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "bal_`cell',`pkg',`r',`h',.,." _n
                }
            }
        }
    }

    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
