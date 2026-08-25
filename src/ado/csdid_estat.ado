*! csdid_estat 2.0.0 25aug2026
program define csdid_estat, eclass
    version 14
    if "`e(cmd)'" != "csdid" {
        display as error "csdid_estat requires prior csdid results"
        exit 301
    }
    * fall through to Stata's estat_default for the STANDARD estat
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
            * estat summarize is the one forwarded subcommand that reads the
            * DATA in memory rather than stored results: without this check
            * it would describe whatever is in memory now and label it the
            * estimation sample. csdid signs its sample at estimation time;
            * results loaded from a saved RIF carry no signature and no
            * e(sample), and estat summarize already refuses those on its
            * own, so the check is applied only where a signature exists.
            if "`csdid_peek'" == substr("summarize", 1, max(2, `csdid_peek_n')) ///
                & `"`e(datasignaturevars)'"' != "" {
                checkestimationsample
            }
            estat_default `0'
            exit
        }
    }
    * dropmissing is DECLARED and forwarded to csdid_stats on
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
        display as error "from() is no longer supported; it set a lower event-time bound on the simple, group and calendar aggregations, which is now fixed at event time 0 -- the legacy default from(0) already was. Use window(# #) on estat event for event-time windows."
        exit 198
    }
    * The standard saving idiom -- saving(filename, replace) -- is parsed here
    * once for every route, rather than letting the comma travel into the
    * filename (csdid_plot's saving() had the identical defect and was fixed
    * first; csdid's saverif() carries the same
    * parser). `syntax' resets the STANDARD locals whether or not declared,
    * so the ones still needed downstream are saved around the sub-option
    * parse and put back.
    if `"`saving'"' != "" {
        mata: st_local("_sv_comma", strofreal(strpos(st_local("saving"), ",")))
        if `_sv_comma' {
            local _sv_outer_replace `"`replace'"'
            local _sv_rest ""
            gettoken _sv_file _sv_rest : saving, parse(",")
            if `"`_sv_file'"' == "," {
                local _sv_file ""
            }
            else {
                gettoken _sv_c _sv_rest : _sv_rest, parse(",")
                mata: st_local("_sv_file", strtrim(st_local("_sv_file")))
            }
            local _sv_options `"`options'"'
            local _sv_zero `"`0'"'
            local _sv_anything `"`anything'"'
            local 0 `", `_sv_rest'"'
            capture syntax [, REPLACE]
            local _sv_parse_rc = _rc
            local options `"`_sv_options'"'
            local 0 `"`_sv_zero'"'
            local anything `"`_sv_anything'"'
            if `_sv_parse_rc' {
                display as error `"saving() accepts only the replace sub-option; cannot parse: `_sv_rest'"'
                exit 198
            }
            if "`replace'" == "" local replace `"`_sv_outer_replace'"'
            if `"`_sv_file'"' == "" {
                display as error "saving() requires a filename before the comma, as in saving(myfile, replace)"
                exit 198
            }
            local saving `"`_sv_file'"'
        }
    }
    if `"`options'"' != "" {
        * -syntax- hands a REPEATED declared option to
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
    * a bare `csdid_estat' used to fall out of `syntax' with
    * Stata's stock r(100) "argument required" and no hint about what to type,
    * while the informative subcommand list sat one branch away at the bottom
    * of this program. Name the subcommands instead.
    if `"`subcmd'"' == `""' {
        display as error "csdid_estat requires a subcommand; supported subcommands are attgt, event, dynamic, simple, group, calendar, tidy, and glance"
        exit 198
    }
    if `"`subcmd'"' == `"attgt"' {
        * attgt builds no r(table), and csdid_estat is eclass, so
        * nothing here touches r(). matlist actively restores the caller's
        * r() around its own body, and estat.ado's `return add' copies the
        * stale r() back out through the wrapper -- so `estat event' followed
        * by `estat attgt' left the EVENT STUDY's r(table) standing and it
        * read as the result of the attgt command. csdid_estat's help
        * promises r(table) "is never left holding an earlier aggregation's
        * numbers", and _csdid_estat_rclear exists for exactly this; it was
        * called on one route out of eight. It runs AFTER the refusals below
        * (cold-audit F3-B): a refused attgt must not first destroy the
        * previous aggregation's r(table).
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
        * replace only means something to saving(); on its own it was parsed
        * and silently dropped, like the four above it before they were
        * refused. Same treatment.
        if "`replace'" != "" & `"`saving'"' == "" local attgt_bad "`attgt_bad' replace (without saving())"
        if "`attgt_bad'" != "" {
            display as error "estat attgt accepts only saving() and replace; not allowed:`attgt_bad'"
            exit 198
        }
        * An existing saving() target without replace refuses HERE, before
        * the table is rebuilt or written; the -save- inside the tidy helper
        * raised the same r(602), but only after the redisplay had run.
        * -save- writes .dta when the filename has no extension, so the
        * existence probe matches that rule.
        if `"`saving'"' != "" & "`replace'" == "" {
            local _sv_probe `"`saving'"'
            mata: st_local("_sv_noext", strofreal(pathsuffix(st_local("_sv_probe")) == ""))
            if `_sv_noext' local _sv_probe `"`_sv_probe'.dta"'
            confirm new file `"`_sv_probe'"'
        }
        _csdid_estat_rclear
        if `"`saving'"' != "" {
            _csdid_estat_tidy_attgt using `"`saving'"', `replace'
            exit
        }
        * base_time (column 10) is a posting-layer marker, not part of the
        * printed ATT(g,t) table; print the nine documented columns, as csdid's
        * own Display does. It remains readable in e(attgt).
        tempname attgt_show
        matrix `attgt_show' = e(attgt)
        if colsof(`attgt_show') > 9 matrix `attgt_show' = `attgt_show'[1..., 1..9]
        matlist `attgt_show', names(columns) format(%10.6g)
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
        * The aggregation is now ALWAYS
        * recomputed, exactly as the dynamic/simple/group/calendar routes below
        * already did. The old guard
        *     need_recompute = (no e(aggte)) | (agg_type != dynamic) | (window given)
        * reused whatever dynamic aggregation happened to be lying in e(),
        * which had three separately measured consequences, all silent and all
        * rc 0:
        *   - `estat event, level(90)' followed by `estat event,
        *     level(99)' returned the 90% bootstrap band (crit 2.2777391) for
        *     the 99% request; a fresh estimation at level(99) gives 2.8658043.
        *     The help's rationale for this - "a bootstrap band cannot be
        *     re-levelled" - is false: csdid_stats re-levels by recomputing off
        *     the SAME stored multiplier state e(boot_rng_state), which is why
        *     `csdid_stats, type(dynamic) level(99)' already returned
        *     2.8658043 from the identical session.
        *   - e(agg_level) kept the STALE aggregation's level
        *     while r(table) carried the requested one, so r(table), `estat
        *     tidy' (which reads e(agg_level)) and csdid_plot reported three
        *     different intervals for one displayed result.
        *   - after `csdid_stats, window(0 0)', `estat event' replayed
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
        * The dynamic/simple/group/calendar routes used to share
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
        *   dropmissing forwarded, so the documented missing-cell
        *   guarantee has the same meaning on every estat route.
        local agg_type "`subcmd'"
        if "`agg_type'" == "event" local agg_type "dynamic"
        local stat_opts "type(`agg_type') level(`level')"
        if "`dropmissing'" != "" local stat_opts "`stat_opts' dropmissing"
        if "`window'" != "" local stat_opts `"`stat_opts' window(`window')"'
        * csdid_stats reports two things on the TEXT channel that the
        * `quietly' below suppresses, so the estat route printed neither:
        *   - "window() is ignored for type(calendar)", so
        *     `estat calendar, window(0 2)' returned the FULL unwindowed
        *     calendar aggregation, rc 0, with no indication at all;
        *   - the note explaining that every standard error in the
        *     aggregation is missing, leaving the user a column of dots with
        *     the explanation removed.
        * Both are emitted here instead, outside the `quietly'. The window is
        * still FORWARDED and still warn-and-ignored rather than refused:
        * warn-and-return-unrestricted is the documented behaviour and is
        * pinned as an upstream contract, and csdid_estat's help promises
        * window() "behaves exactly as it does" in csdid_stats.
        * replace is meaningless without saving(); refused BEFORE the
        * aggregation runs -- a refusal that fired after the compute left a
        * command that ends r(198) having already replaced e() results, so a
        * capture'd caller continued on estimates Stata said failed. It also
        * precedes the calendar warning: a refused command must not first
        * announce that an aggregation is reported.
        if "`replace'" != "" & `"`saving'"' == "" {
            display as error "replace has no effect without saving(); specify saving(filename) or drop replace"
            exit 198
        }
        if "`agg_type'" == "calendar" & `"`window'"' != "" {
            display as text "warning: window() is ignored for type(calendar); the full calendar aggregation is reported"
        }
        _csdid_estat_rclear
        quietly csdid_stats, `stat_opts'
        * Restated on this route: csdid_stats' own note is inside the
        * `quietly'. Re-derive it from the aggregation it just produced.
        capture confirm matrix e(aggte)
        if !_rc {
            tempname agg_se_check
            matrix `agg_se_check' = e(aggte)
            local agg_se_col = colnumb(`agg_se_check', "se")
            if !missing(`agg_se_col') {
                local agg_se_allmiss 1
                forvalues agg_i = 1/`=rowsof(`agg_se_check')' {
                    if !missing(`agg_se_check'[`agg_i', `agg_se_col']) local agg_se_allmiss 0
                }
                if `agg_se_allmiss' {
                    display as text "note: every standard error in this type(`agg_type') aggregation is missing, because the ATT(g,t) estimates it aggregates have none. The usual causes are a cohort with a single comparison unit, a perfectly collinear covariate design, or an outcome scale that overflows the variance. The point estimates below are still valid: they are the aggregation of the ATT(g,t) estimates."
                }
            }
        }
        tempname show_b
        * No-transit (supersedes the snapshot/restore machinery, including the
        * generic e() snapshot): without `post', _csdid_post no longer
        * touches e(b)/e(V) at all - it builds r(table) directly from the
        * aggregation's B/V - so there is nothing to snapshot and nothing to
        * restore. The old post-then-restore cycle rebuilt e() wholesale twice
        * per estat, Stata-copying every stored matrix; under full storage
        * that includes the one-row-per-unit influence functions, and Stata's
        * classic-matrix layer is quadratic in the longest dimension, so a
        * plain `estat event' after a 20,000-unit estimation spent ~19s
        * copying matrices it did not change. The snapshot's failure mode (a
        * transient posting left behind on the saved-RIF path) cannot occur
        * when no transient posting exists.
        * F-047: windowing happened upstream in csdid_stats, so the poster no
        * longer receives (or fabricates) window bounds.
        * The export runs BEFORE the posting step, and that ordering is the
        * whole refusal contract for saving() on this route (cold-audit
        * F3-A): the file is built from the e(aggte) family the compute just
        * wrote, which the posting step preserves unchanged, so the file's
        * content is identical on either side of the post -- but a failed
        * -save- (target exists without replace, permissions, a full or
        * vanished volume, a race on the name) now exits with the save's own
        * return code while e(b), e(V), e(cmd) and both signature macros
        * still describe the incoming estimation. No preflight probe of the
        * target can deliver that (it can only narrow the window), and a
        * probe placed before the compute also answered an invalid window()
        * with r(602) about an unrelated file. Sequencing is the atomicity.
        if `"`saving'"' != "" {
            _csdid_estat_tidy_aggte using `"`saving'"', `replace'
        }
        * F-045/`event' keeps the historical Tm#/Tp#/Post_avg names
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
            * only `event' displays the coefficient vector; the
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
                * The event table arrived with nothing above it: no title, and
                * no statement of how the standard errors beneath it were
                * produced. `csdid_stats, type(dynamic)' prints both, but its
                * copy is inside the `quietly' this route runs, so a user who
                * reached the same aggregation through estat saw a bare matrix.
                * Same title, same header, from the same e() macros.
                if `have_show' {
                    display as text _newline "Aggregated treatment effects"
                    _csdid_estat_inf_header, level(`level')
                    matlist `show_b', names(columns) format(%10.6g)
                }
            }
            else {
                matlist e(aggte), names(columns) format(%10.6g)
            }
        }
        * (the export ran above, before the posting step; see the F3-A note)
        exit
    }
    if inlist(`"`subcmd'"', "tidy", "glance") & "`dropmissing'" != "" {
        * tidy/glance export whatever aggregation already exists and
        * never call csdid_stats, so dropmissing has nothing to act on here.
        * Refusing beats accepting-then-ignoring the option this release just
        * added.
        display as error `"estat `subcmd' does not accept dropmissing; specify it on the aggregation (e.g. estat dynamic, dropmissing) before exporting"'
        exit 198
    }
    if `"`subcmd'"' == `"tidy"' {
        * see the attgt branch. tidy exports and returns nothing, so
        * without this the previous aggregation's r(table) survives the
        * command and reads as its result.
        _csdid_estat_rclear
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
        * see the attgt branch.
        _csdid_estat_rclear
        if `"`saving'"' == "" {
            display as error "glance requires saving(filename)"
            exit 198
        }
        capture confirm matrix e(aggte)
        if _rc {
            _csdid_estat_glance using `"`saving'"', `replace'
        }
        else {
            _csdid_estat_glance using `"`saving'"', `replace' agg
        }
        exit
    }
    * Stata's own class for this is r(321) ("estat zzz not valid"
    * after regress, measured), but rc 498 here is pinned by the frozen
    * test-f051 contract; changing the class would fail that test. Flagged to
    * the owner rather than changed.
    display as error `"csdid_estat subcommand `subcmd' is not supported; supported subcommands are attgt, event, dynamic, simple, group, calendar, tidy, and glance"'
    exit 498
end

* Duplicate-option helper. Declares exactly the options csdid_estat declares,
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

* The inference header printed above the event table. It states the same facts
* in the same order as the header csdid and csdid_stats print, and reads them
* from the same place: the estimation's e() macros, which the aggregation
* inherits, plus e(agg_cband) -- the band decision the aggregation itself made,
* which is not e(cband) -- posted by the csdid_stats call this route just ran.
program define _csdid_estat_inf_header
    version 14
    syntax , Level(cilevel)

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
    capture confirm scalar e(agg_cband)
    if !_rc {
        if e(agg_cband) == 1 local band_kind "simultaneous"
    }
    display as text "`inf_line'; `level'% `band_kind' bands"
    if `unseeded' {
        display as text "Note: no rseed() set, so these standard errors change slightly between runs; add rseed(#) to reproduce them."
    }
end

* r()-hygiene helper. An rclass program replaces r() wholesale on exit, so calling
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

    * the whole scratch-data block runs -quietly-. On the
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
        * ---------------------------------------------------------------
        * The ATT(g,t) bands come from the ATT(g,t) inference, not from
        * whatever aggregation ran last.
        *
        * e(crit_val)/e(point_crit_val) are NOT stable descriptions of this
        * table. Every bootstrap aggregation overwrites them with its own
        * critical values (csdid_stats.ado, `ereturn scalar crit_val'), and
        * the two are different maxima: the ATT(g,t) uniform band is the max
        * over the (g,t) cells, the dynamic band the max over the surviving
        * event times. `csdid ..., wboot agg(event)' runs an aggregation
        * inside the estimation itself, so the very first export a user ever
        * wrote already carried the event-study band. When the aggregation
        * also ran at a different level(), the exported band was at the wrong
        * level as well.
        *
        * The estimation-time (g,t) values survive in e(boot_attgt), whose
        * crit_val and point_crit_val columns are constant across rows and
        * are carried across every posting round trip by _csdid_post.
        *
        * Under analytical inference there is nothing to recover: csdid posts
        * a pure normal quantile at e(level), which is what this table needs.
        * On the saved-RIF path nothing posts crit_val at all, and reading it
        * unguarded wrote four ALL-MISSING confidence columns at rc 0 -- the
        * band this table's own help promises (csdid_estat.sthlp, "The conf_*
        * columns use the reported critical value ... and the point_conf_*
        * columns use the pointwise one").
        *
        * The fallback is deliberately NOT a blanket normal quantile: under
        * a bootstrap that would silently swap a simultaneous band for a
        * pointwise one. That residual case says so instead.
        * ---------------------------------------------------------------
        local crit = .
        local z = .
        local use_boot 0
        capture confirm scalar e(bstrap)
        if !_rc local use_boot = (e(bstrap) != 0)
        if `use_boot' {
            capture confirm matrix e(boot_attgt)
            if !_rc {
                tempname BA
                matrix `BA' = e(boot_attgt)
                local ccrit = colnumb(`BA', "crit_val")
                local cpoint = colnumb(`BA', "point_crit_val")
                if !missing(`ccrit') local crit = `BA'[1, `ccrit']
                if !missing(`cpoint') local z = `BA'[1, `cpoint']
            }
        }
        if missing(`crit') | missing(`z') {
            local band_level = e(level)
            if missing(`band_level') local band_level = c(level)
            if `use_boot' {
                * `display as error' is the one channel a caller's -quietly-
                * does not suppress; the band just changed meaning.
                display as error "warning: the ATT(g,t) bootstrap critical values are not available (e(boot_attgt) is missing), so the exported conf_low/conf_high columns are pointwise normal bands at `band_level'%, not the simultaneous bootstrap band. Re-run csdid to restore them."
            }
            local normal_crit = invnormal(1 - (100 - `band_level') / 200)
            if missing(`crit') local crit = `normal_crit'
            if missing(`z') local z = `normal_crit'
        }
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
    * The dispatcher that chose this route probed e(aggte) with -capture-,
    * and that probe's return code is what a caller's `if _rc' would read
    * after a successful export; the export's last act clears it.
    capture local _estat_rc_clear 1
end

program define _csdid_estat_glance
    version 14
    syntax using/ [, REPLACE AGG]

    * One row of estimation metadata. The ATT(g,t) export and the aggregation
    * export differ in one column: an aggregation names its type.
    *
    * That column is created FIRST, before the counts, because the saved file
    * carries the variables in creation order and the aggregation export has
    * always led with type - see the glance_aggte_* column lists in the f027
    * export schema.
    *
    * see _csdid_estat_tidy_attgt - the export block runs
    * -quietly- so the scratch-data chatter and the "Press any key" prompt do
    * not fire on the happy path. `display as error' still reaches the user.
    quietly {
        preserve
        clear
        set obs 1
        if "`agg'" != "" {
            generate str16 type = "`e(agg_type)'"
        }
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
    * The dispatcher that chose this route probed e(aggte) with -capture-,
    * and that probe's return code is what a caller's `if _rc' would read
    * after a successful export; the export's last act clears it.
    capture local _estat_rc_clear 1
end

program define _csdid_estat_tidy_aggte
    version 14
    syntax using/ [, REPLACE]

    * see _csdid_estat_tidy_attgt - the export block runs
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
    * The dispatcher that chose this route probed e(aggte) with -capture-,
    * and that probe's return code is what a caller's `if _rc' would read
    * after a successful export; the export's last act clears it.
    capture local _estat_rc_clear 1
end
