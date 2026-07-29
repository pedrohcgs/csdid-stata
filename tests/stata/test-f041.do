version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f041_run_cell
    version 15
    syntax , PANEL(string) METHOD(string) OUTFILE(string) [APPEND]

    import delimited using "`c(pwd)'/tests/fixtures/parity/f041/inputs/table7-input.csv", clear asdouble
    local wopt ""
    if "`panel'" == "weighted" local wopt "[iw=set_wt]"

    quietly csdid crude_rate_20_64 perc_female perc_white perc_hispanic unemp_rate poverty_rate median_income `wopt', analytical ///
        ivar(county_code) time(year) gvar(treat_year) method(`method') base_period(universal) bal(none)
    assert "`e(panel_mode)'" == "panel"
    assert "`e(method)'" == "`method'"
    assert "`e(base_period)'" == "universal"
    assert e(N) == 4400
    assert e(N_units) == 2200

    quietly csdid_stats, type(simple) na_rm
    matrix G = e(aggte)
    local n_agg = rowsof(G)
    preserve
    clear
    svmat double G, names(col)
    gen str12 panel = "`panel'"
    gen str8 method = "`method'"
    gen double estimate_stata = overall_att
    gen double se_stata = overall_se
    gen double n_stata = 4400
    gen double n_units_stata = 2200
    keep panel method estimate_stata se_stata n_stata n_units_stata
    if "`append'" == "" {
        save "`outfile'", replace
    }
    else {
        append using "`outfile'"
        save "`outfile'", replace
    }
    restore
end

confirm file "`root'/tests/fixtures/parity/f041/inputs/table7-input.csv"
confirm file "`root'/tests/fixtures/parity/f041/expected/r/table7-analytical.csv"
confirm file "`root'/tests/fixtures/parity/f041/expected/jel/table7-committed.csv"
confirm file "`root'/tests/fixtures/parity/f041/metadata/manifest.json"

tempfile actual
local first 1
foreach panel in unweighted weighted {
    foreach method in reg ipw dr {
        local appendopt ""
        if !`first' local appendopt "append"
        f041_run_cell, panel(`panel') method(`method') outfile("`actual'") `appendopt'
        local first 0
    }
}

import delimited using "`root'/tests/fixtures/parity/f041/expected/r/table7-analytical.csv", clear asdouble
merge 1:1 panel method using "`actual'", nogen assert(match)
assert group == 2014
assert n == n_stata
assert n_units == n_units_stata
gen double estimate_absdiff = abs(estimate - estimate_stata)
gen double se_absdiff = abs(se - se_stata)
quietly count if estimate_absdiff > 1e-8 + 1e-8 * abs(estimate)
if r(N) > 0 {
    list panel method estimate estimate_stata estimate_absdiff, abbreviate(32)
}
assert estimate_absdiff <= 1e-8 + 1e-8 * abs(estimate)
quietly count if se_absdiff > 1e-8 + 1e-8 * abs(se)
if r(N) > 0 {
    list panel method se se_stata se_absdiff, abbreviate(32)
}
assert se_absdiff <= 1e-8 + 1e-8 * abs(se)

preserve
keep panel method estimate
tempfile expected_est
save "`expected_est'", replace
restore

import delimited using "`root'/tests/fixtures/parity/f041/expected/jel/table7-committed.csv", clear asdouble
keep if source == "R_committed"
merge 1:1 panel method using "`expected_est'", nogen assert(match)
assert abs(estimate_displayed - round(estimate, .01)) <= .005
