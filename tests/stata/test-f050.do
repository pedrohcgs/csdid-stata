version 15
clear all
set more off

local root "`c(pwd)'"
confirm file "`root'/tests/fixtures/parity/f050/expected/new-stata/install-schema.json"

do "`root'/src/build.do"
capture confirm file "`root'/build/csdid.pkg"
assert _rc != 0
capture confirm file "`root'/build/stata.toc"
assert _rc != 0

local plus "`c(tmpdir)'/csdid-f050-plus"
local personal "`c(tmpdir)'/csdid-f050-personal"
capture mkdir "`plus'"
capture mkdir "`personal'"
sysdir set PLUS "`plus'"
sysdir set PERSONAL "`personal'"

net install csdid, from("`root'") replace

foreach f in csdid.ado csdid_estat.ado csdid_stats.ado csdid_plot.ado csdid.mata csdid.sthlp csdid_postestimation.sthlp csdid_estat.sthlp csdid_stats.sthlp csdid_plot.sthlp {
    quietly findfile `f'
    local found "`r(fn)'"
    assert strpos("`found'", "`plus'") == 1
}

which csdid
which csdid_estat
which csdid_stats
which csdid_plot
which csdid.mata

import delimited using "`root'/tests/fixtures/parity/f050/inputs/input.csv", clear asdouble
csdid y, time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
matrix A = e(attgt)
assert rowsof(A) == 1
assert abs(A[1,4] - 2) < 1e-12
assert "`e(cmd)'" == "csdid"

csdid_stats simple
matrix G = e(aggte)
assert rowsof(G) == 1
assert abs(G[1,2] - 2) < 1e-12

import delimited using "`root'/tests/fixtures/parity/f050/inputs/input.csv", clear asdouble
tempfile rif
csdid y, time(time) gvar(g) method(reg) saverif("`rif'") replace analytical nevertreated base_period(varying) bal(none)
confirm file "`rif'"
use "`rif'", clear
unab vars : _all
assert "`vars'" == "rif_row id group weight rif1"
assert weight == 1
assert "`: char _dta[csdid_artifact]'" == "rif"
