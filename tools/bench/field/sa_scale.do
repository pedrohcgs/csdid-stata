*-----------------------------------------------------------------------------
*      sa_scale.do -- does the csdid-reg / eventstudyinteract gap shrink?
*-----------------------------------------------------------------------------
* With covariates the two are different estimators of the same estimand; the
* mean absolute difference should fall at the root-n rate. n = 500 to
* 32,000, 20 draws each. Output: sa_scale.csv. Run from the bench/ folder.
*   Usage: stata-mp -b do sa_scale.do <reps>
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
args reps
if "`reps'" == "" local reps 20
quietly do "simdgp.do"

capture file close out
file open out using "sa_scale.csv", write replace text
file write out "n,mean_absdiff,mean_diff,reps" _n

foreach n in 500 2000 8000 32000 {
    local sumabs = 0
    local sumdif = 0
    local k = 0
    forvalues r = 1/`reps' {
        quietly sim_dgp, n(`n') seed(`=90000 + `r'') regime(balanced) cov
        tempfile d
        quietly save "`d'", replace
        local c0 = .
        capture csdid y x1 x2, ivar(id) time(time) gvar(gvar) method(reg) nevertreated
        if _rc == 0 {
            capture estat event, window(0 2)
            if _rc == 0 {
                matrix E = r(table)
                local ce : colnames E
                local j : list posof "Tp0" in ce
                if `j' > 0 local c0 = E[1,`j']
            }
        }
        use "`d'", clear
        quietly {
            gen int ry = time - gvar if gvar > 0
            gen byte nevertr = (gvar == 0)
            local dums ""
            foreach k2 in -4 -3 -2 0 1 2 3 4 {
                local nm = cond(`k2' < 0, "g_m`=abs(`k2')'", "g_p`k2'")
                gen byte `nm' = (ry == `k2')
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
        local s0 = .
        capture eventstudyinteract y `dums', cohort(gvar_miss) ///
            control_cohort(nevertr) covariates(`xl') absorb(id time) vce(cluster id)
        if _rc == 0 {
            matrix BS = e(b_iw)
            local cn : colnames BS
            local j : list posof "g_p0" in cn
            if `j' > 0 local s0 = BS[1,`j']
        }
        if `c0' < . & `s0' < . {
            local sumabs = `sumabs' + abs(`c0' - `s0')
            local sumdif = `sumdif' + (`c0' - `s0')
            local k = `k' + 1
        }
    }
    local v1 = string(`sumabs'/`k', "%18.0g")
    local v2 = string(`sumdif'/`k', "%18.0g")
    file write out "`n',`v1',`v2',`k'" _n
}
file close out
display "MCDONE sa_scale.csv"
