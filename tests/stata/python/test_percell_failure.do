version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define py018_assert_log_contains
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

program define py018_count_log_contains, rclass
    version 15
    syntax using/, MESSAGE(string)

    tempname fh
    local body ""
    local count 0
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
    local pos = strpos(`"`compact_body'"', `"`compact_message'"')
    while `pos' > 0 {
        local ++count
        local compact_body = substr(`"`compact_body'"', `pos' + strlen(`"`compact_message'"'), .)
        local pos = strpos(`"`compact_body'"', `"`compact_message'"')
    }
    return scalar count = `count'
end

confirm file "`root'/tests/fixtures/parity/py018/inputs/zero-weight-failure.csv"
confirm file "`root'/tests/fixtures/parity/py018/inputs/normal.csv"
confirm file "`root'/tests/fixtures/parity/py018/inputs/tiny-group.csv"
confirm file "`root'/tests/fixtures/parity/py018/inputs/collinear-covariates.csv"
confirm file "`root'/tests/fixtures/parity/py018/inputs/overlap-failure.csv"
confirm file "`root'/tests/fixtures/parity/py018/inputs/singular-control.csv"
confirm file "`root'/tests/fixtures/parity/py018/inputs/small-comparison-upstream.csv"
confirm file "`root'/tests/fixtures/parity/py018/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py018/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py018/expected/r/failure-pattern.csv"
confirm file "`root'/tests/fixtures/parity/py018/expected/r/events.csv"
confirm file "`root'/tests/fixtures/parity/py018/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py018/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 4
foreach source_test in test_collinear_covariates_no_crash ///
    test_tiny_group_warns_not_crashes test_failed_cells_are_nan ///
    test_normal_data_unaffected {
    quietly count if source_test == "`source_test'" & coverage_status == "mapped"
    assert r(N) == 1
}
quietly count if source_test == "test_collinear_covariates_no_crash" & mapped_scenario == "collinear_covariates_no_crash"
assert r(N) == 1
quietly count if source_test == "test_normal_data_unaffected" & mapped_scenario == "normal_data_unaffected"
assert r(N) == 1
assert source_file == "csdid/test_csdid/test_percell_failure.py"
assert source_sha256 == "e15c0c8cde82b8d035fa285f344be7735b775e15d5b0b9fc4dd2159c5f05fe8e"

tempfile actual
tempfile tinylog
tempfile collinearlog
tempfile overlaplog
tempfile singularlog
tempfile smallcomparisonlog
local first 1

import delimited using "`root'/tests/fixtures/parity/py018/inputs/zero-weight-failure.csv", clear asdouble
quietly csdid y x [iw=w], ivar(id) time(period) gvar(g) method(dr) analytical
assert e(N) == 360
assert e(N_units) == 90
matrix A = e(attgt)
preserve
clear
quietly svmat double A, names(col)
generate str40 scenario = "zero_weight_group_failure"
generate byte att_missing_stata = missing(att)
generate byte se_missing_stata = missing(se)
rename (event_time att se) (event_time_stata att_stata se_stata)
keep scenario group time event_time_stata att_stata se_stata att_missing_stata se_missing_stata
save "`actual'", replace
restore

matrix A = e(attgt)
forvalues i = 1/`=rowsof(A)' {
    if A[`i', 1] == 2 {
        assert !missing(A[`i', 4])
        assert !missing(A[`i', 5])
    }
    if A[`i', 1] == 3 {
        assert missing(A[`i', 4])
        assert missing(A[`i', 5])
    }
}

import delimited using "`root'/tests/fixtures/parity/py018/inputs/normal.csv", clear asdouble
quietly csdid y, ivar(id) time(year) gvar(group) method(dr) analytical
matrix A = e(attgt)
preserve
clear
quietly svmat double A, names(col)
generate str40 scenario = "normal_data_unaffected"
generate byte att_missing_stata = missing(att)
generate byte se_missing_stata = missing(se)
rename (event_time att se) (event_time_stata att_stata se_stata)
keep scenario group time event_time_stata att_stata se_stata att_missing_stata se_missing_stata
append using "`actual'"
save "`actual'", replace
restore

matrix A = e(attgt)
forvalues i = 1/`=rowsof(A)' {
    assert !missing(A[`i', 4])
}

import delimited using "`root'/tests/fixtures/parity/py018/inputs/tiny-group.csv", clear asdouble
capture log close py018warning
log using "`tinylog'", text replace name(py018warning)
capture noisily csdid y, ivar(id) time(year) gvar(group) method(dr) analytical
local actual_rc = _rc
log close py018warning
assert `actual_rc' == 0
py018_assert_log_contains using "`tinylog'", message("very few observations")
matrix A = e(attgt)
preserve
clear
quietly svmat double A, names(col)
generate str40 scenario = "tiny_group_no_crash"
generate byte att_missing_stata = missing(att)
generate byte se_missing_stata = missing(se)
rename (event_time att se) (event_time_stata att_stata se_stata)
keep scenario group time event_time_stata att_stata se_stata att_missing_stata se_missing_stata
append using "`actual'"
save "`actual'", replace
restore

matrix A = e(attgt)
local saw2006 0
forvalues i = 1/`=rowsof(A)' {
    if A[`i', 1] == 2006 {
        local saw2006 1
        assert !missing(A[`i', 4])
        assert !missing(A[`i', 5])
    }
}
assert `saw2006' == 1

import delimited using "`root'/tests/fixtures/parity/py018/inputs/collinear-covariates.csv", clear asdouble
capture log close py018collinear
log using "`collinearlog'", text replace name(py018collinear)
capture noisily csdid y x1 x2, ivar(id) time(year) gvar(group) method(dr) analytical
local actual_rc = _rc
log close py018collinear
assert `actual_rc' == 0
py018_count_log_contains using "`collinearlog'", message("singular or numerically ill-conditioned")
assert r(count) == 0
py018_count_log_contains using "`collinearlog'", message("overlap condition violated for group")
assert r(count) == 0
matrix A = e(attgt)
preserve
clear
quietly svmat double A, names(col)
generate str40 scenario = "collinear_covariates_no_crash"
generate byte att_missing_stata = missing(att)
generate byte se_missing_stata = missing(se)
rename (event_time att se) (event_time_stata att_stata se_stata)
keep scenario group time event_time_stata att_stata se_stata att_missing_stata se_missing_stata
append using "`actual'"
save "`actual'", replace
restore

matrix A = e(attgt)
forvalues i = 1/`=rowsof(A)' {
    assert !missing(A[`i', 4])
    assert !missing(A[`i', 5])
}

import delimited using "`root'/tests/fixtures/parity/py018/expected/r/events.csv", clear varnames(1)
keep if scenario == "collinear_covariates_no_crash" & event_key == "any_warning"
assert _N == 1
summarize expected_count, meanonly
assert r(mean) == 0

import delimited using "`root'/tests/fixtures/parity/py018/inputs/overlap-failure.csv", clear asdouble
capture log close py018overlap
log using "`overlaplog'", text replace name(py018overlap)
capture noisily csdid y xsep, ivar(id) time(period) gvar(g) method(dr) analytical
local actual_rc = _rc
log close py018overlap
assert `actual_rc' == 0
py018_count_log_contains using "`overlaplog'", message("overlap condition violated for group")
local overlap_count = r(count)
py018_count_log_contains using "`overlaplog'", message("missing or zero variance")
local wald_count = r(count)
py018_count_log_contains using "`overlaplog'", message("treated early in the panel")
assert r(count) == 0
py018_count_log_contains using "`overlaplog'", message("Error computing internal 2x2 DiD")
assert r(count) == 0
matrix A = e(attgt)
preserve
clear
quietly svmat double A, names(col)
generate str40 scenario = "overlap_failure"
generate byte att_missing_stata = missing(att)
generate byte se_missing_stata = missing(se)
rename (event_time att se) (event_time_stata att_stata se_stata)
keep scenario group time event_time_stata att_stata se_stata att_missing_stata se_missing_stata
append using "`actual'"
save "`actual'", replace
restore

matrix A = e(attgt)
forvalues i = 1/`=rowsof(A)' {
    assert missing(A[`i', 4])
    assert missing(A[`i', 5])
}

import delimited using "`root'/tests/fixtures/parity/py018/expected/r/events.csv", clear varnames(1)
keep if scenario == "overlap_failure" & event_key == "overlap_condition_violated"
assert _N == 1
summarize expected_count, meanonly
assert `overlap_count' == r(mean)
import delimited using "`root'/tests/fixtures/parity/py018/expected/r/events.csv", clear varnames(1)
keep if scenario == "overlap_failure" & event_key == "wald_missing_zero_variance"
assert _N == 1
summarize expected_count, meanonly
assert `wald_count' == r(mean)

foreach method in reg dr {
    import delimited using "`root'/tests/fixtures/parity/py018/inputs/singular-control.csv", clear asdouble
    capture log close py018singular
    log using "`singularlog'", text replace name(py018singular)
    capture noisily csdid y x, ivar(id) time(period) gvar(g) method(`method') notyet analytical
    local actual_rc = _rc
    log close py018singular
    assert `actual_rc' == 0
    py018_count_log_contains using "`singularlog'", message("singular or numerically ill-conditioned")
    local singular_count = r(count)
    py018_count_log_contains using "`singularlog'", message("Error computing internal 2x2 DiD")
    assert r(count) == 0

    matrix A = e(attgt)
    preserve
    clear
    quietly svmat double A, names(col)
    generate str40 scenario = "singular_notyet_`method'"
    generate byte att_missing_stata = missing(att)
    generate byte se_missing_stata = missing(se)
    rename (event_time att se) (event_time_stata att_stata se_stata)
    keep scenario group time event_time_stata att_stata se_stata att_missing_stata se_missing_stata
    append using "`actual'"
    save "`actual'", replace
    restore

    import delimited using "`root'/tests/fixtures/parity/py018/expected/r/events.csv", clear varnames(1)
    keep if scenario == "singular_notyet_`method'" & event_key == "singular_control_matrix"
    assert _N == 1
    summarize expected_count, meanonly
    assert `singular_count' == r(mean)
}

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/py018/inputs/small-comparison-upstream.csv", clear asdouble
    capture log close py018smallcomparison
    log using "`smallcomparisonlog'", text replace name(py018smallcomparison)
    capture noisily csdid y x, ivar(id) time(period) gvar(g) method(`method') notyet analytical
    local actual_rc = _rc
    log close py018smallcomparison
    assert `actual_rc' == 0

    py018_count_log_contains using "`smallcomparisonlog'", message("very few observations")
    local small_group_count = r(count)
    py018_count_log_contains using "`smallcomparisonlog'", message("overlap condition violated for group")
    local overlap_count = r(count)
    py018_count_log_contains using "`smallcomparisonlog'", message("singular or numerically ill-conditioned")
    local singular_count = r(count)
    py018_count_log_contains using "`smallcomparisonlog'", message("Error computing internal 2x2 DiD")
    assert r(count) == 0

    matrix A = e(attgt)
    preserve
    clear
    quietly svmat double A, names(col)
    generate str40 scenario = "small_comparison_notyet_`method'"
    generate byte att_missing_stata = missing(att)
    generate byte se_missing_stata = missing(se)
    rename (event_time att se) (event_time_stata att_stata se_stata)
    keep scenario group time event_time_stata att_stata se_stata att_missing_stata se_missing_stata
    append using "`actual'"
    save "`actual'", replace
    restore

    import delimited using "`root'/tests/fixtures/parity/py018/expected/r/events.csv", clear varnames(1)
    keep if scenario == "small_comparison_notyet_`method'" & event_key == "small_group_warning"
    assert _N == 1
    summarize expected_count, meanonly
    assert `small_group_count' == r(mean)

    if inlist("`method'", "dr", "ipw") {
        import delimited using "`root'/tests/fixtures/parity/py018/expected/r/events.csv", clear varnames(1)
        keep if scenario == "small_comparison_notyet_`method'" & event_key == "overlap_condition_violated"
        assert _N == 1
        summarize expected_count, meanonly
        assert `overlap_count' == r(mean)
        assert `singular_count' == 0
    }
    else {
        import delimited using "`root'/tests/fixtures/parity/py018/expected/r/events.csv", clear varnames(1)
        keep if scenario == "small_comparison_notyet_`method'" & event_key == "singular_control_matrix"
        assert _N == 1
        summarize expected_count, meanonly
        assert `singular_count' == r(mean)
        assert `overlap_count' == 0
    }
}

import delimited using "`root'/tests/fixtures/parity/py018/expected/r/failure-pattern.csv", clear asdouble
merge 1:1 scenario group time using "`actual'", nogen assert(match)
assert event_time == event_time_stata
assert att_missing == att_missing_stata
assert se_missing == se_missing_stata
assert missing(att) == missing(att_stata)
assert missing(se) == missing(se_stata)
assert missing(att) | abs(att - att_stata) < 1e-8
assert missing(se) | abs(se - se_stata) < 1e-8
