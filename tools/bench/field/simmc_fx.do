* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do simmc_fx.do 1000 500 mc_fx.csv
* Monte Carlo: one DGP, one fixed target (2.0 / 2.5 / 3.0), flexdid only, on
* the two repeated-cross-section regimes (rcs and rcsvar).
* Writes one row per (regime, package, rep, horizon) so nothing is aggregated
* before it is inspected.
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
    foreach reg in rcs rcsvar {
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(`reg')
        tempfile d
        quietly save "`d'", replace
        local plist "flexdid"
        foreach pkg of local plist {
            local realpkg = cond("`pkg'" == "csdidpair", "csdid", "`pkg'")
            local bopt = cond("`pkg'" == "csdidpair", "pair", "none")
            use "`d'", clear
            capture noisily sim_est3, pkg(`realpkg') regime(`reg') bal(`bopt')
            if _rc == 0 & r(ok) == 1 {
                matrix RR = r(R)
                * every numeric goes through string(): file write's (exp)
                * writer chokes on a missing value, and a degenerate cell's
                * se (or estimate) is legitimately missing
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',`h',`v1',`v2'" _n
                }
                * r(OVR) undefined does NOT error a matrix assignment - Stata
                * reads it as scalar missing and builds a 1x1 - so the guard
                * is the scalar count only csdid returns
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
    }
    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
