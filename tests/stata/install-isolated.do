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

* ---------------------------------------------------------------------------
* Coexistence with the csdid2 package, which distributes lcsdid.mlib. Our
* library is lcsdid_v2.mlib precisely so the two installs cannot overwrite
* each other; simulate an existing csdid2 install by planting a foreign
* lcsdid.mlib in PLUS before installing, and prove it survives untouched.
* ---------------------------------------------------------------------------
capture mkdir "`plus'/l"
mata: mata mlib create lcsdid, dir("`plus'/l") replace
confirm file "`plus'/l/lcsdid.mlib"
checksum "`plus'/l/lcsdid.mlib"
local foreign_checksum = r(checksum)

net install csdid, from("`root'") replace
confirm file "`plus'/l/lcsdid_v2.mlib"
confirm file "`plus'/l/lcsdid.mlib"
checksum "`plus'/l/lcsdid.mlib"
assert r(checksum) == `foreign_checksum'
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
* WHICH ENGINE SERVED THE RUN.
*
* This install ships a compiled library built by this Stata, so the library
* must be what answered. The alternative -- csdid quietly compiling its source
* copy instead, every session, forever -- produces identical numbers and is
* therefore invisible to every other assertion in this file: it is a permanent
* silent fall-through that no figure can see. A user would meet it only as the
* first csdid of every session taking noticeably longer.
*
* The loader records what it resolved in $CSDID_ENGINE_RESOLVED, whose first
* semicolon-delimited field is the engine's own stamp. The compiled library
* carries `2.0.0|<the Stata that built it>'; the source copy ships reading
* `2.0.0|source' and says so. So the assertion is on the half after the bar:
* a number means the library answered, the word `source' means it did not.
* ---------------------------------------------------------------------------
local resolved `"$CSDID_ENGINE_RESOLVED"'
if `"`resolved'"' == "" {
    display as error "the installed copy recorded no engine resolution at all"
    exit 9
}
local semi = strpos(`"`resolved'"', ";")
assert `semi' > 1
local stamp = substr(`"`resolved'"', 1, `semi' - 1)
local bar = strpos("`stamp'", "|")
assert `bar' > 1
local pkg_half = substr("`stamp'", 1, `bar' - 1)
local route    = substr("`stamp'", `bar' + 1, .)
display as text "installed-package engine stamp: `stamp'"
assert "`pkg_half'" == "2.0.0"
if "`route'" == "source" {
    display as error "the installed copy fell back to compiling csdid.mata: the shipped library did not answer"
    display as error "engine stamp was `stamp'; a library-served run stamps 2.0.0|<stata version>"
    exit 9
}
if missing(real("`route'")) {
    display as error "the installed copy's engine stamp names no Stata version: `stamp'"
    exit 9
}

* ---------------------------------------------------------------------------
* The compiled accelerator, run FROM THE INSTALLED PACKAGE.
*
* Every other plugin test runs against src/ through adopath, and a net-install
* test that uses analytical standard errors never executes the binary net
* install actually delivers. Without this check the shipped plugin can lag its
* own C source -- an old binary, missing the all-zero RNG-state guard, sitting
* in pkg/ while every gate stays green.
*
* On macOS the accelerator must be the one that ran. Elsewhere no binary ships
* and Mata is correct, so the assertion is that a documented status was
* recorded -- not that a plugin was used.
* ---------------------------------------------------------------------------
* The dataset above is perfectly deterministic -- every treated unit 0 then 2,
* every control constant -- which gives the influence function zero variance
* and trips a separate, pre-existing bootstrap defect. Add variation so this
* check is about the
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
