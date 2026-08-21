version 15
clear all
set more off

* rt033: the three panel-shape refusals -- irreversible gvar(), duplicate
* (ivar, time) and a time-varying cluster() -- must be decided on the sample as
* it was supplied, not on the sample left after rows with missing values have
* been removed. A duplicated row whose second copy has no outcome is still a
* duplicated row, and a run that estimates it reports numbers from data the
* normative source refuses outright.
*
* The fixture carries three kinds of design, and all three are load-bearing.
* The nine cells put each check against a violation on a surviving row, the
* same violation on a row the screen removes, and a clean panel. The screen
* negatives are violations that must NOT refuse, because the normative source
* screens its own columns per check and each check screens a different set: a
* duplicate excused by a missing time or a missing ivar, a reversal excused by
* a missing gvar or a missing ivar, and a cluster missing in every period of a
* unit -- which is one value, not two. The order designs break two rules at
* once and pin which sentence the user is asked to act on.
*
* Reference verdicts are R fixtures produced by
* tools/parity/generators/rt033/generate.R.

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local fixture "`root'/tests/fixtures/parity/rt033"
confirm file "`fixture'/expected/r/verdicts.csv"

program define rt033_classify_log
    version 15
    syntax using/, RESULT(name)

    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    * the wrapped log breaks messages across lines; compare without spaces
    local compact = subinstr(`"`body'"', " ", "", .)
    local seen "none"
    if strpos(`"`compact'"', "gvar()mustbetime-invariantwithinivar()") > 0 ///
        local seen "gvar"
    else if strpos(`"`compact'"', "mustbeuniquewithintime()") > 0 ///
        local seen "dup"
    else if strpos(`"`compact'"', "cluster()mustbetime-invariantwithinivar()") > 0 ///
        local seen "cluster"
    c_local `result' "`seen'"
end

* -----------------------------------------------------------------------
* One design: run csdid on the fixture input and compare the refusal, and
* WHICH refusal, against the recorded verdict.
* -----------------------------------------------------------------------
program define rt033_check_design
    version 15
    syntax, TAG(string) FIXTURE(string) REFUSES(integer) REFUSAL(string)

    quietly import delimited using "`fixture'/inputs/`tag'.csv", ///
        asdouble varnames(1) clear

    tempfile evlog
    capture log close rt033event
    log using "`evlog'", text replace name(rt033event)
    capture noisily csdid y x [iweight=w], ivar(id) time(t) gvar(g) ///
        cluster(cl) method(dr) notyet
    local rc = _rc
    log close rt033event

    rt033_classify_log using "`evlog'", result(seen)

    if `refuses' {
        if `rc' != 459 {
            display as error "rt033 `tag': expected a refusal, got rc `rc'"
            exit 9
        }
        if "`seen'" != "`refusal'" {
            display as error "rt033 `tag': expected the `refusal' refusal, saw `seen'"
            exit 9
        }
    }
    else {
        if `rc' != 0 {
            display as error "rt033 `tag': expected an estimation, got rc `rc'"
            exit 9
        }
        if "`seen'" != "none" {
            display as error "rt033 `tag': estimated, but printed the `seen' refusal"
            exit 9
        }
    }
    display as text "rt033 `tag': ok (rc `rc', `seen')"
end

* -----------------------------------------------------------------------
* Drive every recorded verdict. The count is asserted too: a fixture that
* silently lost its designs would otherwise pass by checking nothing.
* -----------------------------------------------------------------------
quietly import delimited using "`fixture'/expected/r/verdicts.csv", ///
    varnames(1) stringcols(1 4) clear
quietly count
local n_designs = r(N)
assert `n_designs' == 23

local tags ""
local refuses ""
local refusals ""
forvalues i = 1/`n_designs' {
    local tags "`tags' `=tag[`i']'"
    local refuses "`refuses' `=refuses[`i']'"
    local refusals "`refusals' `=refusal[`i']'"
}

forvalues i = 1/`n_designs' {
    local tag : word `i' of `tags'
    local ref : word `i' of `refuses'
    local kind : word `i' of `refusals'
    rt033_check_design, tag("`tag'") fixture("`fixture'") ///
        refuses(`ref') refusal("`kind'")
}

display as text "rt033: `n_designs' designs agree with the recorded verdicts"
