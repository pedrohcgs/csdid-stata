* F064 -- the Stata 14/15 matsize floor is refused by name, not discovered as
* a bare r(908) after the estimation has already run.
*
* Stata 14 and 15 cap classic-matrix dimensions with `set matsize', default
* 400. Every bootstrap path writes at least one biters-row Stata matrix, and a
* seeded run builds a 1 x 625 RNG-state matrix BEFORE the kernel runs. So on a
* stock Stata 14/15 the DEFAULT run -- reps(1000), bootstrap on unless
* analytical -- had no working path at all, and said so only through an
* unnamed r(908) raised after the whole estimation had been computed.
*
* The guard is gated on c(stata_version) < 16, because Stata 16 removed the
* cap and still reports c(matsize) = 400: an ungated check would refuse the
* entire modern user base.
*
* That gate is exactly why this test exists in the shape it does. On any Stata
* this suite actually runs on, the guard can never fire, so asserting "it did
* not fire" would prove nothing about whether it works. The test therefore
* copies the two ado files into a scratch adopath with the version gate opened
* and drives them there, which is the only way to see the check do its job --
* and then confirms that the real, gated files leave every one of the same
* commands alone.

version 15
clear all
set more off

local root "`c(pwd)'"

program define f064_make_panel
    version 15
    clear
    quietly set obs 90
    quietly generate long id = _n
    quietly generate double g = cond(mod(id, 3) == 0, 0, ///
        cond(mod(id, 3) == 1, 3, 4))
    quietly expand 5
    quietly bysort id: generate double time = _n
    quietly generate double y = mod(id * 7 + time * 11, 23) / 23 ///
        + 0.15 * time + cond(g > 0 & time >= g, 1.2, 0)
end

* -----------------------------------------------------------------------
* 1. The shipped files: the guard is inert here, whatever c(matsize) says.
* -----------------------------------------------------------------------
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* The suite runs on Stata 16 or later, where the cap does not exist. If that
* ever stops being true this assertion says so rather than silently making
* the rest of the file vacuous.
assert c(stata_version) >= 16
assert c(matsize) < 1000

f064_make_panel
capture quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    wboot(reps(1000))
assert _rc == 0
capture quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    wboot(reps(199) rseed(7))
assert _rc == 0

* -----------------------------------------------------------------------
* 2. The same code with the version gate opened: the guard fires, and only
*    where it should.
* -----------------------------------------------------------------------
tempfile gatedir
local gated "`c(tmpdir)'/csdid_f064_gated"
capture mkdir "`gated'"
capture erase "`gated'/csdid.ado"
capture erase "`gated'/csdid_stats.ado"

* -filefilter- does the substitution; copying an ado line by line through
* -file read/write- cannot, because ado source legitimately contains
* unbalanced quotes.
foreach f in csdid csdid_stats {
    capture erase "`gated'/`f'_raw.ado"
    copy "`root'/src/ado/`f'.ado" "`gated'/`f'_raw.ado", replace
    quietly filefilter "`gated'/`f'_raw.ado" "`gated'/`f'.ado", ///
        from("c(stata_version) < 16") to("c(stata_version) < 99") replace
    assert r(occurrences) > 0
    erase "`gated'/`f'_raw.ado"
}

adopath ++ "`gated'"
* The gated copies must be the ones that answer now.
capture program drop csdid
capture program drop csdid_stats

f064_make_panel
* Establish a prior estimation, so the refusal below can prove it is an ENTRY
* refusal: it fires at option-resolution time, before the data are touched,
* and the previous results survive it exactly -- the old placement ran the
* whole ATT kernel first and then cleared e() on its way out.
capture quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    analytical
assert _rc == 0
tempname MS0 MS1
matrix `MS0' = e(b)
* reps(1000) over a matsize of 400: refused, by name, before anything runs.
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    wboot(reps(1000))
assert _rc == 908
assert "`e(cmd)'" == "csdid"
matrix `MS1' = e(b)
assert mreldif(`MS0', `MS1') == 0

* A seeded run needs 625 for the RNG state even at a small reps().
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    wboot(reps(199) rseed(7))
assert _rc == 908

* Under the floor, the same command runs: the guard is a floor, not a ban.
capture quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    wboot(reps(199))
assert _rc == 0

* And analytical inference never touches a draws matrix, so it is untouched.
capture quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet ///
    analytical
assert _rc == 0

adopath - "`gated'"
capture program drop csdid
capture program drop csdid_stats
capture erase "`gated'/csdid.ado"
capture erase "`gated'/csdid_stats.ado"

display as text "test-f064: matsize floor refused by name on Stata 14/15, inert elsewhere OK"
