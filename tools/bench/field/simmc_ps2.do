* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do simmc_ps2.do 1000 500 mc_ps2.csv
* Monte Carlo: the pscore-misspec cell (latent-index selection,
* observed x2 = standardized exp(0.8 w), shifts at half scale). One cell,
* full roster. Same seeds as the DR arm.
args nunits reps outfile
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {
    quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(balanced) cov misspec(pscore2)
    tempfile d
    quietly save "`d'", replace
    local reg "bal_ps2"
    local plist "csdid_dr csdid_ipw csdid_reg jwdid bjs dcdh lpdid flexdid"
    foreach pkg of local plist {
        local realpkg "`pkg'"
        local mopt ""
        if strpos("`pkg'", "csdid_") {
            local realpkg "csdid"
            local mopt "method(`=substr("`pkg'", 7, .)')"
        }
        use "`d'", clear
        capture noisily sim_est3, pkg(`realpkg') regime(balanced) bal(none) cov `mopt'
        if _rc == 0 & r(ok) == 1 {
            matrix RR = r(R)
            forvalues h = 0/2 {
                local v1 = string(RR[`h'+1,1], "%18.0g")
                local v2 = string(RR[`h'+1,2], "%18.0g")
                file write out "`reg',`pkg',`r',`h',`v1',`v2'" _n
            }
            local ncell = r(n_cells)
            if `ncell' < . {
                matrix OV = r(OVR)
                local v1 = string(OV[1,1], "%18.0g")
                local v2 = string(OV[1,2], "%18.0g")
                file write out "`reg',`pkg',`r',99,`v1',`v2'" _n
                matrix CE = r(CELLS)
                forvalues c = 1/`ncell' {
                    local code = 1000 * CE[`c',1] + CE[`c',2]
                    local v1 = string(CE[`c',3], "%18.0g")
                    local v2 = string(CE[`c',4], "%18.0g")
                    file write out "`reg',`pkg',`r',`code',`v1',`v2'" _n
                }
            }
        }
        else {
            forvalues h = 0/2 {
                file write out "`reg',`pkg',`r',`h',.,." _n
            }
        }
    }
    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
