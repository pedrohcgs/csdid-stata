version 15
clear all
set more off

capture log close csdid_install_smoke
log using "install-smoke.log", replace text name(csdid_install_smoke)

local root "`c(pwd)'"
confirm file "`root'/install.do"
confirm file "`root'/examples/data/mpdta.csv"

local plus "`c(tmpdir)'/csdid-install-plus"
local personal "`c(tmpdir)'/csdid-install-personal"
capture mkdir "`plus'"
capture mkdir "`personal'"
sysdir set PLUS "`plus'"
sysdir set PERSONAL "`personal'"

do install.do

which csdid
which csdid_estat
which csdid_stats
which csdid_plot

csdid version
assert "`e(version)'" == "2.0.0"

clear
set seed 20260708
set obs 240
generate long id = ceil(_n / 6)
bysort id: generate int year = _n
generate int first_treat = cond(id <= 10, 0, cond(id <= 22, 3, 4))
generate int state = mod(id, 5) + 1
generate double x1 = sin(id / 5) + year / 10
generate double x2 = cos(id / 7)
generate double w = .75 + mod(id, 4) / 4
generate double treated = first_treat > 0 & year >= first_treat
generate double y = 1 + .2 * x1 - .1 * x2 + .05 * year + .4 * treated + rnormal()

csdid y x1 x2, id(id) time(year) gvar(first_treat) reps(31) rseed(20260708)
assert "`e(method)'" == "dr"
assert e(bstrap) == 1
assert e(cband) == 1
assert e(biters) == 31
assert e(N_attgt) > 0
local expected_plugin "csdid_bootstrap_unix.plugin"
if strpos(lower("`c(machine_type)'"), "mac") > 0 local expected_plugin "csdid_bootstrap_macosx.plugin"
if lower("`c(os)'") == "windows" local expected_plugin "csdid_bootstrap_windows.plugin"
capture quietly findfile `expected_plugin'
if !_rc {
    assert "`e(bootstrap_accelerator)'" == "plugin"
    assert "`e(bootstrap_accelerator_file)'" == "`expected_plugin'"
}

* dropmissing is required and that is deliberate: this workflow leaves 5 of 12
* cells unestimated, and the aggregation now refuses by name rather than
* silently averaging the 7 that succeeded. The installation smoke exercises the
* documented option, so it verifies the shipped behaviour rather than the one
* the command had before.
estat event, window(-2 2) dropmissing
tempfile plotdata
csdid_plot, saving("`plotdata'") replace
confirm file "`plotdata'"

csdid_stats simple, dropmissing
assert rowsof(e(aggte)) == 1

drop if mod(id, 11) == 0 & inlist(year, 2, 5)
* bal(none) is what selects the allow_unbalanced kernel. Without it the command
* balances the panel and reports panel_mode "panel", so this assertion could
* never hold and the smoke never covered the unbalanced path it names.
csdid y x1 x2 [iw=w], id(id) time(year) gvar(first_treat) method(dr) vce(cluster state) analytical bal(none)
assert "`e(panel_mode)'" == "allow_unbalanced"
assert "`e(clustervar)'" == "state"
assert e(N_attgt) > 0
csdid_stats event, window(-2 2) dropmissing
assert rowsof(e(aggte)) > 0

do examples/06_mpdta_workflow.do

log close csdid_install_smoke
