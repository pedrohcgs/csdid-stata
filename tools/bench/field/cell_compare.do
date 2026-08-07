*-----------------------------------------------------------------------------
*      cell_compare.do -- ATT(g,t) cells against e(b_interact), one draw
*-----------------------------------------------------------------------------
* With covariates the disagreement between csdid reg (nevertreated) and the
* interaction-weighted estimator is already present at the cell level, not
* only after aggregation. Output: cell_compare.csv. Run from the bench/
* folder.
*   Usage: stata-mp -b do cell_compare.do
*-----------------------------------------------------------------------------
clear all
set more off
* replication-package layout puts src/ beside bench/; in the repo checkout it
* sits three levels up -- probe for it
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "simdgp.do"
quietly sim_dgp, n(4000) seed(90001) regime(balanced) cov
tempfile d
quietly save "`d'", replace

capture file close out
file open out using "cell_compare.csv", write replace text
file write out "source,cell,value" _n

quietly csdid y x1 x2, ivar(id) time(time) gvar(gvar) method(reg) nevertreated
matrix CB = e(b)
local cn : colnames CB
forvalues j = 1/`=colsof(CB)' {
    local nm : word `j' of `cn'
    local v = string(CB[1,`j'], "%18.0g")
    file write out "csdid,`nm',`v'" _n
}

use "`d'", clear
quietly {
    gen int ry = time - gvar if gvar > 0
    gen byte nevertr = (gvar == 0)
    local dums ""
    foreach k in -4 -3 -2 0 1 2 3 4 {
        local nm = cond(`k' < 0, "g_m`=abs(`k')'", "g_p`k'")
        gen byte `nm' = (ry == `k')
        replace `nm' = 0 if missing(`nm')
        local dums "`dums' `nm'"
    }
    local xl ""
    forvalues t = 2/7 {
        gen double xa_`t' = x1*(time==`t')
        gen double xb_`t' = x2*(time==`t')
        local xl "`xl' xa_`t' xb_`t'"
    }
}
quietly eventstudyinteract y `dums', cohort(gvar_miss) ///
    control_cohort(nevertr) covariates(`xl') absorb(id time) vce(cluster id)
matrix BI = e(b_interact)
local rn : rownames BI
local cnn : colnames BI
forvalues i = 1/`=rowsof(BI)' {
    local g : word `i' of `rn'
    forvalues j = 1/`=colsof(BI)' {
        local e : word `j' of `cnn'
        local v = string(BI[`i',`j'], "%18.0g")
        file write out "sa_b_interact,g`g'_`e',`v'" _n
    }
}
matrix W = e(ff_w)
forvalues i = 1/`=rowsof(W)' {
    local g : word `i' of `rn'
    forvalues j = 1/`=colsof(W)' {
        local e : word `j' of `cnn'
        local v = string(W[`i',`j'], "%18.0g")
        file write out "sa_ff_w,g`g'_`e',`v'" _n
    }
}
file close out
display "MCDONE cell_compare.csv"
