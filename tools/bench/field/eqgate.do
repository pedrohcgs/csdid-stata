*-----------------------------------------------------------------------------
*      eqgate.do -- seed-level equivalence gate for the refactored arms
*-----------------------------------------------------------------------------
* Every arm moved from inline driver code into sim_est3 must reproduce the
* inline command exactly, estimate and standard error, at the same seed.
* csdid arms use multiplier-bootstrap inference, so the RNG is reset to the
* same state immediately before the branch call and the inline call; the
* other arms consume no randomness at estimation.
* Output: eqgate.csv, one row per (seed, arm, horizon) with both values.
* Run from the bench/ folder. Pass = max |difference| is exactly zero.
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
quietly do "fielddgp.do"
quietly do "simrun3.do"

capture file close out
file open out using "eqgate.csv", write replace text
file write out "seed,arm,h,b_branch,b_inline,se_branch,se_inline" _n

foreach sd in 90001 90002 90003 {
    dgp_master, n(2000) seed(`sd')
    tempfile d
    quietly save "`d'", replace

    foreach arm in csdid_reg csdid_dr csdid_reg_nt lpdid lpdid_rw lpdid_ctl lpdid_rw_ctl dcdh_tnp sa_xt {

        * ---- branch path ----
        use "`d'", clear
        set seed 7654321
        local covopt = cond(inlist("`arm'", "lpdid", "lpdid_rw"), "", "cov")
        capture sim_est3, pkg(`arm') regime(balanced) bal(none) `covopt'
        matrix RB = r(R)

        * ---- inline path: the literal command the old drivers ran ----
        use "`d'", clear
        set seed 7654321
        matrix RI = J(3, 2, .)
        if inlist("`arm'", "csdid_reg", "csdid_dr", "csdid_reg_nt") {
            local mth = cond(strpos("`arm'", "_dr"), "dr", "reg")
            local nt  = cond(strpos("`arm'", "_nt"), "nevertreated", "")
            capture csdid y x1 x2, ivar(id) time(time) gvar(gvar) method(`mth') `nt'
            if _rc == 0 {
                capture estat event, window(0 2)
                if _rc == 0 {
                    matrix E = r(table)
                    local ce : colnames E
                    forvalues h = 0/2 {
                        local j : list posof "Tp`h'" in ce
                        if `j' > 0 {
                            matrix RI[`h'+1,1] = E[1,`j']
                            matrix RI[`h'+1,2] = E[2,`j']
                        }
                    }
                }
            }
        }
        else if inlist("`arm'", "lpdid", "lpdid_rw", "lpdid_ctl", "lpdid_rw_ctl") {
            local rwo = cond(strpos("`arm'", "rw"), "rw", "")
            local cto = cond(strpos("`arm'", "ctl"), "controls(x1 x2)", "")
            capture lpdid y, unit(id) time(time) treat(treated) post_window(2) ///
                pre_window(3) `rwo' `cto'
            if _rc == 0 {
                capture matrix B = e(results)
                if _rc == 0 {
                    local rn : rownames B
                    forvalues h = 0/2 {
                        local pos : list posof "tau`h'" in rn
                        if `pos' > 0 {
                            matrix RI[`h'+1,1] = B[`pos',1]
                            matrix RI[`h'+1,2] = B[`pos',2]
                        }
                    }
                }
            }
        }
        else if "`arm'" == "dcdh_tnp" {
            capture did_multiplegt_dyn y id time treated, effects(3) ///
                trends_nonparam(x1) graphoptions(nodraw) graph_off
            forvalues h = 0/2 {
                local j = `h' + 1
                local b = .
                local se = .
                capture local b = e(Effect_`j')
                capture local se = e(se_effect_`j')
                if `b' < . {
                    matrix RI[`h'+1,1] = `b'
                    matrix RI[`h'+1,2] = `se'
                }
            }
        }
        else if "`arm'" == "sa_xt" {
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
            capture eventstudyinteract y `dums', cohort(gvar_miss) ///
                control_cohort(nevertr) covariates(`xl') absorb(id time) vce(cluster id)
            if _rc == 0 {
                matrix BS = e(b_iw)
                matrix VS = e(V_iw)
                local cn : colnames BS
                forvalues h = 0/2 {
                    local j : list posof "g_p`h'" in cn
                    if `j' > 0 {
                        matrix RI[`h'+1,1] = BS[1,`j']
                        matrix RI[`h'+1,2] = sqrt(VS[`j',`j'])
                    }
                }
            }
        }

        forvalues h = 0/2 {
            local bb = string(RB[`h'+1,1], "%21.0g")
            local bi = string(RI[`h'+1,1], "%21.0g")
            local sb = string(RB[`h'+1,2], "%21.0g")
            local si = string(RI[`h'+1,2], "%21.0g")
            file write out "`sd',`arm',`h',`bb',`bi',`sb',`si'" _n
        }
    }
}
file close out
