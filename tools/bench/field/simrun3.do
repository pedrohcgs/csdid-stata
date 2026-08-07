* Run from the bench/ folder of the replication package. Not run on its
* own: the drivers load it with -do-.  It defines sim_est3.
* One estimator, one regime -> matrix R (3x2): h=0,1,2 estimate and SE.
*
* Every package is invoked as ITS OWN documentation prescribes, and where a
* package does not claim support the attempt is still made and whatever it
* returns is recorded -- including "nothing". did_multiplegt_dyn never mentions
* repeated cross sections, so its RCS row is the extreme-unbalanced path (each
* unit observed once), not a fabricated group structure.

capture program drop _fxes_parse
program define _fxes_parse
    * parse "e | est se ..." rows for exposures 0..2 and the Overall row from
    * a captured flexdid display log; returns fx_b0..fx_se2, fx_ov, fx_ovse
    * via c_local. flexdid's r() results are destroyed by two non-rclass
    * wrapper hops, so the displayed table is the only harvestable surface.
    args logfile
    foreach k in b0 se0 b1 se1 b2 se2 ov ovse {
        local `k' "."
    }
    tempname fh
    file open `fh' using "`logfile'", read text
    file read `fh' line
    while r(eof) == 0 {
        local bar = strpos(`"`line'"', "|")
        if `bar' > 0 {
            local lhs = strtrim(substr(`"`line'"', 1, `bar' - 1))
            local rest = substr(`"`line'"', `bar' + 1, .)
            if inlist(`"`lhs'"', "0", "1", "2") {
                local b`lhs' : word 1 of `rest'
                local se`lhs' : word 2 of `rest'
            }
            else if `"`lhs'"' == "Overall" {
                local ov : word 1 of `rest'
                local ovse : word 2 of `rest'
            }
        }
        file read `fh' line
    }
    file close `fh'
    foreach k in b0 se0 b1 se1 b2 se2 ov ovse {
        c_local fx_`k' "``k''"
    }
end

capture program drop sim_est3

program define sim_est3, rclass
    syntax , PKG(string) REGIME(string) [BAL(string) COV METHod(string)]
    tempname R
    matrix `R' = J(3, 2, .)
    local ok = 1
    local note ""

    if "`pkg'" == "csdid" {
        local mth = cond("`method'" == "", "", "method(`method')")
        local xv = cond("`cov'" != "", "x1 x2", "")
        if inlist("`regime'", "rcs", "rcsvar") {
            capture csdid y `xv', time(time) gvar(gvar) notyet analytical base_period(varying) rcs `mth'
        }
        else {
            local bm = cond("`regime'" == "unbalanced", "`bal'", "none")
            capture csdid y `xv', ivar(id) time(time) gvar(gvar) notyet analytical ///
                base_period(varying) bal(`bm') `mth'
        }
        if _rc local ok = 0
        else {
            capture quietly estat event, window(0 2)
            if _rc local ok = 0
            else {
                matrix A = e(aggte)
                forvalues r = 1/`=rowsof(A)' {
                    forvalues h = 0/2 {
                        if A[`r',1] == `h' {
                            matrix `R'[`h'+1,1] = A[`r',2]
                            matrix `R'[`h'+1,2] = A[`r',3]
                        }
                    }
                }
                * the windowed overall (equal-weight average of the post
                * event-time effects) and its se, identical in every row
                matrix OVR = (A[1,4], A[1,5])
                * post-treatment ATT(g,t) cells against their known truths
                matrix AT = e(attgt)
                matrix CELLS = J(rowsof(AT), 4, .)
                local nc = 0
                forvalues r = 1/`=rowsof(AT)' {
                    if AT[`r',2] >= AT[`r',1] {
                        local ++nc
                        matrix CELLS[`nc',1] = AT[`r',1]
                        matrix CELLS[`nc',2] = AT[`r',2]
                        matrix CELLS[`nc',3] = AT[`r',4]
                        matrix CELLS[`nc',4] = AT[`r',5]
                    }
                }
                return scalar n_cells = `nc'
                return matrix CELLS = CELLS
                return matrix OVR = OVR
            }
        }
    }
    else if "`pkg'" == "jwdid" {
        if inlist("`regime'", "rcs", "rcsvar") {
            local xv = cond("`cov'" != "", "x1 x2", "")
            capture jwdid y `xv', tvar(time) gvar(gvar)
        }
        else {
            local xv = cond("`cov'" != "", "x1 x2", "")
            capture jwdid y `xv', ivar(id) tvar(time) gvar(gvar)
        }
        if _rc local ok = 0
        else {
            capture quietly estat event
            if _rc local ok = 0
            else {
                matrix B = r(table)
                local cn : colnames B
                local base = .
                foreach c of local cn {
                    if strpos("`c'","bn.__event__") local base = real(subinstr("`c'","bn.__event__","",.))
                }
                if missing(`base') local ok = 0
                else {
                    forvalues h = 0/2 {
                        local lev = `base' + `h'
                        local pos : list posof "`lev'.__event__" in cn
                        if `pos' == 0 local pos : list posof "`lev'bn.__event__" in cn
                        if `pos' > 0 {
                            matrix `R'[`h'+1,1] = B[1,`pos']
                            matrix `R'[`h'+1,2] = B[2,`pos']
                        }
                    }
                }
            }
        }
    }
    else if "`pkg'" == "jwdid_uc" {
        if inlist("`regime'", "rcs", "rcsvar") {
            local xv = cond("`cov'" != "", "x1 x2", "")
            capture jwdid y `xv', tvar(time) gvar(gvar) method(regress) corr
        }
        else {
            local xv = cond("`cov'" != "", "x1 x2", "")
            capture jwdid y `xv', ivar(id) tvar(time) gvar(gvar) method(regress) corr
        }
        if _rc local ok = 0
        else {
            capture quietly estat event, vce(unconditional)
            if _rc local ok = 0
            else {
                matrix B = r(table)
                local cn : colnames B
                local base = .
                foreach c of local cn {
                    if strpos("`c'","bn.__event__") local base = real(subinstr("`c'","bn.__event__","",.))
                }
                if missing(`base') local ok = 0
                else {
                    forvalues h = 0/2 {
                        local lev = `base' + `h'
                        local pos : list posof "`lev'.__event__" in cn
                        if `pos' == 0 local pos : list posof "`lev'bn.__event__" in cn
                        if `pos' > 0 {
                            matrix `R'[`h'+1,1] = B[1,`pos']
                            matrix `R'[`h'+1,2] = B[2,`pos']
                        }
                    }
                }
            }
        }
    }
    else if "`pkg'" == "bjs" {
        if inlist("`regime'", "rcs", "rcsvar") {
            if "`cov'" != "" {
                * covariates exactly as the did_imputation help prescribes:
                * binary (gender-like) via fe() interacted with period
                * dummies; continuous time-invariant via timecontrols(),
                * which enters i.t#c.x2 with an unrestricted coefficient
                * per period
                capture did_imputation y id time gvar_miss, horizons(0/2) ///
                    fe(gvar time x1#time) timecontrols(x2)
            }
            else {
                capture did_imputation y id time gvar_miss, horizons(0/2) fe(gvar time)
            }
        }
        else {
            if "`cov'" != "" {
                * same help-prescribed path as the repeated-cross-section
                * branch: fe() for the binary covariate's period
                * interactions, timecontrols() for the continuous one
                capture did_imputation y id time gvar_miss, horizons(0/2) autosample ///
                    fe(id time x1#time) timecontrols(x2)
            }
            else capture did_imputation y id time gvar_miss, horizons(0/2) autosample
        }
        if _rc local ok = 0
        else {
            matrix B = r(table)
            local cn : colnames B
            forvalues h = 0/2 {
                local pos : list posof "tau`h'" in cn
                if `pos' > 0 {
                    matrix `R'[`h'+1,1] = B[1,`pos']
                    matrix `R'[`h'+1,2] = B[2,`pos']
                }
            }
        }
    }
    else if "`pkg'" == "dcdh" {
        local ctl = cond("`cov'" != "", "controls(x1 x2)", "")
        capture did_multiplegt_dyn y id time treated, effects(3) `ctl' graphoptions(nodraw)
        if _rc local ok = 0
        else {
            forvalues h = 0/2 {
                local j = `h' + 1
                capture matrix `R'[`h'+1,1] = e(Effect_`j')
                capture matrix `R'[`h'+1,2] = e(se_effect_`j')
            }
        }
    }
    else if "`pkg'" == "flexdid" {
        if (0) local ok = 0
        else {
            tempfile fxlog
            capture log close fxparse
            quietly log using "`fxlog'", text replace name(fxparse)
            local xv = cond("`cov'" != "", "x1 x2", "")
            capture noisily flexdid y `xv', tx(treated) group(gvar) time(time) ///
                specification(lagsandleads) vce(robust)
            local fxrc = _rc
            capture noisily estat atet, byexposure nograph
            if `fxrc' == 0 local fxrc = _rc
            quietly log close fxparse
            if `fxrc' local ok = 0
            else {
                _fxes_parse "`fxlog'"
                matrix `R'[1,1] = real("`fx_b0'")
                matrix `R'[1,2] = real("`fx_se0'")
                matrix `R'[2,1] = real("`fx_b1'")
                matrix `R'[2,2] = real("`fx_se1'")
                matrix `R'[3,1] = real("`fx_b2'")
                matrix `R'[3,2] = real("`fx_se2'")
                matrix OVR = (real("`fx_ov'"), real("`fx_ovse'"))
                return scalar n_cells = 0
                matrix CELLS = J(1, 4, .)
                return matrix CELLS = CELLS
                return matrix OVR = OVR
            }
        }
    }
    else if "`pkg'" == "sa" {
        * Sun & Abraham interaction-weighted estimator (eventstudyinteract).
        * Full relative-time dummy set, reference -1, never-treated control.
        capture drop ry_XX nevertr_XX g_XX*
        quietly gen int ry_XX = time - gvar if gvar > 0
        quietly gen byte nevertr_XX = (gvar == 0)
        local dums ""
        foreach k in -4 -3 -2 0 1 2 3 4 {
            local nm = cond(`k' < 0, "g_XXm`=abs(`k')'", "g_XXp`k'")
            quietly gen byte `nm' = (ry_XX == `k')
            quietly replace `nm' = 0 if missing(`nm')
            local dums "`dums' `nm'"
        }
        local sacov = cond("`cov'" != "", "covariates(x1 x2)", "")
        capture eventstudyinteract y `dums', cohort(gvar_miss) ///
            control_cohort(nevertr_XX) `sacov' absorb(id time) vce(cluster id)
        if _rc local ok = 0
        else {
            capture matrix BSA = e(b_iw)
            capture matrix VSA = e(V_iw)
            if _rc local ok = 0
            else {
                local cnsa : colnames BSA
                forvalues h = 0/2 {
                    local jj : list posof "g_XXp`h'" in cnsa
                    if `jj' > 0 {
                        matrix `R'[`h'+1,1] = BSA[1,`jj']
                        matrix `R'[`h'+1,2] = sqrt(VSA[`jj',`jj'])
                    }
                }
            }
        }
    }
    else if inlist("`pkg'", "csdid_dr", "csdid_ipw", "csdid_reg") | ///
        inlist("`pkg'", "csdid_dr_nt", "csdid_ipw_nt", "csdid_reg_nt") {
        * field-design csdid arms: package defaults (multiplier-bootstrap
        * inference), method and comparison group parsed from the arm name,
        * harvested from estat event's r(table)
        local mth : word 2 of `=subinstr("`pkg'", "_", " ", .)'
        local nt = cond(strpos("`pkg'", "_nt"), "nevertreated", "")
        local xv = cond("`cov'" != "", "x1 x2", "")
        capture csdid y `xv', ivar(id) time(time) gvar(gvar) method(`mth') `nt'
        if _rc local ok = 0
        else {
            capture estat event, window(0 2)
            if _rc local ok = 0
            else {
                matrix E = r(table)
                local ce : colnames E
                forvalues h = 0/2 {
                    local j : list posof "Tp`h'" in ce
                    if `j' > 0 {
                        matrix `R'[`h'+1,1] = E[1,`j']
                        matrix `R'[`h'+1,2] = E[2,`j']
                    }
                }
            }
        }
    }
    else if inlist("`pkg'", "lpdid_ctl", "lpdid_rw_ctl") {
        local rwo = cond(strpos("`pkg'", "_rw"), "rw", "")
        capture lpdid y, unit(id) time(time) treat(treated) post_window(2) ///
            pre_window(3) `rwo' controls(x1 x2)
        if _rc local ok = 0
        else {
            capture matrix B = e(results)
            if _rc local ok = 0
            else {
                local rn : rownames B
                forvalues h = 0/2 {
                    local pos : list posof "tau`h'" in rn
                    if `pos' > 0 {
                        matrix `R'[`h'+1,1] = B[`pos',1]
                        matrix `R'[`h'+1,2] = B[`pos',2]
                    }
                }
            }
        }
    }
    else if "`pkg'" == "dcdh_tnp" {
        capture did_multiplegt_dyn y id time treated, effects(3) ///
            trends_nonparam(x1) graphoptions(nodraw) graph_off
        forvalues h = 0/2 {
            local j = `h' + 1
            local b = .
            local se = .
            capture local b = e(Effect_`j')
            capture local se = e(se_effect_`j')
            if `b' < . {
                matrix `R'[`h'+1,1] = `b'
                matrix `R'[`h'+1,2] = `se'
            }
        }
    }
    else if "`pkg'" == "sa_xt" {
        * Sun & Abraham with covariate-by-period-dummy interactions
        quietly {
            capture drop ry_XX nevertr_XX g_XX* xa_XX* xb_XX*
            gen int ry_XX = time - gvar if gvar > 0
            gen byte nevertr_XX = (gvar == 0)
            local dums ""
            foreach k in -4 -3 -2 0 1 2 3 4 {
                local nm = cond(`k' < 0, "g_XXm`=abs(`k')'", "g_XXp`k'")
                gen byte `nm' = (ry_XX == `k')
                replace `nm' = 0 if missing(`nm')
                local dums "`dums' `nm'"
            }
            local xl ""
            if "`cov'" != "" {
                forvalues t = 2/7 {
                    gen double xa_XX`t' = x1*(time==`t')
                    gen double xb_XX`t' = x2*(time==`t')
                    local xl "`xl' xa_XX`t' xb_XX`t'"
                }
            }
        }
        capture eventstudyinteract y `dums', cohort(gvar_miss) ///
            control_cohort(nevertr_XX) covariates(`xl') absorb(id time) vce(cluster id)
        if _rc local ok = 0
        else {
            capture matrix BSA = e(b_iw)
            capture matrix VSA = e(V_iw)
            if _rc local ok = 0
            else {
                local cnsa : colnames BSA
                forvalues h = 0/2 {
                    local jj : list posof "g_XXp`h'" in cnsa
                    if `jj' > 0 {
                        matrix `R'[`h'+1,1] = BSA[1,`jj']
                        matrix `R'[`h'+1,2] = sqrt(VSA[`jj',`jj'])
                    }
                }
            }
        }
    }
    else if "`pkg'" == "bjs_wtr" {
        * did_imputation with population-share wtr() weights
        mkwtr
        local sopt = cond("`cov'" != "", "fe(id time x1#time) timecontrols(x2)", "")
        capture did_imputation y id time gvar_miss, wtr(w0 w1 w2) autosample `sopt'
        if _rc local ok = 0
        else {
            matrix W = r(table)
            local cw : colnames W
            forvalues h = 0/2 {
                local p : list posof "tau_w`h'" in cw
                if `p' > 0 {
                    matrix `R'[`h'+1,1] = W[1,`p']
                    matrix `R'[`h'+1,2] = W[2,`p']
                }
            }
        }
    }
    else if "`pkg'" == "lpdid" {
        local ctl = cond("`cov'" != "", "controls(x1 x2)", "")
        capture lpdid y, unit(id) time(time) treat(treated) post_window(2) pre_window(3) `ctl'
        if _rc local ok = 0
        else {
            capture matrix B = e(results)
            if _rc local ok = 0
            else {
                local rn : rownames B
                forvalues h = 0/2 {
                    local pos : list posof "tau`h'" in rn
                    if `pos' > 0 {
                        matrix `R'[`h'+1,1] = B[`pos',1]
                        matrix `R'[`h'+1,2] = B[`pos',2]
                    }
                }
            }
        }
    }
    else if "`pkg'" == "lpdid_rw" {
        local ctl = cond("`cov'" != "", "controls(x1 x2)", "")
        capture lpdid y, unit(id) time(time) treat(treated) post_window(2) pre_window(3) rw `ctl'
        if _rc local ok = 0
        else {
            capture matrix B = e(results)
            if _rc local ok = 0
            else {
                local rn : rownames B
                forvalues h = 0/2 {
                    local pos : list posof "tau`h'" in rn
                    if `pos' > 0 {
                        matrix `R'[`h'+1,1] = B[`pos',1]
                        matrix `R'[`h'+1,2] = B[`pos',2]
                    }
                }
            }
        }
    }
    return scalar ok = `ok'
    return matrix R = `R'
end