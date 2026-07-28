version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

mata:
real scalar f040__maxabsdiff(string scalar aname, string scalar bname)
{
    real matrix a, b

    a = st_matrix(aname)
    b = st_matrix(bname)
    if (rows(a) != rows(b) | cols(a) != cols(b)) return(.)
    return(max(abs(vec(a :- b))))
}
end

confirm file "`root'/tests/fixtures/parity/f040/expected/contract/scenario-coverage.csv"
confirm file "`root'/tests/fixtures/parity/f040/expected/contract/source-audit.csv"
confirm file "`root'/tests/fixtures/parity/f040/metadata/manifest.json"
confirm file "`root'/tests/fixtures/parity/f041/metadata/manifest.json"
confirm file "`root'/tests/fixtures/parity/f042/metadata/manifest.json"
confirm file "`root'/tests/fixtures/parity/f043/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/f040/expected/contract/scenario-coverage.csv", clear varnames(1) stringcols(_all)
assert _N == 6
assert matrix_id == "F040"
assert source_kind == "python-test-map"
assert coverage_status == "covered"
assert inlist(stata_gate, "F040", "F041", "F042", "F043")
quietly count if scenario_id == "jel_faster_mode_table7_dr_weighted" & stata_gate == "F040"
assert r(N) == 1

import delimited using "`root'/tests/fixtures/parity/f040/expected/contract/source-audit.csv", clear varnames(1) stringcols(_all)
assert _N == 2
quietly count if source == "r-did" & status == "available"
assert r(N) == 1
quietly count if source == "python-csdid" & inlist(status, "available", "absent-in-available-checkout")
assert r(N) == 1

import delimited using "`root'/tests/fixtures/parity/f041/inputs/table7-input.csv", clear asdouble
quietly csdid crude_rate_20_64 perc_female perc_white perc_hispanic unemp_rate poverty_rate median_income [iw=set_wt], analytical ///
    ivar(county_code) time(year) gvar(treat_year) method(dr) base_period(universal) nofast
assert e(fast_requested) == 0
assert e(fast_allowed) == 0
assert e(fast_used) == 0
assert "`e(compute_path)'" == "baseline"
matrix A0 = e(attgt)
quietly csdid_stats, type(simple) na_rm
matrix S0 = e(aggte)

quietly csdid crude_rate_20_64 perc_female perc_white perc_hispanic unemp_rate poverty_rate median_income [iw=set_wt], analytical ///
    ivar(county_code) time(year) gvar(treat_year) method(dr) base_period(universal) fast
assert e(fast_requested) == 1
assert e(fast_used) == 1
if "`e(panel_mode)'" == "panel" {
    assert "`e(compute_path)'" == "fast-balanced-panel"
}
else {
    assert "`e(compute_path)'" == "fast-allow-unbalanced"
}
matrix A1 = e(attgt)
quietly csdid_stats, type(simple) na_rm
matrix S1 = e(aggte)

mata: st_numscalar("f040_att_diff", f040__maxabsdiff("A0", "A1"))
mata: st_numscalar("f040_simple_diff", f040__maxabsdiff("S0", "S1"))
assert scalar(f040_att_diff) <= 1e-12
assert scalar(f040_simple_diff) <= 1e-12
