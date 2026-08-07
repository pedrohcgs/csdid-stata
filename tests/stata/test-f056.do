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

display as text "test-f056: post-balance refusal order OK"
