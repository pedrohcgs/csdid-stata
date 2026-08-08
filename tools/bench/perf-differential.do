* ---------------------------------------------------------------------------
* perf-differential.do -- freeze every output channel of a wide option grid,
* so a performance change can be shown to move no number before it is believed.
*
*   stata-mp -b do tools/bench/perf-differential.do <tag> [size]
*
* <tag>   names the snapshot, e.g. `before' / `after'.
* [size]  `small' (default, correctness sweep) or `timing' (larger n, fewer
*         cells, for wall-clock).
*
* Writes one .dta per (cell, channel) under tools/bench/perfdiff/<tag>/ plus
* tools/bench/perfdiff/<tag>/timings.dta. Compare two snapshots with
* tools/bench/perf-differential-compare.do.
*
* WHY IT CAPTURES SO MUCH. A performance patch that changes an accumulation
* order, a mask, or a loop bound can move a number in exactly one cell of one
* option combination and nowhere else. Comparing the headline ATT would miss
* it. So every cell writes:
*
*   attgt      the full e(attgt) matrix, all ten columns, INCLUDING the
*              missing pattern (missingness is a result here: a cell that
*              starts or stops being estimable is a change)
*   b, V       the posted coefficient vector and the diagonal of its
*              covariance, with the coefficient NAMES, since a naming change
*              is a contract change
*   aggte      every aggregation the run supports
*   draws      the bootstrap draw matrix, which is where an RNG-order change
*              shows up first and an SE change shows up second
*   scalars    N, N_units, N_attgt, crit_val, wald_*, compute_path, and the
*              accelerator status, so a silent fallback to a slower or
*              different path is visible rather than hidden behind identical
*              numbers
*   log        the run's own text, so a warning that appears or disappears is
*              part of the comparison
*
* The grid is deliberately unbalanced, weighted, clustered and covariate-laden
* in different combinations rather than one "typical" run: the paths that
* diverge are the ones only one combination reaches.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

args tag size only
if "`tag'" == "" {
    display as error "usage: do perf-differential.do <tag> [small|timing] [cell]"
    exit 198
}
if "`size'" == "" local size "small"
* ONE CELL PER PROCESS. csdid is measurably session-order dependent at the
* last bit -- see session-order-1ulp-repro.do in the 2026-08-05 session folder
* -- so cells run in one process contaminate each other, and a snapshot
* comparison then measures the change AND the contamination. The shell driver
* (perf-differential.sh) passes a cell name and starts a fresh Stata for each,
* which removes the confound entirely. Running without a cell name still works
* and does the whole grid in one process, which is fine for a quick look but
* is not what a verdict should rest on.

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local out "`root'/tools/bench/perfdiff/`tag'"
capture mkdir "`root'/tools/bench/perfdiff"
capture mkdir "`out'"

* ---------------------------------------------------------------------------
* Frozen data. No rnormal(): every value is an explicit function of (id, time)
* so the fixture cannot drift with a Stata RNG change, and the same numbers
* appear in every snapshot on any machine.
* ---------------------------------------------------------------------------
program define pd_data
    version 15
    syntax , NUNITS(integer) NPERIODS(integer) NGROUPS(integer) ///
        [UNBALanced MISSCOV]

    clear
    quietly set obs `nunits'
    quietly generate long id = _n
    quietly generate byte arm = mod(_n, `ngroups' + 1)
    quietly generate double g = cond(arm == 0, 0, 1 + arm * ///
        floor((`nperiods' - 1) / (`ngroups' + 1)) + 1)
    quietly replace g = 0 if g > `nperiods'
    quietly generate double cl = mod(id, 17) + 1
    quietly generate double w = 0.5 + mod(id * 7, 13) / 13
    quietly generate double ui = mod(id * 11, 23) / 23 - 0.5
    quietly expand `nperiods'
    quietly bysort id: generate double time = _n
    quietly generate double x1 = mod(id * 13 + time * 5, 29) / 29
    quietly generate double x2 = mod(id * 3 + time * 17, 19) / 19
    quietly generate double y = ui + 0.2 * time + 0.7 * x1 - 0.4 * x2 ///
        + mod(id * 5 + time * 3, 31) / 31 ///
        + cond(g > 0 & time >= g, 1.1 + 0.3 * (time - g), 0)
    if "`unbalanced'" != "" {
        quietly drop if mod(id, 7) == 3 & time == `nperiods'
        quietly drop if mod(id, 11) == 5 & time == 2
    }
    if "`missdcov'" != "" | "`misscov'" != "" {
        quietly replace x2 = . if mod(id, 23) == 4
    }
end

* ---------------------------------------------------------------------------
* One cell: run it, time it, and freeze every channel.
* ---------------------------------------------------------------------------
program define pd_cell
    version 15
    syntax , CELL(string) CMD(string) OUT(string) [AGGS(string)]

    * When the driver names a single cell, skip every other one.
    if "$PD_ONLY" != "" & "$PD_ONLY" != "`cell'" exit

    tempfile clog
    timer clear 1
    log using "`clog'", text replace name(pdlog)
    timer on 1
    capture noisily `cmd'
    local rc = _rc
    timer off 1
    log close pdlog
    quietly timer list 1
    local secs = r(t1)

    * scalars and macros, one row
    preserve
    clear
    quietly set obs 1
    quietly generate str64 cell = "`cell'"
    quietly generate double rc = `rc'
    foreach s in N N_units N_attgt N_groups N_time bstrap biters cband ///
        level crit_val point_crit_val wald_stat wald_df wald_pvalue ///
        N_clusters time_first fast_used {
        quietly generate double s_`s' = .
        capture confirm scalar e(`s')
        if !_rc quietly replace s_`s' = e(`s')
    }
    foreach m in cmd panel_mode control_group method base_period ///
        compute_path storage bootstrap_accelerator ///
        bootstrap_accelerator_status agg_type {
        quietly generate str48 m_`m' = "`e(`m')'"
    }
    quietly save "`out'/scalars_`cell'.dta", replace
    restore

    * e(attgt), all columns, missing pattern included
    capture confirm matrix e(attgt)
    if !_rc {
        tempname AT
        matrix `AT' = e(attgt)
        preserve
        clear
        quietly svmat double `AT', names(col)
        quietly generate str64 cell = "`cell'"
        quietly save "`out'/attgt_`cell'.dta", replace
        restore
    }

    * e(b) and diag(e(V)), with the coefficient names
    capture confirm matrix e(b)
    if !_rc {
        tempname B V
        matrix `B' = e(b)
        matrix `V' = e(V)
        local bn : colnames `B'
        preserve
        clear
        quietly set obs `=colsof(`B')'
        quietly generate str64 cell = "`cell'"
        quietly generate str48 name = ""
        quietly generate double b = .
        quietly generate double vdiag = .
        forvalues j = 1/`=colsof(`B')' {
            local nm : word `j' of `bn'
            quietly replace name = "`nm'" in `j'
            quietly replace b = `B'[1, `j'] in `j'
            quietly replace vdiag = `V'[`j', `j'] in `j'
        }
        quietly save "`out'/b_`cell'.dta", replace
        restore
    }

    * the bootstrap draws: where an RNG-order change shows first
    capture confirm matrix e(boot_draws)
    if !_rc {
        tempname DR
        matrix `DR' = e(boot_draws)
        preserve
        clear
        quietly svmat double `DR'
        quietly generate str64 cell = "`cell'"
        quietly save "`out'/draws_`cell'.dta", replace
        restore
    }

    * every aggregation the run supports
    foreach a of local aggs {
        capture quietly csdid_stats, type(`a') dropmissing
        if !_rc {
            capture confirm matrix e(aggte)
            if !_rc {
                tempname AG
                matrix `AG' = e(aggte)
                preserve
                clear
                quietly svmat double `AG', names(col)
                quietly generate str64 cell = "`cell'"
                quietly generate str16 agg = "`a'"
                quietly save "`out'/agg_`cell'_`a'.dta", replace
                restore
            }
        }
    }

    * the run's own text, so an appearing or vanishing warning is a diff
    preserve
    quietly infix str line 1-240 using "`clog'", clear
    quietly drop if strpos(line, "log:") | strpos(line, "log type:") | ///
        strpos(line, "opened on:") | strpos(line, "closed on:") | ///
        strpos(line, "name:")
    quietly generate str64 cell = "`cell'"
    quietly save "`out'/log_`cell'.dta", replace
    restore

    * timing, one file per cell so parallel/serial per-process runs cannot
    * race on a shared append
    preserve
    clear
    quietly set obs 1
    quietly generate str64 cell = "`cell'"
    quietly generate double seconds = `secs'
    quietly generate double rc = `rc'
    quietly save "`out'/timing_`cell'.dta", replace
    restore
end

global PD_ONLY "`only'"
if "`only'" == "" capture erase "`out'/timings.dta"

if "`size'" == "timing" {
    local NU 4000
    local NT 8
    local NG 4
}
else {
    local NU 400
    local NT 6
    local NG 3
}

* ---------------------------------------------------------------------------
* The grid. Every line is a path that some other line does not reach.
* ---------------------------------------------------------------------------
local ALLAGG "simple group calendar dynamic"

pd_data, nunits(`NU') nperiods(`NT') ngroups(`NG')
pd_cell, cell(panel_reg_never_analytic) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) nevertreated analytical")
pd_cell, cell(panel_dr_notyet_analytic) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) notyet analytical")
pd_cell, cell(panel_ipw_notyet_analytic) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y x1 x2, ivar(id) time(time) gvar(g) method(ipw) notyet analytical")
* dr and ipw with NO covariates. Every other dr/ipw cell in this grid carries
* covariates, so before these existed the grid could not see any change to the
* intercept-only design -- the one place where the three estimators coincide
* algebraically and where routing therefore becomes a live question. The nofast
* twin is what makes the pair a real check rather than a tautology: it pins the
* general kernel while its neighbour exercises the accelerated one.
pd_cell, cell(panel_dr_nocov) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(dr) notyet analytical")
pd_cell, cell(panel_dr_nocov_nofast) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(dr) notyet analytical nofast")
pd_cell, cell(panel_ipw_nocov) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(ipw) notyet analytical")
pd_cell, cell(panel_reg_varying) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical base_period(varying)")
pd_cell, cell(panel_dr_anticip2) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y x1, ivar(id) time(time) gvar(g) method(dr) notyet analytical anticipation(2)")
pd_cell, cell(panel_reg_weighted) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y [iw=w], ivar(id) time(time) gvar(g) method(reg) notyet analytical")
pd_cell, cell(panel_dr_weighted_cov) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y x1 x2 [iw=w], ivar(id) time(time) gvar(g) method(dr) notyet analytical")
pd_cell, cell(panel_reg_cluster) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical cluster(cl)")
pd_cell, cell(panel_reg_wboot) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet wboot(reps(199) rseed(20260806))")
pd_cell, cell(panel_dr_wboot_cluster) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y x1, ivar(id) time(time) gvar(g) method(dr) notyet cluster(cl) wboot(reps(199) rseed(20260806))")
pd_cell, cell(panel_reg_fixw_base) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y [iw=w], ivar(id) time(time) gvar(g) method(reg) notyet analytical fix_weights(base_period)")
pd_cell, cell(panel_reg_pair) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical bal(pair)")
pd_cell, cell(panel_reg_storeall) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical storeall")
pd_cell, cell(panel_reg_nofast) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical nofast")
pd_cell, cell(panel_reg_fast) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical fast")

* repeated cross sections: no ivar()
pd_cell, cell(rcs_reg) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, time(time) gvar(g) method(reg) notyet analytical")
pd_cell, cell(rcs_dr_cov) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y x1 x2, time(time) gvar(g) method(dr) notyet analytical")
* dr and ipw with NO covariates on the repeated-cross-section kernel. As with
* the panel cells above, every other rcs/unbal dr cell here carries covariates,
* so before these existed the grid could not see a change to the intercept-only
* design on this path either -- which is exactly where csdid__dr_rc_fit
* delegates to the regression fit. The weighted variant is the one that matters:
* unweighted the two were already bit-identical.
pd_cell, cell(rcs_dr_nocov) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, time(time) gvar(g) method(dr) notyet analytical")
pd_cell, cell(rcs_dr_nocov_weighted) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y [iw=w], time(time) gvar(g) method(dr) notyet analytical")
pd_cell, cell(rcs_ipw_nocov) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, time(time) gvar(g) method(ipw) notyet analytical")
pd_cell, cell(rcs_reg_wboot) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, time(time) gvar(g) method(reg) notyet wboot(reps(199) rseed(20260806))")

* unbalanced panels
pd_data, nunits(`NU') nperiods(`NT') ngroups(`NG') unbalanced
pd_cell, cell(unbal_reg_none) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical bal(none)")
pd_cell, cell(unbal_dr_none_cov) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y x1, ivar(id) time(time) gvar(g) method(dr) notyet analytical bal(none)")
pd_cell, cell(unbal_dr_none_nocov_w) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y [iw=w], ivar(id) time(time) gvar(g) method(dr) notyet analytical bal(none)")
pd_cell, cell(unbal_reg_full) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical bal(full)")
pd_cell, cell(unbal_reg_pair) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical bal(pair)")
pd_cell, cell(unbal_reg_none_wboot) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet bal(none) wboot(reps(199) rseed(20260806))")
pd_cell, cell(unbal_reg_none_cluster) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical bal(none) cluster(cl)")

* factor-variable covariates, which is where the expansion screen lives
pd_data, nunits(`NU') nperiods(`NT') ngroups(`NG')
quietly generate byte reg3 = mod(id, 3)
pd_cell, cell(panel_dr_factor) out("`out'") aggs("`ALLAGG'") ///
    cmd("csdid y x1 i.reg3, ivar(id) time(time) gvar(g) method(dr) notyet analytical")

global PD_ONLY ""
display as text "perf-differential: snapshot `tag' (`size') written to `out'"
