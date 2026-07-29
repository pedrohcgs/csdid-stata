version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f035_assert_log_contains
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

program define f035_assert_boot_equal
    version 15
    args left right

    assert rowsof(`left') == rowsof(`right')
    assert colsof(`left') == colsof(`right')
    forvalues i = 1/`=rowsof(`left')' {
        forvalues j = 1/`=colsof(`left')' {
            assert missing(`left'[`i', `j']) == missing(`right'[`i', `j']) if missing(`left'[`i', `j']) | missing(`right'[`i', `j'])
            assert abs(`left'[`i', `j'] - `right'[`i', `j']) < 1e-12 if !missing(`left'[`i', `j']) & !missing(`right'[`i', `j'])
        }
    }
end

confirm file "`root'/tests/fixtures/parity/f035/inputs/input.csv"
confirm file "`root'/tests/fixtures/parity/f035/expected/new-stata/bootstrap-options.json"
confirm file "`root'/tests/fixtures/parity/f035/expected/new-stata/events.csv"
confirm file "`root'/tests/fixtures/parity/f035/expected/new-stata/events.json"
confirm file "`root'/tests/fixtures/parity/f035/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/f035/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/f035/metadata/manifest.json"

quietly do "`root'/src/mata/csdid.mata"
mata:
    st = csdid__bmisc_rng_init(20240924)
    got = J(12, 1, .)
    expected = (.2 \ .2 \ -.4 \ .2 \ -.2 \ 0 \ -.2 \ .2 \ -.2 \ -.6 \ -.6 \ .4)
    for (i = 1; i <= 12; i++) got[i] = mean(csdid__bmisc_bootstrap_draw(10, st))
    st_numscalar("f035_bmisc_delta", max(abs(got :- expected)))
end
assert scalar(f035_bmisc_delta) <= 1e-12

mata:
    oldstate = rngstate()
    x = sin((1::37) * (1..4) :* .017)
    uniformseed(20260709)
    reference = J(53, cols(x), .)
    for (b = 1; b <= 53; b++) {
        draw = 2 :* (runiform(rows(x), 1) :>= .5) :- 1
        reference[b, .] = draw' * x
    }
    reference_state = rngstate()
    uniformseed(20260709)
    optimized = csdid__native_rboot_rows(x, 53)
    optimized_state = rngstate()
    rngstate(oldstate)
    st_numscalar("f035_native_dense_delta", max(abs(reference :- optimized)))
    st_numscalar("f035_native_state_equal", reference_state == optimized_state)
end
assert scalar(f035_native_dense_delta) <= 1e-12
assert scalar(f035_native_state_equal) == 1

mata:
    oldstate = rngstate()
    x = cos((1::23) * (1..5) :* .021)
    uniformseed(20260710)
    reference = J(41, cols(x), .)
    for (j = 1; j <= cols(x); j++) {
        reference[., j] = csdid__native_rboot(x[., j], 41, 0)
    }
    reference_state = rngstate()
    uniformseed(20260710)
    optimized = csdid__native_rboot_indep(x, 41)
    optimized_state = rngstate()
    rngstate(oldstate)
    st_numscalar("f035_native_indep_delta", max(abs(reference :- optimized)))
    st_numscalar("f035_native_indep_state_equal", reference_state == optimized_state)
end
assert scalar(f035_native_indep_delta) <= 1e-12
assert scalar(f035_native_indep_state_equal) == 1

import delimited using "`root'/tests/fixtures/parity/f035/expected/contract/approved-divergence.csv", clear varnames(1) stringcols(_all)
assert _N == 2
quietly count if divergence_id == "F035-DIV001"
assert r(N) == 1
quietly count if divergence_id == "F035-DIV002"
assert r(N) == 1

tempfile evlog

import delimited using "`root'/tests/fixtures/parity/f035/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(31) rseed(12345)) nevertreated base_period(varying) bal(none)
assert e(bstrap) == 1
assert e(biters) == 31
assert e(cband) == 1
assert "`e(boot_seed)'" == "12345"
assert "`e(boot_dist)'" == "rademacher"
assert "`e(boot_dist_requested)'" == "rademacher"
matrix B0 = e(boot_attgt)

import delimited using "`root'/tests/fixtures/parity/f035/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(biters(31) rseed(12345) wtype(rademacher)) nevertreated base_period(varying) bal(none)
assert e(bstrap) == 1
assert e(biters) == 31
assert "`e(boot_seed)'" == "12345"
assert "`e(boot_dist)'" == "rademacher"
assert "`e(boot_dist_requested)'" == "rademacher"
matrix B1 = e(boot_attgt)
f035_assert_boot_equal B0 B1

import delimited using "`root'/tests/fixtures/parity/f035/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) wboot reps(31) rseed(12345) nevertreated base_period(varying) bal(none)
assert e(bstrap) == 1
assert e(biters) == 31
assert "`e(boot_seed)'" == "12345"
assert "`e(boot_dist)'" == "rademacher"
assert "`e(boot_dist_requested)'" == "rademacher"
matrix BSH1 = e(boot_attgt)
f035_assert_boot_equal B0 BSH1

import delimited using "`root'/tests/fixtures/parity/f035/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) wboot reps(31) seed(12345) nevertreated base_period(varying) bal(none)
assert e(bstrap) == 1
assert e(biters) == 31
assert "`e(boot_seed)'" == "12345"
assert "`e(boot_dist)'" == "rademacher"
assert "`e(boot_dist_requested)'" == "rademacher"
matrix BSH2 = e(boot_attgt)
f035_assert_boot_equal B0 BSH2

foreach badtype in "wbtype(mammen)" "wbtype(gaussian)" "wtype(normal)" {
    capture log close f035event
    log using "`evlog'", text replace name(f035event)
    import delimited using "`root'/tests/fixtures/parity/f035/inputs/input.csv", clear asdouble
    capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(31) seed(1357) `badtype') pointwise nevertreated base_period(varying) bal(none)
    local actual_rc = _rc
    log close f035event
    assert `actual_rc' == 498
    f035_assert_log_contains using "`evlog'", message("wboot() currently supports only R-compatible rademacher multipliers")
}

capture log close f035event
log using "`evlog'", text replace name(f035event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) analytical rseed(123) nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f035event
assert `actual_rc' == 198
f035_assert_log_contains using "`evlog'", message("reps(), biters(), seed(), and rseed() require bootstrap inference; omit vce(analytical)")

foreach bad in "reps(-2)" "reps(1.5)" {
    capture log close f035event
    log using "`evlog'", text replace name(f035event)
    capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(`bad') nevertreated base_period(varying) bal(none)
    local actual_rc = _rc
    log close f035event
    assert `actual_rc' == 198
    f035_assert_log_contains using "`evlog'", message("wboot() reps() must be a positive integer")
}

capture log close f035event
log using "`evlog'", text replace name(f035event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(31) rseed(0)) nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f035event
assert `actual_rc' == 198
f035_assert_log_contains using "`evlog'", message("wboot() rseed() must be a positive integer")

capture log close f035event
log using "`evlog'", text replace name(f035event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(31) wtype(foo)) nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f035event
assert `actual_rc' == 498
f035_assert_log_contains using "`evlog'", message("wboot() currently supports only R-compatible rademacher multipliers")

capture log close f035event
log using "`evlog'", text replace name(f035event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) wboot(reps(31) cluster(cl2)) nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f035event
assert `actual_rc' == 198
f035_assert_log_contains using "`evlog'", message("wboot(cluster()) must match cluster() when both are supplied")

capture log close f035event
log using "`evlog'", text replace name(f035event)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(31) cluster(cl cl2)) nevertreated base_period(varying) bal(none)
local actual_rc = _rc
log close f035event
assert `actual_rc' == 198
f035_assert_log_contains using "`evlog'", message("wboot(cluster()) accepts one numeric cluster variable")

import delimited using "`root'/tests/fixtures/parity/f035/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(31) cluster(cl) rseed(97531)) nevertreated base_period(varying) bal(none)
assert e(bstrap) == 1
assert e(biters) == 31
assert e(N_clusters) == 5
assert "`e(clustervar)'" == "cl"
matrix BC = e(boot_attgt)
assert rowsof(BC) == e(N_attgt)
preserve
clear
svmat double BC, names(col)
quietly count if !missing(se_boot) & se_boot > 0
assert r(N) > 0
restore

* ---------------------------------------------------------------------------
* F035 R-oracle comparison (added 2026-07-27)
* The assertions above prove the four wboot option spellings agree with each other.
* This pins the resulting seeded bootstrap value against R.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/f035/expected/r/attgt.csv"
tempfile f035_actual
quietly {
    clear
    set obs 0
    gen str60 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`f035_actual'", replace emptyok
}
capture program drop f035_grab
program define f035_grab
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

import delimited using "`root'/tests/fixtures/parity/f035/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) wboot(reps(31) rseed(12345)) nevertreated base_period(varying) bal(none)
f035_grab "wboot31_seed12345" "`f035_actual'"

import delimited using "`root'/tests/fixtures/parity/f035/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`f035_actual'", assert(match) nogen
quietly count
assert r(N) == 6
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "F035 OK: 6 cells (seeded wild bootstrap) match R to <1e-9"
