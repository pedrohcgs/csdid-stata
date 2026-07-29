version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt026_compare_tidy
    version 15
    syntax, Actual(string) Expected(string) Key(string)

    tempfile actual_renamed
    use "`actual'", clear
    foreach v in estimate std_error statistic p_value conf_low conf_high point_conf_low point_conf_high {
        rename `v' `v'_stata
    }
    save "`actual_renamed'", replace

    import delimited using "`expected'", clear asdouble
    merge 1:1 `key' using "`actual_renamed'", nogen assert(match)
    foreach v in estimate std_error statistic p_value conf_low conf_high point_conf_low point_conf_high {
        assert missing(`v') == missing(`v'_stata) if missing(`v') | missing(`v'_stata)
        assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v') & !missing(`v'_stata)
    }
    assert p_value >= 0 & p_value <= 1 if !missing(p_value)
    assert abs(statistic - estimate / std_error) <= 1e-10 if !missing(statistic) & !missing(std_error)
    assert abs(p_value - 2 * (1 - normal(abs(statistic)))) <= 1e-10 if !missing(p_value) & !missing(statistic)
end

program define rt026_append_nobs
    version 15
    syntax, Object(string) Outfile(string) [APPEND]

    preserve
    clear
    set obs 1
    gen str16 object = "`object'"
    gen double nobs_stata = e(N_units)
    if "`append'" == "" {
        save "`outfile'", replace
    }
    else {
        append using "`outfile'"
        save "`outfile'", replace
    }
    restore
end

confirm file "`root'/tests/fixtures/parity/rt026/inputs/mpdta.csv"
confirm file "`root'/tests/fixtures/parity/rt026/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt026/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt026/expected/r/tidy-attgt.csv"
confirm file "`root'/tests/fixtures/parity/rt026/expected/r/tidy-aggte-dynamic.csv"
confirm file "`root'/tests/fixtures/parity/rt026/expected/r/tidy-aggte-group.csv"
confirm file "`root'/tests/fixtures/parity/rt026/expected/r/tidy-aggte-calendar.csv"
confirm file "`root'/tests/fixtures/parity/rt026/expected/r/tidy-aggte-simple.csv"
confirm file "`root'/tests/fixtures/parity/rt026/expected/r/nobs.csv"
confirm file "`root'/tests/fixtures/parity/rt026/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt026/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 12
quietly count if coverage_status == "mapped"
assert r(N) == 12

tempfile tidy_attgt tidy_agg actual_nobs

import delimited using "`root'/tests/fixtures/parity/rt026/inputs/mpdta.csv", clear asdouble
csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical nevertreated base_period(varying) bal(none)
csdid_estat tidy, saving("`tidy_attgt'") replace
rt026_append_nobs, object(MP) outfile("`actual_nobs'")

rt026_compare_tidy, ///
    actual("`tidy_attgt'") ///
    expected("`root'/tests/fixtures/parity/rt026/expected/r/tidy-attgt.csv") ///
    key("term group time")

foreach agg_type in dynamic group calendar simple {
    csdid_stats, type(`agg_type')
    csdid_estat tidy, saving("`tidy_agg'") replace
    rt026_append_nobs, object(`agg_type') outfile("`actual_nobs'") append

    local tidy_key "type term"
    if "`agg_type'" == "group" local tidy_key "type term group"
    if "`agg_type'" == "calendar" local tidy_key "type term time"
    if "`agg_type'" == "dynamic" local tidy_key "type term event_time"

    rt026_compare_tidy, ///
        actual("`tidy_agg'") ///
        expected("`root'/tests/fixtures/parity/rt026/expected/r/tidy-aggte-`agg_type'.csv") ///
        key("`tidy_key'")
}

import delimited using "`root'/tests/fixtures/parity/rt026/expected/r/nobs.csv", clear asdouble
merge 1:1 object using "`actual_nobs'", nogen assert(match)
assert nobs == nobs_stata
