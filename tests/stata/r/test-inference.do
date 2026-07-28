version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt015_assert_public_inference
    version 15
    syntax, AGGTYPE(string)

    matrix A = e(attgt)
    matrix IF = e(inffunc)
    assert rowsof(A) > 0
    assert rowsof(IF) > 0
    assert colsof(IF) == rowsof(A)
    preserve
    clear
    svmat double A, names(col)
    quietly count if !missing(att)
    assert r(N) > 0
    quietly count if !missing(se) & se > 0
    assert r(N) > 0
    restore

    quietly csdid_stats, type(`aggtype') na_rm
    matrix G = e(aggte)
    assert rowsof(G) > 0
    preserve
    clear
    svmat double G, names(col)
    quietly count if !missing(se) & se > 0
    assert r(N) > 0
    restore
end

confirm file "`root'/tests/fixtures/parity/rt015/inputs/panel.csv"
confirm file "`root'/tests/fixtures/parity/rt015/inputs/repeated-cross-section.csv"
confirm file "`root'/tests/fixtures/parity/rt015/inputs/unbalanced.csv"
confirm file "`root'/tests/fixtures/parity/rt015/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt015/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt015/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt015/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt015/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/rt015/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt015/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 8
quietly count if coverage_status == "mapped"
assert r(N) == 7
quietly count if coverage_status == "approved-divergence" & divergence_id == "RT015-DIV001"
assert r(N) == 1

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/rt015/inputs/panel.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') analytical
    assert "`e(panel_mode)'" == "panel"
    rt015_assert_public_inference, aggtype(dynamic)

    import delimited using "`root'/tests/fixtures/parity/rt015/inputs/panel.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') cluster(cluster) analytical
    assert "`e(clustervar)'" == "cluster"
    assert e(N_clusters) > 0
    rt015_assert_public_inference, aggtype(group)

    import delimited using "`root'/tests/fixtures/parity/rt015/inputs/repeated-cross-section.csv", clear asdouble
    quietly csdid y x, time(period) gvar(g) method(`method') analytical
    assert "`e(panel_mode)'" == "repeated-cross-section"
    rt015_assert_public_inference, aggtype(calendar)

    import delimited using "`root'/tests/fixtures/parity/rt015/inputs/repeated-cross-section.csv", clear asdouble
    quietly csdid y x, time(period) gvar(g) method(`method') cluster(cluster) analytical
    assert "`e(clustervar)'" == "cluster"
    assert e(N_clusters) > 0
    rt015_assert_public_inference, aggtype(dynamic)
}

* ---------------------------------------------------------------------------
* RT015 R-oracle comparison (added 2026-07-27)
*
* Everything above runs csdid across panel/repeated-cross-section, the three
* methods, and clustered/unclustered analytical inference, but never compared a
* standard error against R. The block below pins all eighteen combinations --
* panel, repeated cross-section and unbalanced panel x three methods x
* clustered/unclustered, 162 cells, half of them clustered -- against R's own
* ATT and SE.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/rt015/expected/r/attgt.csv"

tempfile rt015_actual
quietly {
    clear
    set obs 0
    gen str32 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`rt015_actual'", replace emptyok
}

capture program drop rt015_grab
program define rt015_grab
    args tag store
    tempname A
    matrix `A' = e(attgt)
    local nr = rowsof(`A')
    preserve
    quietly {
        clear
        set obs `nr'
        gen str32 scenario = "`tag'"
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

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/rt015/inputs/panel.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') analytical
    rt015_grab "panel_`method'" "`rt015_actual'"

    import delimited using "`root'/tests/fixtures/parity/rt015/inputs/panel.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') cluster(cluster) analytical
    rt015_grab "panel_cluster_`method'" "`rt015_actual'"

    import delimited using "`root'/tests/fixtures/parity/rt015/inputs/repeated-cross-section.csv", clear asdouble
    quietly csdid y x, time(period) gvar(g) method(`method') analytical
    rt015_grab "rcs_`method'" "`rt015_actual'"

    import delimited using "`root'/tests/fixtures/parity/rt015/inputs/repeated-cross-section.csv", clear asdouble
    quietly csdid y x, time(period) gvar(g) method(`method') cluster(cluster) analytical
    rt015_grab "rcs_cluster_`method'" "`rt015_actual'"

    * Unbalanced panel, with and without clustering. Upstream's two unbalanced
    * inference tests assert agreement with a historical did 2.1.2 install,
    * which is out of scope for this package -- it tracks the current did only.
    * Pinning these scenarios against the current package is stronger: it fixes
    * the numbers instead of checking that two versions agree with each other.
    import delimited using "`root'/tests/fixtures/parity/rt015/inputs/unbalanced.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') analytical
    assert "`e(panel_mode)'" == "allow_unbalanced"
    rt015_grab "unbal_`method'" "`rt015_actual'"

    import delimited using "`root'/tests/fixtures/parity/rt015/inputs/unbalanced.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') cluster(cluster) analytical
    assert "`e(panel_mode)'" == "allow_unbalanced"
    rt015_grab "unbal_cluster_`method'" "`rt015_actual'"
}

import delimited using "`root'/tests/fixtures/parity/rt015/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`rt015_actual'", assert(match) nogen
quietly count
assert r(N) == 162
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9

display "RT015 OK: 162 cells across 18 inference scenarios (81 clustered) match R to <1e-9"
