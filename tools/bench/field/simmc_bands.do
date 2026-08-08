* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do simmc_bands.do 1000 500 mc_bands.csv
* Whole-path inference: csdid multiplier-bootstrap uniform bands, balanced
* panel, no covariates, same seeds as the core study. Rows: h=0..2 carry
* (att, se_boot); rows h=40x carry the BAND (ci_low, ci_high) for h=x.
* Rivals' per-rep pointwise results already exist in the core CSV (same
* seeds), so joint pointwise coverage is computed from there.
args nunits reps outfile
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n
forvalues r = 1/`reps' {
    quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(balanced)
    capture csdid y, ivar(id) time(time) gvar(gvar) notyet base_period(varying) ///
        bal(none) wboot(reps(999) rseed(`=70000 + `r''))
    if _rc == 0 {
        capture quietly estat event, window(0 2)
        if _rc == 0 {
            matrix BG = e(boot_aggte)
            matrix A = e(aggte)
            forvalues i = 1/`=rowsof(A)' {
                local h = A[`i',1]
                if inlist(`h', 0, 1, 2) {
                    local v1 = string(BG[`i',2], "%18.0g")
                    local v2 = string(BG[`i',3], "%18.0g")
                    file write out "bands,csdid_band,`r',`h',`v1',`v2'" _n
                    local lo = string(BG[`i',5], "%18.0g")
                    local hi = string(BG[`i',6], "%18.0g")
                    file write out "bands,csdid_band,`r',`=400+`h'',`lo',`hi'" _n
                }
            }
        }
    }
    if mod(`r', 25) == 0 display "MCPROG rep `r' of `reps'"
}
file close out
display "MCDONE"
