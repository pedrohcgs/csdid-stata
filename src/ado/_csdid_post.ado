*! _csdid_post 2.0.0 30jul2026
program define _csdid_post, eclass
    version 14
    gettoken subcmd 0 : 0, parse(" ,")
    if "`subcmd'" == "attgt" {
        _csdid_post_attgt `0'
        exit
    }
    if "`subcmd'" == "event" {
        _csdid_post_event `0'
        exit
    }
    * F-045: generic aggregation poster entry point (see _csdid_post_aggte).
    if "`subcmd'" == "aggte" {
        _csdid_post_aggte `0'
        exit
    }
    if "`subcmd'" == "replacebv" {
        _csdid_post_replace_bv `0'
        exit
    }
    display as error `"_csdid_post subcommand `subcmd' is not implemented"'
    exit 198
end

program define _csdid_post_attgt, eclass
    version 14
    syntax [, Level(cilevel)]

    capture confirm matrix e(attgt)
    if _rc exit

    tempname A B V
    matrix `A' = e(attgt)

    local names ""
    local k = 0
    forvalues i = 1/`=rowsof(`A')' {
        local g = `A'[`i', 1]
        local t = `A'[`i', 2]
        local ev = `A'[`i', 3]
        local att = `A'[`i', 4]
        local se = `A'[`i', 5]
        if missing(`att') continue
        if abs(`ev' + 1) < 1e-8 continue

        local base = `g' - 1
        local gtxt : display %21.0f `g'
        local ttxt : display %21.0f `t'
        local btxt : display %21.0f `base'
        local gtxt = strtrim("`gtxt'")
        local ttxt = strtrim("`ttxt'")
        local btxt = strtrim("`btxt'")
        local cname "g`gtxt'___`ttxt'_`btxt'"

        if missing(`se') local vval 0
        else local vval = `se' ^ 2

        local ++k
        if `k' == 1 {
            matrix `B' = (`att')
            matrix `V' = (`vval')
        }
        else {
            matrix `B' = `B', (`att')
            matrix `V' = (`V', J(rowsof(`V'), 1, 0))
            matrix `V' = (`V' \ J(1, `k', 0))
            matrix `V'[`k', `k'] = `vval'
        }
        local names "`names' `cname'"
    }

    if `k' == 0 exit
    local post_if ""
    capture confirm matrix e(inffunc)
    if !_rc local post_if "e(inffunc)"
    local post_cluster ""
    capture confirm matrix e(cluster_vec)
    if !_rc local post_cluster "e(cluster_vec)"
    local post_boot ""
    local use_boot 0
    capture confirm scalar e(bstrap)
    if !_rc local use_boot = e(bstrap)
    if `use_boot' {
        capture confirm matrix e(boot_draws)
        if !_rc local post_boot "e(boot_draws)"
    }
    mata: csdid_post_attgt_v("e(attgt)", "`post_if'", "`post_cluster'", "`post_boot'", `use_boot', "`V'")
    matrix colnames `B' = `names'
    matrix colnames `V' = `names'
    matrix rownames `V' = `names'
    _csdid_post_replace_bv `B' `V'
end

program define _csdid_post_event, eclass
    version 14
    * F-047 fix: MINE/MAXE/INCLUDEOMIT are gone. Windowing belongs to
    * csdid_stats (the R-parity-verified path) BEFORE this routine runs;
    * re-windowing here is what produced the unwindowed Post_avg and the
    * fabricated zero-variance grid (see fix-register F-047). Every
    * non-missing e(aggte) row is posted, INCLUDING e = -1: R's
    * tidy/ggdid event frames carry it, so the coefficient set now matches
    * the oracle's.
    syntax [, Level(cilevel) POST]

    capture confirm matrix e(aggte)
    if _rc {
        * F-047: auto-compute quietly at the requested level.
        quietly csdid_stats, type(dynamic) na_rm level(`level')
    }
    * F-045: delegate to the generic poster with the historical event names.
    _csdid_post_aggte, level(`level') eventnames `post'
end

program define _csdid_post_aggte, eclass
    version 14
    * F-045 fix: generic aggte poster - turns the current e(aggte) (any
    * aggregation type) into e(b)/e(V) so `test' / `lincom' operate on the
    * AGGREGATED effects. Naming: dynamic -> Tm#/Tp# + Post_avg (the
    * historical event names); group -> G#; calendar -> T#; simple -> ATT.
    syntax [, Level(cilevel) EVENTNAMES POST]

    capture confirm matrix e(aggte)
    if _rc {
        * F-045: nothing to post; refuse loudly rather than silently exiting.
        display as error "no aggregation results in e(aggte); run csdid_stats first"
        exit 301
    }

    tempname A B V T MAP
    matrix `A' = e(aggte)
    * F-045: coefficient naming follows the aggregation type.
    local atype "`e(agg_type)'"

    local names ""
    local k = 0
    local has_agg_if 0
    local overall_col 0
    local post_if_src "e(agg_inffunc)"
    capture confirm matrix e(agg_inffunc)
    if !_rc {
        local has_agg_if 1
        local overall_col = colsof(e(agg_inffunc))
    }
    else {
        * Lean aggregation posts no e(agg_inffunc): the influence functions
        * stay in the Mata cache because an n_units-row matrix costs quadratic
        * time in Stata's classic-matrix layer (see csdid_stats.ado). Use the
        * cache for the posted covariances only when its token ties it to the
        * ACTIVE results - a cache left behind by a later csdid run must not
        * be merged into this estimation's e(aggte). Without this fallback the
        * posted e(V) would be diagonal and a subsequent test/lincom across
        * event times would silently use zero covariances.
        capture confirm scalar e(mata_cache_token)
        if !_rc {
            tempname aggif_probe
            capture mata: st_numscalar("`aggif_probe'", ///
                (CSDID_LAST_AGG_TOKEN == st_numscalar("e(mata_cache_token)")) * ///
                cols(CSDID_LAST_AGG_INFFUNC))
            if !_rc {
                if scalar(`aggif_probe') > 0 & scalar(`aggif_probe') < . {
                    local has_agg_if 1
                    local overall_col = scalar(`aggif_probe')
                    local post_if_src ""
                }
            }
        }
    }
    * F-047 fix: the fabricated zero-variance window grid is DELETED. Event
    * times absent from the data are not reported (R does not report them),
    * and no row is filtered here - e(aggte) already carries exactly the
    * rows csdid_stats produced for the requested window.
    * F-045: `simple' has no per-row panel; only the overall ATT is posted.
    if "`atype'" != "simple" {
        forvalues i = 1/`=rowsof(`A')' {
            local ev = `A'[`i', 1]
            local att = `A'[`i', 2]
            local se = `A'[`i', 3]
            if missing(`att') continue

            * F-045: dynamic (or an explicit eventnames request) keeps the
            * historical Tm#/Tp# names; group -> G#; calendar -> T#.
            if "`atype'" == "dynamic" | "`eventnames'" != "" {
                if `ev' < 0 {
                    local abs_ev = abs(round(`ev'))
                    local cname "Tm`abs_ev'"
                }
                else {
                    local pos_ev = round(`ev')
                    local cname "Tp`pos_ev'"
                }
            }
            else if "`atype'" == "group" {
                local cname "G`=round(`ev')'"
            }
            else {
                local cname "T`=round(`ev')'"
            }

            if missing(`se') local vval 0
            else local vval = `se' ^ 2

            local ++k
            if `k' == 1 {
                matrix `B' = (`att')
                matrix `V' = (`vval')
                matrix `MAP' = (`i')
            }
            else {
                matrix `B' = `B', (`att')
                matrix `V' = (`V', J(rowsof(`V'), 1, 0))
                matrix `V' = (`V' \ J(1, `k', 0))
                matrix `V'[`k', `k'] = `vval'
                matrix `MAP' = `MAP', (`i')
            }
            local names "`names' `cname'"
        }
    }

    if rowsof(`A') > 0 {
        local post_att = `A'[1, 4]
        local post_se = `A'[1, 5]
        if !missing(`post_att') {
            if missing(`post_se') local post_v 0
            else local post_v = `post_se' ^ 2
            * F-045: overall-column name follows the aggregation type.
            local oname = cond("`atype'" == "dynamic" | "`eventnames'" != "", ///
                "Post_avg", cond("`atype'" == "simple", "ATT", "Overall"))

            local ++k
            if `k' == 1 {
                matrix `B' = (`post_att')
                matrix `V' = (`post_v')
                matrix `MAP' = (`overall_col')
            }
            else {
                matrix `B' = `B', (`post_att')
                matrix `V' = (`V', J(rowsof(`V'), 1, 0))
                matrix `V' = (`V' \ J(1, `k', 0))
                matrix `V'[`k', `k'] = `post_v'
                matrix `MAP' = `MAP', (`overall_col')
            }
            * F-045: was hardcoded Post_avg.
            local names "`names' `oname'"
        }
    }

    if `k' == 0 exit
    if `has_agg_if' {
        local post_cluster ""
        capture confirm matrix e(cluster_vec)
        if !_rc local post_cluster "e(cluster_vec)"
        local post_boot ""
        local use_boot 0
        capture confirm scalar e(bstrap)
        if !_rc local use_boot = e(bstrap)
        if `use_boot' {
            capture confirm matrix e(agg_boot_draws)
            if !_rc local post_boot "e(agg_boot_draws)"
        }
        mata: csdid_post_mapped_v("`post_if_src'", "`post_cluster'", "`post_boot'", `use_boot', "`MAP'", "`V'")
    }
    matrix colnames `B' = `names'
    matrix colnames `V' = `names'
    matrix rownames `V' = `names'
    tempname EB EV
    if "`post'" != "" {
        _csdid_post_replace_bv `B' `V'
        matrix `EB' = e(b)
        matrix `EV' = e(V)
    }
    else {
        * No-transit path. A non-post estat is a display-and-return command,
        * but it used to post the aggregation into e(b)/e(V) anyway and the
        * caller then restored the originals. Each of those swaps rebuilds
        * e() wholesale, Stata-copying every stored matrix - including the
        * one-row-per-unit influence functions under full storage - and
        * Stata's classic-matrix layer is quadratic in a matrix's longest
        * dimension (measured: 4s at 25k rows, 27s at 50k, per copy). A plain
        * `estat event' after a 20,000-unit estimation spent ~19 of its 19
        * seconds copying matrices it did not change. r(table) is built from
        * the same B/V the posting path would have posted, so its contents
        * are identical; e() is simply never touched.
        matrix `EB' = `B'
        matrix `EV' = `V'
    }
    matrix `T' = J(9, `k', .)
    * F-046 fix: level() was DEAD - the pointwise critical value computed
    * from it was unconditionally overwritten by the estimation-time
    * e(crit_val). The band now follows the REQUESTED level under analytic
    * inference; under bootstrap the estimation crit is kept (a bootstrap
    * band cannot be re-levelled after the fact - R has no such knob either).
    local pointcrit = invnormal(1 - (100 - `level') / 200)
    local bandcrit = `pointcrit'
    local use_boot_crit 0
    capture confirm scalar e(bstrap)
    if !_rc {
        if e(bstrap) == 1 local use_boot_crit 1
    }
    if `use_boot_crit' {
        capture local bandcrit = e(crit_val)
        if missing(`bandcrit') local bandcrit = `pointcrit'
    }
    forvalues j = 1/`k' {
        matrix `T'[1, `j'] = `EB'[1, `j']
        local v = `EV'[`j', `j']
        if !missing(`v') & `v' >= 0 {
            local se = sqrt(`v')
            matrix `T'[2, `j'] = `se'
            if `se' > 0 {
                matrix `T'[3, `j'] = `EB'[1, `j'] / `se'
                matrix `T'[4, `j'] = 2 * normal(-abs(`EB'[1, `j'] / `se'))
            }
            matrix `T'[5, `j'] = `EB'[1, `j'] - `bandcrit' * `se'
            matrix `T'[6, `j'] = `EB'[1, `j'] + `bandcrit' * `se'
            matrix `T'[8, `j'] = `bandcrit'
        }
        matrix `T'[9, `j'] = 0
    }
    matrix colnames `T' = `names'
    matrix rownames `T' = b se z pvalue ll ul df crit eform
    _csdid_post_return_table `T'
end

program define _csdid_post_return_table, rclass
    version 14
    args tablemat
    return matrix table = `tablemat'
end

program define _csdid_post_replace_bv, eclass
    version 14
    args bmat vmat

    tempname ATT IF GP UG CLV AGG AGGIF BATT BDRAWS BAGG AGGBDRAWS BRNG ///
        PROF BPROF BKPROF ABPROF
    capture confirm matrix e(attgt)
    local has_ATT = !_rc
    if `has_ATT' matrix `ATT' = e(attgt)
    capture confirm matrix e(inffunc)
    local has_IF = !_rc
    if `has_IF' matrix `IF' = e(inffunc)
    capture confirm matrix e(group_prob)
    local has_GP = !_rc
    if `has_GP' matrix `GP' = e(group_prob)
    capture confirm matrix e(unit_group)
    local has_UG = !_rc
    if `has_UG' matrix `UG' = e(unit_group)
    capture confirm matrix e(cluster_vec)
    local has_CLV = !_rc
    if `has_CLV' matrix `CLV' = e(cluster_vec)
    capture confirm matrix e(aggte)
    local has_AGG = !_rc
    if `has_AGG' matrix `AGG' = e(aggte)
    capture confirm matrix e(agg_inffunc)
    local has_AGGIF = !_rc
    if `has_AGGIF' matrix `AGGIF' = e(agg_inffunc)
    capture confirm matrix e(boot_attgt)
    local has_BATT = !_rc
    if `has_BATT' matrix `BATT' = e(boot_attgt)
    capture confirm matrix e(boot_draws)
    local has_BDRAWS = !_rc
    if `has_BDRAWS' matrix `BDRAWS' = e(boot_draws)
    capture confirm matrix e(boot_aggte)
    local has_BAGG = !_rc
    if `has_BAGG' matrix `BAGG' = e(boot_aggte)
    capture confirm matrix e(agg_boot_draws)
    local has_AGGBDRAWS = !_rc
    if `has_AGGBDRAWS' matrix `AGGBDRAWS' = e(agg_boot_draws)
    capture confirm matrix e(boot_rng_state)
    local has_BRNG = !_rc
    if `has_BRNG' matrix `BRNG' = e(boot_rng_state)
    capture confirm matrix e(profile)
    local has_PROF = !_rc
    if `has_PROF' matrix `PROF' = e(profile)
    capture confirm matrix e(bootstrap_profile)
    local has_BPROF = !_rc
    if `has_BPROF' matrix `BPROF' = e(bootstrap_profile)
    capture confirm matrix e(bootstrap_kernel_profile)
    local has_BKPROF = !_rc
    if `has_BKPROF' matrix `BKPROF' = e(bootstrap_kernel_profile)
    capture confirm matrix e(agg_bootstrap_profile)
    local has_ABPROF = !_rc
    if `has_ABPROF' matrix `ABPROF' = e(agg_bootstrap_profile)

    capture confirm scalar e(bootstrap_accelerator_rc)
    local has_boot_accel_rc = !_rc
    if `has_boot_accel_rc' local boot_accel_rc = e(bootstrap_accelerator_rc)
    capture confirm scalar e(bootstrap_accelerator_seconds)
    local has_boot_accel_seconds = !_rc
    if `has_boot_accel_seconds' local boot_accel_seconds = e(bootstrap_accelerator_seconds)
    capture confirm scalar e(agg_boot_accel_rc)
    local has_agg_boot_rc = !_rc
    if `has_agg_boot_rc' local agg_boot_rc = e(agg_boot_accel_rc)

    local boot_accel `"`e(bootstrap_accelerator)'"'
    local boot_accel_status `"`e(bootstrap_accelerator_status)'"'
    local boot_accel_file `"`e(bootstrap_accelerator_file)'"'
    local agg_boot_accel `"`e(agg_boot_accelerator)'"'
    local agg_boot_status `"`e(agg_boot_accel_status)'"'

    * F-055: time_first and performance_auto_threshold were posted by
    * estimation but missing from this enumeration, so every replacebv
    * round-trip (all estat event paths, agg() at estimation) silently
    * dropped them - and balance_e() reads e(time_first), so
    * `csdid_stats event, balance_e()' hard-errored after any `estat event'.
    local scalar_names N N_units N_attgt N_groups N_time anticipation pscoretrim ///
        bstrap biters cband pointwise fast_requested fast_auto fast_allowed fast_used crit_val point_crit_val ///
        N_clusters level agg_cluster_fallback agg_level N_aggte time_first ///
        allow_unbalanced mata_cache mata_cache_token
    * (F-055's separate handling of performance_auto_threshold is gone with
    * the scalar itself: storage is unified on lean, so no threshold exists.)
    foreach s of local scalar_names {
        capture confirm scalar e(`s')
        local has_scalar_`s' = !_rc
        if `has_scalar_`s'' local scalar_`s' = e(`s')
    }

    * SP-03: marginsnotok was missing from this enumeration (same class as the
    * F-055 omissions above), so every estat posting path stripped csdid's
    * margins guard: after `estat simple, post' or even a plain non-post
    * `estat event', `predict' returned rc 0 and `margins, noesample' printed a
    * full "Predictive margins" table off e(b) - fabricated numbers from an
    * estimator that has no prediction. depvar/vce/vcetype/predict are carried
    * for the same reason (HS-06/HS-03 post them at estimation time).
    local local_names cmd cmdline version yname timevar gvar idvar clustervar ///
        panel_mode control_group method method_requested weightvar base_period ///
        fix_weights boot_dist boot_dist_requested boot_seed fast_mode compute_path rif_file ///
        storage agg_type agg_clustervar ///
        marginsnotok depvar vce vcetype predict
    foreach m of local local_names {
        local local_`m' `"`e(`m')'"'
    }
    * SP-03: csdid.ado sets marginsnotok unconditionally, but the saved-RIF
    * entry path (csdid_stats using) never does. margins is never valid after
    * csdid on any path, so default it rather than leave the guard off.
    if `"`local_marginsnotok'"' == "" local local_marginsnotok "_ALL"

    * SP-03/DS-10: reps and rseed may be posted either as scalars or as macros
    * depending on how the inference settings are stored; preserve whichever
    * form is actually present instead of silently converting one to the other.
    foreach x in reps rseed {
        capture confirm scalar e(`x')
        if !_rc {
            local isnum_`x' 1
            local keep_`x' = e(`x')
        }
        else {
            local isnum_`x' 0
            local keep_`x' `"`e(`x')'"'
        }
    }

    * Carry e(sample) across the wipe: the estimation marked it, and a posted
    * aggregation must keep describing the same estimation sample. e(sample)
    * evaluates rowwise to 0 everywhere when it was never set, so an empty
    * marking is detected by count and simply not re-posted.
    tempvar esmp
    local has_esample 0
    quietly count if e(sample)
    if r(N) > 0 {
        quietly generate byte `esmp' = e(sample)
        local has_esample 1
    }
    ereturn clear
    local esamp_opt ""
    if `has_esample' local esamp_opt "esample(`esmp')"
    if `has_scalar_N' {
        ereturn post `bmat' `vmat', obs(`scalar_N') `esamp_opt'
    }
    else {
        ereturn post `bmat' `vmat', `esamp_opt'
    }

    if `has_ATT' ereturn matrix attgt = `ATT'
    if `has_IF' ereturn matrix inffunc = `IF'
    if `has_GP' ereturn matrix group_prob = `GP'
    if `has_UG' ereturn matrix unit_group = `UG'
    if `has_CLV' ereturn matrix cluster_vec = `CLV'
    if `has_AGG' ereturn matrix aggte = `AGG'
    if `has_AGGIF' ereturn matrix agg_inffunc = `AGGIF'
    if `has_BATT' ereturn matrix boot_attgt = `BATT'
    if `has_BDRAWS' ereturn matrix boot_draws = `BDRAWS'
    if `has_BAGG' ereturn matrix boot_aggte = `BAGG'
    if `has_AGGBDRAWS' ereturn matrix agg_boot_draws = `AGGBDRAWS'
    if `has_BRNG' ereturn matrix boot_rng_state = `BRNG'
    if `has_PROF' ereturn matrix profile = `PROF'
    if `has_BPROF' ereturn matrix bootstrap_profile = `BPROF'
    if `has_BKPROF' ereturn matrix bootstrap_kernel_profile = `BKPROF'
    if `has_ABPROF' ereturn matrix agg_bootstrap_profile = `ABPROF'

    foreach s of local scalar_names {
        if `has_scalar_`s'' {
            ereturn scalar `s' = `scalar_`s''
        }
    }

    foreach m of local local_names {
        if `"`local_`m''"' != "" {
            ereturn local `m' `"`local_`m''"'
        }
    }
    * SP-03/DS-10: re-post reps/rseed in whichever form they were stored.
    foreach x in reps rseed {
        if `isnum_`x'' {
            ereturn scalar `x' = `keep_`x''
        }
        else if `"`keep_`x''"' != "" {
            ereturn local `x' `"`keep_`x''"'
        }
    }
    if `has_boot_accel_rc' ereturn scalar bootstrap_accelerator_rc = `boot_accel_rc'
    if `has_boot_accel_seconds' ereturn scalar bootstrap_accelerator_seconds = `boot_accel_seconds'
    if `has_agg_boot_rc' ereturn scalar agg_boot_accel_rc = `agg_boot_rc'
    if `"`boot_accel'"' != "" ereturn local bootstrap_accelerator `"`boot_accel'"'
    if `"`boot_accel_status'"' != "" ereturn local bootstrap_accelerator_status `"`boot_accel_status'"'
    if `"`boot_accel_file'"' != "" ereturn local bootstrap_accelerator_file `"`boot_accel_file'"'
    if `"`agg_boot_accel'"' != "" ereturn local agg_boot_accelerator `"`agg_boot_accel'"'
    if `"`agg_boot_status'"' != "" ereturn local agg_boot_accel_status `"`agg_boot_status'"'
    ereturn local cmd "csdid"
    ereturn local estat_cmd "csdid_estat"
    ereturn local properties "b V"
end
