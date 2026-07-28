*! csdid_plot 2.0.0 26jul2026
program define csdid_plot
    version 14
    if "`e(cmd)'" != "csdid" {
        display as error "csdid_plot requires prior csdid results"
        exit 301
    }
    syntax [, SAVing(string) REPLACE GROUP(numlist) *]
    if `"`options'"' != "" {
        * D-1: compound quotes. A quoted option VALUE (e.g.
        * title("Cohort 2004")) puts a double quote inside `options', and the
        * plain-quoted display then breaks the string, producing a garbled
        * message and r(111) instead of the documented r(198).
        display as error `"unsupported option(s): `options'"'
        exit 198
    }
    if `"`saving'"' == "" {
        display as error "csdid_plot requires saving(filename). To export plot data, run: csdid_plot, saving(filename) replace"
        exit 198
    }
    * SP-04 fix: saving() took its whole argument as a filename, so the
    * standard saving(filename, replace) idiom returned rc 0 after writing a
    * file literally called "filename, replace.dta" (csdid_plot.sthlp:114-116
    * anticipates the mistake; nothing guarded it). The comma form is now
    * parsed: replace is the only sub-option saving() accepts, and anything
    * else refuses by name instead of becoming part of the filename.
    local plotgroup `"`group'"'
    local dorepl `"`replace'"'
    local savefile `"`saving'"'
    * st_local() reads the macro's raw text, so a quoted filename cannot break
    * the scan the way strpos(`"`saving'"', ",") would.
    mata: st_local("_sp04comma", strofreal(strpos(st_local("saving"), ",")))
    if `_sp04comma' {
        gettoken savefile srest : saving, parse(",")
        if `"`savefile'"' == "," {
            * saving(, replace): the comma itself came back as the token, so
            * there is no filename at all.
            local savefile ""
        }
        else {
            gettoken comma srest : srest, parse(",")
            mata: st_local("savefile", strtrim(st_local("savefile")))
        }
        local 0 `", `srest'"'
        capture syntax [, REPLACE]
        if _rc {
            display as error `"saving() accepts only the replace sub-option; cannot parse: `srest'"'
            exit 198
        }
        if "`replace'" != "" local dorepl replace
        if `"`savefile'"' == "" {
            display as error "saving() requires a filename before the comma, as in saving(myfile, replace)"
            exit 198
        }
    }

    capture confirm matrix e(aggte)
    if _rc {
        _csdid_plot_attgt using `"`savefile'"', `dorepl' group(`plotgroup')
    }
    else {
        * F-053 fix: group() was silently discarded on this branch (fourth
        * F-045-family instance). It is now forwarded: group-type
        * aggregations filter to the requested cohorts (absent cohorts fall
        * back to all, with the same note as the attgt branch); for other
        * aggregation types the option is meaningless and says so out loud.
        _csdid_plot_aggte using `"`savefile'"', `dorepl' group(`plotgroup')
    }
end

program define _csdid_plot_attgt
    version 14
    syntax using/ [, REPLACE GROUP(numlist)]

    tempname A
    matrix `A' = e(attgt)
    * EUX-003/SP-06 fix: this export block ran noisily, so a successful export
    * printed scratch-data chatter ("number of observations will be reset to
    * 12", "(1 real change made)", "(file ... not found)") and, worse, svmat's
    * observation-count notice raised a BLOCKING "Press any key to continue,
    * or Break to abort" prompt on the happy path. The whole block is quiet
    * now; genuinely user-facing notes are emitted with `noisily'.
    quietly {
        preserve
        clear
        svmat double `A', names(col)
        generate str24 plot_type = "attgt"
        generate str8 series = cond(time >= group, "Post", "Pre")
        generate double x = time
        generate str32 x_label = strtrim(strofreal(time, "%21.0g"))
        rename att estimate
        local crit = e(crit_val)
        if missing(`crit') local crit = invnormal(1 - (100 - e(level)) / 200)
        generate double ci_low = estimate - `crit' * se
        generate double ci_high = estimate + `crit' * se
        generate byte significant = ((ci_low > 0 & ci_low < .) | (ci_high < 0 & ci_high < .))

        if `"`group'"' != "" {
            generate byte _csdid_keep = 0
            foreach g of numlist `group' {
                replace _csdid_keep = 1 if group == `g'
            }
            count if _csdid_keep
            if r(N) == 0 {
                noisily display as text "Some of the specified groups do not exist in the data. Reporting all available groups."
                replace _csdid_keep = 1
            }
            keep if _csdid_keep
            drop _csdid_keep
        }

        keep plot_type series x x_label estimate ci_low ci_high group time event_time significant
        order plot_type series x x_label estimate ci_low ci_high group time event_time significant
        sort group time
        save `"`using'"', `replace'
        restore
    }
end

program define _csdid_plot_aggte
    version 14
    * F-053: accept the group() option forwarded by csdid_plot.
    syntax using/ [, REPLACE GROUP(numlist)]

    if "`e(agg_type)'" == "simple" {
        display as error "Plot method not available for this type of aggregation"
        exit 498
    }
    if !inlist("`e(agg_type)'", "dynamic", "group", "calendar") {
        display as error "unknown aggregation type `e(agg_type)'"
        exit 498
    }
    * F-053: group() selects treatment cohorts, which only exist as rows on a
    * group-type aggregation; on dynamic/calendar plots it is meaningless and
    * is dropped loudly instead of being silently discarded.
    if `"`group'"' != "" & "`e(agg_type)'" != "group" {
        display as text "group() applies to group-type aggregations; ignored for the `e(agg_type)' aggregation plot."
        local group ""
    }

    tempname A
    matrix `A' = e(aggte)
    * EUX-003/SP-06 fix: quiet export block - see _csdid_plot_attgt.
    quietly {
    preserve
    clear
    svmat double `A', names(col)
    * F-053: same cohort filter and same absent-cohort fallback note as the
    * attgt branch, applied to the group-type aggregation rows (egt = cohort).
    if `"`group'"' != "" {
        generate byte _csdid_keep = 0
        foreach g of numlist `group' {
            replace _csdid_keep = 1 if egt == `g'
        }
        count if _csdid_keep
        if r(N) == 0 {
            noisily display as text "Some of the specified groups do not exist in the data. Reporting all available groups."
            replace _csdid_keep = 1
        }
        keep if _csdid_keep
        drop _csdid_keep
    }
    generate str24 plot_type = "aggte_" + "`e(agg_type)'"
    generate str8 series = cond(egt >= 0, "Post", "Pre")
    generate double x = egt
    generate str32 x_label = strtrim(strofreal(egt, "%21.0g"))
    rename att estimate
    capture confirm scalar e(agg_level)
    if _rc local agg_level = e(level)
    else local agg_level = e(agg_level)
    local crit = invnormal(1 - (100 - `agg_level') / 200)
    capture confirm scalar e(bstrap)
    if !_rc & e(bstrap) local crit = e(crit_val)
    generate double ci_low = estimate - `crit' * se
    generate double ci_high = estimate + `crit' * se
    generate double group = .
    generate double time = .
    generate double event_time = .
    if "`e(agg_type)'" == "dynamic" {
        replace event_time = egt
    }
    else if "`e(agg_type)'" == "calendar" {
        replace time = egt
    }
    else if "`e(agg_type)'" == "group" {
        replace group = egt
    }
    generate byte significant = ((ci_low > 0 & ci_low < .) | (ci_high < 0 & ci_high < .))

    keep plot_type series x x_label estimate ci_low ci_high group time event_time significant
    order plot_type series x x_label estimate ci_low ci_high group time event_time significant
    sort x
    save `"`using'"', `replace'
    restore
    }
end
