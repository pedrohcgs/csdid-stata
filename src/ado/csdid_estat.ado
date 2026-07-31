*! csdid_estat 2.0.0 30jul2026
program define csdid_estat, eclass
    version 14
    if "`e(cmd)'" != "csdid" {
        display as error "csdid_estat requires prior csdid results"
        exit 301
    }
    * HS-04 fix: fall through to Stata's estat_default for the STANDARD estat
    * subcommands csdid does not implement itself (vce, summarize, ic,
    * bootstrap). Before this, `estat vce' after csdid printed csdid's own
    * subcommand menu and returned 498, even though e(V) is posted and the
    * report is free; didregress_estat.ado:56 is StataCorp's precedent for
    * forwarding the remainder to estat_default. The subcommand is peeked at
    * BEFORE the option parser runs so estat_default receives its OWN options
    * (e.g. `estat vce, format(%9.4f)'), which csdid_estat's catch-all would
    * otherwise reject as "unsupported option(s)". Only estat_default's own
    * key set is forwarded, so a genuinely unknown subcommand still gets
    * csdid's named refusal rather than Stata's generic r(321).
    gettoken csdid_peek : 0, parse(" ,")
    local csdid_peek = lower(strtrim(`"`csdid_peek'"'))
    local csdid_peek_n = length("`csdid_peek'")
    if !inlist("`csdid_peek'", "attgt", "event", "dynamic", "simple", "group") & ///
       !inlist("`csdid_peek'", "calendar", "tidy", "glance", "", ",") {
        if "`csdid_peek'" == "ic" | "`csdid_peek'" == "vce" | ///
           "`csdid_peek'" == substr("summarize", 1, max(2, `csdid_peek_n')) | ///
           "`csdid_peek'" == substr("bootstrap", 1, max(4, `csdid_peek_n')) {
            estat_default `0'
            exit
        }
    }
    * OPT-007 fix: dropmissing is DECLARED and forwarded to csdid_stats on
    * every aggregation route. It used to be absent here, so the documented
    * guarantee (csdid_stats.sthlp: aggregation refuses on missing ATT(g,t)
    * cells unless dropmissing is given) had no route through estat at all -
    * `estat dynamic, dropmissing' died with "unsupported option(s)" while
    * `estat event' silently hardcoded the opposite.
    syntax [anything(name=subcmd)] [, SAVing(string) REPLACE WINDOW(string) ///
        POST Level(cilevel) DROPMissing FROM(string) *]
    local subcmd = lower(strtrim(`"`subcmd'"'))
    * from() is unsupported by design; legacy accepted it on estat simple, group
    * and calendar. Refused BEFORE the leftover-options block so that a repeated
    * from() also gets this explanation rather than "specified more than once" -
    * the option is unsupported either way - and so _csdid_estat_optdup, which
    * must mirror only the SUPPORTED declarations, needs no change.
    if `"`from'"' != "" {
        display as error "from() is no longer supported; it set a lower event-time bound on the simple, group and calendar aggregations, which R fixes at event time 0. Use window(# #) on estat event for event-time windows."
        exit 198
    }
    if `"`options'"' != "" {
        * EUX-010/EUX-013/EUX-014: -syntax- hands a REPEATED declared option to
        * the `*' catch-all (measured: `window(-1 1) window(0 1)' leaves
        * "window(0 1)" in `options'), so `estat event, window(-1 1) window(0 1)'
        * used to be refused as an "unsupported option" even though window() is
        * one of this command's own options - the user is told to remove a
        * supported option instead of being told they typed it twice. Lead with
        * the real fault, as csdid_stats already does for its own duplicated
        * options, and echo what was typed; a genuinely unknown option still
        * gets the generic text (the F036 contract pins the exact string
        * "unsupported option(s): style(foo)").
        * The test is delegated to a second -syntax- over the leftover with the
        * SAME option declarations and no `*': if Stata can parse it, every
        * leftover option is one of this command's own and the only way it got
        * here is repetition. Delegating also means abbreviations
        * (`level(90) lev(80)', `dropm dropm') and blanks inside parentheses
        * (`window( 0 1 )') are matched by Stata's own rules rather than by a
        * hand-written table that would drift from the syntax line above.
        capture _csdid_estat_optdup, `options'
        if !_rc {
            display as error `"option(s) specified more than once: `options'"'
            exit 198
        }
        * D-1: compound quotes. A quoted option VALUE (e.g.
        * title("Cohort 2004")) puts a double quote inside `options', and the
        * plain-quoted display then breaks the string, producing a garbled
        * message and r(111) instead of the documented r(198).
        display as error `"unsupported option(s): `options'"'
        exit 198
    }
    * EUX-015 fix: a bare `csdid_estat' used to fall out of `syntax' with
    * Stata's stock r(100) "argument required" and no hint about what to type,
    * while the informative subcommand list sat one branch away at the bottom
    * of this program. Name the subcommands instead.
    if `"`subcmd'"' == `""' {
        display as error "csdid_estat requires a subcommand; supported subcommands are attgt, event, dynamic, simple, group, calendar, tidy, and glance"
        exit 198
    }
    if `"`subcmd'"' == `"attgt"' {
        * attgt redisplays the stored ATT(g,t) table, and with saving() writes
        * that same table out as a dataset. saving() is how Stata spells "put
        * this in a file" -- margins, simulate and graph all take it -- so it is
        * an option on the thing being computed rather than a separate export
        * command.
        *
        * The rest stay refused. They were PARSED at the syntax line above and
        * then silently discarded, so `estat attgt, post' returned rc 0 while
        * doing nothing the user asked for.
        local attgt_bad ""
        if "`post'" != "" local attgt_bad "`attgt_bad' post"
        if `"`window'"' != "" local attgt_bad "`attgt_bad' window()"
        if `level' != c(level) local attgt_bad "`attgt_bad' level()"
        if "`dropmissing'" != "" local attgt_bad "`attgt_bad' dropmissing"
        if "`attgt_bad'" != "" {
            display as error "estat attgt accepts only saving() and replace; not allowed:`attgt_bad'"
            exit 198
        }
        if `"`saving'"' != "" {
            _csdid_estat_tidy_attgt using `"`saving'"', `replace'
            exit
        }
        matlist e(attgt), names(columns) format(%10.6g)
        exit
    }
    if inlist(`"`subcmd'"', "event", "dynamic", "simple", "group", "calendar") {
        * F-047 fix: the window is FORWARDED to csdid_stats, whose windowing
        * is the R-parity-verified path, instead of being re-applied to an
        * unwindowed e(aggte). Consequences, each a former defect:
        *   - Post_avg IS the windowed overall (was: lifted unwindowed from
        *     A[1,4], wrong by up to 117% on mpdta);
        *   - empty / all-pre windows REFUSE exactly as csdid_stats and R do
        *     (was: rc 0 with a fabricated or fallback display);
        *   - no zero-variance coefficients are fabricated for event times
        *     that do not exist (the includeomit grid is gone, F-047 defect 2);
        *   - the auto-compute runs quietly (was: dumped the full ATT(g,t)
        *     table above the asked result, F-047 defect 4).
        * F-044: level() is forwarded too, so the aggregation bands at the
        * requested level instead of the session default.
        * SP-01/SP-02/OPT-006/OPT-016 fix (P0). The aggregation is now ALWAYS
        * recomputed, exactly as the dynamic/simple/group/calendar routes below
        * already did. The old guard
        *     need_recompute = (no e(aggte)) | (agg_type != dynamic) | (window given)
        * reused whatever dynamic aggregation happened to be lying in e(),
        * which had three separately measured consequences, all silent and all
        * rc 0:
        *   - SP-01: `estat event, level(90)' followed by `estat event,
        *     level(99)' returned the 90% bootstrap band (crit 2.2777391) for
        *     the 99% request; a fresh estimation at level(99) gives 2.8658043.
        *     The help's rationale for this - "a bootstrap band cannot be
        *     re-levelled" - is false: csdid_stats re-levels by recomputing off
        *     the SAME stored multiplier state e(boot_rng_state), which is why
        *     `csdid_stats, type(dynamic) level(99)' already returned
        *     2.8658043 from the identical session.
        *   - SP-02/OPT-016: e(agg_level) kept the STALE aggregation's level
        *     while r(table) carried the requested one, so r(table), `estat
        *     tidy' (which reads e(agg_level)) and csdid_plot reported three
        *     different intervals for one displayed result.
        *   - OPT-006: after `csdid_stats, window(0 0)', `estat event' replayed
        *     the windowed aggregation (N_aggte=1) while `estat dynamic'
        *     recomputed the full one (N_aggte=7). csdid_stats does not store
        *     the window it used, so a stale window is not detectable from e();
        *     recomputing unconditionally is the only way `estat event' and
        *     `estat dynamic' can be guaranteed to agree.
        * Recomputation is exactly reproducible, including under wboot: the
        * multiplier draws come from e(boot_rng_state) (or e(boot_seed)),
        * both of which csdid posts at estimation time and
        * _csdid_post_replace_bv preserves, so repeated aggregations of the
        * same estimation are bit-identical (measured). The cost is one extra
        * aggregation, the same cost the other four routes already pay.
        *
        * SP-07 fix. The dynamic/simple/group/calendar routes used to share
        * everything with `event' EXCEPT the posting step: without `post' they
        * ran the aggregation and went straight to `matlist e(aggte)', so
        * _csdid_post never ran and r(table) was never built. Measured
        * consequence: csdid_estat.sthlp:410-415 promises r(table) for
        * "estat event and estat aggregation", but after a non-post
        * `estat dynamic/simple/group/calendar' r(table) either did not exist
        * or - worse - still held the table of an EARLIER aggregation, which
        * reads as this one's. The two branches are therefore merged here: one
        * route computes the aggregation, posts it (which is what fills
        * r(table)), and, when `post' was not asked for, restores the previous
        * e(b)/e(V) exactly as the event route already did. `event' still
        * displays the posted coefficient vector and the aggregation routes
        * still display e(aggte), so no displayed table changes.
        * The r() reset below closes the stale half: if this aggregation fails
        * or posts nothing, the previous aggregation's r(table) must not be
        * left standing as if it belonged to the command the user just typed.
        * Carried over from the branch this merge absorbed:
        *   F-044: level() forwarded (was parsed and dropped - no estat route
        *   could produce a non-default band);
        *   F-045: post forwarded (was parsed and dropped - e(b) silently kept
        *   the ATT(g,t) vector, so a following test/lincom tested the wrong
        *   quantity at rc=0);
        *   OPT-007: dropmissing forwarded, so the documented missing-cell
        *   guarantee has the same meaning on every estat route.
        local agg_type "`subcmd'"
        if "`agg_type'" == "event" local agg_type "dynamic"
        local stat_opts "type(`agg_type') level(`level')"
        if "`dropmissing'" != "" local stat_opts "`stat_opts' dropmissing"
        if "`window'" != "" local stat_opts `"`stat_opts' window(`window')"'
        _csdid_estat_rclear
        quietly csdid_stats, `stat_opts'
        tempname show_b
        * No-transit (supersedes the snapshot/restore machinery, including the
        * SP-08 generic e() snapshot): without `post', _csdid_post no longer
        * touches e(b)/e(V) at all - it builds r(table) directly from the
        * aggregation's B/V - so there is nothing to snapshot and nothing to
        * restore. The old post-then-restore cycle rebuilt e() wholesale twice
        * per estat, Stata-copying every stored matrix; under full storage
        * that includes the one-row-per-unit influence functions, and Stata's
        * classic-matrix layer is quadratic in the longest dimension, so a
        * plain `estat event' after a 20,000-unit estimation spent ~19s
        * copying matrices it did not change. SP-08's failure mode (a
        * transient posting left behind on the saved-RIF path) cannot occur
        * when no transient posting exists.
        * F-047: windowing happened upstream in csdid_stats, so the poster no
        * longer receives (or fabricates) window bounds.
        * F-045/SP-07: `event' keeps the historical Tm#/Tp#/Post_avg names
        * through the eventnames branch of _csdid_post_aggte; the other four
        * types get the naming their own aggregation implies (G#, T#, ATT,
        * Overall). Both entry points build r(table).
        if `"`subcmd'"' == `"event"' {
            _csdid_post event, level(`level') `post'
        }
        else {
            _csdid_post aggte, level(`level') `post'
        }
        if "`post'" == "" {
            * SP-07: only `event' displays the coefficient vector; the
            * aggregation routes display e(aggte). Without `post' nothing was
            * posted, so the display vector comes from r(table) row 1 - the
            * same values, with the same column names, the posting path would
            * have put in e(b). The guard matters because _csdid_post returns
            * no table when the aggregation produced no usable coefficient
            * (every att missing).
            local have_show 0
            capture matrix `show_b' = r(table)
            if !_rc {
                matrix `show_b' = `show_b'[1, 1...]
                local have_show 1
            }
            if `"`subcmd'"' == `"event"' {
                if `have_show' matlist `show_b', names(columns) format(%10.6g)
            }
            else {
                matlist e(aggte), names(columns) format(%10.6g)
            }
        }
        * saving() was parsed at the syntax line and then ignored here, so
        * `estat event, saving(f)' returned rc 0 and wrote no file. It now
        * writes the aggregation that was just computed -- the same file
        * `estat tidy, saving(f)' writes if run immediately afterwards.
        if `"`saving'"' != "" {
            _csdid_estat_tidy_aggte using `"`saving'"', `replace'
        }
        exit
    }
    if inlist(`"`subcmd'"', "tidy", "glance") & "`dropmissing'" != "" {
        * OPT-007: tidy/glance export whatever aggregation already exists and
        * never call csdid_stats, so dropmissing has nothing to act on here.
        * Refusing beats accepting-then-ignoring the option this release just
        * added.
        display as error `"estat `subcmd' does not accept dropmissing; specify it on the aggregation (e.g. estat dynamic, dropmissing) before exporting"'
        exit 198
    }
    if `"`subcmd'"' == `"tidy"' {
        if `"`saving'"' == "" {
            display as error "tidy requires saving(filename)"
            exit 198
        }
        capture confirm matrix e(aggte)
        if _rc {
            _csdid_estat_tidy_attgt using `"`saving'"', `replace'
        }
        else {
            _csdid_estat_tidy_aggte using `"`saving'"', `replace'
        }
        exit
    }
    if `"`subcmd'"' == `"glance"' {
        if `"`saving'"' == "" {
            display as error "glance requires saving(filename)"
            exit 198
        }
        capture confirm matrix e(aggte)
        if _rc {
            _csdid_estat_glance_attgt using `"`saving'"', `replace'
        }
        else {
            _csdid_estat_glance_aggte using `"`saving'"', `replace'
        }
        exit
    }
    * EUX-006 note: Stata's own class for this is r(321) ("estat zzz not valid"
    * after regress, measured), but rc 498 here is pinned by the frozen
    * test-f051 contract; changing the class would fail that test. Flagged to
    * the owner rather than changed - see the EUX-006 entry in the handover.
    display as error `"csdid_estat subcommand `subcmd' is not supported; supported subcommands are attgt, event, dynamic, simple, group, calendar, tidy, and glance"'
    exit 498
end

* EUX-010/EUX-013 helper. Declares exactly the options csdid_estat declares,
* minus the `*' catch-all, so a -capture- call over the LEFTOVER options tells
* the caller whether every leftover is one of csdid_estat's own (i.e. it was
* typed twice) or whether at least one is genuinely unknown. Keeping the two
* declaration lists side by side is the point: Stata does the abbreviation and
* whitespace matching, so this cannot drift into accepting a spelling the real
* syntax line rejects.
program define _csdid_estat_optdup
    version 14
    syntax [, SAVing(string) REPLACE WINDOW(string) POST Level(cilevel) DROPMissing]
end

* SP-07 helper. An rclass program replaces r() wholesale on exit, so calling
* this one with nothing to return is the supported way to drop a previous
* aggregation's r(table) before a new aggregation runs (measured: r(table) is
* gone afterwards, rc 111). Without it a failed or empty aggregation would
* leave the PREVIOUS aggregation's r(table) in place, and it would read as the
* result of the command the user just typed.
program define _csdid_estat_rclear, rclass
    version 14
end

program define _csdid_estat_tidy_attgt
    version 14
    syntax using/ [, REPLACE]

    * EUX-003/SP-06 fix: the whole scratch-data block runs -quietly-. On the
    * happy path of every export it used to print "number of observations will
    * be reset to ...", "(file ... not found)", the eleven "(1 real change
    * made)" notes, and - whenever the user has `set more on' - the blocking
    * "Press any key to continue, or Break to abort" prompt, none of which the
    * user asked for and none of which is about their results. csdid_plot's
    * export block was wrapped this way already; these four were the two files'
    * shared dependency that neither owner wrapped. -quietly- suppresses text
    * and result output but NOT `display as error' (measured), so the refusals
    * inside stay visible.
    quietly {
        tempname A
        matrix `A' = e(attgt)
        preserve
        clear
        svmat double `A', names(col)
        generate str40 term = "ATT(" + strtrim(strofreal(group, "%21.0g")) + "," + strtrim(strofreal(time, "%21.0g")) + ")"
        rename att estimate
        rename se std_error
        generate double statistic = estimate / std_error
        generate double p_value = 2 * normal(-abs(statistic))
        local crit = e(crit_val)
        local z = e(point_crit_val)
        generate double conf_low = estimate - `crit' * std_error
        generate double conf_high = estimate + `crit' * std_error
        generate double point_conf_low = estimate - `z' * std_error
        generate double point_conf_high = estimate + `z' * std_error
        label variable std_error "std.error"
        label variable p_value "p.value"
        label variable conf_low "conf.low"
        label variable conf_high "conf.high"
        label variable point_conf_low "point.conf.low"
        label variable point_conf_high "point.conf.high"
        keep term group time estimate std_error statistic p_value conf_low conf_high point_conf_low point_conf_high
        order term group time estimate std_error statistic p_value conf_low conf_high point_conf_low point_conf_high
        save `"`using'"', `replace'
        restore
    }
end

program define _csdid_estat_glance_attgt
    version 14
    syntax using/ [, REPLACE]

    * EUX-003/SP-06 fix: see _csdid_estat_tidy_attgt - the export block runs
    * -quietly- so the scratch-data chatter and the "Press any key" prompt do
    * not fire on the happy path. `display as error' still reaches the user.
    quietly {
        preserve
        clear
        set obs 1
        generate double nobs = e(N_units)
        generate double ngroup = e(N_groups)
        generate double ntime = e(N_time)
        generate str32 control_group = "`e(control_group)'"
        generate str32 est_method = "`e(method)'"
        label variable control_group "control.group"
        label variable est_method "est.method"
        save `"`using'"', `replace'
        restore
    }
end

program define _csdid_estat_tidy_aggte
    version 14
    syntax using/ [, REPLACE]

    * EUX-003/SP-06 fix: see _csdid_estat_tidy_attgt - the export block runs
    * -quietly- so the scratch-data chatter and the "Press any key" prompt do
    * not fire on the happy path. `display as error' still reaches the user.
    quietly {
        tempname A
        matrix `A' = e(aggte)
        preserve
        clear
        svmat double `A', names(col)
        generate str16 type = "`e(agg_type)'"
        capture confirm scalar e(agg_level)
        if _rc local agg_level = e(level)
        else local agg_level = e(agg_level)
        local crit = invnormal(1 - (100 - `agg_level') / 200)
        local z = `crit'
        capture confirm scalar e(bstrap)
        if !_rc & e(bstrap) {
            local crit = e(crit_val)
            local z = e(point_crit_val)
        }

        if "`e(agg_type)'" == "simple" {
            generate str40 term = "ATT(simple average)"
            rename att estimate
            rename se std_error
            generate double statistic = estimate / std_error
            generate double p_value = 2 * normal(-abs(statistic))
            generate double conf_low = estimate - `crit' * std_error
            generate double conf_high = estimate + `crit' * std_error
            generate double point_conf_low = estimate - `z' * std_error
            generate double point_conf_high = estimate + `z' * std_error
            keep type term estimate std_error statistic p_value conf_low conf_high point_conf_low point_conf_high
            order type term estimate std_error statistic p_value conf_low conf_high point_conf_low point_conf_high
        }
        else if "`e(agg_type)'" == "dynamic" {
            generate double event_time = egt
            generate str40 term = "ATT(" + strtrim(strofreal(event_time, "%21.0g")) + ")"
            rename att estimate
            rename se std_error
            generate double statistic = estimate / std_error
            generate double p_value = 2 * normal(-abs(statistic))
            generate double conf_low = estimate - `crit' * std_error
            generate double conf_high = estimate + `crit' * std_error
            generate double point_conf_low = estimate - `z' * std_error
            generate double point_conf_high = estimate + `z' * std_error
            keep type term event_time estimate std_error statistic p_value conf_low conf_high point_conf_low point_conf_high
            order type term event_time estimate std_error statistic p_value conf_low conf_high point_conf_low point_conf_high
        }
        else if "`e(agg_type)'" == "calendar" {
            generate double time = egt
            generate str40 term = "ATT(" + strtrim(strofreal(time, "%21.0g")) + ")"
            rename att estimate
            rename se std_error
            generate double statistic = estimate / std_error
            generate double p_value = 2 * normal(-abs(statistic))
            generate double conf_low = estimate - `crit' * std_error
            generate double conf_high = estimate + `crit' * std_error
            generate double point_conf_low = estimate - `z' * std_error
            generate double point_conf_high = estimate + `z' * std_error
            keep type term time estimate std_error statistic p_value conf_low conf_high point_conf_low point_conf_high
            order type term time estimate std_error statistic p_value conf_low conf_high point_conf_low point_conf_high
        }
        else if "`e(agg_type)'" == "group" {
            generate str40 term = "ATT(" + strtrim(strofreal(egt, "%21.0g")) + ")"
            generate str40 group = strtrim(strofreal(egt, "%21.0g"))
            rename att estimate
            rename se std_error
            generate double statistic = estimate / std_error
            generate double p_value = 2 * normal(-abs(statistic))
            generate double conf_low = estimate - `crit' * std_error
            generate double conf_high = estimate + `crit' * std_error
            generate double point_conf_low = estimate - `z' * std_error
            generate double point_conf_high = estimate + `z' * std_error
            set obs `=_N + 1'
            replace type = "`e(agg_type)'" in L
            replace term = "ATT(Average)" in L
            replace group = "Average" in L
            replace estimate = overall_att[1] in L
            replace std_error = overall_se[1] in L
            replace statistic = estimate / std_error in L
            replace p_value = 2 * normal(-abs(statistic)) in L
            replace conf_low = estimate - `crit' * std_error in L
            replace conf_high = estimate + `crit' * std_error in L
            replace point_conf_low = estimate - `z' * std_error in L
            replace point_conf_high = estimate + `z' * std_error in L
            generate byte _csdid_order = cond(group == "Average", 0, 1)
            sort _csdid_order egt
            keep type term group estimate std_error statistic p_value conf_low conf_high point_conf_low point_conf_high
            order type term group estimate std_error statistic p_value conf_low conf_high point_conf_low point_conf_high
        }
        else {
            display as error "tidy aggregation export is not implemented for type(`e(agg_type)')"
            exit 498
        }

        label variable std_error "std.error"
        label variable p_value "p.value"
        label variable conf_low "conf.low"
        label variable conf_high "conf.high"
        label variable point_conf_low "point.conf.low"
        label variable point_conf_high "point.conf.high"
        save `"`using'"', `replace'
        restore
    }
end

program define _csdid_estat_glance_aggte
    version 14
    syntax using/ [, REPLACE]

    * EUX-003/SP-06 fix: see _csdid_estat_tidy_attgt - the export block runs
    * -quietly- so the scratch-data chatter and the "Press any key" prompt do
    * not fire on the happy path. `display as error' still reaches the user.
    quietly {
        preserve
        clear
        set obs 1
        generate str16 type = "`e(agg_type)'"
        generate double nobs = e(N_units)
        generate double ngroup = e(N_groups)
        generate double ntime = e(N_time)
        generate str32 control_group = "`e(control_group)'"
        generate str32 est_method = "`e(method)'"
        label variable control_group "control.group"
        label variable est_method "est.method"
        save `"`using'"', `replace'
        restore
    }
end
