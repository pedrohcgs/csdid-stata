version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

confirm file "`root'/tests/fixtures/parity/py002/inputs/clustered-data.csv"
confirm file "`root'/tests/fixtures/parity/py002/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py002/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py002/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py002/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py002/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 3
quietly count if coverage_status == "mapped"
assert r(N) == 3
quietly count if source_test == "test_analytical_clustered_se_runs"
assert r(N) == 1
quietly count if source_test == "test_analytical_clustered_se_matches_bootstrap"
assert r(N) == 1
quietly count if source_test == "test_aggte_with_analytical_clustered_se"
assert r(N) == 1

import delimited using "`root'/tests/fixtures/parity/py002/expected/contract/scenarios.csv", clear varnames(1) stringcols(_all)
assert _N == 1
local biters = real(bootstrap_biters[1])
local seed = real(bootstrap_seed[1])
local rtol = real(bootstrap_rtol[1])
local nclusters = real(n_clusters[1])

import delimited using "`root'/tests/fixtures/parity/py002/inputs/clustered-data.csv", clear asdouble
csdid y, ivar(id) time(year) gvar(group) method(dr) cluster(cluster) analytical nevertreated base_period(varying) bal(none)
assert e(N_clusters) == `nclusters'
assert "`e(clustervar)'" == "cluster"
matrix AN = e(attgt)
preserve
clear
svmat double AN, names(col)
quietly count if !missing(se) & se > 0
assert r(N) == _N
restore

csdid_stats, type(simple)
matrix AG = e(aggte)
assert rowsof(AG) > 0
assert !missing(AG[1,5])
assert AG[1,5] > 0

import delimited using "`root'/tests/fixtures/parity/py002/inputs/clustered-data.csv", clear asdouble
csdid y, ivar(id) time(year) gvar(group) method(dr) cluster(cluster) wboot(reps(`biters') rseed(`seed')) nevertreated base_period(varying) bal(none)
assert e(bstrap) == 1
assert e(biters) == `biters'
assert e(N_clusters) == `nclusters'
assert "`e(clustervar)'" == "cluster"
matrix BOOT = e(boot_attgt)
preserve
clear
svmat double BOOT, names(col)
quietly count if !missing(se_boot) & se_boot > 0
assert r(N) == _N
quietly count if !missing(se_analytic) & se_analytic > 0
assert r(N) == _N
generate double rel = abs(se_analytic - se_boot) / se_boot
quietly summarize rel, meanonly
assert r(max) < `rtol'
restore

* ---------------------------------------------------------------------------
* PY002 R-oracle comparison (added 2026-07-27)
* The assertions above check that clustered standard errors are positive and
* differ from the iid ones; they never compared a value against R. This pins
* every cell of the analytical scenarios.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py002/expected/r/attgt.csv"
tempfile py002_actual
quietly {
    clear
    set obs 0
    gen str24 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`py002_actual'", replace emptyok
}
capture program drop py002_grab
program define py002_grab
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

import delimited using "`root'/tests/fixtures/parity/py002/inputs/clustered-data.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(dr) analytical nevertreated base_period(varying) bal(none)
py002_grab "iid_dr" "`py002_actual'"
import delimited using "`root'/tests/fixtures/parity/py002/inputs/clustered-data.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(dr) cluster(cluster) analytical nevertreated base_period(varying) bal(none)
py002_grab "cluster_dr" "`py002_actual'"

import delimited using "`root'/tests/fixtures/parity/py002/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`py002_actual'", assert(match) nogen
quietly count
assert r(N) == 12
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "PY002 OK: 12 cells (iid and clustered analytical) match R to <1e-9"
