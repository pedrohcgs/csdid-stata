* Run from the bench/ folder of the replication package. Not run on its
* own: the drivers load it with -do-.  It defines bench_csdid, bench_jwdid, bench_bjs, bench_dcdh, bench_lpdid, bench_flexdid, bench_esi, bench_xthdid and bench_hdid.
* ---------------------------------------------------------------------------
* One runner per package. Each takes the SAME dataset and the SAME inference
* request, and returns the event-study coefficients in one shape:
*
*   bench_<pkg>, horizons(#) cluster(varname) [covariates(varlist) mode(string)]
*     -> r(secs)     wall time for the estimation call alone
*     -> r(ok)       1 if it produced coefficients
*     -> r(note)     anything the package refused, dropped, or omitted
*     -> matrix ES   horizon | estimate | se   (rows = horizons 0..H)
*
* mode is one of:
*   pointwise   analytical / asymptotic SEs, pointwise intervals
*   bootstrap   the package's own bootstrap, matched reps where available
*   bands       simultaneous / uniform confidence bands over the event study
*
* Every runner clusters on the same variable. Where a package cannot honour a
* request, the runner records WHY rather than silently substituting something
* else -- a benchmark that quietly downgrades one package's inference and then
* reports it as slower would be worthless.
* ---------------------------------------------------------------------------

capture program drop bench_reset
program define bench_reset, rclass
    capture matrix drop ES
end

* ------------------------------------------------------------------ csdid
capture program drop bench_csdid
program define bench_csdid, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string) STRUCTure(string) METHod(string)]
    if "`mode'" == "" local mode "pointwise"
    if "`structure'" == "" local structure "balanced"

    local inf "analytical"
    if "`mode'" == "bootstrap" local inf "wboot(reps(999) rseed(20260729)) pointwise"
    if "`mode'" == "bands"     local inf "wboot(reps(999) rseed(20260729))"

    * Match what every other package does with an incomplete panel: use all of
    * it. csdid's DEFAULT is bal(full), which drops units not observed in every
    * period -- on a 20-period panel with 15% of rows missing that is 96% of
    * units, and timing the 4% that remain would be a fabricated speed win, not
    * a measurement. rcs declares repeated cross sections, where no unit is
    * followed at all.
    local struct_opt "bal(none)"
    if "`structure'" == "rcs" local struct_opt "rcs"

    timer clear 99
    timer on 99
    local meth_opt = cond("`method'" == "", "", "method(`method')")
    capture noisily csdid y `covariates', ivar(id) time(time) gvar(gvar) ///
        notyet cluster(`cluster') `inf' `struct_opt' `meth_opt'
    local rc = _rc
    timer off 99
    quietly timer list 99
    local fitsecs = r(t99)
    return scalar ok = (`rc' == 0)
    return scalar secs_fit = `fitsecs'
    if `rc' {
        return scalar secs = `fitsecs'
        return local note "used_N=`e(N)'"
        exit
    }

    * The event study is part of what a user asks for, so it is part of what
    * we time. csdid and jwdid deliver it in a SECOND call; every other command
    * in this comparison delivers it inside its single call. Timing only the
    * fit would hand these two a deliverable that the others pay for. The
    * split survives as secs_fit / secs_agg.
    timer clear 98
    timer on 98
    capture quietly estat event, window(0 `horizons')
    local arc = _rc
    timer off 98
    quietly timer list 98
    local aggsecs = r(t98)
    return scalar secs_agg = `aggsecs'
    return scalar secs = `fitsecs' + `aggsecs'
    if `arc' {
        return scalar ok = 0
        return local note "; estat event rc=`arc'"
        exit
    }
    return local note ""

    * e(aggte) is egt | att | se | overall_att | overall_se
    matrix A = e(aggte)
    matrix ES = J(`horizons' + 1, 3, .)
    forvalues k = 1/`=`horizons'+1' {
        if `k' > rowsof(A) continue
        matrix ES[`k', 1] = A[`k', 1]
        matrix ES[`k', 2] = A[`k', 2]
        matrix ES[`k', 3] = A[`k', 3]
    }
    return scalar overall = A[1, 4]
    return scalar overall_se = A[1, 5]
    return matrix ES = ES
end

* ------------------------------------------------------------------ jwdid
capture program drop bench_jwdid
program define bench_jwdid, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string) STRUCTure(string)]
    if "`mode'" == "" local mode "pointwise"

    * jwdid has no bootstrap and no band option: it reports analytical
    * cluster-robust SEs only. Recorded, not silently substituted.
    local note ""
    if "`mode'" != "pointwise" local note "no bootstrap or band option; analytical SEs only"

    timer clear 99
    timer on 99
    * repeated cross sections: jwdid's documented route is to omit ivar()
    local iv = cond("`structure'" == "rcs", "", "ivar(id)")
    capture noisily jwdid y `covariates', `iv' tvar(time) gvar(gvar) cluster(`cluster')
    local rc = _rc
    timer off 99
    quietly timer list 99
    local fitsecs = r(t99)
    return scalar ok = (`rc' == 0)
    return scalar secs_fit = `fitsecs'
    if `rc' {
        return scalar secs = `fitsecs'
        return local note "`note'"
        exit
    }

    * The event study is part of what a user asks for, so it is part of what
    * we time. csdid and jwdid deliver it in a SECOND call; every other command
    * in this comparison delivers it inside its single call. Timing only the
    * fit would hand these two a deliverable that the others pay for. The
    * split survives as secs_fit / secs_agg.
    timer clear 98
    timer on 98
    * windowed exactly like the csdid aggregation it is compared with
    capture quietly estat event, window(0 `horizons')
    local arc = _rc
    timer off 98
    quietly timer list 98
    local aggsecs = r(t98)
    return scalar secs_agg = `aggsecs'
    return scalar secs = `fitsecs' + `aggsecs'
    if `arc' {
        return scalar ok = 0
        return local note "`note'; estat event rc=`arc'"
        exit
    }
    return local note "`note'"
    * estat event names columns <level>.__event__, where <level> is an internal
    * recoding of event time and the base (marked "bn") is the e = -1 reference.
    * The offset between level and event time depends on how many pre-periods
    * the panel has, so it MUST be derived from the base column rather than
    * assumed: a hardcoded offset leaves missing coefficients on a panel of a
    * different shape, which would be misread as jwdid failing to estimate
    * them.
    matrix B = r(table)
    matrix ES = J(`horizons' + 1, 3, .)
    local cn : colnames B
    local base = .
    foreach c of local cn {
        if strpos("`c'", "bn.__event__") {
            local base = real(subinstr("`c'", "bn.__event__", "", .))
        }
    }
    if missing(`base') {
        return scalar ok = 0
        return local note "`note'; could not locate the event-time base column"
        exit
    }
    forvalues h = 0/`horizons' {
        local k = `h' + 1
        matrix ES[`k', 1] = `h'
        * The column marked "bn" is Stata's factor-variable base for the
        * DISPLAY, not the event-study reference period: estat event reports
        * post-treatment coefficients only, and that first column IS h = 0.
        * Verified against a known DGP: reading bn as e = -1 shifts every
        * horizon by one and makes jwdid look badly biased when it is not.
        local lev = `base' + `h'
        * h = 0 is the column carrying the "bn" display marker, so its name is
        * <lev>bn.__event__ rather than <lev>.__event__
        local pos : list posof "`lev'.__event__" in cn
        if `pos' == 0 {
            local pos : list posof "`lev'bn.__event__" in cn
        }
        if `pos' > 0 {
            matrix ES[`k', 2] = B[1, `pos']
            matrix ES[`k', 3] = B[2, `pos']
        }
    }
    return matrix ES = ES
end

* --------------------------------------------------------- did_imputation
capture program drop bench_bjs
program define bench_bjs, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string)]
    if "`mode'" == "" local mode "pointwise"

    local note ""
    if "`mode'" != "pointwise" local note "no bootstrap or band option; analytical SEs only"

    local ctrl ""
    if "`covariates'" != "" local ctrl "controls(`covariates')"

    * autosample is BJS's own remedy for observations whose fixed effects it
    * cannot impute. Without it the command refuses outright, so the comparison
    * would have no BJS column at all -- but it means BJS estimates on a
    * SMALLER sample than the others, which the guide must state.
    timer clear 99
    timer on 99
    capture noisily did_imputation y id time gvar_miss, ///
        horizons(0/`horizons') cluster(`cluster') autosample `ctrl'
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    local asdrop "`e(autosample_drop)'"
    local asnote = cond("`asdrop'" == "", "autosample requested, nothing dropped", "autosample dropped: `asdrop'")
    return local note "`note'; N=`e(N)'; `asnote'"
    if `rc' exit

    matrix B = r(table)
    matrix ES = J(`horizons' + 1, 3, .)
    local k = 0
    forvalues h = 0/`horizons' {
        local k = `k' + 1
        matrix ES[`k', 1] = `h'
        capture matrix ES[`k', 2] = B[1, "tau`h'"]
        capture matrix ES[`k', 3] = B[2, "tau`h'"]
    }
    return matrix ES = ES
end

* ---------------------------------------------------- did_multiplegt_dyn
capture program drop bench_dcdh
program define bench_dcdh, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string)]
    if "`mode'" == "" local mode "pointwise"

    local boot ""
    local note ""
    if "`mode'" == "bootstrap" local boot "bootstrap(999)"
    if "`mode'" == "bands" {
        local boot "bootstrap(999)"
        local note "no simultaneous band option; bootstrap pointwise only"
    }
    local ctrl ""
    if "`covariates'" != "" local ctrl "controls(`covariates')"

    local eff = `horizons' + 1
    timer clear 99
    timer on 99
    * graph_off is the package's own no-graph switch; graphoptions(nodraw)
    * only suppresses the display and leaves the construction in the timer
    capture noisily did_multiplegt_dyn y id time treated, ///
        effects(`eff') cluster(`cluster') `boot' `ctrl' graph_off
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    return local note "`note'"
    if `rc' exit

    matrix ES = J(`horizons' + 1, 3, .)
    local k = 0
    forvalues h = 0/`horizons' {
        local k = `k' + 1
        local j = `h' + 1
        matrix ES[`k', 1] = `h'
        capture matrix ES[`k', 2] = e(Effect_`j')
        capture matrix ES[`k', 3] = e(se_effect_`j')
    }
    return matrix ES = ES
end

* ------------------------------------------------------------------ lpdid
capture program drop bench_lpdid
program define bench_lpdid, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string)]
    if "`mode'" == "" local mode "pointwise"

    local boot ""
    local note ""
    if "`mode'" == "bootstrap" local boot "bootstrap(999)"
    if "`mode'" == "bands" {
        local boot "bootstrap(999)"
        local note "no simultaneous band option; bootstrap pointwise only"
    }
    local ctrl ""
    if "`covariates'" != "" local ctrl "controls(`covariates')"

    timer clear 99
    timer on 99
    * nograph: without it the timed call also builds the event-study
    * graph, which no other command is being charged for
    capture noisily lpdid y, unit(id) time(time) treat(treated) ///
        post_window(`horizons') pre_window(3) cluster(`cluster') nograph `boot' `ctrl'
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    return local note "`note'"
    if `rc' exit

    * e(results): rows pre3..pre1, tau0..tauH; cols coefficient se t p ci_low ci_high obs
    capture matrix B = e(results)
    matrix ES = J(`horizons' + 1, 3, .)
    local rn : rownames B
    forvalues h = 0/`horizons' {
        local k = `h' + 1
        matrix ES[`k', 1] = `h'
        local pos : list posof "tau`h'" in rn
        if `pos' > 0 {
            matrix ES[`k', 2] = B[`pos', 1]
            matrix ES[`k', 3] = B[`pos', 2]
        }
    }
    return matrix ES = ES
end

* ------------------------------------------------------------------ flexdid
* Timing-only runner: wall time for the estimation call. flexdid displays its
* overall at estimation time and its r() results are unreachable, so the
* timing needs no extraction machinery.
capture program drop bench_flexdid
program define bench_flexdid, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string) STRUCTure(string)]
    timer clear 99
    timer on 99
    capture quietly flexdid y `covariates', tx(treated) group(gvar) time(time) ///
        specification(lagsandleads) vce(cluster `cluster')
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    return local note "vce(cluster) as in every column; overall displayed at estimation; no band or bootstrap option"
end

* ------------------------------------------------- xthdidregress (Stata)
* Stata's own Callaway and Sant'Anna estimator for panels. The arm maps onto
* csdid's method(): ra <-> reg, ipw <-> ipw, aipw <-> dr. Covariates go in the
* outcome model for ra, the treatment model for ipw, and both for aipw, which
* is the mapping the two commands' own documentation implies.
*
* xtset is panel setup, not estimation, so it happens OUTSIDE the timer, on
* the same footing as the prepared inputs eventstudyinteract receives. The
* event study comes from a second call, as it does for csdid and jwdid, and
* both calls are timed.
capture program drop bench_xthdid
program define bench_xthdid, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string) STRUCTure(string) ARM(string)]
    if "`arm'" == "" local arm "ra"
    capture quietly xtset id time

    local om = cond("`arm'" == "ipw", "", "`covariates'")
    local tm = cond("`arm'" == "ra", "", "`covariates'")

    * On an UNBALANCED panel xthdidregress derives each unit's cohort from its
    * first OBSERVED treated period, so a unit whose true first treated period
    * is a missing row is silently placed in a later cohort and all of its
    * cells move with it. Supplying the true cohort restores the full-panel
    * answer exactly (the article's missingness section shows this). Without
    * it this column would be
    * timing a command answering a different question from every other column,
    * which is not a speed comparison. On a balanced panel the derivation is
    * already correct and nothing is supplied, so the command runs exactly as
    * a user would run it.
    local uc ""
    if "`structure'" == "unbalanced" local uc "usercohort(gvar_miss)"

    timer clear 99
    timer on 99
    capture quietly xthdidregress `arm' (y `om') (treated `tm'), ///
        group(id) vce(cluster `cluster') `uc'
    local rc = _rc
    timer off 99
    quietly timer list 99
    local fitsecs = r(t99)
    return scalar ok = (`rc' == 0)
    return scalar secs_fit = `fitsecs'
    if `rc' {
        return scalar secs = `fitsecs'
        return local note "xthdidregress `arm' rc=`rc'; used_N=`e(N)'"
        exit
    }

    timer clear 98
    timer on 98
    capture quietly estat aggregation, dynamic
    local arc = _rc
    timer off 98
    quietly timer list 98
    return scalar secs_agg = r(t98)
    return scalar secs = `fitsecs' + r(t98)
    if `arc' {
        return scalar ok = 0
        return local note "estat aggregation rc=`arc'"
        exit
    }
    local ucnote = cond("`uc'" == "", "cohort derived by the command", "usercohort() supplies the true cohort")
    return local note "Stata `c(stata_version)' native; arm=`arm'; vce(cluster) as in every column; `ucnote'"
end

* ------------------------------------------------- hdidregress (Stata)
* The repeated-cross-section sibling of xthdidregress: no unit is followed, so
* the cohort is carried by a group variable and the period by time().
capture program drop bench_hdid
program define bench_hdid, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string) STRUCTure(string) ARM(string)]
    if "`arm'" == "" local arm "ra"

    local om = cond("`arm'" == "ipw", "", "`covariates'")
    local tm = cond("`arm'" == "ra", "", "`covariates'")

    timer clear 99
    timer on 99
    capture quietly hdidregress `arm' (y `om') (treated `tm'), ///
        group(gvar) time(time) vce(cluster `cluster')
    local rc = _rc
    timer off 99
    quietly timer list 99
    local fitsecs = r(t99)
    return scalar ok = (`rc' == 0)
    return scalar secs_fit = `fitsecs'
    if `rc' {
        return scalar secs = `fitsecs'
        return local note "hdidregress `arm' rc=`rc'; used_N=`e(N)'"
        exit
    }

    timer clear 98
    timer on 98
    capture quietly estat aggregation, dynamic
    local arc = _rc
    timer off 98
    quietly timer list 98
    return scalar secs_agg = r(t98)
    return scalar secs = `fitsecs' + r(t98)
    if `arc' {
        return scalar ok = 0
        return local note "estat aggregation rc=`arc'"
        exit
    }
    return local note "Stata `c(stata_version)' native, repeated cross sections; arm=`arm'"
end

* ------------------------------------------------- eventstudyinteract
* Sun and Abraham (2021) interaction-weighted estimator. The command takes a
* user-built saturated set of relative-time dummies (reference e = -1) and a
* never-treated control cohort, exactly as the reliability arms build them;
* both are constructed OUTSIDE the timer, on the same footing as the prepared
* inputs every other runner receives. The single timed call estimates every
* cohort-by-relative-time interaction and aggregates to the IW event study,
* so it sits in the one-shot family in the published tables.
capture program drop bench_esi
program define bench_esi, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string)]
    if "`mode'" == "" local mode "pointwise"
    local note "never-treated control cohort (the command takes no not-yet-treated option); dummy build timed"
    if "`mode'" != "pointwise" local note "`note'; no bootstrap or band option"

    * The saturated dummy set is estimator-specific input the user must
    * build to run this command at all, so its construction belongs inside
    * the timer -- unlike gvar/treated, which are facts of the data every
    * runner receives. Disclosed in the protocol note.
    timer clear 99
    timer on 99
    capture drop ry_XX nevertr_XX g_XX*
    quietly generate int ry_XX = time - gvar if gvar > 0
    quietly generate byte nevertr_XX = (gvar == 0)
    quietly levelsof ry_XX, local(rys)
    local dums ""
    foreach k of local rys {
        if `k' == -1 continue
        local nm = cond(`k' < 0, "g_XXm`=abs(`k')'", "g_XXp`k'")
        quietly generate byte `nm' = (ry_XX == `k')
        local dums "`dums' `nm'"
    }
    local sacov = cond("`covariates'" != "", "covariates(`covariates')", "")
    capture noisily eventstudyinteract y `dums', cohort(gvar_miss) ///
        control_cohort(nevertr_XX) `sacov' absorb(id time) vce(cluster `cluster')
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    return local note "`note'"
    if `rc' exit

    matrix B = e(b_iw)
    matrix V = e(V_iw)
    local cn : colnames B
    matrix ES = J(`horizons' + 1, 3, .)
    forvalues h = 0/`horizons' {
        local k = `h' + 1
        matrix ES[`k', 1] = `h'
        local pos : list posof "g_XXp`h'" in cn
        if `pos' > 0 {
            matrix ES[`k', 2] = B[1, `pos']
            matrix ES[`k', 3] = sqrt(V[`pos', `pos'])
        }
    }
    return matrix ES = ES
end
