* ---------------------------------------------------------------------------
* F044 is the JEL artifact inventory gate. It asserts that all eighteen
* JEL001-JEL018 reference artifacts -- seven tables, nine figures, and the
* rest -- are mapped, present on both sides, marked release-blocking, and
* carry full-reproduction-pass status, and that each smoke gate points at
* the fixture that actually covers it. It also pins the evidence record:
* the report path and the exact opt-in command that produces it. This is
* the check that catches an artifact quietly dropped from the replication
* set, or an evidence pointer that no longer resolves.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"

confirm file "`root'/tests/fixtures/parity/f044/expected/contract/jel-artifact-inventory.csv"
confirm file "`root'/tests/fixtures/parity/f044/expected/contract/full-reproduction-evidence.csv"
confirm file "`root'/tests/fixtures/parity/f044/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/f044/expected/contract/jel-artifact-inventory.csv", clear varnames(1) stringcols(_all)
assert _N == 18
assert r_exists == "1"
assert stata_exists == "1"
assert release_blocking == "1"
quietly count if artifact_type == "table"
assert r(N) == 7
quietly count if artifact_type == "figure"
assert r(N) == 9
quietly count if release_status == "full-reproduction-pass"
assert r(N) == 18
quietly count if artifact_id == "JEL009" & smoke_gate == "F041-table7-analytical-smoke"
assert r(N) == 1
quietly count if artifact_id == "JEL012" & smoke_gate == "F042-figure3-dynamic-smoke"
assert r(N) == 1
quietly count if artifact_id == "JEL018" & smoke_gate == "F043-figure9-dynamic-smoke"
assert r(N) == 1

import delimited using "`root'/tests/fixtures/parity/f044/expected/contract/full-reproduction-evidence.csv", clear varnames(1) stringcols(_all)
assert _N == 18
assert release_status == "full-reproduction-pass"
assert evidence_report == "reports/jel-full-reproduction-result.md"
assert full_gate == "CSDID_RUN_JEL_FULL=1 tests/run-jel-full-reproduction.sh"
