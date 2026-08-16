* F056 -- R parity of the REFUSAL ORDER: the small-group warning, the
* never-treated-too-small refusal and the no-never-treated fallback warning are
* decided on the BALANCED sample.
*
* R did 2.5.1 pre_process_did.R balances the panel first (the keep_bal filter
* around line 430) and only then measures the groups, under its own comment at
* line 527: "more error handling after we have balanced the panel". csdid
* measured them in its prescan, BEFORE the bal(full) drop. Balancing only
* removes rows, so every group size was overstated and both refusals fired
* strictly less often than R's.
*
* Two witnesses, both requiring bal(full) plus at least one incomplete unit:
*
*   1. A never-treated group that clears the threshold before balancing and
*      falls below it after. R stops. csdid did reach a stop -- but from the
*      kernel, in R's wording and with no preceding warning naming the group --
*      so this test pins the ado's diagnosis, which is what the pre-balance
*      measurement suppressed.
*
*   2. Balancing removes EVERY never-treated unit. The kernel then silently
*      coerces the latest treated cohort into the comparison group, changing
*      the estimand, while the warning that discloses it was gated on the
*      stale pre-balance never-treated count and never printed.
*
* Threshold arithmetic in both scenarios: no covariates, so reqsize = 5, and
* the group size is ROWS / n_periods (R's gcnt / length(tlist)), with 4
* periods.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f056_assert_log, rclass
    version 15
    syntax using/, MESSAGE(string) [OMIT]

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
    local found = strpos(`"`body'"', `"`message'"') > 0 | ///
                  strpos(`"`compact_body'"', `"`compact_message'"') > 0
    if "`omit'" == "" {
        assert `found'
    }
    else {
        assert !`found'
    }
end

* -----------------------------------------------------------------------
* Scenario 1: the never-treated group is large enough before balancing
* (21 rows / 4 periods = 5.25 >= 5) and too small after it (12 / 4 = 3).
* -----------------------------------------------------------------------
clear
* 8 complete treated units (cohort 3), 3 complete never-treated units,
* 3 never-treated units missing period 4.
quietly set obs 14
quietly generate long id = _n
quietly generate double g = cond(id <= 8, 3, 0)
quietly generate byte incomplete = (id >= 12)
quietly expand 4
quietly bysort id: generate double time = _n
quietly drop if incomplete & time == 4
quietly generate double y = mod(id * 7 + time * 3, 13) / 13 + ///
    cond(g > 0 & time >= g, 1, 0)

* Pre-balance the never-treated group has 21 rows over 4 periods (5.25) and
* clears the threshold; after balancing it has 12 (3.0) and does not.
quietly count if g == 0
assert r(N) == 21
quietly count if g == 0 & !incomplete
assert r(N) == 12

tempfile lg1
log using "`lg1'", text replace name(f056a)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) ///
    nevertreated analytical bal(full)
local rc1 = _rc
log close f056a
assert `rc1' == 459
assert "`e(cmd)'" == ""

* The refusal is now raised by the driver, on the balanced sample, with the
* warning that names the offending group in front of it. Pre-fix the driver
* saw 5.25 and said nothing; the run died later inside the kernel with R's
* wording and no group named.
f056_assert_log using "`lg1'", message("Some groups in your dataset have very few observations")
f056_assert_log using "`lg1'", message("Check groups: 0.")
f056_assert_log using "`lg1'", message("too small to serve as a reliable comparison group")
f056_assert_log using "`lg1'", message("too small to serve as a reliable control") omit

* bal(none) keeps every unit, so on the SAME data nothing is refused: the
* refusal is a consequence of the balancing, not of the raw data.
capture quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
    nevertreated analytical bal(none)
assert _rc == 0

* -----------------------------------------------------------------------
* Scenario 2: balancing removes EVERY never-treated unit, so the fallback
* that coerces the latest treated cohort must be disclosed.
* -----------------------------------------------------------------------
clear
* 8 complete units in cohort 3, 8 complete units in cohort 4, and 7
* never-treated units observed in only 3 of the 4 periods.
quietly set obs 23
quietly generate long id = _n
quietly generate double g = cond(id <= 8, 3, cond(id <= 16, 4, 0))
quietly generate byte incomplete = (g == 0)
quietly expand 4
quietly bysort id: generate double time = _n
quietly drop if incomplete & time == 4
quietly generate double y = mod(id * 11 + time * 5, 17) / 17 + ///
    cond(g > 0 & time >= g, 1, 0)

* 21 rows / 4 = 5.25 before balancing, so the never-treated group clears the
* small-group threshold; after balancing it has no rows at all.
quietly count if g == 0
assert r(N) == 21

tempfile lg2
log using "`lg2'", text replace name(f056b)
capture noisily csdid y, ivar(id) time(time) gvar(g) method(reg) ///
    nevertreated analytical bal(full)
local rc2 = _rc
log close f056b
assert `rc2' == 0

* The estimand changed -- the latest treated cohort is standing in for a
* never-treated group that balancing removed -- and the run has to say so.
* Pre-fix this warning was gated on the pre-balance count of 21 rows and was
* therefore never printed.
f056_assert_log using "`lg2'", message("No never-treated group available")
f056_assert_log using "`lg2'", message("using the latest treated cohort as never-treated")

* -----------------------------------------------------------------------
* Scenario 3: the driver and the kernel refuse on ONE threshold, and it is
* R's.
*
* Both layers carry this refusal -- the driver raises it before estimating,
* the kernel raises it as a backstop -- and they used to compute the size
* they demand differently. R's is
*     reqsize <- length(rhs_vars(xformla)) + 5      pre_process_did.R:540
* which counts the covariates NAMED in the formula. The driver counts the
* same thing. The kernel only ever sees the expanded design and rebuilt the
* number from it as `cols(x) + 4', so one factor covariate with five levels
* made it demand nine never-treated units where R and the driver demand six,
* and it refused designs both of them accept. The kernel is now given the
* driver's reqsize.
*
* Design A (four never-treated units) is below the threshold on both
* readings, and pins that the two paths refuse it in the same words. Design B
* (eight) is above R's threshold and below the old expanded-column one: it is
* the design the two layers used to disagree about. Both are balanced panels,
* where the driver's rows/n_periods and the kernel's unit count are the same
* number, so the only thing being varied is the threshold.
* -----------------------------------------------------------------------
clear
quietly set obs 16
quietly generate long id = _n
quietly generate double g = cond(id <= 12, 3, 0)
quietly generate byte state = mod(id, 5) + 1
quietly expand 4
quietly bysort id: generate double time = _n
quietly generate double y = mod(id * 7 + time * 3, 13) / 13 + 0.2 * state + ///
    cond(g > 0 & time >= g, 1, 0)
quietly tabulate state, generate(st_)
quietly count if g == 0 & time == 1
assert r(N) == 4

tempfile lg3a
log using "`lg3a'", text replace name(f056c)
capture noisily csdid y i.state, ivar(id) time(time) gvar(g) method(reg) ///
    nevertreated analytical
local rc3a = _rc
log close f056c
assert `rc3a' == 459
f056_assert_log using "`lg3a'", message("too small to serve as a reliable comparison group")

* The kernel on the same design, called directly so that the driver's refusal
* cannot stand in for it: the expanded design it would have received, and the
* reqsize the driver computed (one named covariate + 5 = 6).
tempvar touse3a usemark3a
quietly generate byte `touse3a' = 1
quietly generate byte `usemark3a' = 0
tempname a3a if3a gp3a ug3a ct3a fu3a bp3a nt3a
tempfile lg3b
log using "`lg3b'", text replace name(f056d)
capture noisily mata: csdid_basic_attgt("y", "time", "g", "id", ///
    "st_2 st_3 st_4 st_5", "", "reg", "`touse3a'", "", "", "universal", ///
    "full", "", 0, 0.999, 6, 0, "`fu3a'", "`bp3a'", "`nt3a'", 0, "`a3a'", ///
    "`if3a'", "`gp3a'", "`ug3a'", "`ct3a'", "`usemark3a'")
local rc3b = _rc
log close f056d
assert `rc3b' == 459
f056_assert_log using "`lg3b'", message("too small to serve as a reliable comparison group")
f056_assert_log using "`lg3b'", message("too small to serve as a reliable control") omit

* Design B: eight never-treated units, one covariate. R's threshold is 6 and
* both layers estimate; the kernel's old cols(x) + 4 was 9 and it refused.
clear
quietly set obs 20
quietly generate long id = _n
quietly generate double g = cond(id <= 12, 3, 0)
quietly generate byte state = mod(id, 5) + 1
quietly expand 4
quietly bysort id: generate double time = _n
quietly generate double y = mod(id * 7 + time * 3, 13) / 13 + 0.2 * state + ///
    cond(g > 0 & time >= g, 1, 0)
quietly tabulate state, generate(st_)
quietly count if g == 0 & time == 1
assert r(N) == 8

capture noisily csdid y i.state, ivar(id) time(time) gvar(g) method(reg) ///
    nevertreated analytical
assert _rc == 0
assert e(N_attgt) == 4

tempvar touse3b usemark3b
quietly generate byte `touse3b' = 1
quietly generate byte `usemark3b' = 0
tempname a3b if3b gp3b ug3b ct3b fu3b bp3b nt3b
capture noisily mata: csdid_basic_attgt("y", "time", "g", "id", ///
    "st_2 st_3 st_4 st_5", "", "reg", "`touse3b'", "", "", "universal", ///
    "full", "", 0, 0.999, 6, 0, "`fu3b'", "`bp3b'", "`nt3b'", 0, "`a3b'", ///
    "`if3b'", "`gp3b'", "`ug3b'", "`ct3b'", "`usemark3b'")
assert _rc == 0
assert rowsof(`a3b') == 4

display as text "test-f056: post-balance refusal order OK"
