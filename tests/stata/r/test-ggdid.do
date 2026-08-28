version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt013_assert_log_contains
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

program define rt013_normalize_plot_expected
    version 15
    capture confirm numeric variable x_label
    if !_rc {
        tostring x_label, replace format(%21.0g)
    }
    foreach v in group time event_time {
        capture confirm variable `v'
        if !_rc {
            capture confirm string variable `v'
            if !_rc {
                drop `v'
                generate double `v' = .
            }
        }
    }
end

program define rt013_compare_plot_data
    version 15
    syntax, Actual(string) Expected(string) Key(string)

    tempfile actual_renamed
    use "`actual'", clear
    foreach v in series x_label estimate ci_low ci_high group time event_time significant {
        local iskey = strpos(" `key' ", " `v' ") > 0
        if !`iskey' {
            rename `v' `v'_stata
        }
    }
    save "`actual_renamed'", replace

    import delimited using "`expected'", clear asdouble
    rt013_normalize_plot_expected
    merge 1:1 `key' using "`actual_renamed'", nogen assert(match)

    foreach v in series x_label {
        local iskey = strpos(" `key' ", " `v' ") > 0
        if !`iskey' assert `v' == `v'_stata
    }
    foreach v in significant {
        local iskey = strpos(" `key' ", " `v' ") > 0
        if !`iskey' assert `v' == `v'_stata
    }
    foreach v in estimate ci_low ci_high group time event_time {
        local iskey = strpos(" `key' ", " `v' ") > 0
        if !`iskey' {
            assert missing(`v') == missing(`v'_stata) if missing(`v') | missing(`v'_stata)
            assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v') & !missing(`v'_stata)
        }
    }
end

confirm file "`root'/tests/fixtures/parity/rt013/inputs/sim-ggdid.csv"
confirm file "`root'/tests/fixtures/parity/rt013/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt013/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt013/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt013/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt013/expected/contract/events.csv"
confirm file "`root'/tests/fixtures/parity/rt013/expected/r/plot-data-attgt.csv"
confirm file "`root'/tests/fixtures/parity/rt013/expected/r/plot-data-attgt-first-group.csv"
confirm file "`root'/tests/fixtures/parity/rt013/expected/r/plot-data-aggte-dynamic.csv"
confirm file "`root'/tests/fixtures/parity/rt013/expected/r/plot-data-aggte-group.csv"
confirm file "`root'/tests/fixtures/parity/rt013/expected/r/plot-data-aggte-calendar.csv"
confirm file "`root'/tests/fixtures/parity/rt013/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt013/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 12
quietly count if coverage_status == "mapped"
assert r(N) == 8
quietly count if coverage_status == "approved-divergence"
assert r(N) == 4

import delimited using "`root'/tests/fixtures/parity/rt013/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 1
assert divergence_id[1] == "RT013-DIV001"

tempfile plotdata evlog

import delimited using "`root'/tests/fixtures/parity/rt013/expected/r/plot-data-attgt-first-group.csv", clear asdouble
quietly summarize group, meanonly
local first_group = r(min)

import delimited using "`root'/tests/fixtures/parity/rt013/inputs/sim-ggdid.csv", clear asdouble
* the rt013 fixtures are generated with cband = FALSE (aggte pointwise), so
* the Stata side runs analytical POINTWISE: analytical alone now bands
* aggregations simultaneously by bootstrap, exactly as R's bstrap = FALSE
* cband = TRUE does, which is a different estimand than these fixtures pin.
csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical pointwise nevertreated base_period(varying) bal(none)
csdid_plot, saving("`plotdata'") replace
rt013_compare_plot_data, ///
    actual("`plotdata'") ///
    expected("`root'/tests/fixtures/parity/rt013/expected/r/plot-data-attgt.csv") ///
    key("plot_type group time")

csdid_plot, saving("`plotdata'") replace group(`first_group')
rt013_compare_plot_data, ///
    actual("`plotdata'") ///
    expected("`root'/tests/fixtures/parity/rt013/expected/r/plot-data-attgt-first-group.csv") ///
    key("plot_type group time")

capture log close rt013event
log using "`evlog'", text replace name(rt013event)
capture noisily csdid_plot, saving("`plotdata'") replace group(9999)
local actual_rc = _rc
log close rt013event
assert `actual_rc' == 0
rt013_assert_log_contains using "`evlog'", message("Some of the specified groups do not exist")
rt013_compare_plot_data, ///
    actual("`plotdata'") ///
    expected("`root'/tests/fixtures/parity/rt013/expected/r/plot-data-attgt.csv") ///
    key("plot_type group time")

foreach agg_type in dynamic group calendar {
    import delimited using "`root'/tests/fixtures/parity/rt013/inputs/sim-ggdid.csv", clear asdouble
    csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical pointwise nevertreated base_period(varying) bal(none)
    csdid_stats, type(`agg_type')
    csdid_plot, saving("`plotdata'") replace
    rt013_compare_plot_data, ///
        actual("`plotdata'") ///
        expected("`root'/tests/fixtures/parity/rt013/expected/r/plot-data-aggte-`agg_type'.csv") ///
        key("plot_type x")
}

import delimited using "`root'/tests/fixtures/parity/rt013/inputs/sim-ggdid.csv", clear asdouble
csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical pointwise nevertreated base_period(varying) bal(none)
csdid_stats, type(simple)
capture log close rt013event
log using "`evlog'", text replace name(rt013event)
capture noisily csdid_plot, saving("`plotdata'") replace
local actual_rc = _rc
log close rt013event
assert `actual_rc' == 498
rt013_assert_log_contains using "`evlog'", message("Plot method not available for this type of aggregation")

import delimited using "`root'/tests/fixtures/parity/rt013/inputs/sim-ggdid.csv", clear asdouble
csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical pointwise nevertreated base_period(varying) bal(none)
capture log close rt013event
log using "`evlog'", text replace name(rt013event)
capture noisily csdid_plot, saving("`plotdata'") replace xlab(Time)
local actual_rc = _rc
log close rt013event
assert `actual_rc' == 198
rt013_assert_log_contains using "`evlog'", message("unsupported option")
