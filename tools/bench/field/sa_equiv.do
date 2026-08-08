*-----------------------------------------------------------------------------
*      sa_equiv.do -- the csdid / eventstudyinteract equivalence, one draw
*-----------------------------------------------------------------------------
* One draw per sampling regime, no covariates: csdid with nevertreated and
* the interaction-weighted estimator coincide to machine precision on the
* balanced panel and part ways once the panel is unbalanced or period sizes
* vary. Output: sa_equiv.csv. Run from the bench/ folder.
*   Usage: stata-mp -b do sa_equiv.do
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

capture file close out
file open out using "sa_equiv.csv", write replace text
file write out "regime,h,sa,csdid_nyt,diff" _n

foreach reg in balanced unbalanced varmiss {
    quietly sim_dgp, n(2000) seed(90007) regime(`reg')
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
    }
    capture eventstudyinteract y `dums', cohort(gvar_miss) ///
        control_cohort(nevertr) absorb(id time) vce(cluster id)
    matrix BS = e(b_iw)
    local cn : colnames BS
    capture csdid y, ivar(id) time(time) gvar(gvar) nevertreated
    capture estat event, window(0 2)
    matrix E = r(table)
    local ce : colnames E
    forvalues h = 0/2 {
        local j : list posof "g_p`h'" in cn
        local sa = cond(`j' > 0, BS[1,`j'], .)
        local jc : list posof "Tp`h'" in ce
        local cs = cond(`jc' > 0, E[1,`jc'], .)
        local v1 = string(`sa', "%18.0g")
        local v2 = string(`cs', "%18.0g")
        local v3 = string(`sa' - `cs', "%18.0g")
        file write out "`reg',`h',`v1',`v2',`v3'" _n
    }
}
file close out
display "MCDONE sa_equiv.csv"
