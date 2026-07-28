version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f037_run_scenario
    version 15
    syntax , SCENARIO(string) METHOD(string) CONTROL(string) BASE(string) PANEL(integer) ANTICIPation(integer) AGGTYPE(string) ATTFILE(string) AGGFILE(string) [APPEND]

    import delimited using "`c(pwd)'/tests/fixtures/parity/f037/inputs/input.csv", clear asdouble
    local panelopt ""
    if `panel' local panelopt "ivar(id)"
    local controlopt ""
    if "`control'" == "notyettreated" local controlopt "notyet"

    quietly csdid y x, `panelopt' time(period) gvar(g) method(`method') `controlopt' base_period(`base') anticipation(`anticipation') analytical
    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    gen str80 scenario = "`scenario'"
    rename (att se) (att_stata se_stata)
    keep scenario group time event_time att_stata se_stata
    if "`append'" == "" {
        save "`attfile'", replace
    }
    else {
        append using "`attfile'"
        save "`attfile'", replace
    }
    restore

    quietly csdid_stats, type(`aggtype') na_rm
    matrix M = e(aggte)
    preserve
    clear
    svmat double M, names(col)
    gen str80 scenario = "`scenario'"
    gen str16 type = "`aggtype'"
    gen seq = _n
    rename (egt att se overall_att overall_se) ///
           (egt_stata att_stata se_stata overall_att_stata overall_se_stata)
    keep scenario type seq egt att_stata se_stata overall_att_stata overall_se_stata
    if "`append'" == "" {
        save "`aggfile'", replace
    }
    else {
        append using "`aggfile'"
        save "`aggfile'", replace
    }
    restore
end

confirm file "`root'/tests/fixtures/parity/f037/inputs/input.csv"
confirm file "`root'/tests/fixtures/parity/f037/expected/r/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/f037/expected/r/attgt.csv"
confirm file "`root'/tests/fixtures/parity/f037/expected/r/aggte.csv"
confirm file "`root'/tests/fixtures/parity/f037/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/f037/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/f037/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/f037/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "F037-DIV001"

tempfile actual_att actual_agg
local first 1

foreach method in dr reg ipw {
    foreach control in nevertreated notyettreated {
        foreach base in varying universal {
            local scenario "combo_a__`method'__`control'__`base'"
            local appendopt ""
            if !`first' local appendopt "append"
            f037_run_scenario, scenario("`scenario'") method(`method') control(`control') base(`base') panel(1) anticipation(0) aggtype(simple) attfile("`actual_att'") aggfile("`actual_agg'") `appendopt'
            local first 0
        }
    }
}

foreach method in dr reg ipw {
    foreach panel in 1 0 {
        local panelname = cond(`panel', "panel", "rc")
        local scenario "combo_b__`method'__`panelname'"
        f037_run_scenario, scenario("`scenario'") method(`method') control(nevertreated) base(varying) panel(`panel') anticipation(0) aggtype(dynamic) attfile("`actual_att'") aggfile("`actual_agg'") append
    }
}

foreach method in dr reg ipw {
    foreach ant in 0 1 {
        local scenario "combo_c__`method'__ant`ant'"
        f037_run_scenario, scenario("`scenario'") method(`method') control(nevertreated) base(varying) panel(1) anticipation(`ant') aggtype(simple) attfile("`actual_att'") aggfile("`actual_agg'") append
    }
}

foreach method in dr reg ipw {
    foreach aggtype in simple dynamic group calendar {
        local scenario "combo_f__`method'__`aggtype'"
        f037_run_scenario, scenario("`scenario'") method(`method') control(nevertreated) base(varying) panel(1) anticipation(0) aggtype(`aggtype') attfile("`actual_att'") aggfile("`actual_agg'") append
    }
}

import delimited using "`root'/tests/fixtures/parity/f037/expected/r/attgt.csv", clear asdouble
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

import delimited using "`root'/tests/fixtures/parity/f037/expected/r/aggte.csv", clear asdouble
merge 1:1 scenario type seq using "`actual_agg'", nogen assert(match)
assert missing(egt) == missing(egt_stata) if missing(egt) | missing(egt_stata)
assert abs(egt - egt_stata) <= 1e-10 if !missing(egt)
foreach v in att se overall_att overall_se {
    assert missing(`v') == missing(`v'_stata) if missing(`v') | missing(`v'_stata)
    assert abs(`v' - `v'_stata) <= 1e-7 + 1e-7 * abs(`v') if !missing(`v')
}
