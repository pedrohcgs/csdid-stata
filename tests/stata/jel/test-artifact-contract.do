version 15
clear all
set more off

local root "`c(pwd)'"

confirm file "`root'/tests/fixtures/jel/expected/contract/jel-artifact-rollup.csv"
confirm file "`root'/tests/fixtures/jel/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/jel/expected/contract/jel-artifact-rollup.csv", clear varnames(1) stringcols(_all)
assert _N == 18
assert audit_status == "recorded"
assert parity_verified == "1"
assert evidence_report == "reports/jel-full-reproduction-result.md"
assert stata_test_file == "tests/stata/jel/test-artifact-contract.do"
tempfile rollup
save "`rollup'", replace

quietly count if artifact_type == "r-master-script"
assert r(N) == 1
quietly count if artifact_type == "stata-master-script"
assert r(N) == 1
quietly count if artifact_type == "table"
assert r(N) == 7
quietly count if artifact_type == "figure"
assert r(N) == 9

forvalues i = 1/18 {
    local aid = lower(artifact_id[`i'])
    confirm file "`root'/tests/fixtures/jel/`aid'/expected/contract/artifact-audit.csv"
    confirm file "`root'/tests/fixtures/jel/`aid'/expected/contract/full-reproduction-evidence.csv"
    confirm file "`root'/tests/fixtures/jel/`aid'/expected/contract/full-reproduction-evidence.json"
    confirm file "`root'/tests/fixtures/jel/`aid'/metadata/manifest.json"

    preserve
    import delimited using "`root'/tests/fixtures/jel/`aid'/expected/contract/artifact-audit.csv", clear varnames(1) stringcols(_all)
    assert _N >= 1
    assert exists == "1"
    destring bytes, replace
    assert bytes > 0
    assert sha256 != ""
    restore

    preserve
    import delimited using "`root'/tests/fixtures/jel/`aid'/expected/contract/full-reproduction-evidence.csv", clear varnames(1) stringcols(_all)
    assert _N == 1
    assert artifact_id == upper("`aid'")
    assert status == "pass"
    assert report == "reports/jel-full-reproduction-result.md"
    assert full_gate == "CSDID_RUN_JEL_FULL=1 tests/run-jel-full-reproduction.sh"
    restore
}

use "`rollup'", clear
keep if artifact_type == "table"
forvalues i = 1/`=_N' {
    local aid = lower(artifact_id[`i'])
    confirm file "`root'/tests/fixtures/jel/`aid'/expected/contract/table-token-summary.csv"
    preserve
    import delimited using "`root'/tests/fixtures/jel/`aid'/expected/contract/table-token-summary.csv", clear varnames(1) stringcols(_all)
    assert _N == 2
    assert inlist(role, "r", "stata")
    destring numeric_token_count, replace
    assert numeric_token_count > 0
    restore
}

use "`rollup'", clear
keep if artifact_type == "figure"
forvalues i = 1/`=_N' {
    local aid = lower(artifact_id[`i'])
    confirm file "`root'/tests/fixtures/jel/`aid'/expected/contract/figure-pdf-audit.csv"
    preserve
    import delimited using "`root'/tests/fixtures/jel/`aid'/expected/contract/figure-pdf-audit.csv", clear varnames(1) stringcols(_all)
    assert _N == 2
    assert inlist(role, "r", "stata")
    assert pdf_header == "%PDF-"
    destring bytes, replace
    assert bytes > 0
    restore
}
