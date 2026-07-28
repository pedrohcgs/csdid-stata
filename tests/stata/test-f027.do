version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define compare_tidy_export
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
end

program define compare_glance_export
    version 15
    syntax, Actual(string) Expected(string) Key(string)

    tempfile actual_renamed
    use "`actual'", clear
    local nobs_key = strpos(" `key' ", " nobs ") > 0
    if !`nobs_key' {
        rename nobs nobs_stata
    }
    rename ngroup ngroup_stata
    rename ntime ntime_stata
    rename control_group control_group_stata
    rename est_method est_method_stata
    save "`actual_renamed'", replace

    import delimited using "`expected'", clear asdouble
    merge 1:1 `key' using "`actual_renamed'", nogen assert(match)
    if !`nobs_key' {
        assert nobs == nobs_stata
    }
    assert ngroup == ngroup_stata
    assert ntime == ntime_stata
    assert control_group == control_group_stata
    assert est_method == est_method_stata
end

confirm file "`root'/tests/fixtures/parity/f027/expected/new-stata/export-schema.json"

tempfile tidy_attgt glance_attgt tidy_agg glance_agg actual

import delimited using "`root'/tests/fixtures/parity/f027/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
csdid_estat tidy, saving("`tidy_attgt'") replace
csdid_estat glance, saving("`glance_attgt'") replace

compare_tidy_export, ///
    actual("`tidy_attgt'") ///
    expected("`root'/tests/fixtures/parity/f027/expected/r/tidy-attgt.csv") ///
    key("term group time")

compare_glance_export, ///
    actual("`glance_attgt'") ///
    expected("`root'/tests/fixtures/parity/f027/expected/r/glance-attgt.csv") ///
    key("nobs")

foreach agg_type in simple group calendar dynamic {
    import delimited using "`root'/tests/fixtures/parity/f027/inputs/input.csv", clear asdouble
    csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
    csdid_stats, type(`agg_type')
    csdid_estat tidy, saving("`tidy_agg'") replace
    csdid_estat glance, saving("`glance_agg'") replace

    local tidy_key "type term"
    if "`agg_type'" == "group" local tidy_key "type term group"
    if "`agg_type'" == "calendar" local tidy_key "type term time"
    if "`agg_type'" == "dynamic" local tidy_key "type term event_time"

    compare_tidy_export, ///
        actual("`tidy_agg'") ///
        expected("`root'/tests/fixtures/parity/f027/expected/r/tidy-aggte-`agg_type'.csv") ///
        key("`tidy_key'")

    compare_glance_export, ///
        actual("`glance_agg'") ///
        expected("`root'/tests/fixtures/parity/f027/expected/r/glance-aggte-`agg_type'.csv") ///
        key("type")
}
