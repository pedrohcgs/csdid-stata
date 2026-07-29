version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py004_save_attgt_se
    version 15
    syntax, OUTFILE(string)

    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    keep group time att se
    save "`outfile'", replace
    restore
end

program define py004_assert_positive_attgt_se
    version 15

    matrix A = e(attgt)
    assert rowsof(A) > 0
    preserve
    clear
    svmat double A, names(col)
    quietly count if !missing(se) & se > 0
    assert r(N) > 0
    restore
end

program define py004_assert_agg_positive
    version 15
    syntax, TYPE(string)

    quietly csdid_stats, type(`type')
    matrix G = e(aggte)
    assert rowsof(G) > 0
    preserve
    clear
    svmat double G, names(col)
    quietly count if !missing(overall_se) & overall_se > 0
    assert r(N) > 0
    restore
end

program define py004_assert_bootstrap_close
    version 15
    syntax, RTOL(real)

    matrix B = e(boot_attgt)
    preserve
    clear
    svmat double B, names(col)
    quietly count if !missing(se_boot) & se_boot > 0
    assert r(N) > 0
    quietly count if !missing(se_analytic) & se_analytic > 0
    assert r(N) > 0
    generate double rel = abs(se_boot - se_analytic) / se_boot if se_boot > 0 & se_analytic < .
    quietly summarize rel, meanonly
    assert r(max) < `rtol'
    restore
end

confirm file "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-404.csv"
confirm file "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-505.csv"
confirm file "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-606.csv"
confirm file "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-707.csv"
confirm file "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-808.csv"
confirm file "`root'/tests/fixtures/parity/py004/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py004/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py004/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py004/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py004/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 20
quietly count if coverage_status == "mapped"
assert r(N) == 20

tempfile iid cl fast std

import delimited using "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-404.csv", clear asdouble
csdid y, ivar(id) time(t) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
py004_save_attgt_se, outfile("`iid'")
import delimited using "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-404.csv", clear asdouble
csdid y, ivar(id) time(t) gvar(g) method(reg) cluster(cl) analytical nevertreated base_period(varying) bal(none)
py004_save_attgt_se, outfile("`cl'")
use "`iid'", clear
rename se se_iid
merge 1:1 group time using "`cl'", nogen assert(match)
rename se se_cl
generate double rel = abs(se_cl - se_iid) / se_iid if se_iid > 0 & se_cl < .
quietly count if rel > 0.01
assert r(N) > 0

import delimited using "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-505.csv", clear asdouble
csdid y, ivar(id) time(t) gvar(g) method(reg) cluster(cl) analytical nevertreated base_period(varying) bal(none)
py004_assert_positive_attgt_se
foreach type in simple group dynamic {
    py004_assert_agg_positive, type(`type')
}

import delimited using "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-505.csv", clear asdouble
csdid y, ivar(id) time(t) gvar(g) method(reg) cluster(cl) wboot(reps(1499) rseed(20250401)) nevertreated base_period(varying) bal(none)
py004_assert_bootstrap_close, rtol(.35)

import delimited using "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-808.csv", clear asdouble
csdid y, time(t) gvar(g) method(reg) cluster(cl) nofast analytical nevertreated base_period(varying) bal(none)
py004_save_attgt_se, outfile("`std'")
import delimited using "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-808.csv", clear asdouble
csdid y, time(t) gvar(g) method(reg) cluster(cl) fast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-repeated-cross-section"
py004_save_attgt_se, outfile("`fast'")
use "`std'", clear
rename (att se) (att_std se_std)
merge 1:1 group time using "`fast'", nogen assert(match)
rename (att se) (att_fast se_fast)
assert abs(att_std - att_fast) < 1e-10
assert abs(se_std - se_fast) < 1e-8

import delimited using "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-606.csv", clear asdouble
csdid y, time(t) gvar(g) method(reg) cluster(cl) wboot(reps(1499) rseed(20250402)) nevertreated base_period(varying) bal(none)
py004_assert_bootstrap_close, rtol(.35)

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-606.csv", clear asdouble
    csdid y, ivar(id) time(t) gvar(g) method(`method') cluster(cl) analytical nevertreated base_period(varying) bal(none)
    py004_assert_positive_attgt_se
}

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-707.csv", clear asdouble
    csdid y, ivar(id) time(t) gvar(g) method(`method') cluster(cl) analytical nevertreated base_period(varying) bal(none)
    foreach type in simple group dynamic {
        py004_assert_agg_positive, type(`type')
    }
}

* ---------------------------------------------------------------------------
* PY004 R-oracle comparison (added 2026-07-27)
* The assertions above check that clustered standard errors are positive and
* differ from the iid ones; they never compared a value against R. This pins
* every cell of the analytical scenarios.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py004/expected/r/attgt.csv"
tempfile py004_actual
quietly {
    clear
    set obs 0
    gen str24 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`py004_actual'", replace emptyok
}
capture program drop py004_grab
program define py004_grab
    args tag store
    tempname A
    matrix `A' = e(attgt)
    local nr = rowsof(`A')
    preserve
    quietly {
        clear
        set obs `nr'
        gen str24 scenario = "`tag'"
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

import delimited using "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-404.csv", clear asdouble
quietly csdid y, ivar(id) time(t) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
py004_grab "p404_iid_reg" "`py004_actual'"
import delimited using "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-404.csv", clear asdouble
quietly csdid y, ivar(id) time(t) gvar(g) method(reg) cluster(cl) analytical nevertreated base_period(varying) bal(none)
py004_grab "p404_cluster_reg" "`py004_actual'"
import delimited using "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-606.csv", clear asdouble
quietly csdid y, time(t) gvar(g) method(reg) cluster(cl) analytical nevertreated base_period(varying) bal(none)
py004_grab "rcs606_cluster_reg" "`py004_actual'"
foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-606.csv", clear asdouble
    quietly csdid y, ivar(id) time(t) gvar(g) method(`method') cluster(cl) analytical nevertreated base_period(varying) bal(none)
    py004_grab "p606_cluster_`method'" "`py004_actual'"
    import delimited using "`root'/tests/fixtures/parity/py004/inputs/clustered-shocks-707.csv", clear asdouble
    quietly csdid y, ivar(id) time(t) gvar(g) method(`method') cluster(cl) analytical nevertreated base_period(varying) bal(none)
    py004_grab "p707_cluster_`method'" "`py004_actual'"
}

import delimited using "`root'/tests/fixtures/parity/py004/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`py004_actual'", assert(match) nogen
quietly count
assert r(N) == 54
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "PY004 OK: 54 cells (9 clustered analytical scenarios) match R to <1e-9"
