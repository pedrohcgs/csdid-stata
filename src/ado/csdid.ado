*! csdid 2.0.0 28aug2026
program define csdid, eclass sortpreserve
    local csdid_zero_entry `"`0'"'
    * this guard used to sit BELOW `version 14', where it
    * could never fire - on Stata 13 the `version 14' statement itself aborts
    * first with Stata's own generic message. Hoisting it above `version 14'
    * makes it reachable; the guard itself uses only c() and `display', both of
    * which are version-independent, so nothing else changes for Stata >= 14.
    if c(stata_version) < 14 {
        display as error "csdid requires Stata 14 or newer (this is Stata `c(stata_version)')"
        exit 9
    }
    version 14

    if `"`0'"' == "version" {
        display as text "csdid version 2.0.0"
        * A diagnostic, and ONLY a diagnostic: no e() (the help guarantees
        * it, and an e(cmd) stub posted here once let csdid_estat print a
        * fabricated table in a session that had estimated nothing), and no
        * engine load (the loader has session side effects a version query
        * must not trigger). It reports what the session already knows: the
        * copy of csdid that answers, the engine the session decided on, and
        * the accelerator binding -- the three facts that decide which code
        * produced a number, and the three that adopath shadowing changes.
        capture quietly findfile csdid.ado
        if !_rc display as text `"  csdid.ado resolved to: `r(fn)'"'
        local vmarker `"$CSDID_ENGINE_RESOLVED"'
        if `"`vmarker'"' != "" {
            local vsemi = strpos(`"`vmarker'"', ";")
            if `vsemi' > 1 {
                local vstamp = substr(`"`vmarker'"', 1, `vsemi' - 1)
                local vbar = strpos("`vstamp'", "|")
                local vwho = substr("`vstamp'", `vbar' + 1, .)
                if "`vwho'" == "source" {
                    display as text "  engine: compiled from csdid.mata by this session"
                }
                else {
                    display as text "  engine: precompiled library, built by Stata `vwho'"
                }
            }
        }
        else {
            display as text "  engine: not loaded yet (loads on the first estimation of a session)"
        }
        if `"$CSDID_BOOT_PLUGIN_PATH"' != "" {
            display as text `"  bootstrap accelerator: bound to $CSDID_BOOT_PLUGIN_PATH"'
        }
        display as text `"  (a stray older csdid can shadow this one: {stata which csdid, all} lists every copy on the adopath)"'
        exit
    }
    if `"`0'"' == "reset" {
        * Forget every session-level csdid decision: the engine choice, the
        * plugin bindings, and the estimation cache. The next csdid command
        * re-decides from the current adopath. This is the way out of a stale
        * engine decision short of `macro drop _all', which also destroys the
        * user's own globals -- and it is what makes a re-installed csdid
        * usable in a live session.
        capture program drop __csdid_bootstrap_plugin
        capture program drop __csdid_agg_boot_plugin
        capture macro drop CSDID_*
        capture mata: mata drop CSDID_*
        display as text "csdid reset: the engine decision, plugin bindings and estimation cache are cleared; the next csdid command re-decides from the current adopath."
        display as text "(a plugin binary replaced at the SAME path may still be served from memory by the operating system; restart Stata to be certain a re-installed accelerator is the one that runs)"
        exit
    }
    * Replay: a bare `csdid' (or `csdid, level()') after estimation redisplays
    * the results, as every official estimation command does, and `estimates
    * replay' lands here too. level() cannot CHANGE on replay: the CI columns
    * in e(attgt) and the bootstrap band critical values were computed at the
    * estimation's level, and a redisplay that relabelled them would print a
    * band it does not hold -- so a different level() names the re-run that
    * computes it instead.
    if replay() {
        if `"`e(cmd)'"' != "csdid" error 301
        capture confirm matrix e(attgt)
        if _rc | e(level) >= . {
            display as error "the stored csdid results cannot be redisplayed here (no ATT(g,t) table or confidence level is stored); use csdid_stats or csdid_estat on them instead"
            exit 498
        }
        syntax [, Level(passthru)]
        local replay_level = strofreal(e(level), "%12.0g")
        if `"`level'"' != "" {
            local 0 `", `level'"'
            syntax [, Level(cilevel)]
            if `level' != e(level) {
                display as error "level() cannot be changed when replaying csdid results: the confidence bands in the stored results were computed at the `=e(level)'% level at estimation time. Re-run csdid with level(`level') to compute them at that level."
                exit 198
            }
            local replay_level `level'
        }
        Display, level(`replay_level')
        exit
    }
    local cmdline `"csdid `0'"'
    local raw_call `"`0'"'
    * `nofast' cannot be recovered from `syntax' - declaring
    * FAST and NOFAST together makes Stata treat a typed `nofast' as the
    * negation of FAST, so BOTH locals come back empty - hence this raw-string
    * scan. The old scan searched the whole text after the first comma, so it
    * fired on `wboot(reps(5) nofast rseed(1))' and on
    * `saverif("a nofast b.dta")', silently switching the compute path off.
    * Scope it to genuine top-level option text: blank out every quoted string
    * and then every parenthesised group (innermost outwards) BEFORE locating
    * the option-introducing comma, so neither sub-option text nor filename text
    * can reach the match. Each pass strictly shortens the string, so both
    * loops terminate.
    local nofast_raw = 0
    local opt_skeleton = lower(`"`raw_call'"')
    while regexm(`"`opt_skeleton'"', `""[^"]*""') {
        local opt_skeleton = regexr(`"`opt_skeleton'"', `""[^"]*""', " ")
    }
    while regexm(`"`opt_skeleton'"', "\([^()]*\)") {
        local opt_skeleton = regexr(`"`opt_skeleton'"', "\([^()]*\)", " ")
    }
    local comma_pos = strpos(`"`opt_skeleton'"', ",")
    if `comma_pos' > 0 {
        local raw_options = substr(`"`opt_skeleton'"', `comma_pos' + 1, .)
        local nofast_raw = regexm(`"`raw_options'"', "(^|[ ,])nofast([ ,]|$)")
    }

    syntax varlist(fv min=1) [if] [in] [iw], ///
        TIME(varname) ///
        GVAR(varname) ///
        [ IVAR(varname) ID(varname) NOTYET METHOD(string) BASE_period(string) ///
          FIX_weights(string) ///
          ANTICIPation(integer 0) Level(cilevel) AGG(string) DROPMissing ///
          CLuster(varname) VCE(string asis) POINTwise WBOOT(string asis) ///
          REPS(string) BITERS(string) SEED(string) ///
          PSCORETRIM(real 0.995) RSEED(string) ///
          SAVERIF(string) REPLACE FAST NOFAST ///
          ASINR NEVER LONG LONG2 BALance(string) RCS DRYRUN FROM(string) ///
          ANALYTical * ]

    local allow_unbalanced ""
    local store_all ""
    local base_period_alias ""
    local fix_weights_alias ""
    local fix_weights_alias_n 0
    * which spelling supplied the value, so a refusal names the option the
    * user actually typed (in-house review, entry lens: base_period(bogus)
    * was refused as "baseperiod() must be ...")
    local base_period_src "base_period"
    local fix_weights_src "fix_weights"
    local wboot_flag 0
    local nevertreated_alias 0
    * reps()/biters()/seed()/rseed() used to be declared
    * `integer -1', so -1 was indistinguishable from "not specified" and
    * `reps(-1)' / `rseed(-1)' silently ran at the defaults (1000 reps,
    * unseeded) while `reps(-5)' errored. They are string options now: empty
    * means unspecified and every supplied value - including -1 - goes through
    * the positive-integer check below.
    local reps_top = strtrim(`"`reps'"')
    local biters_top = strtrim(`"`biters'"')
    local seed_top = strtrim(`"`seed'"')
    local rseed_top = strtrim(`"`rseed'"')
    if `"`options'"' != "" {
        local options_clean ""
        foreach opt of local options {
            local opt_l = lower(`"`opt'"')
            * Synonyms of bal(none), typed as written -- no abbreviations,
            * matching the balance_e() rule on the aggregation side.
            if inlist(`"`opt_l'"', "unbalanced", "allowunbalanced", "allow_unbalanced") {
                local allow_unbalanced "allow_unbalanced"
            }
            else if `"`opt_l'"' == "wboot" {
                local wboot_flag 1
            }
            * Stata abbreviates options: CLuster() accepts cl. These arrive
            * through the catch-all, where an exact match meant nevertreat and
            * notyettreat were errors while nevertreated and never happened to
            * work -- the latter only because it was separately defined. Two
            * spellings are prefix-matched from a documented minimum, as
            * syntax would:
            *   NEVERtreated   min never (5)
            *   NOTYETtreated  min notyet (6)
            * Everything else in this catch-all is matched EXACTLY, by design:
            * unbalanced / allowunbalanced / allow_unbalanced, storeall /
            * store_all, universal, varying, rcs. That mirrors the
            * full-spelling rule balance_e() follows on the aggregation side,
            * and it is documented as such in help csdid. The comment
            * previously listed abbreviation minima for the exact-match
            * spellings, and two options -- BALANCEAll and BALANCEPair -- that
            * have never existed in any release and are refused by name.
            else if strlen(`"`opt_l'"') >= 6 & ///
                    `"`opt_l'"' == substr("notyettreated", 1, strlen(`"`opt_l'"')) {
                local notyet "notyet"
            }
            else if strlen(`"`opt_l'"') >= 5 & ///
                    `"`opt_l'"' == substr("nevertreated", 1, strlen(`"`opt_l'"')) {
                local nevertreated_alias 1
            }
            else if inlist(`"`opt_l'"', "store_all", "storeall") {
                local store_all "store_all"
            }
            else if inlist(`"`opt_l'"', "universal", "varying") {
                if `"`base_period_alias'"' != "" & `"`base_period_alias'"' != `"`opt_l'"' {
                    display as error "baseperiod() was given as `base_period_alias' and also as `opt_l'. Specify only one."
                    exit 198
                }
                local base_period_alias `"`opt_l'"'
            }
            else if regexm(`"`opt_l'"', "^baseperiod\((.*)\)$") {
                * the value comes from the ORIGINAL token, not the lowered
                * one: option NAMES are matched case-insensitively in this
                * catch-all, but option VALUES are strict lowercase exactly
                * as the reference implementation's match.arg is, so
                * baseperiod(Universal) must refuse the way
                * base_period(Universal) does (in-house review, entry lens).
                local opt_val = strtrim(substr(`"`opt'"', strpos(`"`opt'"', "(") + 1, .))
                local base_period_value = substr(`"`opt_val'"', 1, strlen(`"`opt_val'"') - 1)
                local base_period_value = strtrim(`"`base_period_value'"')
                if `"`base_period_alias'"' != "" & `"`base_period_alias'"' != `"`base_period_value'"' {
                    display as error "baseperiod() aliases universal and varying cannot be combined"
                    exit 198
                }
                local base_period_alias `"`base_period_value'"'
            }
            else if regexm(`"`opt_l'"', "^fixweights\((.*)\)$") {
                * fixweights() reaches us through the `*'
                * catch-all, where a repeated option is NOT caught by `syntax',
                * so `fixweights(base) fixweights(first)' used to let the last
                * one win silently. Refuse it the way `syntax' refuses a
                * repeated declared option.
                if `fix_weights_alias_n' {
                    display as error "option fixweights() specified more than once"
                    exit 198
                }
                local ++fix_weights_alias_n
                * original token, same strict-value rule as baseperiod() above
                local opt_val = strtrim(substr(`"`opt'"', strpos(`"`opt'"', "(") + 1, .))
                local fix_weights_alias = substr(`"`opt_val'"', 1, strlen(`"`opt_val'"') - 1)
                local fix_weights_alias = strtrim(`"`fix_weights_alias'"')
            }
            else {
                local options_clean `"`options_clean' `opt'"'
            }
        }
        local options = strtrim(`"`options_clean'"')
    }
    if `"`options'"' != "" {
        * D-1: compound quotes. A quoted option VALUE (e.g.
        * title("Cohort 2004")) puts a double quote inside `options', and the
        * plain-quoted display then breaks the string, producing a garbled
        * message and r(111) instead of the documented r(198).
        display as error `"unsupported option(s): `options'"'
        exit 198
    }
    if "`id'" != "" {
        if "`ivar'" != "" & "`ivar'" != "`id'" {
            display as error "id(`id') and ivar(`ivar') name different variables. Specify only one, or give both the same variable."
            exit 198
        }
        local ivar "`id'"
    }
    if `"`base_period_alias'"' != "" {
        if `"`base_period'"' != "" & strtrim(`"`base_period'"') != `"`base_period_alias'"' {
            display as error "baseperiod() cannot be combined with a different base-period value"
            exit 198
        }
        if `"`base_period'"' == "" local base_period_src "baseperiod"
        local base_period `"`base_period_alias'"'
    }
    if `"`fix_weights_alias'"' != "" {
        if `"`fix_weights'"' != "" & strtrim(`"`fix_weights'"') != `"`fix_weights_alias'"' {
            display as error "fixweights() cannot be combined with a different fixed-weight value"
            exit 198
        }
        if `"`fix_weights'"' == "" local fix_weights_src "fixweights"
        local fix_weights `"`fix_weights_alias'"'
    }
    if "`dryrun'" != "" {
        display as error "dryrun is an internal legacy option and is unsupported"
        exit 198
    }
    * from() is unsupported by design. In legacy csdid it set a LOWER EVENT-TIME
    * bound on the simple, group and calendar aggregations
    * (tlvl[j] - glvl[i] >= from). R's did fixes that bound at event time 0 for
    * those three types -- compute.aggte() selects them with
    * `which(group <= t & t <= (group + max_e))`, in which `group <= t` hardcodes
    * e >= 0 and only the upper bound is adjustable; min_e applies solely to
    * type == "dynamic". So a nonzero from() has no R counterpart, and from(0),
    * the legacy default, is already what csdid and R both do. Declared in
    * syntax rather than left to the catch-all so a migrating user gets this
    * explanation instead of a bare "unsupported option(s)".
    if `"`from'"' != "" {
        display as error "from() is no longer supported. It set a lower event-time bound on the simple, group and calendar aggregations; those aggregations now fix that bound at event time 0, which is what from(0) -- the legacy default -- already did, so there is no equivalent. For event-time windows use csdid_stats, type(dynamic) window(# #) or estat event, window(# #)."
        exit 198
    }
    if `nofast_raw' local nofast "nofast"
    if "`fast'" != "" & "`nofast'" != "" {
        display as error "fast and nofast ask for opposite things; specify only one. Omitting both lets csdid choose."
        exit 198
    }
    local fast_mode "auto"
    if "`fast'" != "" local fast_mode "on"
    if "`nofast'" != "" local fast_mode "off"

    * Storage is lean at every size; storeall materializes the stored
    * matrices. (The development-era performance()/lean spellings never
    * shipped in any release and were removed before 2.0.0.)
    local performance_mode = cond("`store_all'" != "", "full", "auto")
    * ---------------------------------------------------------------------
    * bal() selects what happens to an unbalanced ivar() panel.
    *
    *   bal(full)  drop units not observed in every period. The DEFAULT, and
    *              what R did does by default.
    *   bal(pair)  balance each 2x2 separately, keeping units observed in both
    *              of its periods. This was csdid Version 1.82's silent default.
    *   bal(none)  keep every unit and use the repeated-cross-section
    *              computation with the matching standard-error accounting.
    *
    * Whenever a mode discards observations it says so and reports how many.
    * Changing the estimand is acceptable; changing it silently is not.
    * ---------------------------------------------------------------------
    local balance_mode ""
    if "`balance'" != "" {
        local balance_mode = lower(strtrim(`"`balance'"'))
        if !inlist("`balance_mode'", "full", "pair", "none") {
            display as error "bal() must be full, pair, or none"
            exit 198
        }
    }
    if "`allow_unbalanced'" != "" {
        if "`balance_mode'" != "" & "`balance_mode'" != "none" {
            display as error "bal(`balance_mode') conflicts with unbalanced, which means bal(none). Specify only one of them."
            exit 198
        }
        * Supported synonyms of bal(none), not deprecations: unbalanced is
        * the documented spelling; allowunbalanced/allow_unbalanced are the
        * R-compatible longhand (att_gt's allow_unbalanced_panel = TRUE).
        local balance_mode "none"
    }
    * DEFAULT: full, matching R did. An unbalanced panel is balanced by
    * dropping units not observed in every period, and says so.
    local balance_explicit = ("`balance_mode'" != "")
    if "`balance_mode'" == "" local balance_mode "full"


    * ---------------------------------------------------------------------
    * rcs -- declare the data to be repeated cross sections.
    *
    * This is the counterpart of R did's panel = FALSE. Without it, csdid
    * infers the structure from ivar(): supplied means panel, omitted means
    * repeated cross sections. That inference forces a false choice on anyone
    * whose repeated cross sections happen to carry an identifier -- a survey
    * respondent id, a county code -- because the only way to declare the data
    * as cross sections was to withhold a variable that genuinely exists.
    *
    * With rcs the declaration is explicit and ivar() may be supplied
    * alongside it. The identifier is then validated and used to mark the
    * estimation sample, exactly as R validates idname and drops rows missing
    * it, but it does not enter estimation: each observation is its own unit.
    * R does the same, overwriting idname with a row sequence.
    * ---------------------------------------------------------------------
    if "`rcs'" != "" {
        if `balance_explicit' & "`balance_mode'" != "none" {
            display as error "rcs declares the data to be repeated cross sections, but bal(`balance_mode') balances a panel; the two describe different data. Specify only one. Repeated cross sections have nothing to balance, so rcs implies bal(none)."
            exit 198
        }
        local balance_mode "none"
    }
    * bal(full) and bal(pair) balance a PANEL. Without ivar() there is no
    * panel: each observation is its own unit, csdid__prescan never marks a
    * drop (its balance pass is gated on ivar()) and pair_mode is 0 in the
    * kernel. Both were therefore complete no-ops that said nothing, while the
    * twin case -- rcs together with an explicit bal() -- is refused at length
    * immediately above. bal(none) agrees with what the no-ivar path already
    * does and stays accepted.
    if "`ivar'" == "" & `balance_explicit' & "`balance_mode'" != "none" {
        display as error "bal(`balance_mode') balances a panel, but no ivar() was given, so each observation is its own unit and there is nothing to balance. Omit bal(), specify bal(none), or supply ivar()."
        exit 198
    }

    if `nevertreated_alias' & "`notyet'" != "" {
        display as error "nevertreated and notyettreated select different comparison groups; specify only one. Omitting both uses not-yet-treated, the default."
        exit 198
    }
    if "`never'" != "" & "`notyet'" != "" {
        display as error "never (the legacy spelling of nevertreated) and notyettreated select different comparison groups; specify only one. Omitting both uses not-yet-treated, the default."
        exit 198
    }
    * DEFAULT: not-yet-treated. Units not yet treated at t form the
    * comparison group, which uses more of the data and does not depend on a
    * never-treated group existing or being large enough to trust.
    * nevertreated (or the legacy never) selects the never-treated
    * comparison group instead.
    *
    * This is a deliberate divergence from R did, which defaults to
    * never-treated. It also means the small-never-treated-group refusal below
    * no longer fires by default -- correctly, since notyet is the remedy that
    * refusal recommends.
    if `nevertreated_alias' == 0 & "`never'" == "" & "`notyet'" == "" {
        local notyet "notyet"
    }
    if "`never'" != "" {
        display as text "csdid legacy compatibility: never is accepted as a request for the never-treated comparison group, which is no longer the default"
    }
    if "`long'`long2'" != "" {
        display as text "warning: long/long2 are legacy event-study aliases slated for removal; do not use them in new code. Specify baseperiod(universal) explicitly for legacy event-study layout"
    }
    if "`asinr'" != "" {
        display as text "csdid legacy compatibility: asinr is accepted and ignored; use notyet to select the not-yet-treated comparison group."
    }
    local agg_type = lower(strtrim(`"`agg'"'))
    if "`agg'" != "" {
        if !inlist("`agg_type'", "event", "dynamic") {
            * 198, the code every other option-value refusal in this command
            * uses. 498 is reserved for a situation with no other code, and a
            * value this option does not take is an ordinary syntax error --
            * a script branching on _rc == 198 to catch a mistyped option
            * missed this one alone.
            display as error "agg() immediate aggregation currently supports only event/dynamic; run csdid_stats for simple, group, or calendar aggregation"
            exit 198
        }
    }
    * dropmissing governs the agg() aggregation and nothing else, so with no
    * agg() it would be a silent no-op. Refuse instead, and name the two
    * places it does mean something.
    if "`dropmissing'" != "" & "`agg'" == "" {
        display as error "dropmissing applies to the aggregation, so it needs agg() on this command. Specify agg(event) to aggregate here, or run csdid_stats, type() dropmissing (or estat event, dropmissing) after estimation."
        exit 198
    }
    capture confirm numeric variable `time'
    if _rc {
        display as error "time() must be numeric"
        exit 198
    }
    capture confirm numeric variable `gvar'
    if _rc {
        display as error "gvar() must be numeric"
        exit 198
    }
    if "`ivar'" != "" {
        capture confirm numeric variable `ivar'
        if _rc {
            display as error "ivar() must be a numeric variable; encode or destring a string identifier first"
            exit 198
        }
    }
    if `"`vce'"' != "" {
        local vce_clean = strtrim(`"`vce'"')
        local vce_words : word count `vce_clean'
        local vce_type : word 1 of `vce_clean'
        local vce_type = lower(`"`vce_type'"')
        if inlist("`vce_type'", "analytical", "analytic") {
            if `vce_words' != 1 {
                display as error "vce(analytical) does not take additional arguments"
                exit 198
            }
            local analytical "analytical"
        }
        else if "`vce_type'" == "cluster" & `vce_words' == 2 {
            local vce_cluster : word 2 of `vce_clean'
            * resolve the abbreviation BEFORE comparing: cluster() arrives
            * syntax-expanded while vce() keeps the typed text, so the same
            * variable spelled two legal ways read as two variables
            * (in-house review, entry lens).
            capture unab vce_cluster : `vce_cluster'
            if "`cluster'" != "" & "`cluster'" != "`vce_cluster'" {
                display as error "vce(cluster `vce_cluster') and cluster(`cluster') name different variables. Specify only one, or give both the same variable."
                exit 198
            }
            local cluster "`vce_cluster'"
        }
        else {
            display as error "vce() currently supports vce(cluster clustvar) and vce(analytical)"
            exit 198
        }
    }
    if "`cluster'" != "" {
        capture confirm numeric variable `cluster'
        if _rc {
            display as error "cluster() must be numeric"
            exit 198
        }
    }
    local bstrap = ("`analytical'" == "")
    if "`analytical'" != "" & (`"`wboot'"' != "" | `wboot_flag') {
        display as error "analytical asks for analytical standard errors and wboot asks for bootstrapped ones; specify only one. Omitting both uses the bootstrap, the default."
        exit 198
    }
    * The old refusal of lean + saverif() is gone: the RIF exporter reads the
    * Mata cache directly, so the artifact no longer needs the influence
    * functions materialized in e().
    * saverif() used to be checked only by the `save' inside
    * _csdid_save_rif, i.e. AFTER the whole estimation had run and printed its
    * table - the run then died r(602) with e(cmd)/e(N) left posted from a
    * command that had just failed. `bootstrap, saving()' refuses before the
    * first replication; do the same here, in the option block, and clear e()
    * so a failed csdid never leaves estimation results behind.
    * replace is meaningless without saverif(): accepting it as a silent
    * no-op would let a user believe an artifact was (re)written when
    * nothing was. Refused BEFORE estimation, mirroring csdid_estat's rule
    * for replace without saving().
    if "`replace'" != "" & `"`saverif'"' == "" {
        display as error "replace has no effect without saverif(); specify saverif(filename) or drop replace"
        exit 198
    }
    if `"`saverif'"' != "" {
        * The standard saving idiom -- saverif(filename, replace) -- is parsed
        * rather than swallowed: before this block, the whole parenthesised
        * text was the filename, so the comma form returned rc 0 after writing
        * a file literally named "filename, replace.dta". csdid_plot's
        * saving() had the identical defect and this is its parser: replace is
        * the only sub-option, anything else refuses by name.
        mata: st_local("_sr_comma", strofreal(strpos(st_local("saverif"), ",")))
        if `_sr_comma' {
            local _sr_outer_replace `"`replace'"'
            local _sr_rest ""
            gettoken _sr_file _sr_rest : saverif, parse(",")
            if `"`_sr_file'"' == "," {
                local _sr_file ""
            }
            else {
                gettoken _sr_c _sr_rest : _sr_rest, parse(",")
                mata: st_local("_sr_file", strtrim(st_local("_sr_file")))
            }
            * `syntax' resets the STANDARD locals (varlist, if, in, weight,
            * exp, options and 0) whether or not they are declared, and the
            * estimation still needs every one of them -- so they are saved
            * around the sub-option parse and put back. csdid_plot's copy of
            * this parser did not need the guard only because nothing there
            * reads them afterwards.
            local _sr_varlist `"`varlist'"'
            local _sr_if `"`if'"'
            local _sr_in `"`in'"'
            local _sr_weight `"`weight'"'
            local _sr_exp `"`exp'"'
            local _sr_options `"`options'"'
            local _sr_zero `"`0'"'
            local 0 `", `_sr_rest'"'
            capture syntax [, REPLACE]
            local _sr_parse_rc = _rc
            local varlist `"`_sr_varlist'"'
            local if `"`_sr_if'"'
            local in `"`_sr_in'"'
            local weight `"`_sr_weight'"'
            local exp `"`_sr_exp'"'
            local options `"`_sr_options'"'
            local 0 `"`_sr_zero'"'
            if `_sr_parse_rc' {
                display as error `"saverif() accepts only the replace sub-option; cannot parse: `_sr_rest'"'
                exit 198
            }
            if "`replace'" == "" local replace `"`_sr_outer_replace'"'
            if `"`_sr_file'"' == "" {
                display as error "saverif() requires a filename before the comma, as in saverif(myfile, replace)"
                exit 198
            }
            local saverif `"`_sr_file'"'
        }
        local saverif_path `"`saverif'"'
        * Match -save-'s own extension rule: .dta is appended only when the
        * FILENAME has no extension at all. The old check appended .dta
        * whenever the last four characters were not ".dta", so for a target
        * like results.v2 - or a tempfile, whose names end in .000001 - it
        * confirmed a file -save- would never write: the replace-guard could
        * refuse on a phantom, or wave the run through and die r(602) inside
        * the writer after the whole estimation had already run and posted,
        * which is exactly what moving this check up here prevents.
        mata: st_local("saverif_base", pathbasename(st_local("saverif_path")))
        if strpos(`"`saverif_base'"', ".") == 0 {
            local saverif_path `"`saverif_path'.dta"'
        }
        capture confirm new file `"`saverif_path'"'
        local saverif_rc = _rc
        * These are ENTRY refusals: nothing has been estimated, so whatever
        * results were in memory belong to a previous, complete command and
        * stay exactly as they were -- clearing them here once destroyed a
        * user's prior estimation over a typo'd filename. The clear this
        * block used to carry belonged to the days the destination check ran
        * mid-estimation, where a partial posting was the thing to prevent.
        if `saverif_rc' == 602 & `"`replace'"' == "" {
            display as error `"saverif() destination `saverif_path' already exists; specify replace to overwrite it"'
            exit 602
        }
        if `saverif_rc' != 0 & `saverif_rc' != 602 {
            display as error `"saverif() destination `saverif_path' cannot be written"'
            exit `saverif_rc'
        }
    }
    local biters 0
    local boot_seed ""
    local boot_dist ""
    local boot_dist_requested ""
    local boot_cluster ""
    * e(cband) records the BAND REQUEST, exactly as the reference object's
    * cband slot does: TRUE unless pointwise was asked for, whatever the
    * inference. Under analytical the ATT(g,t) table itself stays pointwise
    * (the reference's fit carries the pointwise quantile when bstrap is
    * off), but the AGGREGATION reads this request and computes the
    * simultaneous band by multiplier bootstrap, with a note -- see the
    * banded-analytical branch in csdid_stats.ado.
    local cband = ("`pointwise'" == "")
    if !`bstrap' & (`"`rseed_top'"' != "" | `"`seed_top'"' != "" | `"`reps_top'"' != "" | `"`biters_top'"' != "") {
        display as error "reps(), biters(), seed(), and rseed() require bootstrap inference; omit vce(analytical)"
        exit 198
    }
    * with the -1 sentinels gone, every supplied
    * reps()/biters()/seed()/rseed() value is checked here, so a negative or
    * fractional or non-numeric value errors instead of silently reverting to
    * the default. The message names the option the user actually typed.
    foreach csdid_intopt in reps biters seed rseed {
        local csdid_intval `"``csdid_intopt'_top'"'
        if `"`csdid_intval'"' != "" {
            local csdid_intnum = real(`"`csdid_intval'"')
            if missing(`csdid_intnum') | `csdid_intnum' < 1 | `csdid_intnum' != floor(`csdid_intnum') {
                display as error "`csdid_intopt'() must be a positive integer"
                exit 198
            }
        }
        else if regexm(lower(`"`csdid_zero_entry'"'), "[, ]`csdid_intopt'\( *\)") {
            * a TYPED-but-empty count or seed -- reps(), rseed(`unset') --
            * fell through to the defaults silently, so a run the user
            * believed seeded was unseeded and unreproducible at rc 0
            * (in-house review, entry lens). An empty option is a typo, not
            * a request for the default.
            display as error "`csdid_intopt'() is empty; supply a positive integer or omit the option"
            exit 198
        }
    }
    if regexm(lower(`"`wboot'"'), "(reps|biters|seed|rseed)\( *\)") {
        display as error "wboot(`=regexs(1)'()) is empty; supply a positive integer or omit the sub-option"
        exit 198
    }
    if `bstrap' {
        local biters 1000
        local biters_specified 0
        local boot_dist "rademacher"
        local boot_dist_requested "rademacher"
        local wb_cluster ""
        local wb_reps ""
        local wb_biters ""
        local wb_rseed ""
        local wb_seed ""
        local wb_wtype ""
        local wb_wbtype ""
        if `"`wboot'"' != "" {
            * the sub-options used to be pulled out of the
            * raw string with independent regexes, so anything the regexes did
            * not happen to match was discarded without a word - typos
            * (`rep(7)'), junk (`totalnonsense'), missing parentheses
            * (`reps 7'), unknown sub-options (`frobnicate(9)') and repeated
            * sub-options (`reps(7) reps(9)') all returned rc 0 and ran the
            * bootstrap at whatever the regexes salvaged. Parse them with a real
            * nested `syntax' instead: Stata then names the offending
            * sub-option itself and returns 198, and the line below adds the
            * wboot() context.
            capture noisily _csdid_parse_wboot, `wboot'
            if _rc {
                display as error "invalid wboot() sub-option; wboot() accepts reps(), biters(), rseed(), seed(), cluster(), wtype(), and wbtype(), each at most once"
                exit 198
            }
            local wb_cluster `"`r(wb_cluster)'"'
            local wb_reps    `"`r(wb_reps)'"'
            local wb_biters  `"`r(wb_biters)'"'
            local wb_rseed   `"`r(wb_rseed)'"'
            local wb_seed    `"`r(wb_seed)'"'
            local wb_wtype   `"`r(wb_wtype)'"'
            local wb_wbtype  `"`r(wb_wbtype)'"'
        }
        if `"`wb_cluster'"' != "" {
            local boot_cluster = strtrim(`"`wb_cluster'"')
        }
        if `"`wb_reps'"' != "" & `"`wb_biters'"' != "" {
            if real(strtrim(`"`wb_reps'"')) != real(strtrim(`"`wb_biters'"')) {
                display as error "bootstrap reps() and biters() values cannot disagree"
                exit 198
            }
        }
        if `"`wb_reps'"' != "" {
            local biters = real(strtrim(`"`wb_reps'"'))
            local biters_specified 1
        }
        else if `"`wb_biters'"' != "" {
            local biters = real(strtrim(`"`wb_biters'"'))
            local biters_specified 1
        }
        if `"`reps_top'"' != "" {
            if `biters_specified' & `biters' != real(`"`reps_top'"') {
                display as error "bootstrap reps() and biters() values cannot disagree"
                exit 198
            }
            local biters = real(`"`reps_top'"')
            local biters_specified 1
        }
        if `"`biters_top'"' != "" {
            if `biters_specified' & `biters' != real(`"`biters_top'"') {
                display as error "bootstrap reps() and biters() values cannot disagree"
                exit 198
            }
            local biters = real(`"`biters_top'"')
            local biters_specified 1
        }
        if `"`wb_rseed'"' != "" & `"`wb_seed'"' != "" {
            if real(strtrim(`"`wb_rseed'"')) != real(strtrim(`"`wb_seed'"')) {
                display as error "bootstrap seed() and rseed() values cannot disagree"
                exit 198
            }
        }
        if `"`wb_rseed'"' != "" {
            local boot_seed = strtrim(`"`wb_rseed'"')
        }
        else if `"`wb_seed'"' != "" {
            local boot_seed = strtrim(`"`wb_seed'"')
        }
        if `"`rseed_top'"' != "" {
            if "`boot_seed'" != "" & real("`boot_seed'") != real(`"`rseed_top'"') {
                display as error "bootstrap seed() and rseed() values cannot disagree"
                exit 198
            }
            local boot_seed `"`rseed_top'"'
        }
        if `"`seed_top'"' != "" {
            if "`boot_seed'" != "" & real("`boot_seed'") != real(`"`seed_top'"') {
                display as error "bootstrap seed() and rseed() values cannot disagree"
                exit 198
            }
            local boot_seed `"`seed_top'"'
        }
        if `"`wb_wtype'"' != "" & `"`wb_wbtype'"' != "" {
            if lower(strtrim(`"`wb_wtype'"')) != lower(strtrim(`"`wb_wbtype'"')) {
                display as error "wboot() wtype() and wbtype() values cannot disagree"
                exit 198
            }
        }
        if `"`wb_wtype'"' != "" {
            local boot_dist_requested = lower(strtrim(`"`wb_wtype'"'))
        }
        else if `"`wb_wbtype'"' != "" {
            local boot_dist_requested = lower(strtrim(`"`wb_wbtype'"'))
        }
        if inlist("`boot_dist_requested'", "rademacher", "") {
            local boot_dist "rademacher"
        }
        else if inlist("`boot_dist_requested'", "normal", "gaussian", "mammen") {
            display as error "wboot() currently supports only rademacher multipliers; wtype()/wbtype(`boot_dist_requested') is unsupported"
            exit 498
        }
        else {
            display as error "wboot() currently supports only rademacher multipliers"
            exit 498
        }
        if missing(`biters') | `biters' < 1 | `biters' != floor(`biters') {
            display as error "wboot() reps() must be a positive integer"
            exit 198
        }
        * F-017: a handful of multiplier draws is not inference. The empirical
        * quantile used for the simultaneous critical value cannot be resolved
        * from a few draws, and at one draw the bootstrap standard error is a
        * degenerate artifact rather than an estimate. Refuse below 20 rather
        * than return a number that looks like a standard error and is not.
        * DELIBERATE DIVERGENCE (approved): R accepts biters = 1.
        if `biters' <= 20 {
            display as error "wboot() reps() must be greater than 20; `biters' multiplier draws cannot support a standard error or a simultaneous critical value. Use reps(1000), the default, or larger."
            exit 198
        }
        local biters = floor(`biters')
        if "`boot_seed'" != "" {
            local seed_value = real("`boot_seed'")
            if missing(`seed_value') | `seed_value' < 1 | `seed_value' != floor(`seed_value') {
                display as error "wboot() rseed() must be a positive integer"
                exit 198
            }
            local boot_seed : display %21.0f `seed_value'
            local boot_seed = strtrim("`boot_seed'")
        }
    }
    if "`boot_cluster'" != "" {
        local boot_cluster_words : word count `boot_cluster'
        if `boot_cluster_words' != 1 {
            display as error "wboot(cluster()) accepts one numeric cluster variable"
            exit 198
        }
        if "`cluster'" != "" & "`cluster'" != "`boot_cluster'" {
            display as error "wboot(cluster()) must match cluster() when both are supplied"
            exit 198
        }
        local cluster "`boot_cluster'"
        capture confirm numeric variable `cluster'
        if _rc {
            display as error "cluster() must be numeric"
            exit 198
        }
    }

    * -------------------------------------------------------------------
    * Stata 14 and 15 cap classic-matrix dimensions with `set matsize',
    * whose default is 400; Stata 16 removed the cap and ignores the
    * setting. Every bootstrap path writes at least one biters-row Stata
    * matrix, and a seeded run builds a 1 x 625 RNG-state matrix, so on a
    * stock Stata 14/15 the default run -- reps(1000), bootstrap on unless
    * analytical -- has no working path. The check needs nothing but the
    * options just resolved, so it runs HERE, before the data are touched
    * or anything is estimated -- the help's "checks before estimating"
    * promise is a placement promise, and the cold audit measured the old
    * placement breaking it: the refusal fired only after the whole ATT
    * kernel had run. As an entry refusal it leaves whatever estimation
    * results were in memory exactly as they were, like every other entry
    * refusal in this command.
    *
    * Gated on the version, or it would refuse the entire modern user
    * base, where c(matsize) still reports 400 and nothing is wrong.
    *
    * This REFUSES rather than raising matsize itself. Raising it is not
    * universally possible -- Stata/IC 14/15 caps matsize at 800, below
    * the default reps(1000) -- and an estimation command has no business
    * silently changing a global setting the user did not ask about. The
    * message names the exact command to type and the alternative.
    * -------------------------------------------------------------------
    if `bstrap' & c(stata_version) < 16 {
        local matsize_need = `biters'
        if "`boot_seed'" != "" & 625 > `matsize_need' local matsize_need = 625
        if `matsize_need' > c(matsize) {
            display as error "this Stata version limits matrix dimensions with -set matsize- (currently `=c(matsize)'), and this bootstrap needs at least `matsize_need'`=cond("`boot_seed'" != "" & `biters' < 625, " for the seeded random-number state", "")'."
            display as error "Type -set matsize `matsize_need'- and rerun, or lower reps(), or specify analytical for analytical standard errors. Stata/IC caps matsize at 800, so on that flavour reps() must be 800 or fewer."
            exit 908
        }
    }
    gettoken yname xvars : varlist
    capture confirm numeric variable `yname'
    if _rc {
        display as error "outcome variable must be numeric"
        exit 109
    }
    if "`method'" == "" local method "dr"
    local method_requested = lower(strtrim("`method'"))
    local method "`method_requested'"
    if "`method_requested'" == "dripw" {
        display as text "csdid legacy compatibility: method(dripw) is retired; running method(dr), which is the same estimator. Use method(dr) in new code."
        local method "dr"
    }
    else if "`method_requested'" == "stdipw" {
        display as text "csdid legacy compatibility: method(stdipw) is retired; running method(ipw), which is the same estimator. Use method(ipw) in new code."
        local method "ipw"
    }
    if !inlist("`method'", "dr", "reg", "ipw") {
        display as error "method() must be one of dr, reg, or ipw"
        exit 198
    }
    local xvars_expanded ""
    local wvar ""
    if "`weight'" != "" {
        tempvar wtmp
        quietly generate double `wtmp' `exp'
        local wvar "`wtmp'"
    }
    * The VALUES are strict lowercase in both spellings, exactly as the
    * reference implementation's match.arg is -- the synonyms used to be
    * lenient only because the catch-all lowers whole tokens (in-house
    * review, entry lens). The refusals below name the spelling typed.
    local base_period = strtrim(`"`base_period'"')
    local fix_weights = strtrim(`"`fix_weights'"')
    if "`base_period'" == "" {
        * DEFAULT: universal. Every cell is measured against g-1, which is the
        * layout an event-study plot assumes and the one nearly everyone
        * presents. Post-treatment effects are identical either way; only the
        * pre-treatment cells differ, and universal additionally reports the
        * g-1 normalisation row. base_period(varying) is the better choice when
        * PRE-TESTING, because each pre-treatment cell is then its own
        * one-period comparison rather than a cumulative one; see help csdid.
        * This is a deliberate divergence from R did, which defaults to varying.
        local base_period "universal"
    }
    if !inlist("`base_period'", "varying", "universal") {
        display as error "`base_period_src'() must be varying or universal"
        exit 198
    }
    if "`fix_weights'" != "" {
        if inlist("`fix_weights'", "base", "baseperiod") local fix_weights "base_period"
        if inlist("`fix_weights'", "first", "firstperiod") local fix_weights "first_period"
        if !inlist("`fix_weights'", "varying", "base_period", "first_period") {
            display as error "`fix_weights_src'() must be one of varying, base, or first"
            exit 198
        }
        if inlist("`fix_weights'", "base_period", "first_period") & ///
           ("`ivar'" == "" | "`rcs'" != "") {
            local fix_weights_label "`fix_weights'"
            if "`fix_weights'" == "base_period" local fix_weights_label "base"
            if "`fix_weights'" == "first_period" local fix_weights_label "first"
            if "`rcs'" != "" {
                display as error "`fix_weights_src'(`fix_weights_label') holds each unit's weight fixed across periods, which requires following the same unit over time. rcs declares the data to be repeated cross sections, where each observation is a different unit. Use `fix_weights_src'(varying), or drop rcs if these data are a panel."
                exit 198
            }
            display as error "`fix_weights_src'(`fix_weights_label') requires ivar(); repeated cross-section fixed-weight modes are unsupported"
            exit 198
        }
    }
    if `anticipation' < 0 {
        display as error "anticipation() must be nonnegative"
        exit 198
    }
    * pscoretrim() >= 1 means NO TRIMMING and is accepted as such. Legacy csdid
    * defaulted to pscoretrim(1.0), so rejecting it broke any legacy script that
    * wrote the legacy default out explicitly. The engine keeps a control
    * observation when ps < trim_level, and csdid__invlogit() clamps eta to
    * +/-30 and returns t/(1+t), whose maximum attainable value is
    * 0.99999999999999978 (verified for eta up to 1e300) -- strictly below 1 on
    * every estimator path, capped or not. So trim_level >= 1 can never bind,
    * and 1.0, 2, or 1e6 all mean exactly "trim nothing". Only a nonpositive or
    * missing level is an error; the 0.995 default is unchanged.
    * A missing level is refused rather than silently defaulted. pscoretrim(.)
    * essentially only arises when an expression evaluated to missing upstream
    * (an unset local yields pscoretrim(), a different syntax error), so
    * substituting the default would run the analysis at a trim the script did
    * not intend. R does not default either -- DRDID propagates NA straight into
    * ATT = NA. The message names the default so the fix is obvious.
    if missing(`pscoretrim') | `pscoretrim' <= 0 {
        display as error "pscoretrim() must be greater than 0; omit it for the default of .995, or specify 1 (or any larger value) for no trimming"
        exit 198
    }

    marksample touse, novarlist zeroweight
    * The dropped-data warning's baseline is the if/in sample BEFORE any
    * screening at all. marksample itself already removes rows with missing
    * WEIGHTS (even under zeroweight), so a baseline copied from touse hid
    * exactly those rows from the warning -- a missing iweight vanished with
    * no announcement (cold-audit round 8, F5).
    tempvar touse_initial
    quietly mark `touse_initial' `if' `in'
    quietly markout `touse' `yname'
    if "`wvar'" != "" {
        quietly markout `touse' `wvar'
    }
    local markvars "`time' `gvar'"
    if "`ivar'" != "" local markvars "`markvars' `ivar'"
    if "`cluster'" != "" local markvars "`markvars' `cluster'"
    quietly markout `touse' `markvars'
    * -----------------------------------------------------------------------
    * Under rcs the identifier has now done the whole of its job: it was
    * confirmed to exist and to be numeric, and rows missing it have been
    * excluded, which is what R's validate_column_name() plus complete-case
    * filtering achieve. From here on it must not be visible, because every
    * downstream branch reads a non-empty ivar as "this is a panel" -- the
    * covariate listwise deletion immediately below drops a whole unit when any
    * period is missing, which is right for a panel and wrong for cross
    * sections. Clearing it here routes the run down the identical path an
    * ivar()-less repeated cross section already takes, so rcs inherits that
    * path's verification rather than opening a second one.
    * -----------------------------------------------------------------------
    local ivar_declared ""
    if "`rcs'" != "" & "`ivar'" != "" {
        local ivar_declared "`ivar'"
        local ivar ""
        display as text "csdid: rcs declares repeated cross sections, so ivar(`ivar_declared') identifies the estimation sample but is not used as a panel identifier; each observation is treated as its own unit. To cluster standard errors on it, add cluster(`ivar_declared')."
    }
    if `"`xvars'"' != "" {
        capture quietly fvrevar `xvars' if `touse'
        if _rc {
            display as error "covariates must be numeric Stata variables; encode string covariates before using factor-variable notation"
            exit 109
        }
        local xvars_expanded "`r(varlist)'"
        foreach xv of local xvars_expanded {
            capture confirm numeric variable `xv'
            if _rc {
                display as error "covariates must be numeric Stata variables; encode string covariates before using factor-variable notation"
                exit 109
            }
        }
        * One -summarize- per covariate, whose results are reused below for
        * the missing-value probe instead of a second full pass each. r(N) is
        * the count of NON-MISSING values in the if-sample, so it answers both
        * questions.
        quietly count if `touse'
        local xvars_nuse = r(N)
        local xvars_filtered ""
        local xvars_nmiss ""
        foreach xv of local xvars_expanded {
            quietly summarize `xv' if `touse', meanonly
            local xv_n = r(N)
            if substr("`xv'", 1, 2) == "__" {
                if `xv_n' > 0 & r(min) == 0 & r(max) == 0 {
                    continue
                }
            }
            local xvars_filtered "`xvars_filtered' `xv'"
            local xvars_nmiss "`xvars_nmiss' `xv_n'"
        }
        local xvars_expanded "`xvars_filtered'"
        if "`ivar'" != "" {
            * The all-zero screen above already summarized every covariate
            * over `touse', and -summarize- reports r(N) as the count of
            * NON-MISSING values in the if-sample. So the missing-value probe
            * is the same pass a second time. It reuses what the screen
            * measured: `xvars_nmiss' is that r(N) per covariate and
            * `xvars_nuse' the sample size, so a covariate has a missing value
            * exactly when they differ.
            local any_xmiss 0
            local xv_i 0
            foreach xv of local xvars_expanded {
                local ++xv_i
                local xv_n : word `xv_i' of `xvars_nmiss'
                if "`xv_n'" == "" {
                    quietly count if `touse' & missing(`xv')
                    if r(N) > 0 {
                        local any_xmiss 1
                        continue, break
                    }
                }
                else if `xv_n' < `xvars_nuse' {
                    local any_xmiss 1
                    continue, break
                }
            }
            if `any_xmiss' {
                tempvar xmiss xmiss_unit
                tempvar touse_prex
                quietly generate byte `touse_prex' = `touse'
                quietly generate byte `xmiss' = 0 if `touse'
                foreach xv of local xvars_expanded {
                    quietly replace `xmiss' = 1 if `touse' & missing(`xv')
                }
                * -----------------------------------------------------------
                * A calendar period whose covariates are missing on EVERY row
                * ceases to exist before the period list is built -- R's rule
                * exactly (pre_process_did.R: the row-level complete-cases
                * drop at :162 runs before tlist is read off the surviving
                * rows at :215, so a wholly dead period is simply absent, no
                * unit is dropped, and everything downstream -- base-period
                * re-anchoring, the first-period cohort trim, balancing, n --
                * runs on the reduced calendar). The rows are removed here for
                * ALL units so the bal(full) whole-unit rule below cannot
                * over-fire on misses confined to dead periods, and -- the
                * owner's 2026-08-28 decision -- the deletion is ANNOUNCED by
                * period and covariate, where R says only how many rows left.
                * Detection precedes the whole-unit propagation and applies on
                * every balance mode; a period only PARTIALLY missing keeps
                * its survivors and takes the ordinary route below.
                * -----------------------------------------------------------
                quietly levelsof `time' if `touse', local(ds07_periods)
                local ds07_dead ""
                foreach tv of local ds07_periods {
                    quietly count if `touse' & `time' == `tv' & `xmiss' == 0
                    if r(N) == 0 {
                        local ds07_dead "`ds07_dead' `tv'"
                    }
                }
                local ds07_dead = strtrim("`ds07_dead'")
                if "`ds07_dead'" != "" {
                    local ds07_nleft : word count `ds07_periods'
                    local ds07_ndead : word count `ds07_dead'
                    local ds07_nleft = `ds07_nleft' - `ds07_ndead'
                    foreach tv of local ds07_dead {
                        local ds07_names ""
                        foreach xv of local xvars_expanded {
                            quietly count if `touse' & `time' == `tv' & !missing(`xv')
                            if r(N) == 0 {
                                local ds07_lbl "`xv'"
                                if substr("`xv'", 1, 2) == "__" local ds07_lbl "a covariate built from `xvars'"
                                local ds07_names "`ds07_names'`=cond("`ds07_names'" == "", "", ", ")'`ds07_lbl'"
                            }
                        }
                        display as error "warning: covariate `ds07_names' is missing for every observation in period `tv' of time(`time'); the period was dropped and estimation proceeds on the `ds07_nleft' remaining period(s), exactly as if the sample had excluded it (if `time' != `tv'). Supply the covariate for that period to keep it."
                        quietly replace `touse' = 0 if `touse' & `time' == `tv'
                        quietly replace `xmiss' = . if `time' == `tv'
                    }
                }
                if inlist("`balance_mode'", "pair", "none") {
                    * Under bal(pair) and bal(none) a row with a missing
                    * covariate is treated as an UNOBSERVED row: only that
                    * row leaves the sample, and the per-pair presence
                    * machinery these modes already run does the rest --
                    * exactly R's allowed-unbalanced route (complete-case
                    * rows, then per-2x2 availability). Propagating the miss
                    * to the whole unit here silently shrank those samples:
                    * measured (cold-audit round 6, F1), a covariate missing
                    * only at t=3 changed ATT(2,2) from R's 1.1667 to 1.0
                    * by deleting the unit's clean t=1,2 rows. The whole-unit
                    * drop below remains the bal(full) rule, where R's own
                    * balancing removes the now-incomplete unit identically.
                    quietly replace `touse' = 0 if `xmiss' == 1
                }
                else {
                    quietly bysort `ivar': egen byte `xmiss_unit' = max(`xmiss') if `touse'
                    * R reaches the same estimation sample by a different
                    * route -- complete-case ROWS first, then balancing --
                    * so a unit removed whole here, if it still had complete
                    * rows, is a unit R counts in its balance announcement.
                    * Record those units and their complete rows now; the
                    * balance warning below adds them so its count is R's
                    * (in-house review: R announced 1 and 3 units where the
                    * balance scan alone announced 0 and 2).
                    tempvar xtag
                    quietly egen byte `xtag' = tag(`ivar') if `touse' & `xmiss_unit' == 1 & `xmiss' == 0
                    quietly count if `xtag' == 1
                    local xdrop_bal_units = r(N)
                    quietly count if `touse' & `xmiss_unit' == 1 & `xmiss' == 0
                    local xdrop_bal_obs = r(N)
                    quietly replace `touse' = 0 if `xmiss_unit' == 1
                }
                * on the panel path a unit is dropped whole
                * when ANY of its covariate cells is missing, so a covariate
                * that is missing for one entire period annihilates every unit
                * and the run died with a bare r(2000) "no observations" on a
                * dataset with hundreds of usable rows. Diagnose that shape and
                * name the covariate and the period instead. (R's did drops the
                * offending period and estimates on the rest; matching that is a
                * numeric-behaviour change and is recorded as a follow-up owner
                * decision, not implemented here.)
                quietly count if `touse'
                if r(N) == 0 & inlist("`balance_mode'", "pair", "none") {
                    display as error "every observation is missing a value of the covariates (`xvars'), so no estimation sample remains. Supply the missing covariate values, drop the covariate, or restrict the sample."
                    exit 459
                }
                if r(N) == 0 {
                    local ds07_x ""
                    local ds07_t ""
                    quietly levelsof `time' if `touse_prex', local(ds07_times)
                    foreach xv of local xvars_expanded {
                        foreach tv of local ds07_times {
                            quietly count if `touse_prex' & `time' == `tv' & !missing(`xv')
                            if r(N) == 0 {
                                quietly count if `touse_prex' & `time' == `tv'
                                if r(N) > 0 {
                                    local ds07_x "`xv'"
                                    local ds07_t "`tv'"
                                    continue, break
                                }
                            }
                        }
                        if "`ds07_x'" != "" continue, break
                    }
                    if "`ds07_x'" != "" {
                        local ds07_label "`ds07_x'"
                        if substr("`ds07_x'", 1, 2) == "__" {
                            local ds07_label "a covariate built from `xvars'"
                        }
                        display as error "covariate `ds07_label' is missing for every observation in period `ds07_t' of time(`time'); with ivar(`ivar') that drops every unit and leaves no estimation sample. Exclude that period (for example with if `time' != `ds07_t'), supply the covariate for it, or drop the covariate."
                        exit 459
                    }
                    display as error "every unit has at least one missing value of the covariates (`xvars'); with ivar(`ivar') each such unit is dropped whole, so no estimation sample remains. Supply the missing covariate values, drop the covariate, or restrict the sample."
                    exit 459
                }
            }
        }
        else {
            quietly markout `touse' `xvars_expanded'
        }
    }
    quietly count if `touse_initial' & !`touse'
    local n_screened = r(N)
    if r(N) > 0 {
        * Split the count: rows dropped for their OWN missing or non-finite
        * data, and rows that only left because their unit was removed whole
        * (the bal(full) covariate propagation). Counting companions as
        * missing-data rows overstated the data problem (cold-audit round 8,
        * F6: one missing cell in a two-period unit announced as two).
        tempvar own_ok
        quietly mark `own_ok' `if' `in'
        quietly markout `own_ok' `yname' `time' `gvar'
        if "`wvar'" != "" quietly markout `own_ok' `wvar'
        if "`ivar'" != "" quietly markout `own_ok' `ivar'
        if "`cluster'" != "" quietly markout `own_ok' `cluster'
        if `"`xvars_expanded'"' != "" quietly markout `own_ok' `xvars_expanded'
        quietly count if `touse_initial' & !`touse' & !`own_ok'
        local miss_dropped = r(N)
        local unit_dropped = `n_screened' - `miss_dropped'
        * `as error' is a DISPLAY STYLE here, not an error. It is the only
        * channel Stata does not suppress under `quietly csdid ...', and the
        * rule this file states at the bal() drop below -- a warning that
        * announces a SAMPLE change has to survive, because the estimand
        * changed with it -- applies here identically. On `as text' this
        * message went dark on every scripted run and e(N) moved with no
        * trace of why.
        *
        * The count is APPENDED rather than interpolated so the sentence
        * itself stays the frozen substring four tests grep for.
        if `miss_dropped' > 0 {
            display as error "warning: dropped observations with missing or non-finite data (`miss_dropped' observation(s))"
        }
        if `unit_dropped' > 0 {
            display as error "warning: dropped `unit_dropped' further observation(s) whose units left the sample whole (a unit with any missing covariate cell is dropped entirely on this route)"
        }
    }
    * csdid indexes cohorts and periods on a positive calendar-time axis:
    * time() runs from 1 upward, gvar() is the period in which a unit is first
    * treated and so is also 1 or more, and gvar() == 0 is RESERVED to mean
    * never treated. A negative or zero cohort code therefore has no consistent
    * reading -- 0 would be simultaneously "never treated" and a valid position
    * on the axis. Both checks refuse rather than guess, and name the shift that
    * fixes the data; a monotone relabelling of the periods leaves every
    * estimate unchanged. gvar() is checked first so that data violating both
    * rules reports the cohort fault, which is the more surprising of the two.
    * DELIBERATE DIVERGENCE (approved): R estimates axes that run negative.
    * That note is about the RC and the wording, and it is older than did
    * 2.5.1, which refuses a negative gname of its own accord
    * (pre_process_did2.R:54-59) -- so on this rule the two now agree on the
    * verdict and differ only in the number.
    *
    * Where they do NOT agree is the sample, and this one is measured: R asks
    * the question in validate_args, before rows with missing values are
    * removed, and this asks it on `touse', where they already are. A unit
    * whose cohort code is negative in every row and whose every row is
    * screened out -- an outcome missing throughout, say -- stops in R and
    * estimates here. The three panel-shape checks below were widened onto the
    * pre-screen sample for exactly this reason; this check was not, because
    * its rc, its wording and whether it should fire at all are an owner
    * decision that the stale note above has to settle first. Recorded, not
    * closed.
    quietly count if `touse' & `gvar' < 0
    if r(N) > 0 {
        display as error "gvar() negative values are not supported; gvar() must be 0 for never-treated units and 1 or more for treated cohorts. Shift the cohort and time axes so both start at 1 (for example, replace g = g - min_period + 1 for treated units and t = t - min_period + 1); a monotone relabelling of the periods leaves the estimates unchanged."
        exit 198
    }
    quietly count if `touse' & `time' < 1
    if r(N) > 0 {
        quietly summarize `time' if `touse', meanonly
        local tmin = r(min)
        display as error "time() must be 1 or more; the smallest value found is `tmin'. csdid indexes periods on a positive calendar-time axis, and gvar() == 0 is reserved for never-treated units. Shift the axis so it starts at 1 (for example, replace t = t - `tmin' + 1, and the same shift on gvar() for treated units); a monotone relabelling of the periods leaves the estimates unchanged."
        exit 198
    }
    if "`wvar'" != "" {
        quietly count if `touse' & `wvar' < 0
        if r(N) > 0 {
            display as error "iweights must be nonnegative"
            exit 198
        }
        quietly summarize `wvar' if `touse', meanonly
        if r(mean) <= 0 | missing(r(mean)) {
            display as error "iweights must have positive mean"
            exit 198
        }
    }
    quietly count if `touse'
    if r(N) == 0 {
        display as error "no observations"
        exit 2000
    }
    local sample_N = r(N)

    * -----------------------------------------------------------------------
    * bal(full): balance the panel by dropping units not observed in every
    * period, which is what R did does by default.
    *
    * The drop is announced. Reducing the sample changes the estimand, and a
    * user who is not told has no way to know why their N moved. bal(none)
    * keeps every unit and uses the repeated-cross-section computation.
    * -----------------------------------------------------------------------
    local balance_dropped_units = 0
    * The engine is needed a few lines early now: the balance verdict and the
    * group/time measurements below come from one Mata pass (csdid__prescan)
    * instead of two bysorts, two levelsofs, two summarizes and a tempvar
    * generate/replace - each a full pass over the data. Outputs and guard
    * semantics are identical; only the number of passes changed.
    * The loader is shared with csdid_stats, which reaches the engine without
    * csdid on the saved-RIF path: name probe, index retry, the library's
    * stamp, the accepted library's place in the search order, source
    * fallback. It settles all of that on the first call of a session and
    * costs one Mata question on every call after it.
    _csdid_engine_load
    * The library path stores functions only, so the engine's globals are not
    * created by loading it; initialise them explicitly. It has to happen
    * BEFORE the first kernel call, which is csdid__prescan a few lines below;
    * it used to run after it. Idempotent - a no-op once done, so the Mata
    * result cache is never reset mid-session.
    quietly mata: csdid__globals_init()
    tempvar bal_drop
    quietly generate byte `bal_drop' = 0
    tempname ps_gcounts
    local want_bal = ("`ivar'" != "" & "`balance_mode'" == "full")
    capture mata: csdid__prescan("`ivar'", "`time'", "`gvar'", "`cluster'", "`touse'", `anticipation', `want_bal', "`bal_drop'", "`ps_gcounts'")
    if _rc {
        * a scan failure refuses cleanly. Like every entry refusal it
        * PRESERVES whatever estimation results were already in memory --
        * they belong to a previous, complete command, and erasing them
        * over a refused csdid destroyed work (cold-audit F3; the doctrine
        * csdid.sthlp states). Only a failure after the engine has begun
        * clears e().
        local prescan_rc = _rc
        display as error "csdid could not scan the estimation sample (Mata rc `prescan_rc'); the data may be degenerate"
        exit `prescan_rc'
    }
    * The three data-shape violations R refuses -- an irreversible-treatment
    * breach, a duplicate (id, time) row and a time-varying cluster variable --
    * are decided on THIS scan and not on the one below, and refused HERE, in
    * front of the balance block. R checks all three in validate_args()
    * (pre_process_did2.R:72-109), called at :736, before did_standardization()
    * at :763 coerces the balanced panel (:331-390); the bal(full) drop a few
    * lines down removes rows, so a violation confined to a unit it drops is
    * invisible to a scan taken afterwards. Measured witness: 12 units over 3
    * periods with unit 1 present only at t=1 and duplicated there -- R stops,
    * and csdid used to estimate the remaining 11 units. The balance verdict
    * itself still comes from the post-balance scan, which is the sample the
    * estimation uses.
    *
    * The ORDER matters as much as the scan does. Refusing after the balance
    * block meant these designs first printed "the panel is being balanced by
    * dropping them" and then refused, announcing a balancing that decided
    * nothing because nothing was estimated; R validates and stops before it
    * ever balances. One case changes class as a result: a design that both
    * violates one of these AND balances down to zero observations used to
    * report the empty-sample message and exit 2000, and now refuses 459 --
    * which is the R order, since R never reaches its own balancing step.
    *
    * The at-least-two-units refusal is deliberately NOT here. It reads the
    * LAST scan, because it describes the sample that will actually be
    * estimated, and a design balanced down to one unit has to refuse.
    local raw_shape_gvary = 0
    local raw_shape_cvary = 0
    local raw_shape_dup = 0
    capture {
        local raw_shape_gvary = __csdid_ps_shape_gvary
        local raw_shape_cvary = __csdid_ps_shape_cvary
        local raw_shape_dup = __csdid_ps_shape_dup
    }
    * -------------------------------------------------------------------
    * The scan above reads `touse', which by now has lost the rows with a
    * missing outcome, covariate or weight -- and R removes those only
    * AFTER validate_args, in did_standardization. So a violation carried
    * by a row that only csdid has dropped went unrefused: a duplicated
    * (id, time) whose second copy has a missing outcome, a missing weight,
    * a missing covariate or a missing gvar, a cohort reversal on the row
    * with the missing covariate, and a cluster that is present in one
    * period and missing in another all estimated here and stopped in R.
    * csdid_shapescan re-decides the three flags on the sample as it stood
    * before the screen, under R's own per-check screens, which are not the
    * same screen for the three (see the routine's header).
    *
    * The three flags can only go from 0 to 1: that sample is a superset of
    * `touse', so every violation the scan above found is still a violation
    * here, and the pass is taken only when it can change an answer -- when
    * the screen actually removed a row. `mark' rather than `touse_initial'
    * because marksample screens missing WEIGHTS even under -zeroweight-,
    * and R does not; `mark' with no weight is the if/in sample alone, which
    * is what R is handed. Runs on complete data pay one macro comparison.
    * -------------------------------------------------------------------
    local shape_widen = ("`ivar'" != "" & `n_screened' > 0)
    if "`ivar'" != "" & !`shape_widen' & "`wvar'" != "" {
        quietly count if missing(`wvar')
        local shape_widen = (r(N) > 0)
    }
    if `shape_widen' {
        tempvar touse_raw
        mark `touse_raw' `if' `in'
        capture mata: csdid_shapescan("`ivar'", "`time'", "`gvar'", "`cluster'", "`touse_raw'")
        if _rc {
            local shapescan_rc = _rc
            display as error "csdid could not scan the estimation sample (Mata rc `shapescan_rc'); the data may be degenerate"
            exit `shapescan_rc'
        }
        if __csdid_sh_gvary == 1 local raw_shape_gvary = 1
        if __csdid_sh_cvary == 1 local raw_shape_cvary = 1
        if __csdid_sh_dup == 1 local raw_shape_dup = 1
        capture scalar drop __csdid_sh_gvary __csdid_sh_cvary __csdid_sh_dup
    }
    * Wording and rc are the estimation kernel's own; see the kernel-refusal note
    * below for why the kernel's copies are hoisted in front of it rather than
    * left to fire from inside a Mata frame.
    *
    * The ORDER is R's, and it is not the kernel's. R asks in one sequence --
    * irreversible gvar, then duplicate (id, time), then time-varying cluster
    * (pre_process_did2.R:74, :81, :104) -- while the kernel raises whichever
    * of the three its single layout pass reaches first, which puts cluster
    * ahead of duplicates. A design that breaks two rules at once then gets a
    * different diagnosis from each: measured on a panel that both duplicates
    * a row and moves a unit's cluster, R names the duplicate and csdid named
    * the cluster. Both refuse either way; only the sentence the user is asked
    * to act on differs, and it should be R's. The kernel keeps its own order
    * because there the three are decided inside one pass over the rows, and
    * because the checks here now read a SUPERSET of the kernel's sample, so
    * on the panel path the kernel's copies no longer decide anything.
    if "`ivar'" != "" {
        if `raw_shape_gvary' == 1 {
            display as error "gvar() must be time-invariant within ivar(); treatment timing must be irreversible"
            exit 459
        }
        if `raw_shape_dup' == 1 {
            display as error "The value of ivar() must be unique within time(). Some units are observed more than once in a period."
            exit 459
        }
        if `raw_shape_cvary' == 1 {
            display as error "cluster() must be time-invariant within ivar()"
            exit 459
        }
    }
    if `want_bal' {
        * the settled grid, not the raw one: with no never-treated group the
        * kernel deletes the periods at or beyond latest_g - anticipation, and
        * R balances on what survives that deletion (pre_process_did.R:263/:270
        * then :437-446), so a unit missing only a deleted period is kept.
        local bal_T = __csdid_ps_baltime
        local balance_dropped_units = __csdid_ps_incunits
        if "`xdrop_bal_units'" == "" local xdrop_bal_units 0
        if "`xdrop_bal_obs'" == "" local xdrop_bal_obs 0
        * Units the covariate screen removed whole never reach the balance
        * scan, but R counts them in ITS balance message when they still had
        * complete rows -- so they join the announcement here, and the
        * announcement fires even when the scan itself found nothing left to
        * drop. The drop mechanics below still run only on the scan's count.
        if `balance_dropped_units' == 0 & `xdrop_bal_units' > 0 {
            local xdrop_bal_all = `xdrop_bal_units'
            display as error "warning: `xdrop_bal_all' unit(s) are not observed in all `bal_T' periods; the panel is being balanced by dropping them (`xdrop_bal_obs' observation(s)). Use bal(none) to keep every unit, or bal(pair) to balance each 2×2 separately."
        }
        if `balance_dropped_units' > 0 {
            * The announced count is not the marked count. A unit whose every
            * row lies at or beyond the cutoff is removed by R's period filter
            * before uid/n.old are formed (pre_process_did.R:263/:270 then
            * :437-446), so R never announces it as a balance drop; csdid still
            * marks it, which the kernel's own cutoff makes numerically
            * irrelevant. Say what R says.
            local balance_announced_units = __csdid_ps_balunits + `xdrop_bal_units'
            local balance_dropped_obs = __csdid_ps_balobs + `xdrop_bal_obs'
            * "as error" is a DISPLAY STYLE here, not an error: it is the only
            * channel Stata does not suppress under `quietly csdid ...'.
            * Verified: `noisily display' inside a program does NOT survive a
            * caller's quietly, but error-styled output does. This warning has
            * to survive, because the sample just changed and the estimand with
            * it -- a scripted run that silently drops units leaves no trace of
            * why N moved. csdid Version 1.82 used the same channel
            * ("display in red \"Panel is not balanced\"").
            if `balance_announced_units' > 0 {
                display as error "warning: `balance_announced_units' unit(s) are not observed in all `bal_T' periods; the panel is being balanced by dropping them (`balance_dropped_obs' observation(s)). Use bal(none) to keep every unit, or bal(pair) to balance each 2×2 separately."
            }
            quietly replace `touse' = 0 if `bal_drop'
            quietly count if `touse'
            if r(N) == 0 {
                display as error "balancing the panel left no observations: no unit is observed in all `bal_T' periods. Specify bal(none) to keep every unit. Consider also whether these are really an unbalanced panel or a repeated cross section -- for repeated cross sections omit ivar(), since each observation is its own unit."
                exit 2000
            }
            local sample_N = r(N)
            * ---------------------------------------------------------------
            * R parity, refusal ORDER: R did 2.5.1 pre_process_did.R balances
            * the panel first (the keep_bal filter around line 430) and only
            * THEN computes group sizes and raises the small-group warning and
            * the never-treated-too-small stop -- its own comment at line 527
            * reads "more error handling after we have balanced the panel".
            * csdid measured the groups in the prescan above, i.e. BEFORE this
            * drop. Balancing only removes rows, so every group size was
            * overstated and both refusals fired strictly less often than R's:
            * on the same unbalanced panel R stopped and csdid estimated.
            *
            * Re-scan the reduced sample. Everything the scan produces is then
            * a description of the sample that will actually be estimated: the
            * group-size warning list (1112-1125), the never-treated-too-small
            * stop (1126-1131), the no-never-treated fallback warning
            * (1132-1137) and the No-valid-groups refusal (1080-1086). It is
            * one extra pass, taken only when balancing actually dropped a
            * unit.
            *
            * Residual, deliberately not closed here, and measured rather than
            * assumed: R applies two further transformations before it measures
            * -- the no-never-treated period filter with its tlist recompute,
            * and the first-period-treated unit drop -- which this scan does not
            * model. What that costs is the composition of the display-only
            * warning LIST, and nothing else.
            *
            * Both causes push the SAME way, so the list csdid prints is R's
            * list plus extras, never fewer: a cohort R has already dropped is
            * still counted here, and on an unbalanced panel the denominator is
            * the full period count where R's is the reduced one, which makes
            * every cohort look smaller. Measured against did 2.5.1 on four
            * designs with no never-treated group: R warns about nothing and
            * csdid names cohort 1 (balanced, four units treated in the first
            * period), R warns about nothing and csdid names cohorts 1 and 2
            * (the same design with one unit missing its last period), R names
            * cohort 0 and csdid names 0 and 1 (a small never-treated group
            * alongside first-period-treated units).
            *
            * The REFUSALS that read the same measurement do not drift, and the
            * reason is structural rather than lucky. never_small can only fire
            * when a never-treated group exists, and R deletes periods only
            * when one does NOT, so on every design that can reach the refusal
            * R's denominator is this one; dropping first-period-treated units
            * removes no period and no group-0 row. The third design above
            * confirms it -- both stop with r(459) -- and the kernel re-raises
            * the same refusal on the fully final sample anyway
            * (src/mata/csdid.mata, csdid_basic_attgt).
            *
            * Modelling the two transformations here would put the kernel's own
            * settling logic in a second place that can drift from it, to move
            * one warning list. It is recorded rather than attempted.
            * ---------------------------------------------------------------
            capture mata: csdid__prescan("`ivar'", "`time'", "`gvar'", "`cluster'", "`touse'", `anticipation', 0, "`bal_drop'", "`ps_gcounts'")
            if _rc {
                local prescan_rc = _rc
                display as error "csdid could not scan the estimation sample (Mata rc `prescan_rc'); the data may be degenerate"
                exit `prescan_rc'
            }
        }
    }
    * ---------------------------------------------------------------------
    * The all-zero screen on the fvrevar-expanded dummies ran against `touse'
    * as it stood BEFORE two sample reductions that can empty a surviving
    * dummy: the covariate-missingness unit drop above, and the bal(full)
    * drop just above that. A level of i.state whose only units are dropped
    * therefore left an identically-zero column in the covariate list, which
    * reaches the 2x2 regressions as an exactly collinear regressor and blanks
    * cells with a per-cell "singular or numerically ill-conditioned" warning
    * -- where R, which builds its model matrix on the already-reduced data,
    * simply never creates the column and estimates normally.
    *
    * Re-run the screen here, where `touse' is final. Only fvrevar's own
    * generated columns (`__' prefix) are screened, exactly as before: a
    * user-supplied variable that happens to be all zero is the user's to
    * keep.
    *
    * fvrevar also chose the BASE level against the pre-drop sample. If the
    * drops empty the base level instead of a non-base one, the surviving
    * dummies partition the final sample and are exactly collinear with the
    * intercept the kernel prepends -- which no all-zero screen can see,
    * because no single column is all zero. Measured (cold-audit F1,
    * differential 2026-08-25): R estimated every cell of such a design with
    * real numbers while csdid returned rc 0 with every substantive ATT(g,t)
    * silently missing. So the WHOLE expansion is rebuilt here, against the
    * final sample -- exactly what R does by building its model matrix on
    * the already-reduced data: fvrevar picks the base from the levels that
    * actually remain, empty levels never become columns, and on a sample
    * the drops did not change it returns the same columns and base as
    * before, so nothing moves anywhere else. The all-zero screen then runs
    * on the fresh columns, unchanged: only fvrevar's own `__' dummies are
    * screened; a user-supplied all-zero variable is the user's to keep.
    * ---------------------------------------------------------------------
    if `"`xvars'"' != "" & `"`xvars_expanded'"' != "" {
        * An EXPLICITLY pinned base (ib#.) whose level has no observations
        * left in the final sample cannot be rebuilt around: the user chose
        * that reference, and estimating against a different one behind
        * their back is a different regression. The reference implementation
        * errors on an absent reference level; csdid refuses by name
        * (cold-audit round 5, F3 -- measured: the swallowed rebuild left
        * the stale partition and six of eight cells silently missing).
        capture quietly fvexpand `xvars' if `touse'
        if _rc == 0 {
            foreach fvterm in `r(varlist)' {
                foreach fvpart in `: subinstr local fvterm "#" " ", all' {
                    if regexm("`fvpart'", "^([0-9]+)b\.(.+)$") {
                        local fvlev = regexs(1)
                        local fvvar = regexs(2)
                        quietly count if `touse' & `fvvar' == `fvlev'
                        if r(N) == 0 {
                            display as error "the base category `fvlev' of factor covariate `fvvar' has no observations left in the final estimation sample (the covariate screening or the panel-balance requirement removed all of them). Choose a base that survives with ib#.`fvvar', or let Stata pick one with i.`fvvar'."
                            exit 459
                        }
                    }
                }
            }
        }
        capture quietly fvrevar `xvars' if `touse'
        if _rc == 0 {
            local xvars_expanded "`r(varlist)'"
        }
        local xvars_rescreened ""
        foreach xv of local xvars_expanded {
            if substr("`xv'", 1, 2) == "__" {
                quietly summarize `xv' if `touse', meanonly
                if r(N) > 0 & r(min) == 0 & r(max) == 0 {
                    continue
                }
            }
            local xvars_rescreened "`xvars_rescreened' `xv'"
        }
        local xvars_expanded "`xvars_rescreened'"
    }

    * -----------------------------------------------------------------------
    * csdid_basic_attgt() was the one kernel in this file
    * still reached with nothing between it and the user, so its data-shape
    * refusals arrived with two lines of Mata frames stapled underneath:
    *     csdid_basic_attgt():  459  Stata returned error
    *                <istmt>:     -  function returned error
    * The sibling kernels in csdid_stats.ado suppress those frames by calling
    * the kernel under a PLAIN -capture- (measured in Stata 17: -capture
    * noisily- still prints the traceback log) and re-raising the diagnosis
    * from the ado. That form is not available here, because
    * csdid_basic_attgt() also prints the per-cell warnings of a SUCCESSFUL
    * run - "Error computing internal 2x2 DiD", "overlap condition violated
    * for group", "singular or numerically ill-conditioned" - which
    * test-f011, test_percell_failure and test-overlap-guard-cache count in
    * the log; a plain -capture- would swallow those too.
    * The equivalent effect is obtained by hoisting the kernel's own
    * structural checks in front of the call, with the kernel's exact wording
    * and its rc 459. The kernel keeps its copies as the backstop - they are
    * simply no longer reachable for these shapes, so no traceback is
    * produced. All four are panel-only, exactly as the kernel guards them
    * (`idname != ""'), and three of the four have moved further forward
    * still, to the first scan above: R decides them in validate_args, ahead
    * of anything else this file does with the sample. Only the unit COUNT is
    * left here, because it is the one that has to describe the FINAL sample.
    * The kernel tests the count first and the violations after it; forward of
    * the balance block that order reverses, which is R's -- a design that is
    * both down to one unit and shape-violating reports the violation, as
    * validate_args does.
    *
    * The checks are counted in Mata rather than with by-group Stata commands
    * ON PURPOSE. -bysort-/-egen, by()- would reorder the caller's data, and
    * although `sortpreserve' restores that at exit, the KERNEL would have run
    * against the reordered rows in between - and the fast-path detector keys
    * off exactly that layout, so an unsorted dataset could silently switch
    * e(compute_path) from "baseline" to "fast-balanced-panel". Counting
    * distinct rows in Mata reads the data and mutates nothing. If any of it
    * fails the block is abandoned and the kernel's own copy of the check
    * still fires, so a defect here can never turn a working run into a
    * refusal.
    * -----------------------------------------------------------------------
    if "`ivar'" != "" {
        tempname eux_nunit
        scalar `eux_nunit' = .
        * csdid__prescan computes the count while it is already reading id,
        * time, gvar and cluster, and this block only reads the answer back --
        * a pass of its own measured 0.19s of a 0.79s run on 600,000 rows. It
        * comes from the LAST scan, because it describes the sample that will
        * be estimated and a design balanced down to one unit has to refuse.
        * It does not describe the sample the kernel finally settles on, which
        * drops more.
        capture scalar `eux_nunit' = __csdid_ps_shape_nunit
        if scalar(`eux_nunit') == 1 {
            display as error "ivar() identifies only one unit in the estimation sample; csdid needs at least two units (a treated unit and a comparison unit) to form a 2x2 comparison. Check that ivar() names the panel identifier and is not constant."
            exit 459
        }
    }
    local diagnostics_noisy = c(noisily)
    * F-010 (repaired): the no-valid-groups guard below must fire under
    * `quietly csdid ...' too, so the sample statistics it needs are hoisted
    * out of the c(noisily) gate and computed unconditionally. Every hoisted
    * command is quietly-run and side-effect free apart from the `gsmall'
    * tempvar and r(): no sort, no observation changes. The noisy-only
    * diagnostics below reuse them, so noisy runs do no duplicated work.
    local min_time = __csdid_ps_tmin
    * the ATT(g,t) coefficient names are built literally from the g, t and
    * base-period VALUES (g2004___2005_2003). A time axis in epoch seconds
    * once produced a 35-character name and died deep in `matrix colnames'
    * with a bare "invalid name" r(198), and an entry refusal stood here
    * telling the user to rescale -- while R's did estimates those datasets
    * and the help documents the att_# posting fallback as public contract.
    * The refusal is GONE (cold-audit round 8a, F1): the posting site names
    * any cell whose literal name would be overlong, duplicated, or invalid
    * as att_#, keeps the true (g, t, base) values in e(attgt), and announces
    * how many cells were renamed. Estimation, aggregation, and inference
    * never depended on the labels.
    local never_count = __csdid_ps_never
    * F-010 fix (DEC-021): when NO cohort can be estimated the run previously
    * fell through to the estimation kernel, which died with a silent rc=111
    * ("variable not found") from an unguarded `confirm matrix'. A cohort is
    * USABLE when it has a base period (g - anticipation > first period, the
    * same condition as the first-period-treated drop below); with no
    * never-treated units the fallback additionally consumes the LATEST cohort
    * as the control group. Zero usable cohorts -> refuse up front with R's
    * diagnostic ("No valid groups.") and a data-error code. Both silent-111
    * shapes are covered: all-one-cohort (S4757) and anticipation-eats-every-
    * base-period (S192 family).
    local __treated_levels "`__csdid_ps_glevels'"
    local __n_treated : word count `__treated_levels'
    local __n_usable 0
    local __gmax_usable 0
    foreach __gv of local __treated_levels {
        if `__gv' - `anticipation' > `min_time' {
            local ++__n_usable
            local __gmax_usable = `__gv'
        }
    }
    if `never_count' == 0 & `__n_usable' > 0 {
        local __glast : word `__n_treated' of `__treated_levels'
        if `__glast' == `__gmax_usable' {
            local __n_usable = `__n_usable' - 1
        }
    }
    if `__n_usable' <= 0 {
        display as error "No valid groups. The variable in gvar() should be the time period a unit is first treated (0 for never-treated); no treated cohort has both a usable base period and a comparison group under the requested anticipation and comparison-group settings."
        * Pre-kernel refusal: nothing has been estimated, so whatever
        * estimation results were already in memory stay posted -- the
        * refusal doctrine this file follows everywhere (measured: e(cmd)
        * still names the prior estimator after this exit).
        exit 459
    }
    * F-014 R parity: group size is ROWS / n_periods (R's average units per
    * period), not the number of distinct units. Verified against R did 2.5.1
    * `pre_process_did':
    *     gcnt  <- tabulate(match(data[[gname]], gvals))   # rows per group
    *     gsize <- gcnt / length(tlist)                    # rows / n_periods
    *     reqsize <- length(rhs_vars(xformla)) + 5
    * The two metrics agree on balanced panels and diverge on unbalanced ones,
    * where rows/n_periods is strictly smaller, so R refuses sooner. Witness:
    * tests/fixtures/parity/f017 has 5 distinct units but 4.75 rows/period per
    * group against reqsize 5 - R stops, the distinct-unit metric estimated.
    *
    * This block is computed and the refusal raised UNCONDITIONALLY. R's
    * warning()/stop() are not gated on verbosity, and control flow must never
    * depend on `quietly' (the same defect class as the F-010 guard above);
    * only the DISPLAY of the warnings stays inside the noisy gate.
    local csdid_time_levels "`__csdid_ps_tlevels'"
    local n_time : word count `csdid_time_levels'
    * The count is of the covariates the USER NAMED, which is what R counts:
    * rhs_vars() reads the formula, not the design matrix, so i.state is one
    * covariate to it however many indicators it becomes. `xvars_expanded' is
    * the expanded design and is deliberately not used here. This same reqsize
    * is handed to the kernel, whose own never-treated guard used to rebuild it
    * from the expanded column count and so demanded a larger never-treated
    * group than R on every factor-variable model.
    local nx_req : word count `xvars'
    local reqsize = `nx_req' + 5
    local small_groups ""
    local never_small 0
    * F-014: group sizes from ONE sorted pass rather than `levelsof' plus a
    * `count if' per level (a sort plus one full data pass per group).
    tempname gcounts
    matrix `gcounts' = `ps_gcounts'
    forvalues __gi = 1/`=rowsof(`gcounts')' {
        local gv = `gcounts'[`__gi', 1]
        local group_units = `gcounts'[`__gi', 2] / `n_time'
        if `group_units' < `reqsize' {
            local gtxt : display %21.0g `gv'
            local gtxt = strtrim("`gtxt'")
            local small_groups "`small_groups'`=cond("`small_groups'" == "", "", ",")'`gtxt'"
            if `gv' == 0 local never_small 1
        }
    }
    if "`small_groups'" != "" & `diagnostics_noisy' {
        display as text "warning: Some groups in your dataset have very few observations, which may cause estimation problems."
        display as text "  Check groups: `small_groups'."
    }
    if "`small_groups'" != "" & `never_small' & "`notyet'" == "" {
        display as error "The never-treated group is too small to serve as a reliable comparison group. Try specifying notyet to include not-yet-treated units in the comparison group."
        * Pre-kernel refusal: as at the No-valid-groups stop above, whatever
        * estimation results were already in memory stay posted.
        exit 459
    }
    * Both of these announce a change to the SAMPLE or the ESTIMAND, so they
    * follow the rule stated at the bal() drop above: error-styled, which is
    * the one channel a caller's `quietly' does not suppress, and ungated. R
    * raises both through warning(), which is not suppressible either.
    * Previously they were doubly hidden -- `as text' AND gated on
    * diagnostics_noisy -- so under `quietly csdid ...' the comparison group
    * silently became the latest treated cohort, or a set of units silently
    * left the sample, with nothing said.
    *
    * The small-group warning above is deliberately NOT changed: it is
    * advisory and changes neither the sample nor the estimand, and the noisy
    * gate there is a decision already recorded in the comment above it.
    if `never_count' == 0 & "`notyet'" == "" {
        if `__n_treated' > 0 {
            display as error "warning: No never-treated group available; using the latest treated cohort as never-treated, and dropping periods after it (no comparison group is available there)."
        }
    }
    * The count is the point of this line. "Units treated in the first period
    * are dropped" left the reader to work out how many, from an N that had
    * already moved for other reasons; a number turns it into something that
    * can be checked against the data. It is a UNIT count and it is the count
    * the announcing rule uses (see csdid__prescan): rows whose cohort is at or
    * before the first usable period are still dropped, but a unit the
    * fallback's period filter has already removed is not announced, because it
    * was never part of the sample the message describes.
    if __csdid_ps_firstunits > 0 {
        local firstper_note ""
        if `anticipation' > 0 local firstper_note " (accounting for anticipation = `anticipation')"
        display as error "warning: dropped `=__csdid_ps_firstunits' unit(s) already treated in the first period`firstper_note'."
    }
    * csdid__prescan returns its scalar outputs through GLOBAL Stata scalars,
    * and nothing dropped them: every csdid run left them standing in the
    * user's session. This is the last read of any of them; the Wald block
    * below ends the same way. The list below is the whole set the prescan
    * writes -- keep it in step with the st_numscalar() calls in
    * csdid__prescan, which is the only thing that writes them.
    capture scalar drop __csdid_ps_tmin __csdid_ps_tmax __csdid_ps_gmin ///
        __csdid_ps_gmax __csdid_ps_baltime __csdid_ps_never ///
        __csdid_ps_firstunits __csdid_ps_nunits __csdid_ps_incunits ///
        __csdid_ps_incobs __csdid_ps_balunits __csdid_ps_balobs ///
        __csdid_ps_shape_nunit __csdid_ps_shape_gvary ///
        __csdid_ps_shape_cvary __csdid_ps_shape_dup

    local fast_requested = ("`fast'" != "")
    local fast_auto = ("`fast_mode'" == "auto")
    local fast_allowed = ("`fast_mode'" != "off")
    * Storage policy, unified: lean at every sample size. e() carries the
    * estimation contract; the one-row-per-unit objects - influence
    * functions, unit map, cluster vector - stay in the Mata engine, the
    * same way official commands keep unit-level quantities out of e() and
    * provide them on demand. Posting them as Stata matrices costs quadratic
    * time in n_units per write or copy (measured: 4s at 25k rows, 145s at
    * 100k), holds every one of them in memory twice, and - the decisive
    * defect - made the stored-results contract depend on sample size: the
    * old auto rule posted the matrices below 25,000 observations and not
    * above, so the same do-file stored different objects on a subsample
    * than on the full data. storeall is the single explicit opt-in that
    * materializes them; saverif() writes the durable artifact and works
    * under lean storage, because the exporter reads the engine cache.
    local store_large = ("`performance_mode'" == "full")
    local performance_resolved = cond(`store_large', "full", "lean")

    tempname attgt inffunc group_prob unit_group cluster_vec nclusters fast_used panel_balanced panel_ntime cache_token profile bootstrap_profile bootstrap_kernel_profile
    * The kernel writes the settled estimation sample here: touse minus the two
    * drops only it models -- the periods the no-never-treated fallback removes,
    * and the units treated at or before the first usable period. e(N) and
    * e(sample) are taken from this rather than from touse, so that the count,
    * the marker and e(N_units) describe one sample instead of three.
    tempvar use_mark
    quietly generate byte `use_mark' = 0
    capture noisily mata: csdid_basic_attgt("`yname'", "`time'", "`gvar'", "`ivar'", "`xvars_expanded'", "`wvar'", "`method'", "`touse'", "`cluster'", "`notyet'", "`base_period'", "`balance_mode'", "`fix_weights'", `anticipation', `pscoretrim', `reqsize', `fast_allowed', "`fast_used'", "`panel_balanced'", "`panel_ntime'", `store_large', "`attgt'", "`inffunc'", "`group_prob'", "`unit_group'", "`cache_token'", "`use_mark'")
    local csdid_rc = _rc
    if `csdid_rc' {
        ereturn clear
        exit `csdid_rc'
    }
    * From here on, the estimation sample is what the kernel actually used.
    * Falls back to the touse count only if the marker is unusable, which would
    * mean the kernel returned without writing it.
    quietly count if `use_mark'
    if r(N) > 0 {
        local sample_N = r(N)
        quietly replace `touse' = 0 if !`use_mark'
    }
    foreach required_matrix in `attgt' `group_prob' {
        capture confirm matrix `required_matrix'
        local csdid_rc = _rc
        if `csdid_rc' {
            ereturn clear
            exit `csdid_rc'
        }
    }
    if `store_large' {
        foreach required_matrix in `inffunc' `unit_group' {
            capture confirm matrix `required_matrix'
            local csdid_rc = _rc
            if `csdid_rc' {
                ereturn clear
                exit `csdid_rc'
            }
        }
    }
    if "`cluster'" != "" {
        capture noisily mata: csdid_cluster_attgt("`cluster'", "`ivar'", "`touse'", "`attgt'", "`inffunc'", "`unit_group'", "`nclusters'", `store_large', "`cluster_vec'")
        local csdid_rc = _rc
        if `csdid_rc' {
            ereturn clear
            exit `csdid_rc'
        }
    }
    local bootstrap_accelerator "none"
    local bootstrap_accelerator_status "not-requested"
    local bootstrap_accelerator_file ""
    local bootstrap_accelerator_rc 0
    if `bstrap' {
        * (the Stata 14/15 matsize refusal runs at option-resolution time,
        * near the top of this program, before anything is estimated)
        tempname boot_attgt boot_draws boot_crit boot_pointcrit boot_rng_state
        local boot_rng_arg ""
        if "`boot_seed'" != "" {
            mata: st_matrix("`boot_rng_state'", csdid__bmisc_rng_init(`boot_seed'))
            local boot_rng_arg "`boot_rng_state'"
        }
        local boot_time ""
        if "`ivar'" == "" local boot_time "`time'"
        local boot_cluster_arg ""
        if "`cluster'" != "" local boot_cluster_arg "`cluster_vec'"

        local bootstrap_accelerator "mata"
        local bootstrap_accelerator_status "mata-unseeded"
        local plugin_loaded 0
        local plugin_success 0
        if "$CSDID_BOOT_PLUGIN_DISABLE" == "1" {
            local bootstrap_accelerator_status "mata-plugin-disabled"
        }
        else if "`boot_rng_arg'" != "" & "`boot_dist'" == "rademacher" {
            local bootstrap_accelerator_status "mata-plugin-unavailable"
            capture quietly findfile csdid.ado
            if !_rc {
                local csdid_ado_path "`r(fn)'"
                local bootstrap_plugin_file "csdid_bootstrap_unix.plugin"
                local bootstrap_machine = lower("`c(machine_type)'")
                local bootstrap_os = lower("`c(os)'")
                if strpos("`bootstrap_machine'", "mac") > 0 {
                    local bootstrap_plugin_file "csdid_bootstrap_macosx.plugin"
                }
                else if "`bootstrap_os'" == "windows" {
                    local bootstrap_plugin_file "csdid_bootstrap_windows.plugin"
                }
                * The plugin sits beside the resolved csdid.ado. The resolved
                * path always ends with the nine bytes `csdid.ado', so the
                * sibling is a substr, never a substring REPLACEMENT: a
                * directory component that happens to contain the text
                * `csdid.ado' must not be rewritten into a path that does not
                * exist (which would park the accelerator as unavailable with
                * nothing said).
                local _bp_len = strlen("`csdid_ado_path'")
                local bootstrap_plugin_dir ""
                if `_bp_len' > 9 & substr("`csdid_ado_path'", `_bp_len' - 8, .) == "csdid.ado" {
                    local bootstrap_plugin_dir = substr("`csdid_ado_path'", 1, `_bp_len' - 9)
                }
                local bootstrap_plugin_path "`bootstrap_plugin_dir'`bootstrap_plugin_file'"
                capture confirm file "`bootstrap_plugin_path'"
                if _rc {
                    local bootstrap_plugin_file "csdid_bootstrap.plugin"
                    local bootstrap_plugin_path "`bootstrap_plugin_dir'`bootstrap_plugin_file'"
                    capture confirm file "`bootstrap_plugin_path'"
                }
                if !_rc {
                    * A plugin handle is not observable: `program list' on a
                    * bound plugin reports not-found (measured, r(111) always),
                    * so the record of the last successful bind -- the path
                    * global, set only on a bind that returned 0 -- IS the
                    * aliveness check, and `csdid reset' is what clears it. A
                    * bind against a handle that already exists returns rc 110
                    * WITHOUT re-reading the file, so 110 is never accepted as
                    * a load: on a fresh bind it is a failure to report, and
                    * on a moved installation it means the session holds an
                    * image it cannot release, which is said in e() rather
                    * than guessed around -- results still arrive, from Mata.
                    * A binary REPLACED at the same path in a live session is
                    * not detectable here at all; `csdid reset' names the
                    * restart that makes it certain.
                    local bootstrap_plugin_program "__csdid_bootstrap_plugin"
                    if "$CSDID_BOOT_PLUGIN_PATH" == "`bootstrap_plugin_path'" {
                        local plugin_loaded 1
                        local bootstrap_accelerator_file "`bootstrap_plugin_file'"
                    }
                    if !`plugin_loaded' {
                        capture program drop `bootstrap_plugin_program'
                        capture program `bootstrap_plugin_program', plugin using("`bootstrap_plugin_path'")
                        local plugin_bind_rc = _rc
                        if `plugin_bind_rc' == 0 {
                            global CSDID_BOOT_PLUGIN_PATH "`bootstrap_plugin_path'"
                            local plugin_loaded 1
                            local bootstrap_accelerator_file "`bootstrap_plugin_file'"
                        }
                        else if `plugin_bind_rc' == 110 & "$CSDID_BOOT_PLUGIN_PATH" != "" {
                            local bootstrap_accelerator_status "mata-stale-plugin-binding"
                            local bootstrap_accelerator_rc = 110
                        }
                        else {
                            local bootstrap_accelerator_status "mata-plugin-load-failed"
                            local bootstrap_accelerator_rc = `plugin_bind_rc'
                        }
                    }
                }
            }
        }

        if `plugin_loaded' {
            tempname plugin_draws plugin_n plugin_nc plugin_cluster plugin_started boot_rng_backup boot_att_backup
            matrix `boot_rng_backup' = `boot_rng_state'
            matrix `boot_att_backup' = `attgt'
            local plugin_rc 0
            local plugin_if_vars ""
            local plugin_k = rowsof(`attgt')

            * #6. These scratch variables carry the influence functions to the
            * plugin, which reads `in 1/nc' -- one row per unit, or per cluster
            * when clustering. Stata variables span the whole dataset, so on a
            * panel the other rows are allocated and never touched: measured on
            * 600,000 rows, 60,000 units and 40 cells, 183.1MB allocated for
            * 18.3MB of data, and 0.140s just to create them.
            *
            * The dataset is therefore trimmed to the rows the plugin reads for
            * the duration of the call. That is safe precisely here: the only
            * thing the preparation step reads from the DATA is the time
            * variable, at original row positions, and it does that only when
            * ivar() is absent -- i.e. under repeated cross sections, where
            * every row is its own unit and nc is already the whole dataset, so
            * nothing is trimmed. The wasteful case and the data-reading case
            * are disjoint.
            *
            * Everything else the call touches is a matrix or a Mata global,
            * both of which preserve/restore leaves alone. If the row count
            * guessed here were ever too small the store would fail, plugin_rc
            * would be set, and the run would fall back to the Mata bootstrap
            * with identical results -- a slow path, not a wrong one.
            *
            * Two other routes were measured and rejected. The plugin's matrix
            * input task would need an nc x k Stata matrix, and st_matrix() is
            * quadratic in rows: 0.015s at 2,000 rows, 0.328s at 10,000, 3.0s
            * at 30,000, against a flat 0.003s for st_store(). Batching the
            * columns would work -- the multiplier draw depends on the
            * replication and the row, not the column, so resetting the state
            * per batch reproduces it -- but it rewrites the seeded bootstrap
            * for less benefit than this.
            local plugin_rows = `group_prob'[1, 3]
            if "`cluster'" != "" local plugin_rows = scalar(`nclusters')
            preserve
            if `plugin_rows' < _N & "`boot_time'" == "" {
                quietly keep in 1/`plugin_rows'
            }
            forvalues plugin_col = 1/`plugin_k' {
                tempvar plugin_if_var
                capture generate double `plugin_if_var' = .
                if _rc local plugin_rc = _rc
                local plugin_if_vars "`plugin_if_vars' `plugin_if_var'"
            }
            * Break is not a plugin failure. Every capture below funnels its
            * rc into `plugin_rc', and rc 1 is the user pressing Break: left
            * unexamined it is classified by the else-branch as
            * `mata-plugin-failed', the RNG and ATT backups are restored and
            * the whole bootstrap is recomputed on the slower Mata path --
            * so the interrupt makes the run LONGER, the user has to press
            * Break a second time, and a run that finishes reports a broken
            * accelerator in e(bootstrap_accelerator_status) when nothing
            * was broken. Same guard, same wording, as the four in
            * csdid_stats.ado, which carries the aggregation-stage copy of
            * this block. The user's data comes back either way: this branch
            * runs under the preserve above, and Stata unwinds a preserve
            * when a program exits, on rc 1 as on any other (measured).
            if !`plugin_rc' {
                capture mata: csdid_boot_plugin_prepare("`attgt'", "`inffunc'", "`unit_group'", "`boot_time'", "`boot_cluster_arg'", "`plugin_if_vars'", "`plugin_n'", "`plugin_nc'", "`plugin_cluster'", "`plugin_started'")
                local plugin_rc = _rc
                if `plugin_rc' == 1 exit 1
            }
            if !`plugin_rc' {
                capture matrix `plugin_draws' = J(`biters', rowsof(`attgt'), .)
                local plugin_rc = _rc
                if `plugin_rc' == 1 exit 1
            }
            if !`plugin_rc' {
                local plugin_nc_value : display %21.0f scalar(`plugin_nc')
                local plugin_nc_value = strtrim("`plugin_nc_value'")
                capture plugin call `bootstrap_plugin_program' `plugin_if_vars' in 1/`plugin_nc_value', bootstrap_vars `biters' `plugin_nc_value' `plugin_draws' `boot_rng_state'
                local plugin_rc = _rc
                if `plugin_rc' == 1 exit 1
            }
            if !`plugin_rc' {
                capture mata: csdid_boot_plugin_record("`plugin_started'", st_numscalar("`plugin_nc'"), `biters')
                local plugin_rc = _rc
                if `plugin_rc' == 1 exit 1
                if !`plugin_rc' {
                    capture mata: csdid_boot_plugin_finish("`attgt'", "`plugin_draws'", st_numscalar("`plugin_n'"), st_numscalar("`plugin_nc'"), st_numscalar("`plugin_cluster'"), `biters', (100 - `level') / 100, `cband', "`boot_attgt'", "`boot_draws'", "`boot_crit'", "`boot_pointcrit'")
                    local plugin_rc = _rc
                    if `plugin_rc' == 1 exit 1
                }
            }
            if !`plugin_rc' {
                local plugin_success 1
                local bootstrap_accelerator "plugin"
                local bootstrap_accelerator_status "plugin-active"
            }
            else {
                matrix `boot_rng_state' = `boot_rng_backup'
                matrix `attgt' = `boot_att_backup'
                local bootstrap_accelerator_status "mata-plugin-failed"
                local bootstrap_accelerator_rc = `plugin_rc'
            }
            capture drop `plugin_if_vars'
            * back to the full sample; everything produced above lives in
            * matrices and Mata globals, which restore does not touch
            restore
        }

        if !`plugin_success' {
            capture noisily mata: csdid_bootstrap_attgt_fast("`attgt'", "`inffunc'", "`unit_group'", "`boot_time'", "`boot_cluster_arg'", `biters', (100 - `level') / 100, `cband', "`boot_dist'", "`boot_rng_arg'", "`boot_attgt'", "`boot_draws'", "`boot_crit'", "`boot_pointcrit'")
            local csdid_rc = _rc
            if `csdid_rc' {
                ereturn clear
                exit `csdid_rc'
            }
        }
        matrix colnames `boot_attgt' = group time event_time att se_boot se_analytic crit_val ci_low ci_high point_crit_val point_ci_low point_ci_high
        mata: st_matrix("`bootstrap_profile'", CSDID_BOOT_PROFILE)
        matrix colnames `bootstrap_profile' = seconds calls work
        matrix rownames `bootstrap_profile' = input_reorder cluster_reduce active_scan multiplier_draws summarize_cband result_post
        mata: st_matrix("`bootstrap_kernel_profile'", CSDID_BOOT_KERNEL_PROFILE)
        matrix colnames `bootstrap_kernel_profile' = seconds calls work
        matrix rownames `bootstrap_kernel_profile' = rng_twist rng_temper bit_expand reshape_trim matrix_multiply
        local bootstrap_accelerator_seconds = `bootstrap_profile'[4, 1]
    }
    mata: st_matrix("`profile'", CSDID_PROFILE)

    * base_time is the reference period each cell was differenced against. It
    * is appended, so the nine documented columns keep their positions.
    matrix colnames `attgt' = group time event_time att se n_treat_t n_treat_pre n_control_t n_control_pre base_time
    matrix colnames `group_prob' = group prob n_units
    matrix colnames `profile' = seconds calls work
    * `if_assembly' is instrumented now. It was declared and never written, so
    * e(profile) reported a flat zero for the segment that actually dominates
    * a large fit: at 600,000 repeated-cross-section units and 40 cells the
    * profiled phases accounted for 1.16s of a 3.60s run, and the assembly was
    * all of the missing two thirds.
    matrix rownames `profile' = setup cell_extract model_fit if_assembly cache_post cluster bootstrap aggregation
    if `store_large' {
        * On the two period-major sample shapes csdid_basic_attgt appends a 4th
        * unit_group column holding the period the bootstrap draws each row in:
        * the unit's first-appearance period on the allow_unbalanced path
        * (F-001/F-022, csdid__boot_order_unbal), and the observation's own -
        * first and only - period in a repeated cross section
        * (csdid__boot_order_rc), where it is what makes the draw order
        * independent of how the data are sorted after the estimation. It is
        * built inside the Mata map itself, so it reaches the full-storage
        * matrix AND the lean Mata unit-map cache with no separate augmentation
        * pass; name it here so `matrix colnames' does not error on the wider
        * matrix.
        if colsof(`unit_group') == 4 {
            matrix colnames `unit_group' = id group weight first_period
        }
        else {
            matrix colnames `unit_group' = id group weight
        }
    }
    * -----------------------------------------------------------------------
    * F-008 (R parity): Wald pre-test of the parallel-trends assumption.
    *
    * R did 2.5.1 att_gt() computes it from the ANALYTICAL influence-function
    * covariance matrix - never the bootstrap one; verified directly, R returns
    * the identical W under bstrap=TRUE and bstrap=FALSE on mpdta:
    *     V     <- t(inffunc) %*% inffunc / n     [clustered: crossprod(Sc)/n]
    *     se    <- sqrt(diag(V)/n)
    *     se[se <= sqrt(.Machine$double.eps)*10] <- NA
    *     pre   <- which(group > tt)              [minus the NA-se entries]
    *     preV  <- V[pre, pre]
    *     W     <- n * t(att[pre]) %*% solve(preV) %*% att[pre]
    *     Wpval <- round(1 - pchisq(W, length(pre)), 5)
    * with two guards ahead of the last step, in this order: any NA in preV ->
    * no statistic; rcond(preV) <= .Machine$double.eps -> no statistic.
    * summary.MP then prints
    *     P-value for pre-test of parallel trends assumption:  <Wpval>
    * on every run that produced one. Wpval is stored ROUNDED to 5 decimals in
    * R's own object, so rounding here is what makes e(wald_pvalue) equal to
    * the number R reports rather than merely close to it.
    *
    * Reference values measured against R did 2.5.1 this session:
    *     mpdta, method(dr), analytical : W = 7.7912366272,  df 5, p = 0.16812
    *     mpdta + lpop, method(dr)      : W = 6.84182498166, df 5, p = 0.23267
    *     mpdta, notyet                 : W = 7.79092771883, df 5, p = 0.16814
    *     mpdta, baseperiod(universal)  : W = 7.7912366272,  df 5, p = 0.16812
    *     mpdta, repeated cross-section : W = 0.0387610693,  df 5, p = 0.99998
    *
    * Two implementation notes:
    *  - csdid stores V/n (the variance of ATT(g,t) itself) where R stores V,
    *    so the block is multiplied back by n to keep the arithmetic - and the
    *    rcond guard's scale - identical to R's.
    *  - only the pre-treatment COLUMNS of the influence function are crossed:
    *    V[pre,pre] is a submatrix of the full covariance matrix, so this is
    *    the same arithmetic at a fraction of the cost of forming all of V.
    *  - divergence, deliberate: R declines the pre-test whenever clustering is
    *    requested beyond the unit level AND the bootstrap is on, because in
    *    that configuration R never forms a cluster-robust analytical V. csdid
    *    always forms one (it is what e(V) is built from on the clustered path
    *    either way), so the pre-test is reported there too. This can only ADD
    *    a p-value where R reports none; it never changes one R does report.
    * -----------------------------------------------------------------------
    local pre_cells 0
    local pre_valid 0
    forvalues i = 1/`=rowsof(`attgt')' {
        if `attgt'[`i', 1] > `attgt'[`i', 2] {
            local ++pre_cells
            if !missing(`attgt'[`i', 4]) & !missing(`attgt'[`i', 5]) {
                local ++pre_valid
            }
        }
    }
    local wald_available 0
    local wald_stat = .
    local wald_df 0
    local wald_pvalue = .
    local wald_state "none"
    if `pre_cells' > 0 {
        tempname wald_ready wald_clustered wald_q wald_w wald_nas wald_rcond
        scalar `wald_ready' = 0
        scalar `wald_clustered' = 0
        scalar `wald_q' = 0
        scalar `wald_nas' = 0
        scalar `wald_rcond' = .
        capture {
            mata: __csdid_wald_A = st_matrix("`attgt'")
            * Both index vectors below are built as select() over 1::rows() of
            * a mask that carries ONE appended sentinel 0. The sentinel is what
            * makes the orientation deterministic: Mata has to guess whether a
            * 1x1 or empty argument is a row or a column, and selectindex() on
            * a single pre-treatment cell guesses ROW, so an EMPTY keep-set came
            * back 1x0, rows() reported 1 surviving cell, the degenerate
            * quadratic form evaluated to exactly 0, and a run in which every
            * single ATT(g,t) had failed printed "P-value ... 1.00000" instead
            * of the missing-or-zero-variance warning (measured on the
            * fx-boundary overlap-failure fixture). Padding the mask forces
            * rows() >= 2, which removes the guess; the sentinel is never
            * selected, so the indices still address the unpadded arrays.
            mata: __csdid_wald_m = (__csdid_wald_A[., 1] :> __csdid_wald_A[., 2]) \ 0
            mata: __csdid_wald_p = select((1::rows(__csdid_wald_m)), __csdid_wald_m)
            if `store_large' {
                if rowsof(`inffunc') > 0 & colsof(`inffunc') == rowsof(`attgt') {
                    mata: __csdid_wald_S = st_matrix("`inffunc'")[., __csdid_wald_p]
                    scalar `wald_ready' = 1
                }
            }
            else {
                mata: st_numscalar("`wald_ready'", (csdid_cache_if_rows() > 0 & csdid_cache_if_cols() == rows(__csdid_wald_A)))
                if scalar(`wald_ready') {
                    mata: __csdid_wald_S = csdid_cache_if_select(__csdid_wald_p)
                }
            }
        }
        if _rc scalar `wald_ready' = 0
        if scalar(`wald_ready') & "`cluster'" != "" {
            capture {
                mata: __csdid_wald_n = rows(__csdid_wald_S)
                if `store_large' {
                    mata: __csdid_wald_C = st_matrix("`cluster_vec'")
                }
                else {
                    mata: __csdid_wald_C = csdid_cache_cluster_vec()
                }
                mata: st_numscalar("`wald_clustered'", (rows(__csdid_wald_C) == __csdid_wald_n & sum(__csdid_wald_C :>= .) == 0))
            }
            if _rc scalar `wald_clustered' = 0
        }
        if scalar(`wald_ready') {
            capture {
                mata: __csdid_wald_n = rows(__csdid_wald_S)
                * A failed (g,t) cell carries an all-missing influence-function
                * column, and quadcross drops every ROW with a missing anywhere
                * in it -- one such column and V collapses to exact zeros for
                * ALL pre-treatment cells, so the se filter below then discards
                * the healthy cells too. R restricts the pre-test to cells
                * whose influence functions are intact; the same sentinel
                * padding as above keeps the orientation deterministic.
                mata: __csdid_wald_m = (colmissing(__csdid_wald_S)' :== 0) \ 0
                mata: __csdid_wald_g = select((1::rows(__csdid_wald_m)), __csdid_wald_m)
                mata: __csdid_wald_S = __csdid_wald_S[., __csdid_wald_g]
                mata: __csdid_wald_p = __csdid_wald_p[__csdid_wald_g]
                if scalar(`wald_clustered') {
                    mata: __csdid_wald_S = csdid__cluster_sums(__csdid_wald_C, __csdid_wald_S)
                }
                mata: __csdid_wald_V = quadcross(__csdid_wald_S, __csdid_wald_S) :/ __csdid_wald_n
                mata: __csdid_wald_a = __csdid_wald_A[__csdid_wald_p, 4]
                mata: __csdid_wald_e = sqrt(diagonal(__csdid_wald_V) :/ __csdid_wald_n)
                * R drops a pre-treatment cell from the pre-test exactly when
                * its ANALYTICAL se is NA, i.e. missing or <= sqrt(eps)*10.
                * That is also what removes the identically-zero event_time=-1
                * cells under baseperiod(universal) - verified: R reports df 5
                * on mpdta under both base-period conventions.
                mata: __csdid_wald_m = ((__csdid_wald_e :< .) :& (__csdid_wald_e :> 1.4901161193847656e-07) :& (__csdid_wald_a :< .)) \ 0
                mata: __csdid_wald_k = select((1::rows(__csdid_wald_m)), __csdid_wald_m)
                mata: st_numscalar("`wald_q'", rows(__csdid_wald_k))
            }
            if _rc scalar `wald_ready' = 0
        }
        if scalar(`wald_ready') & scalar(`wald_q') > 0 {
            capture {
                mata: __csdid_wald_pV = __csdid_wald_V[__csdid_wald_k, __csdid_wald_k]
                mata: __csdid_wald_pA = __csdid_wald_a[__csdid_wald_k, 1]
                mata: st_numscalar("`wald_nas'", sum(__csdid_wald_pV :>= .))
                mata: st_numscalar("`wald_rcond'", 1 / cond(__csdid_wald_pV, 1))
            }
            if _rc scalar `wald_ready' = 0
        }
        if scalar(`wald_ready') {
            if scalar(`wald_q') == 0 {
                local wald_state "nopre"
            }
            else if scalar(`wald_nas') > 0 {
                local wald_state "na"
            }
            else if missing(scalar(`wald_rcond')) | scalar(`wald_rcond') <= c(epsdouble) {
                local wald_state "singular"
            }
            else {
                capture {
                    mata: st_numscalar("`wald_w'", __csdid_wald_n * (__csdid_wald_pA' * luinv(__csdid_wald_pV) * __csdid_wald_pA))
                }
                if !_rc & !missing(scalar(`wald_w')) {
                    local wald_stat = scalar(`wald_w')
                    local wald_df = scalar(`wald_q')
                    * chi2tail() is the accurate form of R's 1 - pchisq(); the
                    * two agree to machine precision wherever the p-value is
                    * resolvable at all, and R's own round(., 5) - reproduced
                    * here - erases the difference everywhere else.
                    local wald_pvalue = round(chi2tail(`wald_df', `wald_stat'), 0.00001)
                    local wald_available 1
                    local wald_state "ok"
                }
                else {
                    local wald_state "singular"
                }
            }
        }
        else {
            * No influence functions to test with (should not happen on any
            * shipped storage mode): fall back to the pre-repair criterion so
            * the two warning branches below keep their old behaviour.
            local wald_state = cond(`pre_valid' == 0, "nopre", "unavailable")
        }
        capture mata: mata drop __csdid_wald_*
    }
    if `pre_cells' > 0 & "`wald_state'" == "nopre" {
        display as text "warning: No pre-treatment periods available for the Wald pre-test of parallel trends: pre-treatment ATT(g,t) estimates exist, but all of them have missing or zero variance (e.g., because the underlying 2x2 estimation failed for those cells), so they were dropped from the pre-test."
    }
    else if `pre_cells' == 0 {
        * F-012 R parity: did::att_gt also warns when there are NO pre-treatment
        * cells at all (e.g., two-period data or every group treated early);
        * only the exist-but-invalid branch was ported.
        display as text "warning: No pre-treatment periods available for the Wald pre-test of parallel trends. This can happen when all groups are first treated early in the panel (e.g., in the second time period) so that no pre-treatment ATT(g,t) estimates exist."
    }
    else if "`wald_state'" == "na" {
        * R did 2.5.1, att_gt(): warning("Not returning pre-test Wald
        * statistic due to NA pre-treatment values").
        display as text "warning: Not returning pre-test Wald statistic due to NA pre-treatment values."
    }
    else if "`wald_state'" == "singular" {
        * R did 2.5.1, att_gt(): warning("Not returning pre-test Wald
        * statistic due to singular covariance matrix").
        display as text "warning: Not returning pre-test Wald statistic due to singular covariance matrix."
    }
    local n_units = `group_prob'[1, 3]
    local n_attgt = rowsof(`attgt')
    local n_groups = rowsof(`group_prob')
    local n_time = scalar(`panel_ntime')
    * bal(pair) is neither of the other two: the panel is not balanced, and
    * the run does not use the repeated-cross-section computation either.
    * Reporting it as allow_unbalanced would describe a different estimator.
    local panel_mode = cond("`ivar'" == "", "repeated-cross-section", ///
        cond("`balance_mode'" == "pair", "pair-balanced", ///
        cond(scalar(`panel_balanced') != 0, "panel", "allow_unbalanced")))
    local allow_unbalanced_resolved = ("`panel_mode'" == "allow_unbalanced")
    tempname post_b post_V
    local post_names ""
    local post_k = 0
    local post_renamed = 0
    forvalues i = 1/`=rowsof(`attgt')' {
        local post_g = `attgt'[`i', 1]
        local post_t = `attgt'[`i', 2]
        local post_att = `attgt'[`i', 4]
        if missing(`post_att') continue
        * The one cell that must not enter e(b)/e(V) is the universal-base
        * NORMALISATION row, whose ATT is 0 by construction with an
        * identically-zero influence function. The kernel marks it: column 10
        * (base_time) holds the reference period the cell was differenced
        * against, and it equals the cell's own time on exactly that row (see
        * the note at src/mata/csdid.mata, csdid_basic_attgt). The old test
        * `abs(post_e + 1) < 1e-8' assumed the reference period is always one
        * time unit before g, which is false under anticipation(),
        * base_period(varying), and - at DEFAULT settings - on any panel whose
        * periods are not unit-spaced. On those runs it let the fabricated zero
        * into e(b) (making e(V) singular by construction) and dropped a
        * genuine cell instead. Both matrix elements are compared directly, not
        * through locals, so no display-format rounding enters the test.
        if `attgt'[`i', 10] == `attgt'[`i', 2] continue

        * %21.0f ROUNDED each field, so on a non-integer cohort or period axis
        * distinct cells collapsed onto one coefficient name; Stata accepts
        * duplicate colnames and test/lincom/_b[] then resolve silently to the
        * first column carrying the name. %21.0g is injective on the value (it
        * is the format the display and plot paths already use), and "." is not
        * usable in a coefficient name, so it becomes "_".
        local post_gtxt : display %21.0g `post_g'
        local post_ttxt : display %21.0g `post_t'
        * The last field of the coefficient name is documented as the base
        * period, so it is read from base_time rather than assumed to be g-1.
        local post_btxt : display %21.0g `attgt'[`i', 10]
        foreach post_fld in post_gtxt post_ttxt post_btxt {
            local `post_fld' = strtrim("``post_fld''")
            if substr("``post_fld''", 1, 1) == "." local `post_fld' "0``post_fld''"
            local `post_fld' = subinstr("``post_fld''", ".", "_", .)
        }
        local post_cname "g`post_gtxt'___`post_ttxt'_`post_btxt'"

        local ++post_k
        * Residue the format cannot cover: a name past Stata's 32-character
        * limit (the pre-screen above sizes the integer part only), and two
        * field triples whose "_" substitution reassembles the same string.
        * An indexed name is not informative, but it is unique - e(attgt)
        * carries the group, time and base period of every cell.
        if strlen("`post_cname'") > 32 | strpos(" `post_names' ", " `post_cname' ") {
            local post_cname "att_`post_k'"
            local ++post_renamed
        }
        if `post_k' == 1 {
            matrix `post_b' = (`post_att')
        }
        else {
            matrix `post_b' = `post_b', (`post_att')
        }
        local post_names "`post_names' `post_cname'"
    }
    * post_V used to be built here, one bordered row and column per cell:
    * Theta(K^3) element copies and 2(K-1) reallocations through Stata's
    * classic-matrix layer, K the number of named cells. Every element of it
    * was then overwritten by csdid_post_attgt_v below, which builds the whole
    * matrix from the influence functions or the bootstrap draws. The build
    * was pure waste -- seconds to tens of seconds on the large staggered
    * designs where K reaches several hundred -- and its `missing se -> 0'
    * fallback was not load-bearing either: that decision lives in
    * csdid__rescale_v_to_se, on the path this file always takes.
    *
    * A placeholder is still needed for the tempname to exist when
    * csdid_post_attgt_v is handed its name.
    if `post_k' > 0 matrix `post_V' = J(`post_k', `post_k', 0)
    * PARTIAL (see the note below): when every 2x2 cell fails, the loop
    * above names nothing, and csdid returned rc 0 with e(cmd)=="csdid" and
    * e(N) posted but NO e(b)/e(V) at all, and with no message saying so - an
    * estimation command reporting success while every postestimation path
    * (test, lincom, estimates, predict, csdid_stats) was left to break later
    * with an unrelated error. Neither remedy the audit proposes is available:
    *   - "post b/V with missing entries" is impossible. Stata's `ereturn post'
    *     AND `ereturn repost' both reject a missing entry in b or in V with
    *     r(504) "matrix has missing values" (measured).
    *   - "refuse with a nonzero rc" contradicts frozen tests test-f011 (sparse
    *     covariates), test-f030 (output-name collision) and
    *     test-release-hardening, all of which require rc 0 plus an e(attgt)
    *     they compare cell-by-cell against R - and R's did itself returns an
    *     NA-filled object here rather than stopping, so refusing would also
    *     break parity.
    * Posting zeros under the `o.' omitted marker WOULD post an e(b), but a
    * failed cell is not an omitted term: it would put fabricated 0s where the
    * estimate does not exist and let test/lincom report on them.
    * So what is fixed here is the silence: the run now says, in the user's own
    * vocabulary, that every cell failed, why that usually happens, and that no
    * coefficient vector was posted. Whether csdid should break R parity and
    * refuse outright is an owner decision, recorded as a follow-up.
    * Both go through `display as error', the one channel a caller's `quietly'
    * cannot suppress. What they announce is that the run has no e(b) -- the
    * rule this command follows for anything that changes what was estimated.
    if `post_k' == 0 {
        local ds03_valid = 0
        forvalues i = 1/`=rowsof(`attgt')' {
            if !missing(`attgt'[`i', 4]) local ++ds03_valid
        }
        if `ds03_valid' == 0 {
            display as error "warning: every ATT(g,t) cell failed to estimate - all `n_attgt' group-time cells are missing - so no coefficient vector was posted and postestimation commands (csdid_stats, estat, test, lincom, predict) have nothing to work with. Common causes are a covariate that is collinear or constant within the 2x2 comparisons, a propensity-score trim (pscoretrim()) that empties every comparison group, comparison groups with too few units, and an outcome with no variation. Check the covariate list and pscoretrim(), or rerun with method(reg). The ATT(g,t) table is still available in e(attgt)."
        }
        else {
            display as error "warning: no ATT(g,t) coefficient could be named - every estimable cell is a normalised base period - so no coefficient vector was posted. Check baseperiod() and anticipation(). The ATT(g,t) table is still available in e(attgt), where the base period of each cell is reported in the base_time column."
        }
    }
    if `post_renamed' > 0 {
        display as text "note: `post_renamed' ATT(g,t) coefficient(s) could not be given a unique g<g>___<t>_<base> name within Stata's 32-character limit and are named att_# instead. e(attgt) reports the group, time and base period of every cell."
    }
    if `post_k' > 0 {
        local post_if ""
        if `store_large' local post_if "`inffunc'"
        local post_cluster ""
        if "`cluster'" != "" & `store_large' local post_cluster "`cluster_vec'"
        local post_boot ""
        if `bstrap' local post_boot "`boot_draws'"
        * The kernel's cache token: the Mata cluster cache is this run's only
        * when it carries this run's token. Empty means no cache adoption.
        local post_token .
        capture local post_token = scalar(`cache_token')
        mata: csdid_post_attgt_v("`attgt'", "`post_if'", "`post_cluster'", "`post_boot'", `bstrap', "`post_V'", `post_token')
        matrix colnames `post_b' = `post_names'
        matrix colnames `post_V' = `post_names'
        matrix rownames `post_V' = `post_names'
    }
    * F-009: the panel's FIRST time period, which csdid_aggte needs to apply R
    * compute.aggte's balance_e event-time truncation. `min_time' is already
    * exactly it (summarize of time over touse, above), and it is captured here
    * because `ereturn clear' is about to wipe the estimation locals' only sink.
    local time_first = `min_time'
    ereturn clear
    if `post_k' > 0 {
        * e(sample) marks the estimation sample, as every official estimation
        * command does; `summarize ... if e(sample)' and `estat summarize'
        * work off it. esample() consumes the variable it is handed, so it
        * gets a copy of touse rather than touse itself.
        tempvar esmp
        quietly generate byte `esmp' = `touse'
        ereturn post `post_b' `post_V', obs(`sample_N') esample(`esmp')
    }
    ereturn matrix attgt = `attgt'
    if `store_large' ereturn matrix inffunc = `inffunc'
    ereturn matrix group_prob = `group_prob'
    ereturn matrix profile = `profile'
    if `store_large' ereturn matrix unit_group = `unit_group'
    if "`cluster'" != "" & `store_large' {
        matrix colnames `cluster_vec' = cluster
        ereturn matrix cluster_vec = `cluster_vec'
    }
    ereturn local estat_cmd "csdid_estat"
    * e(b) holds ATT(g,t) effects, not coefficients on the regressors, so
    * margins has nothing meaningful to average. It already refused with a bare
    * r(322); declaring it explicitly is the documented Stata convention and
    * produces a message that names the reason.
    ereturn local marginsnotok "_ALL"
    ereturn local cmdline `"`cmdline'"'
    ereturn local version "2.0.0"
    * the conventional Stata estimation macros were all empty,
    * which is what estout/etable/esttab read to label a column and its standard
    * errors. didregress sets e(depvar), e(vce), e(vcetype) and e(predict); set
    * the same four here, IN ADDITION to (not instead of) csdid's own e(yname),
    * e(clustervar) and friends, which the postestimation commands use and which
    * are a documented contract.
    ereturn local depvar "`yname'"
    if `bstrap' {
        ereturn local vce "bootstrap"
        ereturn local vcetype "Bootstrap"
    }
    else if "`cluster'" != "" {
        ereturn local vce "cluster"
        ereturn local vcetype "Robust"
    }
    else {
        ereturn local vce "analytical"
        ereturn local vcetype "Analytical"
    }
    * predict is not meaningful after csdid (e(b) holds ATT(g,t)
    * effects, not coefficients on regressors). Naming the refusal program here
    * is what makes `predict' produce csdid's own message instead of a bare
    * r(111) about an internal coefficient name. csdid_p.ado ships with the
    * package alongside this file.
    ereturn local predict "csdid_p"
    ereturn local yname "`yname'"
    ereturn local timevar "`time'"
    ereturn local gvar "`gvar'"
    ereturn local idvar "`ivar'"
    ereturn local clustervar "`cluster'"
    ereturn local panel_mode "`panel_mode'"
    ereturn local control_group = cond("`notyet'" != "", "notyettreated", "nevertreated")
    ereturn local method "`method'"
    ereturn local method_requested "`method_requested'"
    * e(weightvar) names a TEMPVAR that no longer exists once the command
    * returns, so it can identify nothing after the fact. The weight the user
    * actually typed is what a reader needs, and it is what every official
    * estimation command stores: e(wtype) is the weight type and e(wexp) the
    * expression, including its leading `='.
    ereturn local wtype "`weight'"
    ereturn local wexp `"`exp'"'
    * estat summarize is the one postestimation route that reads the DATA in
    * memory rather than stored results; the signature is what lets it refuse
    * with r(459) when the data changed since estimation, instead of
    * describing a sample the estimation never saw. The aggregation routes
    * read the engine cache and stored results and are guarded by the cache
    * token instead. Three constraints decide what is signed and where:
    * (1) only DURABLE user variables -- `fvrevar, list' returns the base
    * variables behind factor terms, never the __-temporaries the fit built,
    * which die with this program and made check-time fail r(111) on
    * untouched data; (2) the rcs identifier is signed too (it marks the
    * estimation sample even though it is not a panel id); (3) the call sits
    * AFTER e(wexp) is posted, because sign- and check-time both fold the
    * weight variable in from e(wexp) -- signing before it was posted hashed
    * a different variable set than the check read, and every weighted run
    * refused r(459) on untouched data.
    if `post_k' > 0 {
        local sign_covs ""
        if `"`xvars'"' != "" {
            capture fvrevar `xvars', list
            if !_rc local sign_covs "`r(varlist)'"
        }
        quietly signestimationsample `ivar' `ivar_declared' `time' `gvar' `yname' `sign_covs' `cluster'
    }
    ereturn local weightvar "`wvar'"
    ereturn local base_period "`base_period'"
    ereturn local fix_weights "`fix_weights'"
    ereturn local boot_dist "`boot_dist'"
    ereturn local boot_dist_requested "`boot_dist_requested'"
    ereturn local boot_seed "`boot_seed'"
    ereturn local bootstrap_accelerator "`bootstrap_accelerator'"
    ereturn local bootstrap_accelerator_status "`bootstrap_accelerator_status'"
    ereturn local bootstrap_accelerator_file "`bootstrap_accelerator_file'"
    ereturn local fast_mode "`fast_mode'"
    ereturn local storage = cond("`performance_resolved'" == "full", "materialized", "lean")
    local compute_path "baseline"
    if scalar(`fast_used') != 0 {
        if "`panel_mode'" == "panel" {
            local compute_path "fast-balanced-panel"
        }
        else if "`panel_mode'" == "allow_unbalanced" {
            local compute_path "fast-allow-unbalanced"
        }
        else if "`panel_mode'" == "pair-balanced" {
            local compute_path "pair-balanced"
        }
        else {
            local compute_path "fast-repeated-cross-section"
        }
    }
    ereturn local compute_path "`compute_path'"
    ereturn scalar N = `sample_N'
    ereturn scalar N_units = `n_units'
    ereturn scalar N_attgt = `n_attgt'
    ereturn scalar N_groups = `n_groups'
    ereturn scalar N_time = `n_time'
    * F-009: consumed by csdid_aggte for balance_e truncation.
    ereturn scalar time_first = `time_first'
    ereturn scalar anticipation = `anticipation'
    ereturn scalar pscoretrim = `pscoretrim'
    ereturn scalar bstrap = `bstrap'
    ereturn scalar biters = `biters'
    * the inference settings that actually determined the
    * standard errors were unrecoverable from e() - e(reps) and e(rseed) were
    * both empty, so a saved estimate could not be reproduced or even audited,
    * and an unseeded bootstrap left no trace of being unseeded. e(reps) mirrors
    * e(biters) under the name Stata's own bootstrap machinery uses; e(rseed)
    * is the seed actually fed to the multiplier RNG (empty means unseeded, so
    * the standard errors are not reproducible across runs).
    if `bstrap' {
        ereturn scalar reps = `biters'
        ereturn local rseed "`boot_seed'"
    }
    ereturn scalar cband = `cband'
    ereturn scalar pointwise = (`cband' == 0)
    ereturn scalar fast_requested = `fast_requested'
    ereturn scalar fast_auto = `fast_auto'
    ereturn scalar fast_allowed = `fast_allowed'
    ereturn scalar fast_used = scalar(`fast_used')
    ereturn scalar allow_unbalanced = `allow_unbalanced_resolved'
    ereturn scalar mata_cache = ("`performance_resolved'" == "lean")
    ereturn scalar mata_cache_token = scalar(`cache_token')
    if `bstrap' {
        ereturn scalar crit_val = `boot_crit'
        ereturn scalar point_crit_val = `boot_pointcrit'
        ereturn matrix boot_attgt = `boot_attgt'
        ereturn matrix boot_draws = `boot_draws'
        ereturn matrix bootstrap_profile = `bootstrap_profile'
        ereturn matrix bootstrap_kernel_profile = `bootstrap_kernel_profile'
        ereturn scalar bootstrap_accelerator_rc = `bootstrap_accelerator_rc'
        ereturn scalar bootstrap_accelerator_seconds = `bootstrap_accelerator_seconds'
        if "`boot_rng_arg'" != "" ereturn matrix boot_rng_state = `boot_rng_state'
    }
    else {
        ereturn scalar crit_val = invnormal(1 - (100 - `level') / 200)
        ereturn scalar point_crit_val = invnormal(1 - (100 - `level') / 200)
    }
    if "`cluster'" != "" ereturn scalar N_clusters = `nclusters'
    ereturn scalar level = `level'
    * F-008: posted only when the pre-test actually produced a statistic, so
    * that `confirm scalar e(wald_pvalue)' is the test for "R would have
    * printed a p-value here", exactly as `!is.null(mpobj$Wpval)' is in
    * summary.MP. e(wald_stat) is the raw chi-squared statistic; e(wald_pvalue)
    * carries R's own 5-decimal rounding.
    if `wald_available' {
        ereturn scalar wald_stat = `wald_stat'
        ereturn scalar wald_df = `wald_df'
        ereturn scalar wald_pvalue = `wald_pvalue'
    }
    if `"`saverif'"' != "" {
        _csdid_save_rif using `"`saverif'"', `replace'
        ereturn local rif_file `"`saverif'"'
    }

    * Last, as [P] ereturn recommends: e(cmd) is what the postestimation
    * commands read to decide the results are theirs, so it is the one macro
    * that must not be readable while the rest of e() is still being filled
    * in. It stays ahead of the agg() call below, which runs csdid_stats.
    ereturn local cmd "csdid"

    local display_noisy = c(noisily)
    if `display_noisy' Display, level(`level')

    if "`agg_type'" != "" {
        * agg() used to pass an undeclared `na_rm' here, which csdid_stats
        * matched as an alias of dropmissing. So `csdid ..., agg(event)'
        * averaged away every failed ATT(g,t) cell and reported a number,
        * while the SAME aggregation typed by hand -- `csdid_stats,
        * type(dynamic)' -- refused, and so does R's aggte(), whose na.rm
        * defaults to FALSE. That is a silent estimand change on the one
        * aggregation route a user reaches without asking for an aggregation
        * command. The flag is now the user's to set, under the same name
        * csdid_stats and estat use, and agg() refuses exactly as they do.
        csdid_stats, type(dynamic) `dropmissing'
        * agg() posts by design: after `csdid, agg(event)' e(b)/e(V) hold the
        * aggregated coefficients (documented). The estat routes pass `post'
        * only when the user asks for it.
        _csdid_post event, level(`level') post
    }
end

program define _csdid_parse_wboot, rclass
    version 14
    * the nested `syntax' that replaces csdid's old wboot() regexes.
    * Declaring every sub-option in full capitals means the full name must be
    * typed, so `rep(7)' is rejected as an unknown option rather than silently
    * abbreviating to reps(); `syntax' supplies the "specified more than once",
    * "not allowed" and "incorrectly specified" diagnostics for free, all 198.
    syntax [, CLUSTER(string) REPS(string) BITERS(string) ///
              RSEED(string) SEED(string) WTYPE(string) WBTYPE(string) ]
    return local wb_cluster `"`cluster'"'
    return local wb_reps    `"`reps'"'
    return local wb_biters  `"`biters'"'
    return local wb_rseed   `"`rseed'"'
    return local wb_seed    `"`seed'"'
    return local wb_wtype   `"`wtype'"'
    return local wb_wbtype  `"`wbtype'"'
end

program define Display
    version 14
    syntax [, Level(cilevel)]
    tempname out
    matrix `out' = e(attgt)
    * base_time (column 10) is a posting-layer marker, not part of the printed
    * ATT(g,t) table; print the nine documented columns so the displayed table
    * is unchanged. It remains readable in e(attgt).
    if colsof(`out') > 9 matrix `out' = `out'[1..., 1..9]
    display as text _newline "Group-time average treatment effects"
    * -------------------------------------------------------------------
    * nothing in the printed output said how the standard
    * errors were produced. A reader could not tell an analytical run from a
    * 1000-replication multiplier bootstrap, could not see the replication
    * count, and - the part that actually costs people time - could not see
    * that an UNSEEDED bootstrap had been run, whose standard errors drift by
    * several percent between two identical calls. didregress prints its
    * inference settings in the header; print the same facts here, from the
    * e() macros that record them, immediately under the title.
    * -------------------------------------------------------------------
    * "no seed set (not reproducible)" was a label in the middle of the
    * settings line, where it read as one more setting and said nothing about
    * what to do. What it means is that the numbers in the table below move
    * when the command is run again, which is worth a line of its own, in words,
    * naming the option that fixes it. It is printed only when it applies, so
    * the settings line of a seeded or analytical run is unchanged.
    local inf_line ""
    local unseeded 0
    if "`e(vce)'" == "bootstrap" {
        local inf_line "Std. errors: multiplier bootstrap, `=e(biters)' reps"
        if "`e(rseed)'" != "" {
            local inf_line "`inf_line', rseed(`e(rseed)')"
        }
        else {
            local unseeded 1
        }
    }
    else {
        local inf_line "Std. errors: analytical (influence function)"
    }
    if "`e(clustervar)'" != "" {
        local inf_line "`inf_line'; clustered on `e(clustervar)'"
        capture confirm scalar e(N_clusters)
        if !_rc local inf_line "`inf_line' (`=e(N_clusters)' clusters)"
    }
    local band_kind "pointwise"
    * the ATT(g,t) band is simultaneous only when the bootstrap ran: with
    * analytical inference the request e(cband) can be 1 while this table's
    * critical value is the pointwise quantile (the aggregation is where the
    * request is honored, by its own bootstrap).
    capture confirm scalar e(cband)
    if !_rc {
        if e(cband) == 1 & e(bstrap) == 1 local band_kind "simultaneous"
    }
    display as text "`inf_line'; `level'% `band_kind' bands"
    if `unseeded' {
        display as text "Note: no rseed() set, so these standard errors change slightly between runs; add rseed(#) to reproduce them."
    }
    matlist `out', names(columns) format(%10.6g)
    * F-008: R's summary.MP prints this line, in this wording, on every run
    * whose pre-test produced a statistic, and prints nothing at all when it
    * did not (the reason is then carried by the warnings above).
    capture confirm scalar e(wald_pvalue)
    if !_rc {
        display as text "P-value for pre-test of parallel trends assumption:  " %6.5f e(wald_pvalue)
    }
end

program define _csdid_save_rif
    version 14
    syntax using/ [, REPLACE]

    tempname ATT GP
    matrix `ATT' = e(attgt)
    matrix `GP' = e(group_prob)
    local nrif = rowsof(`ATT')

    * -----------------------------------------------------------------------
    * the export below builds the artifact in a scratch
    * copy of the data, and every step of that announced itself on the happy
    * path - "number of observations will be reset to N", the variable-count
    * chatter, and, worst, Stata's own
    *     Press any key to continue, or Break to abort
    * more-prompt, which BLOCKS the run for any user who has `set more on'.
    * `bootstrap, saving()' and `estimates save' say nothing when they
    * succeed; neither should saverif(). The whole scratch-data section runs
    * -quietly-. The two refusals this program can raise are both above this
    * point (the schema mismatch) or are raised by -save- itself with rc != 0,
    * which -quietly- does not suppress, so nothing diagnostic is lost.
    * -----------------------------------------------------------------------
    quietly {
    preserve
    clear
    * The whole scratch dataset is filled by one Mata call: reading the
    * influence functions INTO Mata is linear (measured 0.00s at 50k rows)
    * and st_store back into variables is linear, while the old
    * `matrix IF = e(inffunc)' + svmat route crossed Stata's classic-matrix
    * layer three times, each crossing quadratic in n_units (measured 4s at
    * 25k rows). The schema and the (g,t) refusal are unchanged; the refusal
    * now comes from csdid_rif_export with the same message.
    set obs `=e(N_units)'
    mata: csdid_rif_export()
    generate long rif_row = _n
    order rif_row id group
    forvalues j = 1/`nrif' {
        local g = strofreal(`ATT'[`j', 1], "%21.0g")
        local t = strofreal(`ATT'[`j', 2], "%21.0g")
        local e = strofreal(`ATT'[`j', 3], "%21.0g")
        local a = strofreal(`ATT'[`j', 4], "%21.0g")
        local s = strofreal(`ATT'[`j', 5], "%21.0g")
        local ntt = strofreal(`ATT'[`j', 6], "%21.0g")
        local ntp = strofreal(`ATT'[`j', 7], "%21.0g")
        local nct = strofreal(`ATT'[`j', 8], "%21.0g")
        local ncp = strofreal(`ATT'[`j', 9], "%21.0g")
        * base_time: the reference period this cell was differenced against.
        * Without it a reloaded artifact cannot tell the universal-base
        * normalisation row from a genuine cell, nor name a coefficient with
        * the base period the run actually used.
        local bt = strofreal(`ATT'[`j', 10], "%21.0g")
        label variable rif`j' "RIF group=`g' time=`t' event_time=`e'"
        char rif`j'[csdid_attgt] "`g' `t' `e' `a' `s' `ntt' `ntp' `nct' `ncp' `bt'"
    }
    char _dta[csdid_artifact] "rif"
    char _dta[csdid_cmdline] `"`e(cmdline)'"'
    char _dta[csdid_panel_mode] "`e(panel_mode)'"
    char _dta[csdid_control_group] "`e(control_group)'"
    char _dta[csdid_base_period] "`e(base_period)'"
    char _dta[csdid_method] "`e(method)'"
    char _dta[csdid_N] "`=e(N)'"
    char _dta[csdid_N_units] "`=e(N_units)'"
    char _dta[csdid_N_attgt] "`=e(N_attgt)'"
    char _dta[csdid_N_groups] "`=e(N_groups)'"
    char _dta[csdid_N_time] "`=e(N_time)'"
    char _dta[csdid_anticipation] "`=e(anticipation)'"
    char _dta[csdid_level] "`=e(level)'"
    * clustering has to travel with the artifact, or aggregating the
    * reloaded file reports unclustered standard errors for a clustered
    * estimation. csdid_cluster_recorded is written unconditionally and is
    * what tells the reader an EMPTY csdid_clustervar means "this run was not
    * clustered" rather than "this artifact predates the field".
    char _dta[csdid_cluster_recorded] "1"
    char _dta[csdid_clustervar] "`e(clustervar)'"
    if "`e(clustervar)'" != "" {
        char _dta[csdid_N_clusters] "`=e(N_clusters)'"
    }
    * F-009: balance_e truncation needs the panel's first period. Persist it so
    * `csdid_stats using <rif>, balance()' works instead of refusing; artifacts
    * written before this char existed still get the clean rc 498 refusal.
    char _dta[csdid_time_first] "`=e(time_first)'"
    * #20. These rows record the aggregation weights the estimation used, and
    * csdid_stats checks them on load. The audit called for widening the format
    * here too, on the grounds that `=exp' expansion truncates to about eight
    * significant digits; measured, it does not -- it writes sixteen
    * (.1620512820512821), which is at most an ulp off the double and orders
    * inside the tolerance the check uses. Left alone rather than churn a
    * shipped artifact field for nothing.
    local ngp = rowsof(`GP')
    char _dta[csdid_group_prob_rows] "`ngp'"
    forvalues i = 1/`ngp' {
        char _dta[csdid_group_prob_`i'] "`=`GP'[`i',1]' `=`GP'[`i',2]' `=`GP'[`i',3]'"
    }
    * The artifact's integrity was guarded by aggregate moments alone --
    * counts and group probabilities -- which cannot see a sum-preserving
    * row-level edit: shift weight between two units of one cohort and the
    * totals match, the load accepts the file as the original estimation's,
    * and the reconstructed standard errors are different numbers under the
    * same certificate (cold-audit round 9, computed witness: SE 2.5 became
    * 2.652 with every aggregate check green). -datasignature set- signs the
    * ordered content of every variable, and the loader confirms it.
    * Every operative characteristic joins the signed surface (cold-audit
    * round 10: blanking the clustervar characteristic turned a clustered
    * artifact into IID inference at rc 0, and an added rif column with
    * edited counts rode in under a plain signature). The canonical record
    * of every _dta[csdid_*] characteristic and every column's csdid_attgt
    * characteristic is written into a variable, where -datasignature-
    * covers it; the loader rebuilds the record from the characteristics it
    * finds and requires equality, and confirms the signature with -strict-
    * so an added variable refuses too.
    * Positional content digest: -datasignature-'s checksum is invariant to
    * permuting values within a variable, to exchanging two variables'
    * contents, and to negating a variable (measured: six such mutations of
    * the influence-function, cluster, and weight columns reloaded at rc 0
    * with changed standard errors -- in-house review, artifact lens). The
    * Mata hash below serializes the full numeric content in row-and-column
    * order, so none of those rearrangements survives it; it rides inside
    * the canonical metadata record, which the row signature covers.
    mata: st_local("rif_cdigest", strofreal(hash1(st_data(., .), 2147483647), "%12.0f") + "-" + strofreal(hash1(st_data(., .)', 2147483647), "%12.0f"))
    local meta_canon `"|cdigest=`=subinstr(strtrim("`rif_cdigest'"), " ", "", .)'"'
    foreach ck in artifact cmdline panel_mode control_group base_period method N N_units N_attgt N_groups N_time anticipation level cluster_recorded clustervar N_clusters time_first group_prob_rows {
        local meta_canon `"`meta_canon'|`ck'=`: char _dta[csdid_`ck']'"'
    }
    forvalues mi = 1/`ngp' {
        local meta_canon `"`meta_canon'|gp`mi'=`: char _dta[csdid_group_prob_`mi']'"'
    }
    foreach mv of varlist rif* {
        local meta_canon `"`meta_canon'|`mv'=`: char `mv'[csdid_attgt]'"'
    }
    quietly generate strL __csdid_meta = ""
    quietly replace __csdid_meta = `"`meta_canon'"' in 1
    quietly datasignature set, reset
    save `"`using'"', `replace'
    restore
    * The reader (csdid_stats using) must materialize an N_units-row classic
    * matrix, which this flavour caps at c(max_matdim); the writer has no
    * such cap, so an artifact can be written here that THIS Stata cannot
    * reload (cold-audit M2). Say so at write time, when the user can still
    * plan, instead of at reload time, when the estimation is long gone.
    if e(N_units) > c(max_matdim) {
        display as text "note: this artifact holds `=e(N_units)' unit rows, more than this Stata flavour's matrix limit (c(max_matdim) = `=c(max_matdim)'), so csdid_stats using cannot reload it HERE. A flavour whose limit covers it (e.g. Stata/MP) can."
    }
    }
end
