version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py019_save_attgt
    version 15
    syntax, SCENARIO(string) OUTFILE(string) [APPEND]

    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    gen str32 scenario = "`scenario'"
    rename time t
    rename (att se) (att_stata se_stata)
    keep scenario group t att_stata se_stata
    if "`append'" == "" {
        save "`outfile'", replace
    }
    else {
        append using "`outfile'"
        save "`outfile'", replace
    }
    restore
end

program define py019_save_aggte
    version 15
    syntax, SCENARIO(string) TYPE(string) OUTFILE(string) [APPEND]

    quietly csdid_stats, type(`type') na_rm
    matrix G = e(aggte)
    preserve
    clear
    svmat double G, names(col)
    gen str32 scenario = "`scenario'"
    gen str12 type = "`type'"
    rename (att se overall_att overall_se) ///
           (att_egt_stata se_egt_stata overall_att_stata overall_se_stata)
    if "`type'" == "simple" {
        replace egt = .
        replace att_egt_stata = .
        replace se_egt_stata = .
    }
    keep scenario type egt att_egt_stata se_egt_stata overall_att_stata overall_se_stata
    if "`append'" == "" {
        save "`outfile'", replace
    }
    else {
        append using "`outfile'"
        save "`outfile'", replace
    }
    restore
end

program define py019_assert_attgt
    version 15
    syntax using/, ACTUAL(string)

    import delimited using "`using'", clear asdouble
    merge 1:1 scenario group t using "`actual'", nogen assert(match)
    assert abs(att - att_stata) <= 1e-4 if !missing(att)
    assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
    assert abs(se - se_stata) <= 5e-4 + 0.03 * abs(se) if !missing(se)
end

program define py019_assert_aggte
    version 15
    syntax using/, ACTUAL(string)

    import delimited using "`using'", clear asdouble
    merge 1:1 scenario type egt using "`actual'", nogen assert(match)
    foreach v in att_egt se_egt overall_att overall_se {
        assert missing(`v') == missing(`v'_stata) if missing(`v') | missing(`v'_stata)
    }
    assert abs(att_egt - att_egt_stata) <= 1e-4 if !missing(att_egt)
    assert abs(se_egt - se_egt_stata) <= 5e-4 + 0.03 * abs(se_egt) if !missing(se_egt)
    assert abs(overall_att - overall_att_stata) <= 1e-4 if !missing(overall_att)
    assert abs(overall_se - overall_se_stata) <= 5e-4 + 0.03 * abs(overall_se) if !missing(overall_se)
end

program define py019_assert_attgt_current
    version 15
    * There is deliberately no option to skip the standard-error comparison.
    * There used to be (`nose'), and the one caller that passed it -- the
    * fix_weights block -- was therefore comparing point estimates only. That
    * hid a reference file carrying the did 2.5.0 fix_weights = "varying" bug,
    * whose "varying" SEs were all exactly 2x too large.
    syntax, SCENARIOVAR(string) ATTFILE(string) ACTUAL(string)

    import delimited using "`attfile'", clear asdouble
    merge 1:1 `scenariovar' group t using "`actual'", nogen assert(match)
    assert abs(att - att_stata) <= 1e-6 if !missing(att)
    assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
    assert abs(se - se_stata) <= 5e-4 + 0.03 * abs(se) if !missing(se)
end

foreach input in mpdta sim_data mpdta_tvw factor_cov mpdta_extra {
    confirm file "`root'/tests/fixtures/parity/py019/inputs/`input'.csv"
}
foreach ref in ref_attgt ref_aggte ref_pretest ref_fixweights {
    confirm file "`root'/tests/fixtures/parity/py019/expected/r/`ref'.csv"
}
confirm file "`root'/tests/fixtures/parity/py019/expected/r/sim/ref_factor.csv"
confirm file "`root'/tests/fixtures/parity/py019/expected/r/sim/ref_gaps.csv"
confirm file "`root'/tests/fixtures/parity/py019/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py019/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py019/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py019/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py019/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 42
quietly count if coverage_status == "mapped"
assert r(N) == 42
quietly count if divergence_id != ""
assert r(N) == 0

tempfile actual_att actual_agg
local first_att 1
local first_agg 1

foreach scenario in mpdta_nev_dr mpdta_nyt_dr mpdta_nev_reg_cov mpdta_nev_ipw sim_nev_dr {
    if "`scenario'" == "sim_nev_dr" {
        import delimited using "`root'/tests/fixtures/parity/py019/inputs/sim_data.csv", clear asdouble
        quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
    }
    else {
        import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
        local cov ""
        local method "dr"
        * The mpdta_nev_* scenarios are never-treated by name; say so, because
        * the omitted-option default is now not-yet-treated.
        local control "nevertreated"
        if "`scenario'" == "mpdta_nyt_dr" local control "notyet"
        if "`scenario'" == "mpdta_nev_reg_cov" {
            local cov "lpop"
            local method "reg"
        }
        if "`scenario'" == "mpdta_nev_ipw" local method "ipw"
        quietly csdid lemp `cov', ivar(countyreal) time(year) gvar(firsttreat) method(`method') `control' analytical base_period(varying) bal(none)
    }

    local appendopt ""
    if !`first_att' local appendopt "append"
    py019_save_attgt, scenario("`scenario'") outfile("`actual_att'") `appendopt'
    local first_att 0

    foreach aggtype in simple group dynamic calendar {
        local appendagg ""
        if !`first_agg' local appendagg "append"
        py019_save_aggte, scenario("`scenario'") type(`aggtype') outfile("`actual_agg'") `appendagg'
        local first_agg 0
    }
}

py019_assert_attgt using "`root'/tests/fixtures/parity/py019/expected/r/ref_attgt.csv", actual("`actual_att'")
py019_assert_aggte using "`root'/tests/fixtures/parity/py019/expected/r/ref_aggte.csv", actual("`actual_agg'")

tempfile actual_fix
local first 1
foreach tag in none base_period first_period varying {
    import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta_tvw.csv", clear asdouble
    local fixopt ""
    if "`tag'" != "none" local fixopt "fix_weights(`tag')"
    quietly csdid lemp [iw=wt], ivar(countyreal) time(year) gvar(firsttreat) method(reg) `fixopt' analytical nevertreated base_period(varying) bal(none)
    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    gen str16 fix_weights = "`tag'"
    rename time t
    rename (att se) (att_stata se_stata)
    keep fix_weights group t att_stata se_stata
    if `first' {
        save "`actual_fix'", replace
        local first 0
    }
    else {
        append using "`actual_fix'"
        save "`actual_fix'", replace
    }
    restore
}
* SEs are compared here. They previously were not: this block passed `nose`,
* and the imported reference carried the did 2.5.0 fix_weights = "varying" bug
* (every "varying" SE exactly 2x too large), so nothing would have caught it.
* The reference is now generated locally against the pinned did.
py019_assert_attgt_current, scenariovar(fix_weights) ///
    attfile("`root'/tests/fixtures/parity/py019/expected/r/ref_fixweights.csv") ///
    actual("`actual_fix'")

tempfile actual_factor
local first 1
foreach mode in standard fast {
    import delimited using "`root'/tests/fixtures/parity/py019/inputs/factor_cov.csv", clear asdouble
    encode cat, gen(cat_code)
    local fastopt ""
    if "`mode'" == "fast" local fastopt "fast"
    quietly csdid y i.cat_code, ivar(id) time(period) gvar(g) method(reg) `fastopt' analytical nevertreated base_period(varying) bal(none)
    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    rename time t
    rename (att se) (att_stata se_stata)
    keep group t att_stata se_stata
    if `first' {
        save "`actual_factor'", replace
        local first 0
    }
    else {
        append using "`actual_factor'"
        save "`actual_factor'", replace
    }
    restore
}
use "`actual_factor'", clear
collapse (mean) att_stata se_stata, by(group t)
save "`actual_factor'", replace
import delimited using "`root'/tests/fixtures/parity/py019/expected/r/sim/ref_factor.csv", clear asdouble
merge 1:1 group t using "`actual_factor'", nogen assert(match)
assert abs(att - att_stata) <= 1e-6 if !missing(att)
assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
assert abs(se - se_stata) <= 5e-4 + 0.03 * abs(se) if !missing(se)

tempfile actual_gaps
local first 1
foreach scenario in rc universal anticipation1 weighted clustered {
    import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta_extra.csv", clear asdouble
    if "`scenario'" == "rc" {
        quietly csdid lemp, time(year) gvar(firsttreat) method(reg) analytical nevertreated base_period(varying) bal(none)
    }
    else if "`scenario'" == "universal" {
        quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(reg) base_period(universal) analytical nevertreated bal(none)
    }
    else if "`scenario'" == "anticipation1" {
        quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(reg) anticipation(1) analytical nevertreated base_period(varying) bal(none)
    }
    else if "`scenario'" == "weighted" {
        quietly csdid lemp [iw=wt], ivar(countyreal) time(year) gvar(firsttreat) method(reg) analytical nevertreated base_period(varying) bal(none)
    }
    else if "`scenario'" == "clustered" {
        quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(reg) cluster(clust) analytical nevertreated base_period(varying) bal(none)
    }
    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    gen str16 scenario = "`scenario'"
    rename time t
    rename (att se) (att_stata se_stata)
    keep scenario group t att_stata se_stata
    if `first' {
        save "`actual_gaps'", replace
        local first 0
    }
    else {
        append using "`actual_gaps'"
        save "`actual_gaps'", replace
    }
    restore
}
py019_assert_attgt_current, scenariovar(scenario) ///
    attfile("`root'/tests/fixtures/parity/py019/expected/r/sim/ref_gaps.csv") ///
    actual("`actual_gaps'")

* ---------------------------------------------------------------------------
* Parallel-trends Wald pre-test (W and its chi-square p-value).
*
* Inherited from Python csdid test_pretest.py, which pins the same five
* scenarios. R reports the statistic on the MP object as $W and $Wpval, and
* stores Wpval already rounded to 5 dp; csdid exposes them as e(wald_stat) and
* e(wald_pvalue). The statistic is a deterministic function of the analytical
* influence-function covariance, so it is compared tightly rather than at the
* 1e-3 the Python suite uses.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py019/expected/r/ref_pretest.csv"

tempfile actual_pre
quietly {
    clear
    set obs 0
    gen str24 scenario = ""
    gen double w_stata = .
    gen double wpval_stata = .
    save "`actual_pre'", replace emptyok
}

capture program drop py019_pretest
program define py019_pretest
    args tag store
    preserve
    quietly {
        clear
        set obs 1
        gen str24 scenario = "`tag'"
        gen double w_stata = `e(wald_stat)'
        gen double wpval_stata = `e(wald_pvalue)'
        append using "`store'"
        save "`store'", replace
    }
    restore
end

import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(dr) analytical nevertreated base_period(varying) bal(none)
py019_pretest "mpdta_nev_dr" "`actual_pre'"

import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(dr) notyet analytical base_period(varying) bal(none)
py019_pretest "mpdta_nyt_dr" "`actual_pre'"

import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
quietly csdid lemp lpop, ivar(countyreal) time(year) gvar(firsttreat) method(reg) analytical nevertreated base_period(varying) bal(none)
py019_pretest "mpdta_nev_reg_cov" "`actual_pre'"

import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) method(ipw) analytical nevertreated base_period(varying) bal(none)
py019_pretest "mpdta_nev_ipw" "`actual_pre'"

import delimited using "`root'/tests/fixtures/parity/py019/inputs/sim_data.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none)
py019_pretest "sim_nev_dr" "`actual_pre'"

import delimited using "`root'/tests/fixtures/parity/py019/expected/r/ref_pretest.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario using "`actual_pre'", assert(match) nogen
quietly count
assert r(N) == 5
assert abs(w - w_stata) <= 1e-8 + 1e-8 * abs(w) if !missing(w)
* Wpval is R's 5-dp rounded chi-square tail, so it must agree exactly at that
* precision rather than approximately.
assert abs(wpval - wpval_stata) < 5e-6 if !missing(wpval)

display "PY019 pretest OK: W and Wpval match R on 5 scenarios"
