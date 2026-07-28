version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py015_assert_log_contains
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

program define py015_assert_clustered_mboot
    version 15
    syntax, INPUT(string) BITERS(integer) SEED(integer) NCLUSTERS(integer)

    import delimited using "`input'", clear asdouble
    csdid y, ivar(id) time(t) gvar(g) method(reg) wboot(reps(`biters') cluster(cl) rseed(`seed'))
    assert e(bstrap) == 1
    assert e(biters) == `biters'
    assert e(N_clusters) == `nclusters'
    assert "`e(clustervar)'" == "cl"
    assert "`e(boot_dist)'" == "rademacher"
    assert "`e(boot_seed)'" == "`seed'"
    matrix ATT = e(attgt)
    matrix BOOT = e(boot_attgt)
    assert rowsof(ATT) > 0
    assert rowsof(BOOT) == rowsof(ATT)
    assert colsof(BOOT) == 12

    preserve
    clear
    svmat double ATT, names(col)
    quietly count if !missing(se) & se > 0
    assert r(N) > 0
    restore

    preserve
    clear
    svmat double BOOT, names(col)
    quietly count if !missing(se_boot) & se_boot > 0
    assert r(N) > 0
    restore
end

confirm file "`root'/tests/fixtures/parity/py015/inputs/clustered-unbalanced.csv"
confirm file "`root'/tests/fixtures/parity/py015/inputs/clustered-balanced.csv"
confirm file "`root'/tests/fixtures/parity/py015/inputs/clustered-invalid.csv"
confirm file "`root'/tests/fixtures/parity/py015/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py015/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py015/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py015/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py015/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 3
quietly count if coverage_status == "mapped"
assert r(N) == 3
quietly count if source_test == "test_clustered_mboot_unbalanced_runs"
assert r(N) == 1
quietly count if source_test == "test_clustered_mboot_balanced_runs"
assert r(N) == 1
quietly count if source_test == "test_clustering_validation_rejects_multiple_clustervars"
assert r(N) == 1

py015_assert_clustered_mboot, ///
    input("`root'/tests/fixtures/parity/py015/inputs/clustered-unbalanced.csv") ///
    biters(399) seed(20251501) nclusters(40)

py015_assert_clustered_mboot, ///
    input("`root'/tests/fixtures/parity/py015/inputs/clustered-balanced.csv") ///
    biters(399) seed(20251502) nclusters(40)

import delimited using "`root'/tests/fixtures/parity/py015/inputs/clustered-invalid.csv", clear asdouble
tempfile evlog
capture log close py015event
log using "`evlog'", text replace name(py015event)
capture noisily csdid y, ivar(id) time(t) gvar(g) method(reg) wboot(reps(31) cluster(cl cl2) rseed(20251503))
local rc = _rc
log close py015event
assert `rc' == 198
py015_assert_log_contains using "`evlog'", message("wboot(cluster()) accepts one numeric cluster variable")

* ---------------------------------------------------------------------------
* PY015 R-oracle comparison (added 2026-07-27)
* The assertions above check bootstrap metadata - iteration count, cluster count,
* multiplier distribution, seed - but never compared a bootstrap standard error
* against R. That comparison is only meaningful because csdid reproduces R's
* random-number stream draw for draw, verified at max |dSE| 5.8e-16 before this
* oracle was written. Seeds and iteration counts must match the calls above.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py015/expected/r/attgt.csv"
tempfile py015_actual
quietly {
    clear
    set obs 0
    gen str32 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`py015_actual'", replace emptyok
}
capture program drop py015_grab
program define py015_grab
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

import delimited using "`root'/tests/fixtures/parity/py015/inputs/clustered-unbalanced.csv", clear asdouble
quietly csdid y, ivar(id) time(t) gvar(g) method(reg) wboot(reps(399) cluster(cl) rseed(20251501))
py015_grab "unbalanced_399" "`py015_actual'"
import delimited using "`root'/tests/fixtures/parity/py015/inputs/clustered-balanced.csv", clear asdouble
quietly csdid y, ivar(id) time(t) gvar(g) method(reg) wboot(reps(399) cluster(cl) rseed(20251502))
py015_grab "balanced_399" "`py015_actual'"

import delimited using "`root'/tests/fixtures/parity/py015/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`py015_actual'", assert(match) nogen
quietly count
assert r(N) == 4
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "PY015 OK: 4 cells (clustered multiplier bootstrap, seeded) match R to <1e-9"
