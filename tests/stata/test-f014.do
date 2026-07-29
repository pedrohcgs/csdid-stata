version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f014_assert_log_contains
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

confirm file "`root'/tests/fixtures/parity/f014/inputs/input.csv"
confirm file "`root'/tests/fixtures/parity/f014/expected/r/bootstrap-attgt.csv"
confirm file "`root'/tests/fixtures/parity/f014/expected/r/bootstrap-cluster-attgt.csv"
confirm file "`root'/tests/fixtures/parity/f014/expected/r/events.csv"
confirm file "`root'/tests/fixtures/parity/f014/expected/r/events.json"
confirm file "`root'/tests/fixtures/parity/f014/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/f014/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) nevertreated base_period(varying) bal(none)
matrix A0 = e(attgt)

import delimited using "`root'/tests/fixtures/parity/f014/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(399) rseed(20250622)) nevertreated base_period(varying) bal(none)
assert e(bstrap) == 1
assert e(biters) == 399
assert e(cband) == 1
assert e(crit_val) >= e(point_crit_val)
assert e(crit_val) < 5
assert "`e(boot_dist)'" == "rademacher"
assert "`e(boot_seed)'" == "20250622"
matrix A = e(attgt)
matrix B = e(boot_attgt)
assert rowsof(B) == rowsof(A)
assert colsof(B) == 12
forvalues i = 1/`=rowsof(A)' {
    assert abs(A[`i', 4] - A0[`i', 4]) < 1e-14
}

tempfile actual tidy evlog
preserve
clear
svmat double B, names(col)
rename (att se_boot se_analytic crit_val ci_low ci_high point_crit_val point_ci_low point_ci_high) ///
       (att_stata se_boot_stata se_analytic_stata crit_val_stata ci_low_stata ci_high_stata point_crit_val_stata point_ci_low_stata point_ci_high_stata)
save "`actual'", replace
restore

import delimited using "`root'/tests/fixtures/parity/f014/expected/r/bootstrap-attgt.csv", clear asdouble
merge 1:1 group time using "`actual'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert abs(se_analytic - se_analytic_stata) < 1e-8
assert se_boot_stata > 0
assert abs(se_boot_stata - se_boot_r) / se_boot_r < .20
assert crit_val_stata >= point_crit_val_stata
assert abs(ci_low_stata - (att_stata - crit_val_stata * se_boot_stata)) < 1e-10
assert abs(ci_high_stata - (att_stata + crit_val_stata * se_boot_stata)) < 1e-10
assert abs(point_ci_low_stata - (att_stata - point_crit_val_stata * se_boot_stata)) < 1e-10
assert abs(point_ci_high_stata - (att_stata + point_crit_val_stata * se_boot_stata)) < 1e-10

csdid_estat tidy, saving("`tidy'") replace
use "`tidy'", clear
assert _N == 6
assert conf_low[1] != point_conf_low[1]
assert conf_high[1] != point_conf_high[1]

import delimited using "`root'/tests/fixtures/parity/f014/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(199) rseed(20250622)) pointwise nevertreated base_period(varying) bal(none)
assert e(bstrap) == 1
assert e(cband) == 0
assert abs(e(crit_val) - e(point_crit_val)) < 1e-12

capture log close f014event
log using "`evlog'", text replace name(f014event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(0)) nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f014event
assert `actual_rc' == 198
f014_assert_log_contains using "`evlog'", message("wboot() reps() must be a positive integer")

import delimited using "`root'/tests/fixtures/parity/f014/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) nevertreated base_period(varying) bal(none)
matrix C0 = e(attgt)

import delimited using "`root'/tests/fixtures/parity/f014/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) wboot(reps(199) rseed(20250623)) nevertreated base_period(varying) bal(none)
assert e(bstrap) == 1
assert e(biters) == 199
assert e(N_clusters) == 4
assert "`e(clustervar)'" == "cl"
assert e(cband) == 1
matrix C = e(attgt)
matrix CB = e(boot_attgt)
assert rowsof(CB) == rowsof(C)
assert colsof(CB) == 12
forvalues i = 1/`=rowsof(C)' {
    assert abs(C[`i', 4] - C0[`i', 4]) < 1e-14
}

preserve
clear
svmat double CB, names(col)
rename (att se_boot se_analytic crit_val) (att_stata se_boot_stata se_analytic_stata crit_val_stata)
save "`actual'", replace
restore

import delimited using "`root'/tests/fixtures/parity/f014/expected/r/bootstrap-cluster-attgt.csv", clear asdouble
merge 1:1 group time using "`actual'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert abs(se_analytic - se_analytic_stata) < 1e-8
assert se_boot_stata > 0
assert abs(se_boot_stata - se_boot_r) / se_boot_r < .35
assert crit_val_stata >= 0
