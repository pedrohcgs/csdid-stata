version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py010_assert_log_contains
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

program define py010_assert_plot_file
    version 15
    syntax using/, TYPE(string)

    use `"`using'"', clear
    assert _N > 0
    quietly count if plot_type == "`type'"
    assert r(N) == _N
    assert !missing(estimate)
end

confirm file "`root'/tests/fixtures/parity/py010/inputs/sim-ggdid.csv"
confirm file "`root'/tests/fixtures/parity/py010/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py010/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py010/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/py010/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/py010/expected/contract/plot-scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py010/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py010/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 16
quietly count if coverage_status == "mapped"
assert r(N) == 5
quietly count if coverage_status == "approved-divergence"
assert r(N) == 11

import delimited using "`root'/tests/fixtures/parity/py010/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 2
quietly count if divergence_id == "PY010-DIV001"
assert r(N) == 1
quietly count if divergence_id == "PY010-DIV002"
assert r(N) == 1

tempfile plotdata allplot evlog

import delimited using "`root'/tests/fixtures/parity/py010/inputs/sim-ggdid.csv", clear asdouble
csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical
csdid_plot, saving("`plotdata'") replace
py010_assert_plot_file using "`plotdata'", type("attgt")
copy "`plotdata'" "`allplot'", replace
use "`plotdata'", clear
quietly summarize group if group < ., meanonly
local first_group = r(min)
local all_rows = _N

import delimited using "`root'/tests/fixtures/parity/py010/inputs/sim-ggdid.csv", clear asdouble
csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical
csdid_plot, saving("`plotdata'") replace group(`first_group')
py010_assert_plot_file using "`plotdata'", type("attgt")
use "`plotdata'", clear
assert group == `first_group'
assert _N < `all_rows'

import delimited using "`root'/tests/fixtures/parity/py010/inputs/sim-ggdid.csv", clear asdouble
csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical
capture log close py010event
log using "`evlog'", text replace name(py010event)
capture noisily csdid_plot, saving("`plotdata'") replace group(9999)
local actual_rc = _rc
log close py010event
assert `actual_rc' == 0
py010_assert_log_contains using "`evlog'", message("Some of the specified groups do not exist")
py010_assert_plot_file using "`plotdata'", type("attgt")
use "`plotdata'", clear
assert _N == `all_rows'

foreach agg_type in dynamic group calendar {
    import delimited using "`root'/tests/fixtures/parity/py010/inputs/sim-ggdid.csv", clear asdouble
    csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical
    csdid_stats, type(`agg_type')
    csdid_plot, saving("`plotdata'") replace
    py010_assert_plot_file using "`plotdata'", type("aggte_`agg_type'")
}

import delimited using "`root'/tests/fixtures/parity/py010/inputs/sim-ggdid.csv", clear asdouble
csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical
capture log close py010event
log using "`evlog'", text replace name(py010event)
capture noisily csdid_plot, saving("`plotdata'") replace title(Test)
local actual_rc = _rc
log close py010event
assert `actual_rc' == 198
py010_assert_log_contains using "`evlog'", message("unsupported option")
