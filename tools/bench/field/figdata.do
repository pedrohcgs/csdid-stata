* Per-replication estimates behind the hero figure: every command on the
* unequal-period-sampling design (varmiss), event times 0-2.
* Same DGP and seeds (90000 + rep) as the Reliability I tables, so the
* bias and coverage computed from this file reproduce the published rows.
*   Usage: stata-mp -b do figdata.do <nunits> <reps> <outfile>
args nunits reps outfile
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

* population-share wtr() weights for did_imputation (as in bjswtr.do)
capture program drop mkwtr
program define mkwtr
    quietly capture drop K w0 w1 w2 ncell
    quietly gen int K = time - gvar if gvar > 0 & time >= gvar
    forvalues h = 0/2 {
        quietly capture drop ncell
        quietly bysort gvar time: egen double ncell = total(K == `h') if K == `h'
        quietly gen double w`h' = cond(K == `h' & ncell > 0, 1/(3*ncell), 0)
        quietly replace w`h' = 0 if missing(w`h')
    }
end

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {

    quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(varmiss)
    tempfile d
    quietly save "`d'", replace

    foreach pkg in csdid jwdid jwdid_uc bjs bjs_wtr dcdh lpdid lpdid_rw sa {
        use "`d'", clear
        capture sim_est3, pkg(`pkg') regime(varmiss) bal(none)
        if _rc == 0 & r(ok) == 1 {
            matrix RR = r(R)
            forvalues h = 0/2 {
                local v1 = string(RR[`h'+1,1], "%18.0g")
                local v2 = string(RR[`h'+1,2], "%18.0g")
                file write out "varmiss,`pkg',`r',`h',`v1',`v2'" _n
            }
        }
        else {
            forvalues h = 0/2 {
                file write out "varmiss,`pkg',`r',`h',.,." _n
            }
        }
    }

    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
