* RT073 -- names and labels on a decimal axis read back as R's values.
* Coefficient names, csdid_plot's x_label and the small-group warning wrote
* each value with %21.0g, and often from a sixteen-digit copy in a local:
* 2.2 became 2.200000000000000178, every ATT(g,t) name on a one-decimal axis
* passed 32 characters and fell back to att_#, the event time
* -1.2000000000000002 was named from -1.2, and the distinct event times 1
* and 1.0000000000000002 collided and fell back to eff_#. Each value is now
* written in the shortest form that reads back as the stored double.
version 15
clear all
set more off
set linesize 255
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt073"

program define rt073_log_has, rclass
    version 15
    syntax using/, MESSAGE(string)
    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`macval(line)'"')
        if substr(`"`clean'"', 1, 2) == "> " local clean = strtrim(substr(`"`clean'"', 3, .))
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    return scalar has = strpos(`"`body'"', `"`message'"') > 0
end

* e(b)'s column names as a dataset, one row per name
program define rt073_names
    version 15
    local names : colnames e(b)
    clear
    local n : word count `names'
    quietly set obs `n'
    quietly generate str32 name = ""
    forvalues j = 1/`n' {
        quietly replace name = "`: word `j' of `names''" in `j'
    }
end

import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1)
keep axis group
duplicates drop
tempfile rgroups
save `rgroups'
import delimited using "`fx'/expected/r/aggte.csv", clear asdouble varnames(1)
tempfile raggs
save `raggs'
import delimited using "`fx'/expected/r/warnings.csv", clear varnames(1) bindquote(strict)
keep if strpos(message, "Check groups:")
assert _N == 1 & axis == "onedecimal"
local rcheck = substr(message, strpos(message, "Check groups:"), .)

foreach a in onedecimal residue {
    import delimited using "`fx'/inputs/`a'.csv", clear asdouble varnames(1)
    tempfile lg
    log using "`lg'", text replace name(rt073)
    csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
        base_period(universal) analytical pointwise
    log close rt073
    estimates store rt073_fit
    * the small-group warning names the cohort R names, as R writes it
    rt073_log_has using "`lg'", message(`"`rcheck'"')
    assert r(has) == ("`a'" == "onedecimal")

    * ATT(g,t): no att_# fallback, and every name's cohort field reads back
    * exactly as one of R's cohorts
    preserve
    rt073_names
    assert substr(name, 1, 1) == "g" & strpos(name, "___") > 2
    generate double group = real(subinstr(substr(name, 2, strpos(name, "___") - 2), "_", ".", .))
    generate str12 axis = "`a'"
    local nnames = _N
    merge m:1 axis group using `rgroups', keep(master match)
    assert _merge == 3
    display as text "RT073 `a': `nnames' ATT(g,t) names, each cohort field one of R's"
    restore
    if "`a'" == "onedecimal" {
        * the name the help describes exists and is ATT(2.2, 2.7), base 1.7
        lincom g2_2___2_7_1_7
        tempname AT
        matrix `AT' = e(attgt)
        local hit 0
        forvalues k = 1/`=rowsof(`AT')' {
            if `AT'[`k', 1] == 2.2 & `AT'[`k', 2] == 2.7 {
                assert `AT'[`k', 10] == 1.7
                assert reldif(_b[g2_2___2_7_1_7], `AT'[`k', 4]) < 1e-12
                local ++hit
            }
        }
        assert `hit' == 1
    }

    * estat event/group/calendar, post: every name reads back as R's event
    * time, cohort or period; no eff_# fallback
    foreach type in dynamic group calendar {
        quietly estimates restore rt073_fit
        local sub = cond("`type'" == "dynamic", "event", "`type'")
        quietly estat `sub', post
        preserve
        rt073_names
        local base = cond("`type'" == "dynamic", 3, 2)
        drop if inlist(name, "Post_avg", "Overall")
        assert substr(name, 1, 4) != "eff_"
        generate double egt = real(subinstr(substr(name, `base', .), "_", ".", .))
        if "`type'" == "dynamic" replace egt = -egt if substr(name, 1, 2) == "Tm"
        assert !missing(egt)
        generate str12 axis = "`a'"
        generate str8 type = "`type'"
        merge 1:1 axis type egt using `raggs', keep(master match using)
        drop if axis != "`a'" | type != "`type'"
        * every R row is named, and every name is an R row
        assert _merge == 3
        display as text "RT073 `a' estat `sub': " _N " names read back as R's values"
        restore
    }
}

* the residue axis: 3 - 2 and 2.2 - 1.2 are two event times with two names
quietly estimates restore rt073_fit
quietly estat event, post
local names : colnames e(b)
assert strpos(" `names' ", " Tp1 ") > 0
assert strpos(" `names' ", " Tp1_0000000000000002 ") > 0

* the one-decimal axis: the residue event time 3.1 - 2.2 carries the name the
* help gives, and the plot labels read back as the plotted values
import delimited using "`fx'/inputs/onedecimal.csv", clear asdouble varnames(1)
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    base_period(universal) analytical pointwise
estimates store rt073_fit
tempfile plotfile
csdid_plot, saving(`plotfile', replace)
preserve
use `plotfile', clear
assert real(x_label) == x
quietly count if x_label == "1.2"
assert r(N) > 0
restore
quietly estat event, post
* the exact name: lincom would also accept it as an abbreviation of a longer one
local names : colnames e(b)
assert strpos(" `names' ", " Tp0_8999999999999999 ") > 0
quietly estimates restore rt073_fit
quietly estat event
csdid_plot, saving(`plotfile', replace)
use `plotfile', clear
assert real(x_label) == x
quietly count if x_label == ".8999999999999999"
assert r(N) == 1

display as text "test-decimal-axis-names: names and labels on a decimal axis read back as R's values"
