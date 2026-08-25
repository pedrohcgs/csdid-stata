version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f038_assert_log_contains
    version 15
    syntax using/, MESSAGE(string)

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
    local compact_body = subinstr(`"`body'"', " ", "", .)
    local compact_message = subinstr(`"`message'"', " ", "", .)
    local found = strpos(`"`body'"', `"`message'"') > 0 | strpos(`"`compact_body'"', `"`compact_message'"') > 0
    assert `found'
end

program define f038_save_att
    version 15
    syntax , SCENARIO(string) SAVING(string) [APPEND]

    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    gen str60 scenario = "`scenario'"
    rename (att se) (att_stata se_stata)
    keep scenario group time event_time att_stata se_stata
    if "`append'" == "" {
        save "`saving'", replace
    }
    else {
        append using "`saving'"
        save "`saving'", replace
    }
    restore
end

program define f038_save_agg
    version 15
    syntax , SCENARIO(string) TYPE(string) SAVING(string) [APPEND]

    quietly csdid_stats, type(`type') na_rm
    matrix M = e(aggte)
    preserve
    clear
    svmat double M, names(col)
    gen str60 scenario = "`scenario'"
    gen str16 type = "`type'"
    gen seq = _n
    rename (egt att se overall_att overall_se) ///
           (egt_stata att_stata se_stata overall_att_stata overall_se_stata)
    keep scenario type seq egt_stata att_stata se_stata overall_att_stata overall_se_stata
    if "`append'" == "" {
        save "`saving'", replace
    }
    else {
        append using "`saving'"
        save "`saving'", replace
    }
    restore
end

confirm file "`root'/tests/fixtures/parity/f038/inputs/t1.csv"
confirm file "`root'/tests/fixtures/parity/f038/inputs/missing-cov.csv"
confirm file "`root'/tests/fixtures/parity/f038/inputs/fewer-periods.csv"
confirm file "`root'/tests/fixtures/parity/f038/inputs/zero-pre.csv"
confirm file "`root'/tests/fixtures/parity/f038/inputs/anticipation.csv"
confirm file "`root'/tests/fixtures/parity/f038/expected/r/attgt.csv"
confirm file "`root'/tests/fixtures/parity/f038/expected/r/aggte.csv"
confirm file "`root'/tests/fixtures/parity/f038/expected/r/events.csv"
confirm file "`root'/tests/fixtures/parity/f038/expected/r/events.json"
confirm file "`root'/tests/fixtures/parity/f038/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/f038/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/f038/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/f038/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "F038-DIV001"

tempfile actual_att actual_agg evlog
local first_att 1
local first_agg 1

import delimited using "`root'/tests/fixtures/parity/f038/inputs/t1.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) method(reg) notyet analytical base_period(varying) bal(none)
local appendopt ""
f038_save_att, scenario("t1_column") saving("`actual_att'") `appendopt'
local first_att 0

import delimited using "`root'/tests/fixtures/parity/f038/inputs/missing-cov.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(reg) notyet analytical base_period(varying) bal(none)
* Under bal(none) the missing covariate cell costs its ROW, not the unit
* (the f072 correspondence: bal(none) is R's allowed-unbalanced route), so
* the unit stays, the panel is handled as allow_unbalanced, and the counts
* keep the 239 usable rows. The oracle for this scenario is generated with
* allow_unbalanced_panel = TRUE for the same reason. The old pins (panel /
* 236 / 59) froze the whole-unit over-drop this cell now exists to forbid.
assert "`e(panel_mode)'" == "allow_unbalanced"
assert e(N) == 239
assert e(N_units) == 60
f038_save_att, scenario("missing_covariate") saving("`actual_att'") append

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/f038/inputs/fewer-periods.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') analytical nevertreated base_period(varying) bal(none)
    local scenario "fewer_periods__`method'"
    f038_save_att, scenario("`scenario'") saving("`actual_att'") append
    foreach type in dynamic group calendar {
        local aggappend ""
        if !`first_agg' local aggappend "append"
        f038_save_agg, scenario("`scenario'") type(`type') saving("`actual_agg'") `aggappend'
        local first_agg 0
    }
}

foreach base in universal varying {
    import delimited using "`root'/tests/fixtures/parity/f038/inputs/zero-pre.csv", clear asdouble
    quietly csdid y, ivar(id) time(period) gvar(g) method(reg) notyet base_period(`base') analytical bal(none)
    f038_save_att, scenario("zero_pre__`base'") saving("`actual_att'") append
}

foreach ant in 0 2 {
    import delimited using "`root'/tests/fixtures/parity/f038/inputs/anticipation.csv", clear asdouble
    quietly csdid y, ivar(id) time(period) gvar(g) method(reg) anticipation(`ant') analytical nevertreated base_period(varying) bal(none)
    f038_save_att, scenario("anticipation__`ant'") saving("`actual_att'") append
    if `ant' == 0 {
        matrix A0 = e(attgt)
        forvalues i = 1/`=rowsof(A0)' {
            assert A0[`i', 1] == 4
        }
    }
    else {
        matrix A2 = e(attgt)
        local saw6 0
        forvalues i = 1/`=rowsof(A2)' {
            if A2[`i', 1] == 6 local saw6 1
        }
        assert `saw6' == 1
    }
}

import delimited using "`root'/tests/fixtures/parity/f038/inputs/t1.csv", clear asdouble
capture log close f038event
log using "`evlog'", text replace name(f038event)
capture noisily csdid y x_missing, ivar(id) time(period) gvar(g) method(dr) notyet analytical base_period(varying) bal(none)
local actual_rc = _rc
log close f038event
assert `actual_rc' == 111
f038_assert_log_contains using "`evlog'", message("variable x_missing not found")

import delimited using "`root'/tests/fixtures/parity/f038/expected/r/attgt.csv", clear asdouble
merge 1:1 scenario group time using "`actual_att'", nogen assert(match)
gen double att_absdiff = abs(att - att_stata)
quietly count if att_absdiff > 1e-7 + 1e-7 * abs(att) & !missing(att)
if r(N) > 0 {
    list scenario group time att att_stata att_absdiff if att_absdiff > 1e-7 + 1e-7 * abs(att) & !missing(att), abbreviate(32)
}
assert att_absdiff <= 1e-7 + 1e-7 * abs(att) if !missing(att)
assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
gen double se_absdiff = abs(se - se_stata)
quietly count if se_absdiff > 1e-7 + 1e-7 * abs(se) & !missing(se)
if r(N) > 0 {
    list scenario group time se se_stata se_absdiff if se_absdiff > 1e-7 + 1e-7 * abs(se) & !missing(se), abbreviate(32)
}
assert se_absdiff <= 1e-7 + 1e-7 * abs(se) if !missing(se)

import delimited using "`root'/tests/fixtures/parity/f038/expected/r/aggte.csv", clear asdouble
merge 1:1 scenario type seq using "`actual_agg'", nogen assert(match)
assert missing(egt) == missing(egt_stata) if missing(egt) | missing(egt_stata)
assert abs(egt - egt_stata) <= 1e-10 if !missing(egt)
foreach v in att se overall_att overall_se {
    assert missing(`v') == missing(`v'_stata) if missing(`v') | missing(`v'_stata)
    assert abs(`v' - `v'_stata) <= 1e-7 + 1e-7 * abs(`v') if !missing(`v')
}
