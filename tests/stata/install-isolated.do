version 15
clear all
set more off

local root "`c(pwd)'"
do "`root'/src/build.do"

local plus "`c(tmpdir)'/csdid-plus"
local personal "`c(tmpdir)'/csdid-personal"
capture mkdir "`plus'"
capture mkdir "`personal'"
sysdir set PLUS "`plus'"
sysdir set PERSONAL "`personal'"

net install csdid, from("`root'") replace
which csdid
which csdid_estat
which csdid_stats
which csdid_plot
which csdid.mata
foreach f in csdid.sthlp csdid_postestimation.sthlp csdid_estat.sthlp csdid_stats.sthlp csdid_plot.sthlp {
    quietly findfile `f'
}

clear
input id time g y
1 1 2 0
1 2 2 2
2 1 2 0
2 2 2 2
3 1 2 0
3 2 2 2
4 1 2 0
4 2 2 2
5 1 2 0
5 2 2 2
6 1 0 1
6 2 0 1
7 1 0 1
7 2 0 1
8 1 0 1
8 2 0 1
9 1 0 1
9 2 0 1
10 1 0 1
10 2 0 1
end

csdid y, time(time) gvar(g) analytical nevertreated base_period(varying) bal(none)

matrix A = e(attgt)
assert rowsof(A) == 1
assert abs(A[1,4] - 2) < 1e-12

* ---------------------------------------------------------------------------
* The compiled accelerator, run FROM THE INSTALLED PACKAGE.
*
* Every other plugin test runs against src/ through adopath, and the only
* net-install test used analytical standard errors, so no test ever executed
* the binary that net install actually delivers. That is how a shipped plugin
* sat nine days behind its own C source, without the all-zero RNG-state guard,
* while every gate stayed green.
*
* On macOS the accelerator must be the one that ran. Elsewhere no binary ships
* and Mata is correct, so the assertion is that a documented status was
* recorded -- not that a plugin was used.
* ---------------------------------------------------------------------------
* The dataset above is perfectly deterministic -- every treated unit 0 then 2,
* every control constant -- which gives the influence function zero variance
* and trips a separate, pre-existing bootstrap defect (see
* docs/behavior-decisions.md). Add variation so this check is about the
* installed accelerator and not about that.
quietly replace y = y + mod(id, 3) / 1000
quietly csdid y, time(time) gvar(g) nevertreated base_period(varying) bal(none) ///
    wboot(reps(99) rseed(20260807))
local acc "`e(bootstrap_accelerator_status)'"
display as text "installed-package accelerator: `acc'"
if strpos(lower("`c(machine_type)'"), "mac") > 0 {
    if "`acc'" != "plugin-active" {
        display as error "the installed package did not use the compiled accelerator: `acc'"
        exit 9
    }
}
else {
    assert strpos("`acc'", "mata") == 1
}

* The binary net install delivered must be the one this tree builds. The
* byte comparison lives in tests/meta; what matters here is that the file
* actually arrived in the install directory alongside csdid.ado, because
* csdid.ado resolves the plugin by that path.
findfile csdid.ado
local instdir = subinstr("`r(fn)'", "csdid.ado", "", .)
if strpos(lower("`c(machine_type)'"), "mac") > 0 {
    confirm file "`instdir'csdid_bootstrap_macosx.plugin"
    display as text "installed plugin present alongside csdid.ado"
}
