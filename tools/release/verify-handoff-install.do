version 15
args bundle

* No default. This used to fall back to a hardcoded bundle name that went stale
* with every release, so an omitted argument silently verified the wrong (or a
* missing) bundle instead of saying so.
if `"`bundle'"' == "" {
    display as error "usage: do verify-handoff-install.do <bundle-directory>"
    display as error "for example: dist/csdid-stata-2.0.0"
    exit 198
}

clear all
set more off
capture log close csdid_handoff_verify
log using "csdid-handoff-verify.log", replace text name(csdid_handoff_verify)

confirm file `"`bundle'/install.do"'
confirm file `"`bundle'/validation-tests/install-and-smoke.do"'

local plus "`c(tmpdir)'/csdid-handoff-plus"
local personal "`c(tmpdir)'/csdid-handoff-personal"
capture mkdir "`plus'"
capture mkdir "`personal'"
sysdir set PLUS "`plus'"
sysdir set PERSONAL "`personal'"

cd `"`bundle'"'
do install.do

which csdid
which csdid_estat
which csdid_stats
which csdid_plot

csdid version
assert "`e(version)'" == "2.0.0-rc1"

import delimited using "examples/data/mpdta.csv", clear asdouble
csdid lemp lpop, id(countyreal) time(year) gvar(first_treat) method(reg)
assert "`e(version)'" == "2.0.0-rc1"
csdid_stats simple
assert rowsof(e(aggte)) == 1

local expected_plugin "csdid_bootstrap_unix.plugin"
if strpos(lower("`c(machine_type)'"), "mac") > 0 local expected_plugin "csdid_bootstrap_macosx.plugin"
if lower("`c(os)'") == "windows" local expected_plugin "csdid_bootstrap_windows.plugin"
capture quietly findfile `expected_plugin'
if !_rc {
    import delimited using "examples/data/mpdta.csv", clear asdouble
    csdid lemp lpop, id(countyreal) time(year) gvar(first_treat) method(reg) ///
        reps(31) rseed(20260709) pointwise
    assert "`e(bootstrap_accelerator)'" == "plugin"
    assert "`e(bootstrap_accelerator_file)'" == "`expected_plugin'"
}

do examples/06_mpdta_workflow.do
capture program drop __csdid_bootstrap_plugin
global CSDID_BOOT_PLUGIN_PATH
capture program drop __csdid_agg_boot_plugin
global CSDID_AGG_BOOT_PLUGIN_PATH
discard
do validation-tests/install-and-smoke.do

log close csdid_handoff_verify
