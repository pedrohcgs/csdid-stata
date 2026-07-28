version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py005_assert_log_contains
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

program define py005_save_boot_se
    version 15
    syntax, OUTFILE(string)

    matrix BOOT = e(boot_attgt)
    preserve
    clear
    svmat double BOOT, names(col)
    keep group time se_boot
    save "`outfile'", replace
    restore
end

confirm file "`root'/tests/fixtures/parity/py005/inputs/clustered-data.csv"
confirm file "`root'/tests/fixtures/parity/py005/inputs/time-varying-cluster.csv"
confirm file "`root'/tests/fixtures/parity/py005/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py005/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py005/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py005/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py005/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 5
quietly count if coverage_status == "mapped"
assert r(N) == 5

import delimited using "`root'/tests/fixtures/parity/py005/inputs/clustered-data.csv", clear asdouble
csdid y, ivar(id) time(year) gvar(group) method(dr) wboot(reps(200) cluster(cluster) rseed(20250501))
assert e(bstrap) == 1
assert e(biters) == 200
assert e(N_clusters) == 10
matrix RUN = e(attgt)
assert rowsof(RUN) > 0
preserve
clear
svmat double RUN, names(col)
quietly count if !missing(se) & se > 0
assert r(N) == _N
restore

tempfile no_cluster clustered unit_cluster
import delimited using "`root'/tests/fixtures/parity/py005/inputs/clustered-data.csv", clear asdouble
csdid y, ivar(id) time(year) gvar(group) method(dr) wboot(reps(500) rseed(20250502))
py005_save_boot_se, outfile("`no_cluster'")

import delimited using "`root'/tests/fixtures/parity/py005/inputs/clustered-data.csv", clear asdouble
csdid y, ivar(id) time(year) gvar(group) method(dr) wboot(reps(500) cluster(cluster) rseed(20250502))
py005_save_boot_se, outfile("`clustered'")

use "`no_cluster'", clear
rename se_boot se_no_cluster
merge 1:1 group time using "`clustered'", nogen assert(match)
rename se_boot se_clustered
quietly count if !missing(se_clustered) & se_clustered > 0
assert r(N) == _N
generate double rel_diff = abs(se_clustered - se_no_cluster) / se_no_cluster
quietly count if rel_diff > 0.10
assert r(N) > 0

import delimited using "`root'/tests/fixtures/parity/py005/inputs/clustered-data.csv", clear asdouble
csdid y, ivar(id) time(year) gvar(group) method(dr) wboot(reps(500) rseed(20250503))
py005_save_boot_se, outfile("`no_cluster'")

import delimited using "`root'/tests/fixtures/parity/py005/inputs/clustered-data.csv", clear asdouble
csdid y, ivar(id) time(year) gvar(group) method(dr) wboot(reps(500) cluster(unit_cluster) rseed(20250503))
py005_save_boot_se, outfile("`unit_cluster'")

use "`no_cluster'", clear
rename se_boot se_no_cluster
merge 1:1 group time using "`unit_cluster'", nogen assert(match)
rename se_boot se_unit_cluster
generate double rel_unit = abs(se_unit_cluster - se_no_cluster) / se_no_cluster
quietly summarize rel_unit, meanonly
assert r(max) < 0.30

import delimited using "`root'/tests/fixtures/parity/py005/inputs/time-varying-cluster.csv", clear asdouble
tempfile evlog
capture log close py005event
log using "`evlog'", text replace name(py005event)
capture noisily csdid y, ivar(id) time(year) gvar(group) method(dr) wboot(reps(50) cluster(tv_cluster) rseed(20250504))
local rc = _rc
log close py005event
assert `rc' == 459
py005_assert_log_contains using "`evlog'", message("cluster() must be time-invariant within ivar()")

* ---------------------------------------------------------------------------
* PY005 R-oracle comparison (added 2026-07-27)
* The assertions above compare clustered against iid bootstrap SEs and check that
* they differ; they never compared either against R. Valid only because csdid
* reproduces R's random-number stream draw for draw, verified at max |dSE| 5.8e-16.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py005/expected/r/attgt.csv"
tempfile py005_actual
quietly {
    clear
    set obs 0
    gen str32 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`py005_actual'", replace emptyok
}
capture program drop py005_grab
program define py005_grab
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

import delimited using "`root'/tests/fixtures/parity/py005/inputs/clustered-data.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(dr) wboot(reps(200) cluster(cluster) rseed(20250501))
py005_grab "boot200_cluster" "`py005_actual'"
import delimited using "`root'/tests/fixtures/parity/py005/inputs/clustered-data.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(dr) wboot(reps(500) rseed(20250502))
py005_grab "boot500_iid" "`py005_actual'"
import delimited using "`root'/tests/fixtures/parity/py005/inputs/clustered-data.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(dr) wboot(reps(500) cluster(cluster) rseed(20250502))
py005_grab "boot500_cluster" "`py005_actual'"
import delimited using "`root'/tests/fixtures/parity/py005/inputs/clustered-data.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(dr) wboot(reps(500) rseed(20250503))
py005_grab "boot500_iid_b" "`py005_actual'"
import delimited using "`root'/tests/fixtures/parity/py005/inputs/clustered-data.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(dr) wboot(reps(500) cluster(unit_cluster) rseed(20250503))
py005_grab "boot500_unitcluster" "`py005_actual'"

import delimited using "`root'/tests/fixtures/parity/py005/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`py005_actual'", assert(match) nogen
quietly count
assert r(N) == 30
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "PY005 OK: 30 cells (five seeded bootstrap scenarios) match R to <1e-9"
