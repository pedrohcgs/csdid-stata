*! csdid_stats 2.0.0 01sep2026
program define csdid_stats, eclass
    version 14
    * The saved-RIF route is TRANSACTIONAL. Its loader replaces e() wholesale
    * before the option validation runs (the load is what the later checks
    * are ABOUT on that route), so a refused window()/type()/balance() once
    * returned r(198) having already erased the caller's estimation result
    * and certified the loaded state with e(cmd). The front below holds the
    * incoming e() across the whole route: any nonzero return restores it
    * exactly (or leaves e() empty when there was nothing to restore), and a
    * completed run keeps the new results. The cache route never touches e()
    * before its validations and dispatches straight through.
    local txn_zero `"`0'"'
    capture syntax [anything] [using/] [, *]
    local txn_using `"`using'"'
    local 0 `"`txn_zero'"'
    if `"`txn_using'"' == "" {
        _csdid_stats_main `0'
        exit
    }
    * The hold-to-resolution interval is one atomic group: without nobreak, a
    * Break landing after the hold moved the caller's result away and before
    * the unhold could put it back ended the program with the temp-named hold
    * DISCARDED -- the user's estimation gone on an interrupt. `hold, restore'
    * is the last-resort guarantee ([P] _estimates: restore fires on normal
    * end, on error, and on Break); `capture noisily break' re-enables the
    * interrupt for the long-running worker itself, so the user can still
    * stop an aggregation -- and lands here, where the restore resolves; and
    * `unhold, not' cancels the restoration only once a certified new result
    * actually exists. This is [P] break's canonical critical-section shape.
    tempname txn_held
    local txn_had 0
    local txn_snap 0
    nobreak {
        * `txn_had' records that the hold actually HAPPENED, not that e()
        * looked restorable. A completed `csdid_stats using' posts e(cmd)
        * with no e(b) (the artifact carries no coefficient vector), and
        * `_estimates hold' refuses a b-less state with r(301) -- measured:
        * the second of two back-to-back using-runs died here, in the front,
        * before the worker ever ran. A b-less state still deserves the
        * same guarantee, so when the hold is refused the front copies every
        * e() member by name -- scalars into scalar tempnames, macros into
        * locals, matrices (stripes ride along) into matrix tempnames -- and
        * reposts them on any nonzero return. Two rules from the cold audit:
        * whether anything needs protecting is decided by the member lists
        * themselves, never by e(cmd) (an e-class program may post members
        * without that certification macro), and the copies are stored under
        * INDEXED transaction names, never names derived from the members'
        * own (a legal 32-character result name would overflow a derived
        * local name). A b-less state cannot carry e(sample) (only `ereturn
        * post' marks one, and posting requires e(b)), so the copy is
        * complete for every state the hold refuses.
        local txn_sc : e(scalars)
        local txn_mac : e(macros)
        local txn_mat : e(matrices)
        if `"`txn_sc'`txn_mac'`txn_mat'"' != "" {
            capture _estimates hold `txn_held', restore
            if _rc == 0 local txn_had 1
            else {
                local txn_snap 1
                local txn_i 0
                foreach x of local txn_sc {
                    local ++txn_i
                    tempname txn_s_`txn_i'
                    scalar `txn_s_`txn_i'' = e(`x')
                }
                local txn_i 0
                foreach x of local txn_mac {
                    local ++txn_i
                    local txn_m_`txn_i' `"`e(`x')'"'
                }
                local txn_i 0
                foreach x of local txn_mat {
                    local ++txn_i
                    tempname txn_x_`txn_i'
                    matrix `txn_x_`txn_i'' = e(`x')
                }
            }
        }
        capture noisily break _csdid_stats_main `0'
        local txn_rc = _rc
        if `txn_rc' {
            ereturn clear
            if `txn_had' _estimates unhold `txn_held'
            else if `txn_snap' {
                local txn_i 0
                foreach x of local txn_mat {
                    local ++txn_i
                    ereturn matrix `x' = `txn_x_`txn_i''
                }
                local txn_i 0
                foreach x of local txn_sc {
                    local ++txn_i
                    ereturn scalar `x' = `txn_s_`txn_i''
                }
                local txn_i 0
                foreach x of local txn_mac {
                    local ++txn_i
                    ereturn local `x' `"`txn_m_`txn_i''"'
                }
            }
            exit `txn_rc'
        }
        if `txn_had' {
            if `"`e(cmd)'"' == "csdid" {
                _estimates unhold `txn_held', not
            }
            else {
                ereturn clear
                _estimates unhold `txn_held'
            }
        }
        else if `txn_snap' & `"`e(cmd)'"' != "csdid" {
            * completed without certifying a csdid result: the incoming
            * b-less state stands, exactly as the held branch above rules.
            ereturn clear
            local txn_i 0
            foreach x of local txn_mat {
                local ++txn_i
                ereturn matrix `x' = `txn_x_`txn_i''
            }
            local txn_i 0
            foreach x of local txn_sc {
                local ++txn_i
                ereturn scalar `x' = `txn_s_`txn_i''
            }
            local txn_i 0
            foreach x of local txn_mac {
                local ++txn_i
                ereturn local `x' `"`txn_m_`txn_i''"'
            }
        }
    }
end

program define _csdid_stats_main, eclass
    version 14
    * parse `using' as a declared, optional part of the command
    * instead of running `syntax ... using/' under -capture- and falling back
    * to a second syntax call. The old fallback swallowed the real diagnosis:
    * any option error on the using path (level(150), a duplicate option, a
    * bad window()) made the FIRST syntax fail, and the SECOND syntax then
    * reported "using not allowed" r(101). One declarative syntax reports the
    * option that is actually wrong, on both paths.
    * remedy() is internal plumbing, deliberately undocumented: the callers
    * that reach the aggregation through another surface (csdid_estat, and
    * csdid's own agg()) pass the command THEIR user would retype, so the
    * missing-cell refusal can name it verbatim instead of leaving the user
    * to translate "specify dropmissing" into the surface they are on.
    syntax [anything(name=subcmd)] [using/] [, TYPE(string) Level(string) ///
        WINdow(string) BALance(string) DROPMissing FROM(string) ///
        REMEDY(string) *]
    * from() is unsupported by design; see csdid.ado for the full rationale.
    * Legacy accepted it on the simple, group and calendar aggregations.
    if `"`from'"' != "" {
        display as error "from() is no longer supported; it set a lower event-time bound on the simple, group and calendar aggregations, which is now fixed at event time 0 -- the legacy default from(0) already was. Use window(# #) with type(dynamic) for event-time windows."
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
    * F-034 fix: an OMITTED level() inherits the ESTIMATION-time
    * confidence level from e(level). The direct path defaulted to the
    * SESSION c(level), so every aggregation after "csdid ..., level(90)"
    * silently banded at 95 - the same inheritance R applies by
    * construction, since aggte follows the estimation alp. An EXPLICITLY
    * typed level() is honored verbatim, whatever its value - the string
    * parse below sees presence where cilevel could not.
    *
    * this block used to live ONLY in the non-`using' branch, so
    * the saved-RIF path banded at the session c(level) even though
    * _csdid_stats_load_rif posts e(level) from char _dta[csdid_level].
    * Measured: "csdid ..., level(90) saverif(r90)" then "csdid_stats using
    * r90" gave e(level)=90 with e(agg_level)=95, contradicting
    * csdid_stats.sthlp and the comment above it. It now runs on BOTH paths.
    * level() is parsed as a STRING so that an explicitly typed level --
    * even one equal to the session default, which a cilevel parse cannot
    * distinguish from omission -- is honored verbatim (cold-audit round 9a,
    * measured: estimate at level(90) under c(level)=95, then level(95)
    * typed explicitly inherited the 90 and labeled it 95). Only a truly
    * OMITTED level inherits: first from e(level), the estimation's own
    * level (the F-034 rule, R's alp inheritance by construction), then
    * from the session default.
    if `"`level'"' != "" {
        * two separate tests: -if- evaluates its whole expression, so a
        * non-numeric token inside the range comparison aborted with the
        * stock r(111) before the message could print (in-house review).
        capture confirm number `level'
        if _rc {
            display as error "level(`level') is not a confidence level; specify a value between 10 and 99.99"
            exit 198
        }
        if !(`level' >= 10 & `level' <= 99.99) {
            display as error "level(`level') is not a confidence level; specify a value between 10 and 99.99"
            exit 198
        }
        * The receivers below parse the SAME value with Level(cilevel), which
        * additionally refuses more than two decimals. Without this test the
        * value passes here, the aggregation runs, e() is REPLACED and any
        * saving() file is written, and only then does the display exit 198 --
        * leaving a capture'd caller holding a half-finished aggregation from
        * a command Stata said failed. Refuse before doing the work, which is
        * what csdid itself does (it declares Level(cilevel) at entry).
        * Three-decimal levels are not exotic: 1 - 0.05/3 is level(98.333).
        if `level' != round(`level', 0.01) {
            display as error "level(`level') can have at most two digits after the decimal point"
            exit 198
        }
    }
    else {
        local level = c(level)
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
    * balance() used to be declared BALance(integer -1), so
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
    local agg_cluster_specified 0
    local agg_cluster_name ""
    local unsupported ""
    * -syntax- hands the leftover options back as ONE string,
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
        * capture the WHOLE argument and validate it
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
            * min_e(), max_e() and balance_e() each refuse a repeat; this one
            * last-won in silence. The harm is not symmetric: a mismatch with
            * e(clustervar) exits 498 naming the LAST spelling, so
            * `cluster(state) cluster(county)' on a run clustered by state
            * refused while advising the user to re-run the estimation with
            * county -- i.e. to change a correct estimation to match the
            * accidental second option -- and discarded cluster(state), the
            * one that matched, without a word.
            local cl_name = regexs(1)
            if `agg_cluster_specified' {
                if "`cl_name'" != "`agg_cluster_name'" {
                    display as error "cluster() and clustervars() are the same option under two names; specify only one."
                }
                else {
                    display as error "option `cl_name'() specified more than once"
                }
                exit 198
            }
            local agg_cluster = regexs(2)
            * recover the user's capitalisation: the match ran on the
            * lower-cased token, but e(clustervar) stores the real name.
            * read it off `opt_c' (blanks removed, case kept) so
            * `cluster( State )' recovers "State", not " State ".
            if regexm(`"`opt_c'"', "\(([^)]+)\)$") local agg_cluster = regexs(1)
            local agg_cluster_specified 1
            local agg_cluster_name "`cl_name'"
        }
        * a repeated DECLARED option is handed to the `*' catch-all
        * by -syntax-, so "window(0 2) window(1 3)" used to be reported as an
        * unsupported option. Name the real fault.
        *
        * The old test was a hand-written list of the FULL option names, and
        * Stata's own abbreviations are legal on the same syntax line, so
        * `win(0 1) win(1 2)', `lev(90) lev(80)' and `bal(1) bal(2)' fell
        * through it and exited with "unsupported option(s): win(1 2)" --
        * telling the user that window(), a supported option, is unsupported.
        * Ask -syntax- instead of a table that drifts: _csdid_stats_optdup
        * declares exactly this command's own options and nothing else, so a
        * leftover token it can parse is by definition one of ours typed
        * twice, in whatever spelling. csdid_estat solves the same problem
        * the same way, and its comment names this hazard.
        else {
            capture _csdid_stats_optdup, `opt'
            if _rc == 0 {
                local dup_opt "`r(option)'"
                display as error "option `dup_opt'() specified more than once"
                exit 198
            }
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
    * refuse reversed bounds at parse time, naming the option the
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
    * an extra positional token used to be folded into `subcmd' and
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
    * "csdid_stats simple, type(group)" used to run type(group)
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
        * name what the user actually typed. A bad POSITIONAL
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
        * Name what was TYPED, not all three spellings. The calendar
        * aggregation is over periods, not event times, so any of them is
        * ignored -- but telling a user that min_e() and balance_e() are
        * ignored when they typed window() reads as a message about someone
        * else's command.
        local cal_ignored ""
        if `"`window'"' != "" local cal_ignored "`cal_ignored' window()"
        if `balance_given' local cal_ignored "`cal_ignored' balance()"
        if `min_e_specified' & `"`window'"' == "" local cal_ignored "`cal_ignored' min_e()"
        if `max_e_specified' & `"`window'"' == "" local cal_ignored "`cal_ignored' max_e()"
        if `balance_e_specified' & !`balance_given' local cal_ignored "`cal_ignored' balance_e()"
        if "`cal_ignored'" == "" local cal_ignored " min_e(), max_e(), and balance_e()"
        * as ERROR, not as text: this warning says a documented option the
        * user typed was discarded and a DIFFERENT aggregation is being
        * reported. On the text channel a caller's -quietly- removed it, so
        * `quietly csdid_stats, type(calendar) window(0 1)' returned the full
        * unwindowed calendar table with nothing said. errprintf survives
        * quietly; the estat route was given the same treatment already.
        display as error "warning:`cal_ignored' is ignored for type(calendar); the full calendar aggregation is reported"
    }
    local na_rm_flag = ("`na_rm'" != "")
    local use_cluster = ("`e(clustervar)'" != "")
    if "`agg_cluster'" != "" {
        if "`e(clustervar)'" == "`agg_cluster'" {
            local use_cluster = 1
        }
        else {
            * e(clustervar) is empty whenever the estimation was not
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
    * default at every size unless storeall materializes the matrices)
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
    * The engine, by the same rules csdid uses. `csdid_stats using <riffile>'
    * is the one route that reaches the engine with no csdid before it, so it
    * is also the one route where the library's stamp has to be read here or
    * not at all, and where the search order has never been settled by an
    * earlier command in the session.
    _csdid_engine_load
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
        * plain -capture-, not -capture noisily-. Measured in Stata
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
    * the aggregation kernel used to be called bare, so every kernel
    * refusal ("no event times fall within the requested aggregation window",
    * "missing values found in ATT(g,t) estimates", ...) arrived with two
    * lines of Mata frames stapled underneath it. Run it under -capture- and
    * re-raise the diagnosis from the ado.
    capture scalar drop CSDID_AGG_BAL_DRIFT
    global CSDID_AGG_BAL_DRIFT_LIST
    capture mata: csdid_aggte("`type'", `min_e', `max_e', `balance_e', `na_rm_flag', `use_cluster', `use_cache', "`aggte'", "`agg_inffunc'", `agg_store_large')
    local aggte_rc = _rc
    if `aggte_rc' {
        * no caller-supplied remedy means the user typed csdid_stats
        * themselves; name this command's own retype, keeping the saved-RIF
        * path's `using' -- without it the advice would tell a RIF user to
        * aggregate results that are not in e().
        if `"`remedy'"' == "" {
            local remedy "csdid_stats"
            * The path is quoted in the advice, as the load call quotes it:
            * a saved RIF under a directory with a space produced a retype
            * line that Stata's own `using' qualifier could not parse, so the
            * one caller the remedy exists to help was handed a command that
            * does not run.
            if `"`using'"' != "" local remedy `"`remedy' using "`using'""'
            local remedy `"`remedy', type(`type') dropmissing"'
            * and the options that change WHICH aggregation is computed,
            * spelled as the user spelled them. Advice that drops window() or
            * balance() names a command that runs and answers a different
            * question than the one that just failed -- the numbers come back
            * and nothing says they are a different aggregation.
            if `"`window'"' != "" local remedy `"`remedy' window(`window')"'
            if `"`balance'"' != "" local remedy `"`remedy' balance(`balance')"'
            * level() is deliberately NOT carried: by this point an omitted
            * level has already been filled in from e(level), so echoing it
            * would add an option the user never typed to advice that means
            * the same thing without it.
        }
        _csdid_stats_aggfail, type(`type') mine(`min_e') maxe(`max_e') ///
            bale(`balance_e') narm(`na_rm_flag') usecache(`use_cache') ///
            remedy(`remedy')
        exit `aggte_rc'
    }
    * Owner decision 2026-08-28: when dropmissing removed an estimated cell
    * INSIDE the balanced window, the balanced profile's cohort composition
    * differs across the event times it reports -- announced here, error-styled
    * so it survives a caller's `quietly' (a composition property of the
    * reported table changed; the rule stated at the bal() drop in csdid.ado
    * applies identically).
    capture confirm scalar CSDID_AGG_BAL_DRIFT
    if !_rc {
        local bal_drift = scalar(CSDID_AGG_BAL_DRIFT)
        scalar drop CSDID_AGG_BAL_DRIFT
        local bal_drift_list `"$CSDID_AGG_BAL_DRIFT_LIST"'
        global CSDID_AGG_BAL_DRIFT_LIST
        local bal_drift_more ""
        if `bal_drift' > 5 local bal_drift_more "; ..."
        display as error `"warning: `bal_drift' missing cell(s) fall inside the balance(`balance_e') window (`bal_drift_list'`bal_drift_more'), so under dropmissing their cohorts leave those event times while remaining in the rest of the window: the balanced profile's cohort composition differs across event times. See e(attgt) for the missing cells."'
    }
    capture confirm scalar e(bstrap)
    local bstrap = 0
    if !_rc local bstrap = e(bstrap)
    * ---------------------------------------------------------------------
    * The simultaneous band is an AGGREGATION-level decision in R, and it is
    * not always e(cband). Two cases where R computes no band critical value
    * and reports the pointwise normal quantile instead:
    *
    *   type(simple)  compute.aggte.R:288-322 returns an object with no
    *                 crit.val.egt at all, and AGGTEobj.R:80-83 bands the
    *                 overall ATT at qnorm(1-alp/2).
    *   two periods   pre_process_did.R:523 sets cband <- FALSE on the
    *                 SETTLED time grid, which reaches compute.aggte through
    *                 DIDparams (l.117-118) and skips the mboot band call in
    *                 all three windowed branches (l.366/510/643).
    *
    * The estimation's own e(cband) is untouched: att_gt keeps its local
    * cband TRUE in both cases (att_gt.R:291/694), so the ATT(g,t) band stays
    * simultaneous. Only the aggregation reads the local below, and R draws
    * no band block in these cases either, so passing it to the kernels is
    * what keeps the draw stream aligned, not only the reported crit.
    * ---------------------------------------------------------------------
    local agg_simple = ("`type'" == "simple")
    local cband = 0
    capture confirm scalar e(cband)
    if !_rc local cband = e(cband)
    if `cband' & `agg_simple' local cband = 0
    capture confirm scalar e(N_time)
    if !_rc {
        if `cband' & e(N_time) == 2 local cband = 0
    }
    if `bstrap' {
        local biters = e(biters)
        * Same cap, same gate as the estimation stage: the aggregation
        * bootstrap writes biters-row Stata matrices too, and biters is
        * INHERITED from e(biters), so a run that got past csdid on a raised
        * matsize can still meet the cap here in a later session.
        if c(stata_version) < 16 & `biters' > c(matsize) {
            display as error "this Stata version limits matrix dimensions with -set matsize- (currently `=c(matsize)'), and the aggregation bootstrap inherits e(biters) = `biters' from the estimation. Type -set matsize `biters'- and rerun, or re-run csdid with a smaller reps()."
            exit 908
        }
        local boot_dist "`e(boot_dist)'"
        if "`boot_dist'" == "" local boot_dist "rademacher"
        tempname boot_aggte agg_boot_draws agg_crit agg_pointcrit boot_rng_state agg_bootstrap_profile
        * sources for the variables-input plugin path: unit/group map name,
        * repeated-cross-section time variable, and whether clustering is on
        local agg_unit_src "e(unit_group)"
        if "`e(panel_mode)'" == "allow_unbalanced" {
            capture confirm matrix e(unit_group_boot)
            if !_rc local agg_unit_src "e(unit_group_boot)"
        }
        local agg_time_src ""
        if "`e(idvar)'" == "" local agg_time_src "`e(timevar)'"
        local boot_agg_if ""
        local boot_agg_cluster_vec ""
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
        * The draw policy and the four names the results come back in are the
        * same at all three aggregate-bootstrap kernel call sites below -- the
        * replication count and the level the ESTIMATION settled on, the draw
        * distribution, the seeded state, and the names for the table, the
        * draws and the two critical values. They are written once here so the
        * three cannot drift apart; the arguments that differ (which influence
        * functions, and the cluster vector) stay at each call.
        local agg_boot_args `"`biters', (100 - `level') / 100, `cband', "`boot_dist'", "`boot_rng_arg'", "`boot_aggte'", "`agg_boot_draws'", "`agg_crit'", "`agg_pointcrit'", `agg_simple'"'
        local agg_boot_accel "mata"
        local agg_boot_status "mata-unseeded"
        local agg_boot_rc 0
        * stale flags from an earlier aggregation must not label this one
        capture scalar drop CSDID_AGG_CRIT_FALLBACK
        capture scalar drop CSDID_AGG_CRIT_LARGE
        local agg_plugin_success 0
        * type(simple) is the ONLY aggregation whose overall column reuses
        * the effect column's draws: R computes it with one getSE/mboot call
        * (compute.aggte.R:310). A one-effect event or group window has a
        * bit-identically duplicated influence matrix and is still given its
        * own mboot block for the overall se (compute.aggte.R:414/546/680),
        * so the shape of the influence matrix must not decide this.
        if "$CSDID_BOOT_PLUGIN_DISABLE" == "1" {
            local agg_boot_status "mata-plugin-disabled"
        }
        else if "`boot_rng_arg'" != "" & "`boot_dist'" == "rademacher" & ///
            "`e(bootstrap_accelerator)'" == "plugin" {
            * F-004, resolved rather than avoided. For type(simple) R's aggte
            * runs a SINGLE mboot whose draws serve both the effect and the
            * overall column. The plugin draws the overall column from its own
            * stream, which R never draws, so using it unchanged made
            * overall_se diverge.
            *
            * type(simple) was therefore excluded outright, which left the
            * simplest aggregation as the slowest: measured on 30,000 units and
            * 999 replications, simple took 1.081s on the Mata kernels against
            * 0.350s for group and 0.443s for calendar on the plugin.
            *
            * The Mata rule it was falling back to is two lines -- draw column
            * one, copy it to the overall column, no second draw -- so the
            * plugin can be used and the same rule applied to its output. That
            * is what happens after the call below. The plugin still consumes
            * its overall-column block; the block is discarded rather than
            * read, so the reported draws are R's and the extra consumption
            * only moves the random state, which nothing downstream reads (the
            * state is re-derived from rseed() on the next command).
            local agg_boot_status "mata-plugin-unavailable"
            local agg_plugin_bound 0
            capture quietly findfile csdid.ado
            if !_rc {
                local agg_csdid_path "`r(fn)'"
                local agg_plugin_file "`e(bootstrap_accelerator_file)'"
                * Sibling of the resolved csdid.ado by trailing substr, never
                * substring replacement -- same rule and reasons as the
                * estimation stage's binding block in csdid.ado, which also
                * documents why a plugin handle's aliveness check is the
                * recorded rc-0 bind (program list cannot see plugins) and
                * why rc 110 is never accepted as a load.
                local _ap_len = strlen("`agg_csdid_path'")
                local agg_plugin_dir ""
                if `_ap_len' > 9 & substr("`agg_csdid_path'", `_ap_len' - 8, .) == "csdid.ado" {
                    local agg_plugin_dir = substr("`agg_csdid_path'", 1, `_ap_len' - 9)
                }
                local agg_plugin_path "`agg_plugin_dir'`agg_plugin_file'"
                capture confirm file "`agg_plugin_path'"
                if !_rc {
                    if "$CSDID_AGG_BOOT_PLUGIN_PATH" == "`agg_plugin_path'" {
                        local agg_plugin_bound 1
                    }
                    if !`agg_plugin_bound' {
                        capture program drop __csdid_agg_boot_plugin
                        capture program __csdid_agg_boot_plugin, plugin using("`agg_plugin_path'")
                        local agg_bind_rc = _rc
                        if `agg_bind_rc' == 0 {
                            global CSDID_AGG_BOOT_PLUGIN_PATH "`agg_plugin_path'"
                            local agg_plugin_bound 1
                        }
                        else if `agg_bind_rc' == 110 & "$CSDID_AGG_BOOT_PLUGIN_PATH" != "" {
                            local agg_boot_status "mata-stale-plugin-binding"
                            local agg_boot_rc = 110
                        }
                        else {
                            local agg_boot_status "mata-plugin-load-failed"
                            local agg_boot_rc = `agg_bind_rc'
                        }
                    }
                }
            }
            if `agg_plugin_bound' {
                tempname agg_plugin_independent agg_plugin_common agg_plugin_input ///
                    agg_plugin_n ///
                    agg_plugin_nc agg_plugin_cluster agg_plugin_started agg_rng_backup
                matrix `agg_rng_backup' = `boot_rng_state'
                local agg_plugin_rc 0
                * variables-input path: the influence functions never leave
                * Mata as a Stata matrix (matrix CREATION is quadratic in
                * rows; measured 48s at 100,000 units). The plugin reads them
                * from temp variables, exactly as the estimation stage does.
                local agg_plugin_k 0
                capture mata: st_local("agg_plugin_k", strofreal(csdid_cache_agg_cols()))
                if `agg_plugin_k' < 2 local agg_plugin_rc 498
                local agg_plugin_effects = `agg_plugin_k' - 1
                local agg_plugin_if_vars ""
                if !`agg_plugin_rc' {
                    forvalues agg_plugin_col = 1/`agg_plugin_k' {
                        tempvar agg_plugin_if_var
                        capture generate double `agg_plugin_if_var' = .
                        if _rc local agg_plugin_rc = _rc
                        local agg_plugin_if_vars "`agg_plugin_if_vars' `agg_plugin_if_var'"
                    }
                }
                if !`agg_plugin_rc' {
                    capture mata: csdid_agg_boot_plugin_prep_vars("`agg_unit_src'", "`agg_time_src'", `use_cluster', "`agg_plugin_if_vars'", "`agg_plugin_n'", "`agg_plugin_nc'", "`agg_plugin_cluster'", "`agg_plugin_started'")
                    local agg_plugin_rc = _rc
                    if `agg_plugin_rc' == 1 exit 1
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
                    * `in 1/<rows>' matches the estimation-stage call in
                    * csdid.ado. Without it the plugin received an
                    * unrestricted observation range and read a PREFIX of the
                    * data of the declared width; the plugin now refuses a
                    * range that is not exactly the declared width, so the two
                    * call sites read exactly the rows the influence
                    * functions describe.
                    capture plugin call __csdid_agg_boot_plugin `agg_plugin_if_vars' in 1/`agg_plugin_nc_value', ///
                        bootstrap_agg_vars `biters' `agg_plugin_nc_value' `cband' ///
                        `agg_plugin_independent' ///
                        `agg_plugin_common' `boot_rng_state'
                    local agg_plugin_rc = _rc
                    if `agg_plugin_rc' == 1 exit 1
                }
                if !`agg_plugin_rc' & `agg_simple' {
                    * The duplicate rule, applied to the plugin's output: the
                    * overall column IS the effect column, not a second draw.
                    capture matrix `agg_plugin_independent'[1, `agg_plugin_k'] = ///
                        `agg_plugin_independent'[1..., 1]
                    if _rc local agg_plugin_rc = _rc
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
                    * Break, like the two captures above it. This call
                    * summarizes biters x k draws and computes the
                    * simultaneous critical value, so it is exactly where a
                    * user interrupts; without this the Break was absorbed,
                    * reported as a plugin failure, and the whole bootstrap
                    * was recomputed on the Mata path, forcing the user to
                    * press Break a second time.
                    if `agg_plugin_rc' == 1 exit 1
                }
                if !`agg_plugin_rc' {
                    local agg_plugin_success 1
                    local agg_boot_accel "plugin"
                    local agg_boot_status "plugin-active"
                    if `agg_simple' {
                        * the plugin consumed an overall-column block R never
                        * draws for type(simple); the state posted below must
                        * be R's, so rewind and advance by the single block
                        * R's one mboot call consumes.
                        matrix `boot_rng_state' = `agg_rng_backup'
                        mata: csdid_bmisc_skiponce(st_numscalar("`agg_plugin_nc'"), `biters', "`boot_rng_state'")
                    }
                }
                else {
                    matrix `boot_rng_state' = `agg_rng_backup'
                    local agg_boot_status "mata-plugin-failed"
                    local agg_boot_rc = `agg_plugin_rc'
                }
            }
        }
        local agg_direct_done 0
        if !`agg_plugin_success' & `use_cache' {
            * Fresh fit, lean storage (the default): the aggregation IF lives
            * in the Mata cache. Assemble, bootstrap and write back entirely
            * in Mata. No n_units-row object crosses the Mata-Stata boundary:
            * classic-matrix creation is quadratic in rows (measured per
            * write: 4s at 25k, 27s at 50k, 145s at 100k) and impossible past
            * c(max_matdim) rows, which made the old route take minutes on
            * any platform where the plugin does not run -- unseeded fits,
            * non-rademacher draws, and every OS without the shipped plugin.
            capture mata: csdid_bootstrap_aggte_direct("`aggte'", "`agg_unit_src'", "`agg_time_src'", `use_cluster', `agg_boot_args')
            local agg_boot_kernel_rc = _rc
            if `agg_boot_kernel_rc' == 1 exit 1
            if `agg_boot_kernel_rc' {
                display as error `"csdid_stats could not bootstrap the type(`type') aggregation; rerun csdid before csdid_stats"'
                exit `agg_boot_kernel_rc'
            }
            local agg_direct_done 1
        }
        if !`agg_plugin_success' & !`agg_direct_done' {
            * storeall / saved-RIF entry: the influence functions genuinely
            * live in Stata matrices, so the named-matrix route remains.
            *
            * The `agg_prep_done' flag that used to guard this branch was
            * vestigial: it is initialised to 0 and set to 1 only inside the
            * branch it guards, so it was always 0 where it was tested.
            *
            * The `if !`agg_store_large'' materialization that used to sit
            * here, with its c(max_matdim) refusal, was UNREACHABLE and its
            * comment claimed the opposite ("both facts now refuse loudly"):
            * reaching this branch at all requires use_cache == 0, which is
            * exactly agg_store_large == 1, so the test could never be true.
            * The influence functions are already in a Stata matrix on this
            * route -- that is what storeall means -- so nothing needed
            * materializing. The c(max_matdim) exposure it advertised is real
            * but lives on the saved-RIF LOAD, where it is now refused by name
            * (see _csdid_stats_load_rif).
            local boot_agg_if "`agg_inffunc'"
            local boot_agg_cluster_vec ""
            if `use_cluster' {
                tempname boot_agg_cluster_raw
                capture confirm matrix e(cluster_vec)
                if !_rc {
                    matrix `boot_agg_cluster_raw' = e(cluster_vec)
                }
                else {
                    * an empty Mata cluster cache would otherwise abort
                    * with raw Mata frames instead of a named refusal. The return
                    * code is not enough to detect it: the reader answers an empty
                    * matrix when no csdid has run in this session, and st_matrix()
                    * writes nothing for an empty matrix WITHOUT setting _rc
                    * (measured), so a missing cache would slip past a plain -if
                    * _rc- and surface later as a raw r(111) on a matrix that was
                    * never created. Confirm the matrix arrived instead.
                    capture mata: st_matrix("`boot_agg_cluster_raw'", csdid_cache_cluster_vec())
                    capture confirm matrix `boot_agg_cluster_raw'
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
                * the 4-column cached unit map. csdid_boot_reorder_r then
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
            * capture + re-raise so a bootstrap-kernel refusal
            * ("BMisc bootstrap RNG state is invalid", "stored aggregate
            * influence functions do not match aggregation results") cannot
            * drag Mata frames into the user's log.
            *
            * The two kernels stay two: one scales by the unit count and the other
            * by the cluster count, and they are named separately from outside this
            * file, so which one runs is decided here.
            if `use_cluster' {
                capture mata: csdid_bootstrap_aggte_cluster("`aggte'", "`boot_agg_if'", "`boot_agg_cluster_vec'", `agg_boot_args')
            }
            else {
                capture mata: csdid_bootstrap_aggte("`aggte'", "`boot_agg_if'", `agg_boot_args')
            }
            local agg_boot_kernel_rc = _rc
            if `agg_boot_kernel_rc' {
                display as error `"csdid_stats could not bootstrap the type(`type') aggregation; rerun csdid before csdid_stats"'
                exit `agg_boot_kernel_rc'
            }
        }
        * The kernels reproduce R's aggregation-level band fallbacks by VALUE
        * (crit clamped up to the pointwise quantile); R also warns and
        * relabels the band as pointwise (cband <- FALSE) when that happens.
        * Reproduce the label and the warning here: `cband' feeds both the
        * header line and e(agg_cband) below.
        *
        * These band notes are error-styled, like the bal-drift warning below
        * and for the same reason: -quietly- suppresses text but not error,
        * and csdid_estat reaches this computation through
        * `quietly csdid_stats'. On the text channel every one of them was
        * lost on the estat route -- measured: `estat event' after an
        * analytical estimation printed the aggregation with no hint that its
        * simultaneous band came from 1,000 multiplier draws while the
        * standard errors stayed analytical, a disclosure the identical
        * direct `csdid_stats, type(dynamic)' call did print. Each of these
        * says the band you are being shown is not the band you asked for, or
        * not the band the header implies; none may be silenceable by a
        * caller's -quietly-.
        capture confirm scalar CSDID_AGG_CRIT_FALLBACK
        if !_rc {
            local agg_crit_fallback = scalar(CSDID_AGG_CRIT_FALLBACK)
            scalar drop CSDID_AGG_CRIT_FALLBACK
            if `cband' & `agg_crit_fallback' == 1 {
                display as error "warning: the simultaneous confidence band is narrower than the pointwise confidence interval, which is unexpected. Falling back to pointwise confidence intervals."
                local cband 0
            }
            else if `cband' & `agg_crit_fallback' == 2 {
                display as error "warning: simultaneous critical value is NA, likely because the standard errors could not be computed. Falling back to pointwise confidence intervals."
                local cband 0
            }
        }
        capture confirm scalar CSDID_AGG_CRIT_LARGE
        if !_rc {
            scalar drop CSDID_AGG_CRIT_LARGE
            if `cband' display as error "warning: simultaneous critical value is very large, suggesting it may be unreliable. This typically happens when the number of observations per group is small and/or there is not much variation in outcomes. Consider using pointwise confidence intervals instead (specify pointwise on the estimation)."
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
        * R's aggte draws from the live session stream, so a second
        * aggregation after the same estimation uses FURTHER draws (executed
        * witness: R's chained group crit 2.5068146 against the restarted
        * 2.2719166). The kernels advance `boot_rng_state' in place; posting
        * it back makes the next aggregation start where R's stream stands.
        if "`boot_rng_arg'" != "" {
            tempname agg_rng_out
            matrix `agg_rng_out' = `boot_rng_state'
            ereturn matrix boot_rng_state = `agg_rng_out'
        }
    }
    else if `cband' {
        * R parity, the banded ANALYTICAL aggregation: aggte() on a fit with
        * the bootstrap off but the band request on still computes the
        * SIMULTANEOUS band -- by multiplier bootstrap, because that is the
        * only way to compute one -- and says so (compute.aggte's "Used
        * bootstrap procedure to compute simultaneous confidence band"). The
        * standard errors in the table stay analytical; only the band's
        * critical value is bootstrapped, from ONE joint draw block over the
        * effect columns. Draws come from the session's random-number stream
        * (set seed reproduces them), the reference's own semantics for a fit
        * carrying no bootstrap state, and the reference's default 1000 draws
        * are used since analytical fits carry no reps(). type(simple) and a
        * two-period grid never reach here: their `cband' is already 0 above,
        * as it is in the reference. The saved-RIF route posts no e(cband),
        * so it keeps its documented fully-analytical fallback.
        display as error "note: simultaneous confidence bands can only be computed by the multiplier bootstrap, so the bootstrap was used for the band below: its critical value comes from 1,000 multiplier draws on the session's random-number stream (set seed reproduces it). The standard errors remain analytical (influence function). Specify pointwise for fully analytical, pointwise intervals."
        capture scalar drop CSDID_AGG_CRIT_FALLBACK
        capture scalar drop CSDID_AGG_CRIT_LARGE
        tempname agg_crit agg_pointcrit
        local agg_unit_src "e(unit_group)"
        if "`e(panel_mode)'" == "allow_unbalanced" {
            capture confirm matrix e(unit_group_boot)
            if !_rc local agg_unit_src "e(unit_group_boot)"
        }
        local agg_time_src ""
        if "`e(idvar)'" == "" local agg_time_src "`e(timevar)'"
        if `use_cache' {
            capture mata: csdid_analytical_cband("`aggte'", "", "", "`agg_unit_src'", "`agg_time_src'", `use_cluster', 1000, (100 - `level') / 100, "", "`agg_crit'", "`agg_pointcrit'")
        }
        else {
            local band_cluster_vec ""
            if `use_cluster' {
                capture confirm matrix e(cluster_vec)
                if !_rc {
                    tempname band_cluster_raw
                    matrix `band_cluster_raw' = e(cluster_vec)
                    local band_cluster_vec "`band_cluster_raw'"
                }
            }
            capture mata: csdid_analytical_cband("`aggte'", "`agg_inffunc'", "`band_cluster_vec'", "", "", `use_cluster', 1000, (100 - `level') / 100, "", "`agg_crit'", "`agg_pointcrit'")
        }
        local band_rc = _rc
        if `band_rc' == 1 exit 1
        if `band_rc' {
            display as error `"csdid_stats could not bootstrap the simultaneous band for the type(`type') aggregation; rerun csdid before csdid_stats, or specify pointwise"'
            exit `band_rc'
        }
        * the same fallback labeling the seeded band carries: a band that
        * clamped to (or could not beat) the pointwise quantile is reported
        * AS pointwise, with the reference's warning.
        capture confirm scalar CSDID_AGG_CRIT_FALLBACK
        if !_rc {
            local agg_crit_fallback = scalar(CSDID_AGG_CRIT_FALLBACK)
            scalar drop CSDID_AGG_CRIT_FALLBACK
            if `agg_crit_fallback' == 1 {
                display as error "warning: the simultaneous confidence band is narrower than the pointwise confidence interval, which is unexpected. Falling back to pointwise confidence intervals."
                local cband 0
            }
            else if `agg_crit_fallback' == 2 {
                display as error "warning: simultaneous critical value is NA, likely because the standard errors could not be computed. Falling back to pointwise confidence intervals."
                local cband 0
            }
        }
        capture confirm scalar CSDID_AGG_CRIT_LARGE
        if !_rc {
            scalar drop CSDID_AGG_CRIT_LARGE
            if `cband' display as error "warning: simultaneous critical value is very large, suggesting it may be unreliable. This typically happens when the number of observations per group is small and/or there is not much variation in outcomes. Consider using pointwise confidence intervals instead (specify pointwise on the estimation)."
        }
        ereturn scalar crit_val = `agg_crit'
        ereturn scalar point_crit_val = `agg_pointcrit'
    }
    matrix colnames `aggte' = egt att se overall_att overall_se
    * When every standard error in the aggregation is
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
        display as text "note: every standard error in this type(`type') aggregation is missing, because the ATT(g,t) estimates it aggregates have none. The usual causes are a cohort with a single comparison unit, a perfectly collinear covariate design, or an outcome scale that overflows the variance. The point estimates below are still valid: they are the aggregation of the ATT(g,t) estimates."
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
    ereturn scalar agg_level = `level'
    ereturn scalar N_aggte = `n_aggte'
    * The band the table below actually carries, which is NOT e(cband):
    * type(simple) and a two-period grid are banded pointwise however the
    * estimation was asked to band ATT(g,t) (see the note above). Reading
    * e(cband) after an aggregation therefore describes the estimation, not
    * the aggregation; this is the machine-readable form of the header line
    * Display writes from the same local.
    ereturn scalar agg_cband = `cband'

    local display_noisy = c(noisily)
    if `display_noisy' Display, level(`level') cband(`cband')
end

* Kernel-refusal helper. Reproduces csdid_aggte()'s own refusal diagnosis on the ado
* side so the kernel can be called under a plain -capture- (the only form that
* suppresses the Mata traceback log; -capture noisily- does not, measured in
* Stata 17). The probe reads only e(attgt), e(inffunc) and e(group_prob) -
* state csdid_aggte() has not modified at the point it refuses - and mirrors
* the kernel's wording and its check order. It never aborts: if the probe
* itself fails it is discarded and the caller falls back to a generic message,
* so a probe defect can never turn a working aggregation into a refusal.
* Mirror of csdid_stats's own syntax line, minus the `*' catch-all and the
* options this command parses by hand out of `options' (min_e(), max_e(),
* balance_e(), cluster()/clustervars(), na_rm/na.rm/dropmissing). A leftover
* token that THIS parses is one of csdid_stats's declared options appearing a
* second time, whatever abbreviation was typed -- Stata does the abbreviation
* matching, so the two declaration lists cannot drift into disagreement the
* way a hand-written name list did.
program define _csdid_stats_optdup, rclass
    version 14
    * REMEDY is declared here too, so this mirror keeps holding exactly the
    * main syntax line's options: without it a repeated remedy() fell through
    * to the catch-all and was reported as an UNSUPPORTED option, which is the
    * one thing this program exists to prevent.
    syntax [, TYPE(string) Level(cilevel) WINdow(string) BALance(string) ///
        REMEDY(string) ///
        DROPMissing FROM(string)]
    local hit ""
    if `"`type'"' != "" local hit "type"
    if `"`window'"' != "" local hit "window"
    if `"`balance'"' != "" local hit "balance"
    if `"`from'"' != "" local hit "from"
    if `"`remedy'"' != "" local hit "remedy"
    if "`dropmissing'" != "" local hit "dropmissing"
    * level(cilevel) always resolves to a value, so it is the only declared
    * option a successful parse cannot distinguish by emptiness.
    if "`hit'" == "" local hit "level"
    return local option "`hit'"
end

program define _csdid_stats_aggfail
    version 14
    syntax , TYPE(string) MINE(string) MAXE(string) BALE(string) ///
        NARM(integer) USECACHE(integer) [REMEDY(string)]
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
                    if (`narm' == 0) __csdid_pM = sprintf("%g of the %g ATT(g,t) cells have a missing estimate, so the aggregation is not defined over the full set of cells. Specify dropmissing to aggregate over the %g cells that were estimated (that is: %s), or address the cause of the failures (the per-cell warnings above name it) and re-run.", sum(__csdid_pA[., 4] :>= .), rows(__csdid_pA), sum(__csdid_pA[., 4] :< .), st_local("remedy")); ///
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
    * The probe builds fifteen external Mata objects, one of which is a full
    * copy of e(inffunc), and left every one of them in the session namespace
    * after a refusal. The Wald block in csdid.ado ends the same way.
    capture mata: mata drop __csdid_p*
    if `"`msg'"' == "" {
        local msg "csdid_stats could not compute the type(`type') aggregation from the stored ATT(g,t) results; check window()/balance()/dropmissing and the ATT(g,t) table"
    }
    display as error `"`msg'"'
end

program define Display
    version 14
    syntax [, Level(cilevel) CBand(integer 0)]
    tempname out
    matrix `out' = e(aggte)
    display as text _newline "Aggregated treatment effects"
    * -------------------------------------------------------------------
    * #19. level() was parsed here and never used, and the table printed
    * with nothing above it saying how the standard errors were produced.
    * A reader could not tell an analytical run from a bootstrap, could not
    * see the replication count, and -- the part that costs people time --
    * could not see that an UNSEEDED bootstrap had been run, whose numbers
    * drift between two identical calls. That is the same gap the estimation
    * display closed
    * on the estimation side; this is the aggregation side of it, built
    * from the same e() macros and printed in the same shape.
    *
    * The aggregation has no inference options of its own -- it inherits
    * the estimation's -- so these read from the estimation's stored
    * results, except the level, which is this command's own and is now
    * the argument that was already being passed in.
    * -------------------------------------------------------------------
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
    * The aggregation's own band decision, not e(cband): type(simple) and a
    * two-period grid are banded pointwise (see the caller), and the header
    * has to say which band the table below it carries.
    local band_kind "pointwise"
    if `cband' == 1 local band_kind "simultaneous"
    display as text "`inf_line'; `level'% `band_kind' bands"
    * The estimation side prints the same line; see the note above its copy in
    * csdid.ado for why an unseeded bootstrap gets a sentence rather than a
    * label.
    if `unseeded' {
        display as text "Note: no rseed() set, so these standard errors change slightly between runs; add rseed(#) to reproduce them."
    }
    matlist `out', names(columns) format(%10.6g)
end

program define _csdid_stats_load_rif, eclass
    version 14
    syntax using/

    tempname IF UG ATT GP CL
    preserve
    use `"`using'"', clear
    * -datasignature confirm- verifies the row-level content signature the
    * writer set: any edit to the ordered values of any column -- including
    * a sum-preserving weight shift that every aggregate check would miss
    * (cold-audit round 9) -- refuses here by name. Artifacts written before
    * the signature existed carry none and are told to be rewritten.
    capture datasignature confirm, strict
    if _rc == 9 {
        display as error "saved RIF artifact fails its content signature: the file's rows are not the rows csdid wrote, so aggregating it would report the tampered content under the original estimation's certificate. Re-run csdid with saverif() to rewrite the file."
        exit 459
    }
    if _rc != 0 {
        display as error "saved RIF artifact carries no content signature (it predates the signed format); re-run csdid with saverif() to rewrite the file with one."
        exit 459
    }
    * the canonical metadata record must equal what the characteristics say
    * NOW: any characteristic edit -- a blanked cluster variable, a moved
    * level, doctored counts or probabilities -- breaks the equality even
    * though characteristics sit outside -datasignature-'s own coverage.
    capture confirm variable __csdid_meta
    if _rc {
        display as error "saved RIF artifact carries no signed metadata record (it predates the signed format); re-run csdid with saverif() to rewrite the file."
        exit 459
    }
    * the positional digest must be recomputed over the numeric content in
    * the same shape the writer hashed: read the stored record, drop the
    * record variable, hash what remains, and require the rebuilt canonical
    * record (digest included) to equal the stored one. Any within-column
    * permutation, cross-column exchange, or sign flip -- invisible to
    * -datasignature- -- changes the serialized stream and refuses here.
    local meta_stored = __csdid_meta[1]
    quietly drop __csdid_meta
    mata: st_local("rif_cdigest", strofreal(hash1(st_data(., .), 2147483647), "%12.0f") + "-" + strofreal(hash1(st_data(., .)', 2147483647), "%12.0f"))
    local meta_canon `"|cdigest=`=subinstr(strtrim("`rif_cdigest'"), " ", "", .)'"'
    foreach ck in artifact cmdline panel_mode control_group base_period method N N_units N_attgt N_groups N_time anticipation level cluster_recorded clustervar N_clusters time_first group_prob_rows {
        local meta_canon `"`meta_canon'|`ck'=`: char _dta[csdid_`ck']'"'
    }
    local ngp "`: char _dta[csdid_group_prob_rows]'"
    capture confirm integer number `ngp'
    if !_rc {
        forvalues mi = 1/`ngp' {
            local meta_canon `"`meta_canon'|gp`mi'=`: char _dta[csdid_group_prob_`mi']'"'
        }
    }
    foreach mv of varlist rif* {
        local meta_canon `"`meta_canon'|`mv'=`: char `mv'[csdid_attgt]'"'
    }
    if `"`meta_canon'"' != `"`meta_stored'"' {
        display as error "saved RIF artifact fails its metadata signature: the file's rows or characteristics are not the ones csdid wrote (values moved, exchanged, or flipped; or a cluster marker, level, count, or cell record edited), so aggregating it would report altered inference under the original estimation's certificate. Re-run csdid with saverif() to rewrite the file."
        exit 459
    }
    if "`: char _dta[csdid_artifact]'" != "rif" {
        display as error "saved file is not a csdid RIF artifact"
        exit 498
    }
    * without this marker the file cannot say whether the estimation
    * clustered, and aggregating it would report i.i.d. standard errors for a
    * clustered run with nothing on screen to say so. Refuse by name instead.
    if "`: char _dta[csdid_cluster_recorded]'" != "1" {
        display as error "saved RIF artifact does not record whether the estimation clustered, so aggregating it could report unclustered standard errors for a clustered run. Re-run csdid with saverif() to rewrite the file."
        exit 498
    }
    local rif_clustervar "`: char _dta[csdid_clustervar]'"
    if "`rif_clustervar'" != "" {
        capture confirm variable cluster
        if _rc {
            display as error "saved RIF artifact records clustering on `rif_clustervar' but its cluster column is missing; the file in using() was written by csdid but has been modified since"
            exit 498
        }
    }
    * the artifact-contract checks either side of these two are specific
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
    * -unab- with no match aborts r(111) on its own, before the
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

    * The load materializes the influence functions as CLASSIC Stata
    * matrices, whose dimensions are capped at c(max_matdim) (11,000 on
    * SE/MP, 800 on BE). mkmat raises a bare `error 915' at that cap, naming
    * neither the file, nor the size, nor a remedy -- and the WRITER has no
    * matching cap, because saverif() fills the artifact through st_store,
    * which is linear and uncapped. So a large estimation could write an
    * artifact that could never be read back, and the user found out on the
    * way back with a stock r(915). The test mirrors mkmat's own
    * max(_N, nvar), and it is placed before the first crossing so that it
    * covers all four (two mkmat calls and two ereturn matrix posts).
    quietly count
    local rif_rows = r(N)
    local rif_dim = max(`rif_rows', `nrif')
    if `rif_dim' > c(max_matdim) {
        restore
        display as error "saved RIF artifact in using() holds `rif_rows' unit rows and `nrif' ATT(g,t) columns, and reading it needs a matrix of `rif_dim' rows or columns; this Stata's limit is `=c(max_matdim)'. The artifact is valid -- it was written through a path with no such limit -- but it cannot be read back on this Stata flavour. Use Stata/SE or Stata/MP, or re-run csdid rather than reloading."
        exit 908
    }

    mkmat `rifvars', matrix(`IF')
    if "`rif_clustervar'" != "" mkmat cluster, matrix(`CL')
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
    * Ten columns: the nine documented ATT(g,t) columns plus base_time, the
    * reference period each cell was differenced against. base_time is what
    * lets a reloaded artifact identify the universal-base normalisation row
    * and name coefficients with the base period the run actually used, so an
    * artifact written before the column existed is refused rather than
    * silently reloaded one column short.
    matrix `ATT' = J(`nrif', 10, .)

    local treated_groups ""
    forvalues j = 1/`nrif' {
        local rv : word `j' of `rifvars'
        local meta : char `rv'[csdid_attgt]
        if `"`meta'"' == "" {
            display as error "saved RIF artifact is missing ATT metadata for `rv'"
            exit 498
        }
        if wordcount(`"`meta'"') != 10 {
            display as error "saved RIF artifact has damaged ATT metadata for `rv': it holds `=wordcount(`"`meta'"')' fields where csdid 2.0.0 writes 10 (group, time, event_time, att, se, and the four counts, then base_time). The file in using() was written by csdid but has been modified since, or predates the base_time field. Re-run csdid with saverif() to rewrite it."
            exit 498
        }
        forvalues c = 1/10 {
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

    * ------------------------------------------------------------------
    * #20. The aggregation weights above are REBUILT from the data. The
    * artifact also records what they were when the estimation ran, and
    * nothing read them -- so a RIF whose group or weight column had been
    * edited silently produced different aggregation weights instead of
    * being refused. A MISSING column is already refused above; a changed one
    * went through.
    *
    * They are checked, not substituted. Substituting would silently change
    * results for existing artifacts, and the recorded value is a decimal
    * rendering rather than the exact double, so the tolerance below is set
    * by the stored format -- sixteen significant digits, measured -- and
    * not by the arithmetic.
    *
    * Artifacts written before these chars existed carry none of this and
    * are loaded exactly as before.
    * ------------------------------------------------------------------
    local gp_rows "`: char _dta[csdid_group_prob_rows]'"
    if "`gp_rows'" != "" {
        if `gp_rows' != `n_groups' {
            display as error "this RIF file records `gp_rows' treatment group(s) but the data in it contain `n_groups'; the group column has been altered since the file was written, so the aggregation weights would not be the ones the estimation used. Re-save the RIF from a fresh csdid run."
            exit 459
        }
        forvalues i = 1/`gp_rows' {
            local gp_meta "`: char _dta[csdid_group_prob_`i']'"
            if "`gp_meta'" != "" {
                local want_g : word 1 of `gp_meta'
                local want_p : word 2 of `gp_meta'
                local want_n : word 3 of `gp_meta'
                local got_g = `GP'[`i', 1]
                local got_p = `GP'[`i', 2]
                local got_n = `GP'[`i', 3]
                local bad = 0
                if `want_g' != `got_g' local bad = 1
                if `want_n' != `got_n' local bad = 1
                if abs(`want_p' - `got_p') > 1e-6 * max(1, abs(`want_p')) local bad = 1
                if `bad' {
                    display as error "the aggregation weights rebuilt from this RIF file do not match the ones it records: group `want_g' had probability `want_p' over `want_n' observations, and the file's own data now give group `got_g', probability `got_p' over `got_n'. The group or weight column has been altered since the file was written. Re-save the RIF from a fresh csdid run."
                    exit 459
                }
            }
        }
    }
    local n_attgt_meta "`: char _dta[csdid_N_attgt]'"
    if "`n_attgt_meta'" != "" {
        if `n_attgt_meta' != rowsof(`ATT') {
            display as error "this RIF file records `n_attgt_meta' ATT(g,t) cell(s) but `=rowsof(`ATT')' were read from it; the file has been altered since it was written. Re-save the RIF from a fresh csdid run."
            exit 459
        }
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
    local N_clusters "`: char _dta[csdid_N_clusters]'"
    restore

    matrix colnames `ATT' = group time event_time att se n_treat_t n_treat_pre n_control_t n_control_pre base_time
    matrix colnames `GP' = group prob n_units
    matrix colnames `UG' = id group weight
    matrix colnames `IF' = `rifvars'
    if "`rif_clustervar'" != "" matrix colnames `CL' = cluster

    ereturn clear
    ereturn matrix attgt = `ATT'
    ereturn matrix inffunc = `IF'
    ereturn matrix group_prob = `GP'
    ereturn matrix unit_group = `UG'
    * the aggregation clusters off e(clustervar)/e(cluster_vec), so
    * reposting both is what makes `csdid_stats using' reproduce the standard
    * errors of the estimation that wrote the file rather than its i.i.d. ones.
    if "`rif_clustervar'" != "" {
        ereturn matrix cluster_vec = `CL'
        ereturn local clustervar "`rif_clustervar'"
    }
    ereturn local estat_cmd "csdid_estat"
    * predict is never valid after csdid; csdid_p is the guard that says so
    * instead of letting `predict' fall through to matrix scoring and abort
    * with r(111) naming a coefficient as a missing variable. Set here so the
    * reloaded state carries it before any estat runs.
    ereturn local predict "csdid_p"
    ereturn local marginsnotok "_ALL"
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
    if "`rif_clustervar'" != "" & "`N_clusters'" != "" {
        ereturn scalar N_clusters = real("`N_clusters'")
    }
    * Last, as [P] ereturn recommends: e(cmd)'s presence is the certificate
    * that everything else was stored, and postestimation gates on it.
    ereturn local cmd "csdid"
end
