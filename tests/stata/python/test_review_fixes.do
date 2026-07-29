version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py020_assert_matrix_equal
    version 15
    args left right tol

    assert rowsof(`left') == rowsof(`right')
    assert colsof(`left') == colsof(`right')
    forvalues i = 1/`=rowsof(`left')' {
        forvalues j = 1/`=colsof(`left')' {
            assert missing(`left'[`i', `j']) == missing(`right'[`i', `j']) if missing(`left'[`i', `j']) | missing(`right'[`i', `j'])
            assert abs(`left'[`i', `j'] - `right'[`i', `j']) <= `tol' + `tol' * abs(`left'[`i', `j']) if !missing(`left'[`i', `j']) & !missing(`right'[`i', `j'])
        }
    }
end

program define py020_assert_log_contains
    version 15
    syntax using/, MESSAGE(string)

    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'", 3, .))
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

program define py020_expect_failure
    version 15
    syntax, COMMAND(string) MESSAGE(string)

    tempfile evlog
    capture log close py020event
    log using "`evlog'", text replace name(py020event)
    capture noisily `command'
    local rc = _rc
    log close py020event
    assert `rc' != 0
    py020_assert_log_contains using "`evlog'", message("`message'")
end

foreach input in review-panel clustered-panel boolean-outcome uniform-missing-periods ///
    no-never late-cohort first-period-treated universal-base universal-stochastic id-validation {
    confirm file "`root'/tests/fixtures/parity/py020/inputs/`input'.csv"
}
confirm file "`root'/tests/fixtures/parity/py020/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py020/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py020/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py020/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/py020/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/py020/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py020/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 31
quietly count if coverage_status == "mapped"
assert r(N) == 22
quietly count if coverage_status == "approved-divergence"
assert r(N) == 9

import delimited using "`root'/tests/fixtures/parity/py020/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
* PY020-DIV002 was retired when bal(full) landed: it recorded that csdid had
* no analogue for Python's allow_unbalanced_panel=False balance-dropping path,
* and bal(full) is that path and is now the default.
assert _N == 4
foreach div in PY020-DIV001 PY020-DIV003 PY020-DIV004 PY020-DIV005 {
    quietly count if divergence_id == "`div'"
    assert r(N) == 1
}

import delimited using "`root'/tests/fixtures/parity/py020/inputs/review-panel.csv", clear asdouble
quietly csdid y i.cat_code, ivar(id) time(year) gvar(group) method(reg) analytical nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" == "panel"
matrix Factor = e(attgt)
quietly csdid y, ivar(id) time(year) gvar(group) method(reg) analytical nevertreated base_period(varying) bal(none)
matrix Intercept = e(attgt)
assert rowsof(Factor) == rowsof(Intercept)
local c_att = colnumb(Factor, "att")
local any_diff = 0
forvalues i = 1/`=rowsof(Factor)' {
    if abs(Factor[`i', `c_att'] - Intercept[`i', `c_att']) > 1e-8 {
        local any_diff = 1
    }
}
assert `any_diff' == 1

import delimited using "`root'/tests/fixtures/parity/py020/inputs/review-panel.csv", clear asdouble
quietly csdid y i.cat_code, ivar(id) time(year) gvar(group) method(reg) analytical nevertreated base_period(varying) bal(none)
matrix StdPanel = e(attgt)
quietly csdid y i.cat_code, ivar(id) time(year) gvar(group) method(reg) fast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 1
matrix FastPanel = e(attgt)
py020_assert_matrix_equal StdPanel FastPanel 1e-9

import delimited using "`root'/tests/fixtures/parity/py020/inputs/review-panel.csv", clear asdouble
quietly csdid y i.cat_code, time(year) gvar(group) method(reg) analytical nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" == "repeated-cross-section"
matrix StdRC = e(attgt)
quietly csdid y i.cat_code, time(year) gvar(group) method(reg) fast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 1
matrix FastRC = e(attgt)
py020_assert_matrix_equal StdRC FastRC 1e-9

import delimited using "`root'/tests/fixtures/parity/py020/inputs/review-panel.csv", clear asdouble
quietly csdid y i.cat_code z, ivar(id) time(year) gvar(group) method(dr) analytical nevertreated base_period(varying) bal(none)
matrix Mixed = e(attgt)
preserve
clear
svmat double Mixed, names(col)
quietly count if !missing(att)
assert r(N) > 0
restore

import delimited using "`root'/tests/fixtures/parity/py020/inputs/clustered-panel.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(reg) ///
    wboot(reps(31) cluster(cluster) rseed(202620)) bal(none)
assert e(bstrap) == 1
assert e(biters) == 31
assert e(N_clusters) == 10
matrix ClusterBoot = e(boot_attgt)
preserve
clear
svmat double ClusterBoot, names(col)
quietly count if !missing(se_boot) & se_boot > 0 & se_boot < 10
assert r(N) > 0
restore

import delimited using "`root'/tests/fixtures/parity/py020/inputs/clustered-panel.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(reg) cluster(cluster) analytical nevertreated base_period(varying) bal(none)
assert "`e(clustervar)'" == "cluster"
matrix ClusterAnalytic = e(attgt)
preserve
clear
svmat double ClusterAnalytic, names(col)
quietly count if !missing(se) & se > 0
assert r(N) > 0
restore

import delimited using "`root'/tests/fixtures/parity/py020/inputs/late-cohort.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) anticipation(0) analytical nevertreated base_period(varying) bal(none)
matrix UGLate0 = e(unit_group)
preserve
clear
svmat double UGLate0, names(col)
quietly count if group == 5
assert r(N) == 0
restore

import delimited using "`root'/tests/fixtures/parity/py020/inputs/late-cohort.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) anticipation(1) analytical nevertreated base_period(varying) bal(none)
assert e(N_attgt) > 0

import delimited using "`root'/tests/fixtures/parity/py020/inputs/first-period-treated.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) analytical nevertreated base_period(varying) bal(none)
matrix UGFirst = e(unit_group)
preserve
clear
svmat double UGFirst, names(col)
quietly count if group == 1
assert r(N) == 0
restore

import delimited using "`root'/tests/fixtures/parity/py020/inputs/boolean-outcome.csv", clear asdouble
quietly csdid y_bool, ivar(id) time(year) gvar(group) analytical nevertreated base_period(varying) bal(none)
assert e(N_attgt) > 0

import delimited using "`root'/tests/fixtures/parity/py020/inputs/id-validation.csv", clear asdouble
py020_expect_failure, command("csdid y nonexistent_column, ivar(id) time(year) gvar(group) analytical") message("variable nonexistent_column not found")

import delimited using "`root'/tests/fixtures/parity/py020/inputs/id-validation.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) analytical nevertreated base_period(varying) bal(none)
assert e(N_attgt) > 0
assert "`e(panel_mode)'" == "panel"

import delimited using "`root'/tests/fixtures/parity/py020/inputs/id-validation.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) analytical nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" == "panel"

drop in 2
quietly csdid y, ivar(id) time(year) gvar(group) analytical nevertreated base_period(varying) bal(none)
assert "`e(panel_mode)'" == "allow_unbalanced"

import delimited using "`root'/tests/fixtures/parity/py020/inputs/uniform-missing-periods.csv", clear asdouble
bysort id: gen id_n = _N
summarize id_n, meanonly
egen byte idtag = tag(id)
egen byte ytag = tag(year)
quietly count
local uniform_n = r(N)
quietly count if idtag
local uniform_ids = r(N)
quietly count if ytag
local uniform_times = r(N)
assert `uniform_n' != `uniform_ids' * `uniform_times'
quietly csdid y, ivar(id) time(year) gvar(group) method(reg) notyet analytical base_period(varying) bal(none)
assert "`e(panel_mode)'" == "allow_unbalanced"
assert e(N_attgt) > 0

import delimited using "`root'/tests/fixtures/parity/py020/inputs/no-never.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) analytical nevertreated base_period(varying) bal(none)
matrix UGNoNever = e(unit_group)
preserve
clear
svmat double UGNoNever, names(col)
quietly count if group == 0
assert r(N) > 0
quietly count if group == 4
assert r(N) == 0
restore

import delimited using "`root'/tests/fixtures/parity/py020/inputs/universal-stochastic.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) method(ipw) base_period(universal) analytical nevertreated bal(none)
matrix Uni = e(attgt)
preserve
clear
svmat double Uni, names(col)
quietly count if group == 3 & time == 2 & missing(se)
assert r(N) == 1
quietly count if group == 3 & time != 2 & !missing(se)
assert r(N) > 0
quietly count if group == 3 & time != 2 & missing(se)
assert r(N) == 0
restore

import delimited using "`root'/tests/fixtures/parity/py020/inputs/universal-stochastic.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) method(ipw) base_period(varying) analytical nevertreated bal(none)
matrix Var = e(attgt)
preserve
clear
svmat double Var, names(col)
quietly count if missing(se)
assert r(N) == 0
restore

import delimited using "`root'/tests/fixtures/parity/py020/inputs/universal-base.csv", clear asdouble
quietly csdid y, ivar(id) time(period) gvar(g) method(ipw) base_period(universal) analytical nevertreated bal(none)
matrix Det = e(attgt)
preserve
clear
svmat double Det, names(col)
quietly count if missing(se)
assert r(N) == _N
restore

import delimited using "`root'/tests/fixtures/parity/py020/inputs/id-validation.csv", clear asdouble
generate str12 sid = "unit_" + string(id, "%02.0f")
py020_expect_failure, command("csdid y, ivar(sid) time(year) gvar(group) analytical") message("ivar() must be numeric")

import delimited using "`root'/tests/fixtures/parity/py020/inputs/id-validation.csv", clear asdouble
recast long id
quietly csdid y, ivar(id) time(year) gvar(group) analytical nevertreated base_period(varying) bal(none)
assert e(N_attgt) > 0

* ---------------------------------------------------------------------------
* PY020 R-oracle comparison (added 2026-07-27)
* Includes Stata factor covariates (i.cat_code), which map to R factor(cat_code),
* and a seeded clustered bootstrap.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py020/expected/r/attgt.csv"
tempfile py020_actual
quietly {
    clear
    set obs 0
    gen str60 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`py020_actual'", replace emptyok
}
capture program drop py020_grab
program define py020_grab
    args tag store
    tempname A
    matrix `A' = e(attgt)
    local nr = rowsof(`A')
    preserve
    quietly {
        clear
        set obs `nr'
        gen str60 scenario = "`tag'"
        gen double group = .
        gen double time = .
        gen double att_stata = .
        gen double se_stata = .
        forvalues i = 1/`nr' {
            replace group     = `A'[`i',1] in `i'
            replace time      = `A'[`i',2] in `i'
            replace att_stata = `A'[`i',4] in `i'
            replace se_stata  = `A'[`i',5] in `i'
        }
        append using "`store'"
        save "`store'", replace
    }
    restore
end

import delimited using "`root'/tests/fixtures/parity/py020/inputs/review-panel.csv", clear asdouble
quietly csdid y i.cat_code, ivar(id) time(year) gvar(group) method(reg) analytical nevertreated base_period(varying) bal(none)
py020_grab "factor_reg_panel" "`py020_actual'"
import delimited using "`root'/tests/fixtures/parity/py020/inputs/review-panel.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(reg) analytical nevertreated base_period(varying) bal(none)
py020_grab "nox_reg_panel" "`py020_actual'"
import delimited using "`root'/tests/fixtures/parity/py020/inputs/review-panel.csv", clear asdouble
quietly csdid y i.cat_code, time(year) gvar(group) method(reg) analytical nevertreated base_period(varying) bal(none)
py020_grab "factor_reg_rcs" "`py020_actual'"
import delimited using "`root'/tests/fixtures/parity/py020/inputs/review-panel.csv", clear asdouble
quietly csdid y i.cat_code z, ivar(id) time(year) gvar(group) method(dr) analytical nevertreated base_period(varying) bal(none)
py020_grab "factor_z_dr_panel" "`py020_actual'"
import delimited using "`root'/tests/fixtures/parity/py020/inputs/clustered-panel.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(reg) wboot(reps(31) cluster(cluster) rseed(202620)) nevertreated base_period(varying) bal(none)
py020_grab "clustered_boot31" "`py020_actual'"

import delimited using "`root'/tests/fixtures/parity/py020/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`py020_actual'", assert(match) nogen
quietly count
assert r(N) == 16
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "PY020 OK: 16 cells (factor covariates, RCS, and a seeded clustered bootstrap) match R to <1e-9"
