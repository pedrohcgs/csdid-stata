*-----------------------------------------------------------------------------
*      sa_se.do -- standard errors of csdid and eventstudyinteract compared
*-----------------------------------------------------------------------------
* Balanced panel, no covariates, 200 draws: mean standard errors of the two
* commands and the largest point-estimate gap. Output: sa_se.csv.
* Run from the bench/ folder.
*   Usage: stata-mp -b do sa_se.do <reps>
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
if "`reps'" == "" local reps 200
quietly do "simdgp.do"

matrix S = J(3, 5, 0)
forvalues r = 1/`reps' {
    quietly sim_dgp, n(1000) seed(`=90000 + `r'') regime(balanced)
    quietly {
        capture drop ry nevertr g_m* g_p*
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
    local sa_ok = (_rc == 0)
    if `sa_ok' {
        matrix BS = e(b_iw)
        matrix VS = e(V_iw)
        local cns : colnames BS
    }
    capture csdid y, ivar(id) time(time) gvar(gvar) nevertreated
    local cs_ok = (_rc == 0)
    if `cs_ok' {
        capture estat event, window(0 2)
        matrix EC = r(table)
        local cnc : colnames EC
    }
    if `sa_ok' & `cs_ok' {
        forvalues h = 0/2 {
            local js : list posof "g_p`h'" in cns
            local jc : list posof "Tp`h'" in cnc
            if `js' > 0 & `jc' > 0 {
                local i = `h' + 1
                matrix S[`i',1] = S[`i',1] + sqrt(VS[`js',`js'])
                matrix S[`i',2] = S[`i',2] + EC[2,`jc']
                matrix S[`i',3] = S[`i',3] + 1
                local db = abs(BS[1,`js'] - EC[1,`jc'])
                matrix S[`i',4] = S[`i',4] + `db'
                if `db' > S[`i',5] matrix S[`i',5] = `db'
            }
        }
    }
}
capture file close out
file open out using "sa_se.csv", write replace text
file write out "h,mean_se_sa,mean_se_csdid,reps,mean_absdiff_b,max_absdiff_b" _n
forvalues h = 0/2 {
    local i = `h' + 1
    local n = S[`i',3]
    local v1 = string(S[`i',1]/`n', "%18.0g")
    local v2 = string(S[`i',2]/`n', "%18.0g")
    local v3 = string(S[`i',4]/`n', "%18.0g")
    local v4 = string(S[`i',5], "%18.0g")
    file write out "`h',`v1',`v2',`n',`v3',`v4'" _n
}
file close out
display "MCDONE sa_se.csv"
