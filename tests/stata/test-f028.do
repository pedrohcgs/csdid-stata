version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define normalize_plot_expected
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

program define compare_plot_data
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
    normalize_plot_expected
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

confirm file "`root'/tests/fixtures/parity/f028/expected/new-stata/plot-schema.json"
confirm file "`root'/tests/fixtures/parity/f028/expected/r/events.json"

tempfile plotdata

import delimited using "`root'/tests/fixtures/parity/f028/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
csdid_plot, saving("`plotdata'") replace
compare_plot_data, ///
    actual("`plotdata'") ///
    expected("`root'/tests/fixtures/parity/f028/expected/r/plot-data-attgt.csv") ///
    key("plot_type group time")

csdid_plot, saving("`plotdata'") replace group(3)
compare_plot_data, ///
    actual("`plotdata'") ///
    expected("`root'/tests/fixtures/parity/f028/expected/r/plot-data-attgt-group3.csv") ///
    key("plot_type group time")

foreach agg_type in dynamic group calendar {
    import delimited using "`root'/tests/fixtures/parity/f028/inputs/input.csv", clear asdouble
    csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
    csdid_stats, type(`agg_type')
    csdid_plot, saving("`plotdata'") replace
    compare_plot_data, ///
        actual("`plotdata'") ///
        expected("`root'/tests/fixtures/parity/f028/expected/r/plot-data-aggte-`agg_type'.csv") ///
        key("plot_type x")
}

import delimited using "`root'/tests/fixtures/parity/f028/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
csdid_stats, type(simple)
capture noisily csdid_plot, saving("`plotdata'") replace
assert _rc == 498
