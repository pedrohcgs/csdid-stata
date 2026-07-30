*! csdid_stats 2.0.0 30jul2026
program define csdid_stats, eclass
    version 14
    * EUX-004: parse `using' as a declared, optional part of the command
    * instead of running `syntax ... using/' under -capture- and falling back
    * to a second syntax call. The old fallback swallowed the real diagnosis:
    * any option error on the using path (level(150), a duplicate option, a
    * bad window()) made the FIRST syntax fail, and the SECOND syntax then
    * reported "using not allowed" r(101). One declarative syntax reports the
    * option that is actually wrong, on both paths.
    syntax [anything(name=subcmd)] [using/] [, TYPE(string) Level(cilevel) ///
        WINdow(string) BALance(string) DROPMissing FROM(string) *]
    * from() is unsupported by design; see csdid.ado for the full rationale.
    * Legacy accepted it on the simple, group and calendar aggregations.
    if `"`from'"' != "" {
        display as error "from() is no longer supported; it set a lower event-time bound on the simple, group and calendar aggregations, which R fixes at event time 0. Use window(# #) with type(dynamic) for event-time windows."
        exit 198
    }
    if `"`using'"' != "" {
        _csdid_stats_load_rif using `"`using'"'
    }
    else {
        if "`e(cmd)'" != "csdid" {
            display as error "csdid_stats requires prior csdid results or a saved RIF file"
            exit 301
        }
    }
    * F-034 fix: inherit the ESTIMATION-time confidence level from
    * e(level). The direct path defaulted to the SESSION c(level), so
    * every aggregation after "csdid ..., level(90)" silently banded at
    * 95. Level(cilevel) cannot distinguish an explicit level(c(level))
    * from the default; in that (value-identical) case the estimation
    * level wins - the same rule R applies by construction, since aggte
    * has no level knob and always follows the estimation alp.
    *
    * OPT-005: this block used to live ONLY in the non-`using' branch, so
    * the saved-RIF path banded at the session c(level) even though
    * _csdid_stats_load_rif posts e(level) from char _dta[csdid_level].
    * Measured: "csdid ..., level(90) saverif(r90)" then "csdid_stats using
    * r90" gave e(level)=90 with e(agg_level)=95, contradicting
    * csdid_stats.sthlp and the comment above it. It now runs on BOTH paths.
    if `level' == c(level) {
        capture confirm scalar e(level)
        if !_rc {
            if !missing(e(level)) {
                * F-034: strofreal, NOT a bare "local level = e(level)":
                * that renders the stored double at full precision
                * (99.90000000000001 for level(99.9)) and the level()
                * parser rejects >2 decimals (measured S1468 rc 198).
                local level = strofreal(e(level), "%12.0g")
            }
        }
    }

    local min_e -1e300
    local max_e 1e300
    local balance_e -1
    local min_e_specified 0
    local max_e_specified 0
    local balance_e_specified 0
    local balance_given 0
    if `"`window'"' != "" {
        local window_clean = subinstr(`"`window'"', ",", " ", .)
        local window_n : word count `window_clean'
        if `window_n' != 2 {
            display as error "window() requires two numeric bounds"
            exit 198
        }
        local min_e : word 1 of `window_clean'
        local max_e : word 2 of `window_clean'
        capture confirm number `min_e'
        if _rc {
            display as error "window() requires numeric bounds"
            exit 198
        }
        capture confirm number `max_e'
        if _rc {
            display as error "window() requires numeric bounds"
            exit 198
        }
        local min_e_specified 1
        local max_e_specified 1
    }
    * EUX-010/EUX-011: balance() used to be declared BALance(integer -1), so
    * -1 doubled as "unspecified" and every negative value was silently
    * discarded (measured: balance(-3) rc 0, full unwindowed table), while a
    * non-numeric value fell through the `*' catch-all and was reported as an
    * "unsupported option" even though balance() is supported. Parse it as a
    * string and validate the VALUE.
    if `"`balance'"' != "" {
        local balance_clean = strtrim(`"`balance'"')
        capture confirm number `balance_clean'
        if _rc {
            display as error "balance() requires a nonnegative integer; found `balance_clean'"
            exit 198
        }
        local balance_num = real("`balance_clean'")
        if `balance_num' < 0 | `balance_num' != int(`balance_num') {
            display as error "balance() requires a nonnegative integer; found `balance_clean'"
            exit 198
        }
        local balance_e = `balance_num'
        local balance_e_specified 1
        local balance_given 1
    }
    local na_rm ""
    if "`dropmissing'" != "" local na_rm "na_rm"
    local agg_cluster ""
    local unsupported ""
    * EUX-013/OPT-011: -syntax- hands the leftover options back as ONE string,
    * and the plain `foreach opt of local options' this loop used to open with
    * split that string at every blank. So `min_e( -1 )' - spacing the DECLARED
    * options accept without complaint (measured: `window( -1 1 )' parses) -
    * arrived here as the three tokens "min_e(", "-1" and ")", matched none of
    * the patterns below, and came back as three separate "unsupported options"
    * with the fault misattributed and the typed value scattered across the
    * message. Blank-separated pieces are now re-joined until the parentheses
    * balance, so one option is one token again:
    *   `opt_c'  - blanks removed, case preserved: drives every match below and
    *              recovers the user's capitalisation for cluster();
    *   `opt'    - blanks kept: what any message shows, so nothing the user
    *              typed is lost from the diagnosis either.
    local opt_rest `"`options'"'
    while `"`opt_rest'"' != "" {
        gettoken opt opt_rest : opt_rest, parse(" ")
        local opt = strtrim(`"`opt'"')
        if `"`opt'"' == "" continue
        local opt_c = subinstr(`"`opt'"', " ", "", .)
        local opt_open = length(`"`opt_c'"') - length(subinstr(`"`opt_c'"', "(", "", .))
        local opt_close = length(`"`opt_c'"') - length(subinstr(`"`opt_c'"', ")", "", .))
        while `opt_open' > `opt_close' & `"`opt_rest'"' != "" {
            gettoken opt_more opt_rest : opt_rest, parse(" ")
            local opt_more = strtrim(`"`opt_more'"')
            local opt `"`opt' `opt_more'"'
            local opt_c `"`opt_c'`opt_more'"'
            local opt_open = length(`"`opt_c'"') - length(subinstr(`"`opt_c'"', "(", "", .))
            local opt_close = length(`"`opt_c'"') - length(subinstr(`"`opt_c'"', ")", "", .))
        }
        local opt_l = lower(`"`opt_c'"')
        * OPT-002/OPT-004/OPT-009: capture the WHOLE argument and validate it
        * with -confirm number- before it is interpolated into the Mata call.
        * The old character-class regex accepted "1e", "1.2.3", "-", "++" and
        * "." and handed them straight to Mata, which answered with r(3000)
        * compiler diagnostics ("'1e' found where almost anything else
        * expected") or, for ".", silently ignored max_e while min_e failed
        * downstream with a traceback. A repeated min_e()/max_e()/balance_e()
        * used to last-win in silence.
        if regexm(`"`opt_l'"', "^min_e\((.*)\)$") {
            local min_e_val = strtrim(regexs(1))
            if `"`window'"' != "" {
                display as error "min_e() and window() both set the event-time window; specify only one. window(# #) sets the lower and upper bound together."
                exit 198
            }
            if `min_e_specified' {
                display as error "option min_e() specified more than once"
                exit 198
            }
            if `"`min_e_val'"' == "" {
                display as error "min_e() requires a number"
                exit 198
            }
            capture confirm number `min_e_val'
            if _rc {
                display as error "min_e() requires a nonmissing number; found `min_e_val'"
                exit 198
            }
            local min_e `min_e_val'
            local min_e_specified 1
        }
        else if regexm(`"`opt_l'"', "^max_e\((.*)\)$") {
            local max_e_val = strtrim(regexs(1))
            if `"`window'"' != "" {
                display as error "max_e() and window() both set the event-time window; specify only one. window(# #) sets the lower and upper bound together."
                exit 198
            }
            if `max_e_specified' {
                display as error "option max_e() specified more than once"
                exit 198
            }
            if `"`max_e_val'"' == "" {
                display as error "max_e() requires a number"
                exit 198
            }
            capture confirm number `max_e_val'
            if _rc {
                display as error "max_e() requires a nonmissing number; found `max_e_val'"
                exit 198
            }
            local max_e `max_e_val'
            local max_e_specified 1
        }
        else if regexm(`"`opt_l'"', "^balance_e\((.*)\)$") {
            local balance_e_val = strtrim(regexs(1))
            if `balance_given' {
                display as error "balance_e() and balance() are the same option under two names; specify only one."
                exit 198
            }
            if `balance_e_specified' {
                display as error "option balance_e() specified more than once"
                exit 198
            }
            capture confirm number `balance_e_val'
            if _rc {
                display as error "balance_e() requires a nonnegative integer; found `balance_e_val'"
                exit 198
            }
            local balance_e_num = real("`balance_e_val'")
            if `balance_e_num' < 0 | `balance_e_num' != int(`balance_e_num') {
                display as error "balance_e() requires a nonnegative integer; found `balance_e_val'"
                exit 198
            }
            local balance_e = `balance_e_num'
            local balance_e_specified 1
        }
        else if inlist(`"`opt_l'"', "na_rm", "na.rm", "dropmissing") {
            local na_rm "na_rm"
        }
        else if regexm(`"`opt_l'"', "^(cluster|clustervars)\(([^)]+)\)$") {
            local agg_cluster = regexs(2)
            * recover the user's capitalisation: the match ran on the
            * lower-cased token, but e(clustervar) stores the real name.
            * EUX-013: read it off `opt_c' (blanks removed, case kept) so
            * `cluster( State )' recovers "State", not " State ".
            if regexm(`"`opt_c'"', "\(([^)]+)\)$") local agg_cluster = regexs(1)
        }
        * OPT-004: a repeated DECLARED option is handed to the `*' catch-all
        * by -syntax-, so "window(0 2) window(1 3)" used to be reported as an
        * unsupported option. Name the real fault.
        else if regexm(`"`opt_l'"', "^(window|balance|type|level)\(") {
            local dup_opt = regexs(1)
            display as error "option `dup_opt'() specified more than once"
            exit 198
        }
        else {
            local unsupported "`unsupported' `opt'"
        }
    }
    if `"`unsupported'"' != "" {
        * D-1: compound quotes. A quoted option VALUE (e.g.
        * title("Cohort 2004")) puts a double quote inside `options', and the
        * plain-quoted display then breaks the string, producing a garbled
        * message and r(111) instead of the documented r(198).
        display as error `"unsupported option(s):`unsupported'"'
        exit 198
    }
    * EUX-012: refuse reversed bounds at parse time, naming the option the
    * user typed. They used to reach the kernel and come back as "no event
    * times fall within the requested aggregation window" plus Mata frames.
    if `min_e_specified' & `max_e_specified' {
        if `min_e' > `max_e' {
            if `"`window'"' != "" {
                display as error "window() lower bound `min_e' may not exceed upper bound `max_e'"
            }
            else {
                display as error "min_e(`min_e') may not exceed max_e(`max_e')"
            }
            exit 198
        }
    }
    * OPT-019: an extra positional token used to be folded into `subcmd' and
    * blamed on type(), an option the user never typed.
    * D-1: strip any quotes the user typed (csdid_stats "foo bar") ONCE, here.
    * Leaving them in made the unquoted expansions below exit r(109)/r(111)
    * instead of the documented r(198); compound-quoting the expansions instead
    * would break word counting, because Stata counts a quoted string as ONE
    * word and the extra-token check below would stop firing.
    local subcmd = subinstr(`"`subcmd'"', `"""', "", .)
    local subcmd = strtrim(`"`subcmd'"')
    local n_subcmd : word count `subcmd'
    if `n_subcmd' > 1 {
        local extra_tokens ""
        forvalues j = 2/`n_subcmd' {
            local one_token : word `j' of `subcmd'
            local extra_tokens "`extra_tokens' `one_token'"
        }
        display as error `"csdid_stats accepts at most one subcommand; unexpected token(s):`extra_tokens'"'
        exit 198
    }
    * OPT-008/SP-09: "csdid_stats simple, type(group)" used to run type(group)
    * and discard the subcommand without a word.
    if `"`subcmd'"' != "" & `"`type'"' != "" {
        local subcmd_norm = lower(strtrim(`"`subcmd'"'))
        if "`subcmd_norm'" == "event" local subcmd_norm "dynamic"
        local type_norm = lower(strtrim(`"`type'"'))
        if "`type_norm'" == "event" local type_norm "dynamic"
        if "`subcmd_norm'" != "`type_norm'" {
            display as error `"subcommand `subcmd' conflicts with type(`type'); specify only one"'
            exit 198
        }
    }
    * D-1: compound quotes here too - a quoted subcommand otherwise reaches
    * inlist() still carrying its quotes and exits r(109) type mismatch.
    local type_from_subcmd = (`"`type'"' == "" & `"`subcmd'"' != "")
    if `"`type'"' == "" local type `"`subcmd'"'
    if `"`type'"' == "" local type "group"
    local type = lower(strtrim(`"`type'"'))
    if `"`type'"' == "event" local type "dynamic"
    if !inlist(`"`type'"', "simple", "group", "dynamic", "calendar") {
        * OPT-019: name what the user actually typed. A bad POSITIONAL
        * subcommand used to be reported as a bad type(), an option that was
        * never on the command line. The frozen F029 event contract pins the
        * type() wording for the option form, so only the positional form is
        * re-worded.
        if `type_from_subcmd' {
            display as error `"csdid_stats subcommand `subcmd' is not supported; supported subcommands are simple, group, dynamic/event, and calendar"'
        }
        else {
            display as error "type() must be one of simple, group, dynamic/event, or calendar"
        }
        exit 198
    }
    if "`type'" == "calendar" & (`min_e_specified' | `max_e_specified' | `balance_e_specified') {
        display as text "warning: min_e(), max_e(), and balance_e() are ignored for type(calendar)"
    }
    local na_rm_flag = ("`na_rm'" != "")
    local use_cluster = ("`e(clustervar)'" != "")
    local agg_cluster_fallback = 0
    if "`agg_cluster'" != "" {
        if "`e(clustervar)'" == "`agg_cluster'" {
            local use_cluster = 1
        }
        else {
            * EUX-007: e(clustervar) is empty whenever the estimation was not
            * clustered, and the single message then rendered as "... does not
            * match the estimation cluster ;" and told the user to rerun with
            * the cluster they had just asked for. Split the branch.
            * The frozen RT001 gate requires the phrase "does not match the
            * estimation cluster" on BOTH branches, so it is kept verbatim;
            * only the dangling empty name and the contradictory advice go.
            if "`e(clustervar)'" == "" {
                display as error `"csdid_stats cluster(`agg_cluster') does not match the estimation cluster: the active csdid results are not clustered. Rerun csdid with cluster(`agg_cluster'), or omit cluster()"'
            }
            else {
                display as error `"csdid_stats cluster(`agg_cluster') does not match the estimation cluster `e(clustervar)'; rerun csdid with cluster(`agg_cluster') or omit cluster()"'
            }
            exit 498
        }
    }

    tempname aggte agg_inffunc
    capture confirm matrix e(inffunc)
    local has_inffunc = !_rc
    capture confirm matrix e(unit_group)
    local has_unit_group = !_rc
    local use_cache = !(`has_inffunc' & `has_unit_group')
    * Aggregation storage follows estimation storage. Full storage posted
    * e(inffunc)/e(unit_group), so the aggregation influence functions are
    * posted as e(agg_inffunc) exactly as before. Lean storage (the
    * performance(auto) default at N_units >= 25,000, or performance(lean))
    * keeps the estimation IF in the Mata cache, and the aggregation IF now
    * stays there too: every crossing of an n_units-row matrix into Stata's
    * classic-matrix layer is quadratic in n_units (measured per write or
    * copy: 4s at 25k rows, 27s at 50k, 145s at 100k, orientation-independent),
    * and the old unconditional write + ereturn + post/restore copies made
    * `estat event' after a 400,000-unit estimation spin for hours while the
    * estimation itself took 33 seconds. Consumers of the IF fall back to the
    * Mata cache through the same empty-name convention the bootstrap
    * plumbing already uses (see _csdid_post.ado and csdid_post_mapped_v).
    local agg_store_large = (`use_cache' == 0)
    capture mata: csdid__mean(J(1, 1, 0))
    if _rc {
        capture quietly findfile csdid.mata
        if _rc {
            display as error "csdid Mata source not found on adopath"
            exit 499
        }
        quietly do "`r(fn)'"
    }
    if `use_cache' {
        capture confirm scalar e(mata_cache)
        if _rc | e(mata_cache) != 1 {
            display as error "csdid_stats needs the results of the csdid run it is summarizing; rerun csdid, or rerun it with storeall, immediately before csdid_stats"
            exit 498
        }
        capture confirm scalar e(mata_cache_token)
        if _rc {
            display as error "csdid_stats needs the results of the csdid run it is summarizing; rerun csdid immediately before csdid_stats"
            exit 498
        }
        local cache_token = e(mata_cache_token)
        local cache_n_units = e(N_units)
        local cache_n_attgt = e(N_attgt)
        * EUX-001: plain -capture-, not -capture noisily-. Measured in Stata
        * 17: `capture noisily mata: f()' still prints the Mata traceback log
        * ("csdid_cache_validate(): 498 Stata returned error / <istmt>: -
        * function returned error") under the message; only a bare -capture-
        * suppresses the frames. The message is re-raised here instead.
        capture mata: csdid_cache_validate(`cache_token', `cache_n_units', `cache_n_attgt')
        local cache_rc = _rc
        if `cache_rc' {
            display as error "the stored results do not match the last csdid run; rerun csdid with storeall, or rerun the original estimation, immediately before csdid_stats"
            exit `cache_rc'
        }
    }
    * EUX-001: the aggregation kernel used to be called bare, so every kernel
    * refusal ("no event times fall within the requested aggregation window",
    * "missing values found in ATT(g,t) estimates", ...) arrived with two
    * lines of Mata frames stapled underneath it. Run it under -capture- and
    * re-raise the diagnosis from the ado.
    capture mata: csdid_aggte("`type'", `min_e', `max_e', `balance_e', `na_rm_flag', `use_cluster', `use_cache', "`aggte'", "`agg_inffunc'", `agg_store_large')
    local aggte_rc = _rc
    if `aggte_rc' {
        _csdid_stats_aggfail, type(`type') mine(`min_e') maxe(`max_e') ///
            bale(`balance_e') narm(`na_rm_flag') usecache(`use_cache')
        exit `aggte_rc'
    }
    capture confirm scalar e(bstrap)
    local bstrap = 0
    if !_rc local bstrap = e(bstrap)
    if `bstrap' {
        local biters = e(biters)
        local cband = e(cband)
        local boot_dist "`e(boot_dist)'"
        if "`boot_dist'" == "" local boot_dist "rademacher"
        tempname boot_aggte agg_boot_draws agg_crit agg_pointcrit boot_rng_state agg_bootstrap_profile
        if !`agg_store_large' {
            * The bootstrap plumbing below consumes a named Stata matrix.
            * Under lean aggregation the IF lives only in the Mata cache, so
            * materialize it once here -- the single remaining quadratic
            * boundary crossing, paid only when an aggregation bootstrap is
            * actually requested.
            mata: st_matrix("`agg_inffunc'", CSDID_LAST_AGG_INFFUNC)
        }
        local boot_agg_if "`agg_inffunc'"
        local boot_agg_cluster_vec ""
        if `use_cluster' {
            tempname boot_agg_cluster_raw
            capture confirm matrix e(cluster_vec)
            if !_rc {
                matrix `boot_agg_cluster_raw' = e(cluster_vec)
            }
            else {
                * EUX-001: an unset CSDID_LAST_CLUSTER_VEC would otherwise
                * abort with raw Mata frames instead of a named refusal.
                capture mata: st_matrix("`boot_agg_cluster_raw'", CSDID_LAST_CLUSTER_VEC)
                if _rc {
                    display as error "the clustered bootstrap needs the cluster information from the csdid run; rerun csdid with storeall before csdid_stats"
                    exit 498
                }
            }
            local boot_agg_cluster_vec "`boot_agg_cluster_raw'"
        }
        else if "`e(idvar)'" != "" {
            * F-001/F-022 (repaired, donor label F-003): the allow_unbalanced
            * aggregation bootstrap must consume multiplier draws in R's
            * unbalanced unit order. The repaired estimation stage carries the
            * draw-order key INSIDE the unit/group map itself (4th column =
            * each unit's first-appearance period), so the map this call
            * already passes is the augmented one on every storage mode:
            * full storage posts the 4-column e(unit_group), and lean storage
            * leaves e(unit_group) empty so csdid_boot_reorder_r falls back to
            * the 4-column CSDID_LAST_UNIT_GROUP. csdid_boot_reorder_r then
            * branches on cols >= 4. The donor's separate e(unit_group_boot)
            * export is therefore not required; it is still preferred here if
            * present, and the confirm guard falls back to e(unit_group) so no
            * storage mode can reference an unposted matrix (the donor's
            * unguarded st_matrix on lean storage was the r(3301) crash).
            local boot_agg_unit "e(unit_group)"
            if "`e(panel_mode)'" == "allow_unbalanced" {
                capture confirm matrix e(unit_group_boot)
                if !_rc local boot_agg_unit "e(unit_group_boot)"
            }
            tempname boot_agg_if_ordered boot_agg_cluster_ordered
            capture mata: csdid_boot_reorder_r("`boot_agg_unit'", ///
                "`agg_inffunc'", "", "`boot_agg_if_ordered'", ///
                "`boot_agg_cluster_ordered'")
            local csdid_rc = _rc
            if `csdid_rc' {
                display as error "csdid_stats could not put the aggregate influence functions in bootstrap draw order; rerun csdid before csdid_stats"
                exit `csdid_rc'
            }
            local boot_agg_if "`boot_agg_if_ordered'"
        }
        else {
            tempname boot_agg_if_ordered boot_agg_cluster_ordered
            capture mata: csdid_boot_reorder_rc_r("`e(timevar)'", ///
                "e(unit_group)", "`agg_inffunc'", "", ///
                "`boot_agg_if_ordered'", "`boot_agg_cluster_ordered'")
            local csdid_rc = _rc
            if `csdid_rc' {
                display as error "csdid_stats could not put the aggregate influence functions in bootstrap draw order; rerun csdid before csdid_stats"
                exit `csdid_rc'
            }
            local boot_agg_if "`boot_agg_if_ordered'"
        }
        local boot_rng_arg ""
        capture confirm matrix e(boot_rng_state)
        if !_rc {
            matrix `boot_rng_state' = e(boot_rng_state)
            local boot_rng_arg "`boot_rng_state'"
        }
        else if "`e(boot_seed)'" != "" {
            mata: st_matrix("`boot_rng_state'", csdid__bmisc_rng_init(`e(boot_seed)'))
            local boot_rng_arg "`boot_rng_state'"
        }
        local agg_boot_accel "mata"
        local agg_boot_status "mata-unseeded"
        local agg_boot_rc 0
        local agg_plugin_success 0
        if "$CSDID_BOOT_PLUGIN_DISABLE" == "1" {
            local agg_boot_status "mata-plugin-disabled"
        }
        else if "`boot_rng_arg'" != "" & "`boot_dist'" == "rademacher" & ///
            "`e(bootstrap_accelerator)'" == "plugin" & "`type'" != "simple" {
            * F-004: type(simple) must NOT use the plugin. Its aggregate IF is
            * one column duplicated (effect == overall); R's aggte(simple) runs
            * a single mboot whose draws serve both, and the Mata kernels
            * replicate that via their simple_duplicate branch. The plugin
            * draws an independent second multiplier block for the overall
            * column, which R never draws, so its overall_se diverges from R.
            local agg_boot_status "mata-plugin-unavailable"
            local agg_plugin_bound 0
            capture quietly findfile csdid.ado
            if !_rc {
                local agg_csdid_path "`r(fn)'"
                local agg_plugin_file "`e(bootstrap_accelerator_file)'"
                local agg_plugin_path "`agg_csdid_path'"
                local agg_plugin_path : subinstr local agg_plugin_path ///
                    "csdid.ado" "`agg_plugin_file'", all
                capture confirm file "`agg_plugin_path'"
                if !_rc & ("$CSDID_AGG_BOOT_PLUGIN_PATH" == "" | ///
                    "$CSDID_AGG_BOOT_PLUGIN_PATH" == "`agg_plugin_path'") {
                    capture program __csdid_agg_boot_plugin, plugin using("`agg_plugin_path'")
                    local agg_bind_rc = _rc
                    if inlist(`agg_bind_rc', 0, 110) {
                        global CSDID_AGG_BOOT_PLUGIN_PATH "`agg_plugin_path'"
                        local agg_plugin_bound 1
                    }
                }
            }
            if `agg_plugin_bound' {
                tempname agg_plugin_independent agg_plugin_common agg_plugin_input ///
                    agg_plugin_n ///
                    agg_plugin_nc agg_plugin_cluster agg_plugin_started agg_rng_backup
                matrix `agg_rng_backup' = `boot_rng_state'
                local agg_plugin_rc 0
                local agg_plugin_k = colsof(`boot_agg_if')
                local agg_plugin_effects = `agg_plugin_k' - 1
                local agg_plugin_input_name "`boot_agg_if'"
                if `use_cluster' local agg_plugin_input_name "`agg_plugin_input'"
                if !`agg_plugin_rc' {
                    capture mata: csdid_agg_boot_plugin_prepare("`boot_agg_if'", "`boot_agg_cluster_vec'", "`agg_plugin_input_name'", "`agg_plugin_n'", "`agg_plugin_nc'", "`agg_plugin_cluster'", "`agg_plugin_started'")
                    local agg_plugin_rc = _rc
                }
                if !`agg_plugin_rc' {
                    capture matrix `agg_plugin_independent' = J(`biters', `agg_plugin_k', .)
                    if _rc local agg_plugin_rc = _rc
                    capture matrix `agg_plugin_common' = J(`biters', `agg_plugin_effects', .)
                    if _rc local agg_plugin_rc = _rc
                }
                if !`agg_plugin_rc' {
                    local agg_plugin_nc_value : display %21.0f scalar(`agg_plugin_nc')
                    local agg_plugin_nc_value = strtrim("`agg_plugin_nc_value'")
                    capture plugin call __csdid_agg_boot_plugin, bootstrap_agg ///
                        `biters' `agg_plugin_nc_value' `cband' ///
                        `agg_plugin_input_name' `agg_plugin_independent' ///
                        `agg_plugin_common' `boot_rng_state'
                    local agg_plugin_rc = _rc
                }
                if !`agg_plugin_rc' {
                    capture mata: csdid_agg_boot_plugin_finish("`aggte'", ///
                        "`agg_plugin_independent'", "`agg_plugin_common'", ///
                        st_numscalar("`agg_plugin_n'"), st_numscalar("`agg_plugin_nc'"), ///
                        st_numscalar("`agg_plugin_cluster'"), `biters', ///
                        (100 - `level') / 100, `cband', "`agg_plugin_started'", ///
                        "`boot_aggte'", "`agg_boot_draws'", "`agg_crit'", ///
                        "`agg_pointcrit'")
                    local agg_plugin_rc = _rc
                }
                if !`agg_plugin_rc' {
                    local agg_plugin_success 1
                    local agg_boot_accel "plugin"
                    local agg_boot_status "plugin-active"
                }
                else {
                    matrix `boot_rng_state' = `agg_rng_backup'
                    local agg_boot_status "mata-plugin-failed"
                    local agg_boot_rc = `agg_plugin_rc'
                }
            }
        }
        if !`agg_plugin_success' {
            * EUX-001: capture + re-raise so a bootstrap-kernel refusal
            * ("BMisc bootstrap RNG state is invalid", "stored aggregate
            * influence functions do not match aggregation results") cannot
            * drag Mata frames into the user's log.
            if `use_cluster' {
                capture mata: csdid_bootstrap_aggte_cluster("`aggte'", "`boot_agg_if'", "`boot_agg_cluster_vec'", `biters', (100 - `level') / 100, `cband', "`boot_dist'", "`boot_rng_arg'", "`boot_aggte'", "`agg_boot_draws'", "`agg_crit'", "`agg_pointcrit'")
            }
            else {
                capture mata: csdid_bootstrap_aggte("`aggte'", "`boot_agg_if'", `biters', (100 - `level') / 100, `cband', "`boot_dist'", "`boot_rng_arg'", "`boot_aggte'", "`agg_boot_draws'", "`agg_crit'", "`agg_pointcrit'")
            }
            local agg_boot_kernel_rc = _rc
            if `agg_boot_kernel_rc' {
                display as error `"csdid_stats could not bootstrap the type(`type') aggregation; rerun csdid before csdid_stats"'
                exit `agg_boot_kernel_rc'
            }
        }
        mata: st_matrix("`agg_bootstrap_profile'", CSDID_AGG_BOOT_PROFILE)
        matrix colnames `agg_bootstrap_profile' = seconds calls work
        matrix rownames `agg_bootstrap_profile' = setup multiplier_summary result_post
        matrix colnames `boot_aggte' = egt att se_boot crit_val ci_low ci_high point_crit_val point_ci_low point_ci_high overall_se
        ereturn matrix boot_aggte = `boot_aggte'
        ereturn matrix agg_boot_draws = `agg_boot_draws'
        ereturn matrix agg_bootstrap_profile = `agg_bootstrap_profile'
        ereturn scalar crit_val = `agg_crit'
        ereturn scalar point_crit_val = `agg_pointcrit'
        ereturn local agg_boot_accelerator "`agg_boot_accel'"
        ereturn local agg_boot_accel_status "`agg_boot_status'"
        ereturn scalar agg_boot_accel_rc = `agg_boot_rc'
    }
    matrix colnames `aggte' = egt att se overall_att overall_se
    * DS-11 (aggregation side). When every standard error in the aggregation is
    * missing, the table below prints a column of dots and says nothing about
    * why: the user is left to guess between "the kernel refused", "the data
    * are degenerate" and "csdid_stats is broken". The aggregation itself is
    * not an error - the ATTs are reported, and R behaves the same way - so
    * this stays a note and the rc stays 0; it just names the condition before
    * the table instead of leaving the dots unexplained. Only the all-missing
    * case is reported: a few missing SEs are ordinary and already visible
    * cell by cell.
    local n_se_missing 0
    local n_se_total = rowsof(`aggte')
    local overall_se_missing 0
    if `n_se_total' > 0 {
        forvalues i = 1/`n_se_total' {
            if missing(`aggte'[`i', 3]) local ++n_se_missing
        }
        local overall_se_missing = missing(`aggte'[1, 5])
    }
    if `n_se_total' > 0 & `n_se_missing' == `n_se_total' & `overall_se_missing' {
        display as text "note: every standard error in this type(`type') aggregation is missing. The ATT(g,t) estimates it aggregates have no usable standard errors, which usually means the influence functions are degenerate for these cells (a cohort with a single comparison unit, a perfectly collinear covariate design, or an outcome scale that overflows the variance). The point estimates below are still the aggregation of the ATT(g,t) estimates."
    }
    local n_aggte = rowsof(`aggte')
    ereturn matrix aggte = `aggte'
    * e(agg_inffunc) is posted under full storage only; under lean storage the
    * IF stays in the Mata cache (see the storage note above the aggregation
    * call). This also keeps _csdid_post_replace_bv from round-tripping an
    * n_units-row matrix through Stata's quadratic matrix layer on every
    * subsequent estat call.
    if `agg_store_large' {
        local if_cols = colsof(`agg_inffunc')
        local if_names ""
        forvalues j = 1/`if_cols' {
            if `j' == `if_cols' local if_names "`if_names' overall"
            else local if_names "`if_names' effect`j'"
        }
        matrix colnames `agg_inffunc' = `if_names'
        ereturn matrix agg_inffunc = `agg_inffunc'
    }
    ereturn local agg_type "`type'"
    ereturn local agg_clustervar "`agg_cluster'"
    ereturn scalar agg_cluster_fallback = `agg_cluster_fallback'
    ereturn scalar agg_level = `level'
    ereturn scalar N_aggte = `n_aggte'

    local display_noisy = c(noisily)
    if `display_noisy' Display, level(`level')
end

* EUX-001 helper. Reproduces csdid_aggte()'s own refusal diagnosis on the ado
* side so the kernel can be called under a plain -capture- (the only form that
* suppresses the Mata traceback log; -capture noisily- does not, measured in
* Stata 17). The probe reads only e(attgt), e(inffunc) and e(group_prob) -
* state csdid_aggte() has not modified at the point it refuses - and mirrors
* the kernel's wording and its check order. It never aborts: if the probe
* itself fails it is discarded and the caller falls back to a generic message,
* so a probe defect can never turn a working aggregation into a refusal.
program define _csdid_stats_aggfail
    version 14
    syntax , TYPE(string) MINE(string) MAXE(string) BALE(string) ///
        NARM(integer) USECACHE(integer)
    local msg ""
    capture mata: ///
        __csdid_pM = ""; ///
        __csdid_pA = st_matrix("e(attgt)"); ///
        if (rows(__csdid_pA) == 0) { ///
            __csdid_pM = "no ATT(g,t) results available for aggregation"; ///
        } ///
        if (rows(__csdid_pA) > 0) { ///
            if (`usecache' == 0) { ///
                __csdid_pIF = st_matrix("e(inffunc)"); ///
                if (cols(__csdid_pIF) != rows(__csdid_pA)) __csdid_pM = "stored influence functions do not match ATT(g,t) results"; ///
            } ///
            if (__csdid_pM == "") { ///
                if (sum(__csdid_pA[., 4] :>= .) > 0) { ///
                    if (`narm' == 0) __csdid_pM = "missing values found in ATT(g,t) estimates; specify dropmissing to drop them"; ///
                    if (`narm' != 0) { ///
                        __csdid_pA = select(__csdid_pA, __csdid_pA[., 4] :< .); ///
                        if (rows(__csdid_pA) == 0) __csdid_pM = "all ATT(g,t) estimates are missing; cannot aggregate"; ///
                    } ///
                } ///
            } ///
            if (__csdid_pM == "" & rows(__csdid_pA) > 0) { ///
                if ("`type'" == "simple") { ///
                    if (sum((__csdid_pA[., 1] :<= __csdid_pA[., 2]) :& (__csdid_pA[., 2] :<= __csdid_pA[., 1] :+ (`maxe'))) == 0) __csdid_pM = "no valid ATT(g,t) estimates found for simple aggregation"; ///
                } ///
                if ("`type'" == "group") { ///
                    __csdid_pG = st_matrix("e(group_prob)"); ///
                    if (rows(__csdid_pG) > 0) { ///
                        __csdid_pN = 0; ///
                        __csdid_pE = 0; ///
                        for (__csdid_pI = 1; __csdid_pI <= rows(__csdid_pG); __csdid_pI++) { ///
                            __csdid_pK = sum((__csdid_pA[., 1] :== __csdid_pG[__csdid_pI, 1]) :& (__csdid_pA[., 1] :<= __csdid_pA[., 2]) :& (__csdid_pA[., 2] :<= __csdid_pA[., 1] :+ (`maxe'))); ///
                            if (__csdid_pK == 0) __csdid_pE = 1; ///
                            if (__csdid_pK > 0) __csdid_pN = __csdid_pN + 1; ///
                        } ///
                        if (__csdid_pE == 1 & `narm' == 0) __csdid_pM = "no valid ATT(g,t) estimates found for group aggregation"; ///
                        if (__csdid_pN == 0) __csdid_pM = "no valid ATT(g,t) estimates found for group aggregation"; ///
                    } ///
                } ///
                if ("`type'" == "calendar") { ///
                    __csdid_pG = st_matrix("e(group_prob)"); ///
                    if (rows(__csdid_pG) > 0) { ///
                        __csdid_pT = uniqrows(__csdid_pA[., 2]); ///
                        __csdid_pT = select(__csdid_pT, __csdid_pT :>= min(__csdid_pG[., 1])); ///
                        __csdid_pN = 0; ///
                        for (__csdid_pI = 1; __csdid_pI <= rows(__csdid_pT); __csdid_pI++) { ///
                            if (sum((__csdid_pA[., 2] :== __csdid_pT[__csdid_pI]) :& (__csdid_pA[., 1] :<= __csdid_pA[., 2])) > 0) __csdid_pN = __csdid_pN + 1; ///
                        } ///
                        if (__csdid_pN == 0) __csdid_pM = "no calendar periods have valid post-treatment ATT(g,t) estimates"; ///
                    } ///
                } ///
                if ("`type'" == "dynamic") { ///
                    __csdid_pOK = 1; ///
                    __csdid_pMaxT = 0; ///
                    __csdid_pTF = 0; ///
                    __csdid_pInc = J(rows(__csdid_pA), 1, 1); ///
                    if ((`bale') >= 0) { ///
                        __csdid_pMaxT = max(__csdid_pA[., 2]); ///
                        __csdid_pInc = ((__csdid_pMaxT :- __csdid_pA[., 1]) :>= (`bale')); ///
                        __csdid_pTFm = st_numscalar("e(time_first)"); ///
                        if (rows(__csdid_pTFm) == 0) __csdid_pOK = 0; ///
                        if (__csdid_pOK == 1) { ///
                            __csdid_pTF = __csdid_pTFm[1, 1]; ///
                            if (__csdid_pTF >= .) __csdid_pOK = 0; ///
                        } ///
                        if (__csdid_pOK == 0) __csdid_pM = "e(time_first) not found; re-run csdid before using balance()"; ///
                    } ///
                    if (__csdid_pM == "" & sum(__csdid_pInc) == 0) __csdid_pM = "no event times fall within the requested aggregation window"; ///
                    if (__csdid_pM == "" & sum(__csdid_pInc) > 0) { ///
                        __csdid_pEg = uniqrows(select(__csdid_pA[., 3], __csdid_pInc :!= 0)); ///
                        if ((`bale') >= 0 & rows(__csdid_pEg) > 0) __csdid_pEg = select(__csdid_pEg, (__csdid_pEg :<= (`bale')) :& (__csdid_pEg :>= (`bale') - __csdid_pMaxT + __csdid_pTF)); ///
                        if (rows(__csdid_pEg) > 0) __csdid_pEg = select(__csdid_pEg, (__csdid_pEg :>= (`mine')) :& (__csdid_pEg :<= (`maxe'))); ///
                        if (rows(__csdid_pEg) == 0) __csdid_pM = "no event times fall within the requested aggregation window"; ///
                        if (rows(__csdid_pEg) > 0 & sum(__csdid_pEg :>= 0) == 0) __csdid_pM = "no post-treatment event times fall within the requested aggregation window"; ///
                    } ///
                } ///
            } ///
        } ///
        st_local("msg", __csdid_pM)
    if _rc local msg ""
    if `"`msg'"' == "" {
        local msg "csdid_stats could not compute the type(`type') aggregation from the stored ATT(g,t) results; check window()/balance()/dropmissing and the ATT(g,t) table"
    }
    display as error `"`msg'"'
end

program define Display
    version 14
    syntax [, Level(cilevel)]
    tempname out
    matrix `out' = e(aggte)
    display as text _newline "Aggregated treatment effects"
    matlist `out', names(columns) format(%10.6g)
end

program define _csdid_stats_load_rif, eclass
    version 14
    syntax using/

    tempname IF UG ATT GP
    preserve
    use `"`using'"', clear
    if "`: char _dta[csdid_artifact]'" != "rif" {
        display as error "saved file is not a csdid RIF artifact"
        exit 498
    }
    * SP-12: the artifact-contract checks either side of these two are specific
    * and rc 498 ("saved file is not a csdid RIF artifact", "... does not
    * contain rif# columns", "... is missing ATT metadata for rif3"). These two
    * were bare `confirm variable's, so a RIF file whose id or group column had
    * been dropped or renamed - the commonest way an artifact gets damaged in a
    * user's workflow - answered with Stata's stock r(111) "variable id not
    * found", which names no file, no artifact and no remedy. Same class of
    * diagnosis, same rc, as its siblings.
    capture confirm variable id
    if _rc {
        display as error "saved RIF artifact is missing its id column; the file in using() was written by csdid but has been modified since, or is not the file that was saved"
        exit 498
    }
    capture confirm variable group
    if _rc {
        display as error "saved RIF artifact is missing its group column; the file in using() was written by csdid but has been modified since, or is not the file that was saved"
        exit 498
    }
    * SP-12: -unab- with no match aborts r(111) on its own, before the
    * nrif == 0 branch below could report anything, so the guard was
    * unreachable for exactly the artifact it was written for.
    capture unab allrif : rif*
    if _rc local allrif ""
    local rifvars ""
    foreach v of local allrif {
        if "`v'" != "rif_row" local rifvars "`rifvars' `v'"
    }
    local nrif : word count `rifvars'
    if `nrif' == 0 {
        display as error "saved RIF artifact does not contain rif# columns"
        exit 498
    }

    mkmat `rifvars', matrix(`IF')
    capture confirm variable weight
    if _rc {
        mkmat id group, matrix(`UG')
        matrix `UG' = `UG', J(rowsof(`UG'), 1, 1)
        generate double _csdid_rif_weight = 1
    }
    else {
        mkmat id group weight, matrix(`UG')
        generate double _csdid_rif_weight = weight
    }
    matrix `ATT' = J(`nrif', 9, .)

    local treated_groups ""
    forvalues j = 1/`nrif' {
        local rv : word `j' of `rifvars'
        local meta : char `rv'[csdid_attgt]
        if `"`meta'"' == "" {
            display as error "saved RIF artifact is missing ATT metadata for `rv'"
            exit 498
        }
        forvalues c = 1/9 {
            local val : word `c' of `meta'
            matrix `ATT'[`j', `c'] = `val'
        }
        local g : word 1 of `meta'
        local found : list g in treated_groups
        if !`found' local treated_groups "`treated_groups' `g'"
    }

    quietly count
    local n_rows = r(N)
    local n_groups : word count `treated_groups'
    matrix `GP' = J(`n_groups', 3, .)
    local i = 1
    foreach g of local treated_groups {
        quietly summarize _csdid_rif_weight if group == `g', meanonly
        local g_weight = r(sum)
        matrix `GP'[`i', 1] = `g'
        matrix `GP'[`i', 2] = `g_weight' / `n_rows'
        matrix `GP'[`i', 3] = `n_rows'
        local ++i
    }

    local panel_mode "`: char _dta[csdid_panel_mode]'"
    local control_group "`: char _dta[csdid_control_group]'"
    local base_period "`: char _dta[csdid_base_period]'"
    local method "`: char _dta[csdid_method]'"
    local cmdline "`: char _dta[csdid_cmdline]'"
    local N "`: char _dta[csdid_N]'"
    local N_units "`: char _dta[csdid_N_units]'"
    local N_time "`: char _dta[csdid_N_time]'"
    local anticipation "`: char _dta[csdid_anticipation]'"
    local level "`: char _dta[csdid_level]'"
    * F-009: restore the panel's first period so balance_e() works off a saved
    * RIF. Absent on artifacts written before this char existed; the Mata guard
    * then refuses cleanly with rc 498 rather than aborting.
    local time_first "`: char _dta[csdid_time_first]'"
    restore

    matrix colnames `ATT' = group time event_time att se n_treat_t n_treat_pre n_control_t n_control_pre
    matrix colnames `GP' = group prob n_units
    matrix colnames `UG' = id group weight
    matrix colnames `IF' = `rifvars'

    ereturn clear
    ereturn matrix attgt = `ATT'
    ereturn matrix inffunc = `IF'
    ereturn matrix group_prob = `GP'
    ereturn matrix unit_group = `UG'
    ereturn local cmd "csdid"
    ereturn local estat_cmd "csdid_estat"
    ereturn local rif_file `"`using'"'
    ereturn local cmdline `"`cmdline'"'
    ereturn local version "2.0.0"
    ereturn local panel_mode "`panel_mode'"
    ereturn local control_group "`control_group'"
    ereturn local method "`method'"
    ereturn local base_period "`base_period'"
    ereturn scalar N = real("`N'")
    ereturn scalar N_units = real("`N_units'")
    ereturn scalar N_attgt = `nrif'
    ereturn scalar N_groups = `n_groups'
    ereturn scalar N_time = real("`N_time'")
    ereturn scalar anticipation = real("`anticipation'")
    ereturn scalar level = real("`level'")
    * F-009: only post when the artifact carried it, so older RIFs still hit the
    * clean "re-run csdid before using balance_e" refusal.
    if "`time_first'" != "" & !missing(real("`time_first'")) {
        ereturn scalar time_first = real("`time_first'")
    }
end
