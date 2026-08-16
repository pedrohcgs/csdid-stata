* Two R-parity properties of sample construction that only a degenerate panel
* exercises.
*
*   A. bal(pair) with a (g,t) cell whose pair-balanced unit set is EMPTY. R
*      appends a missing-ATT row and an all-NA influence column for every cell
*      it declines (compute.att_gt.R:679-687, :840-849) and never drops one.
*      csdid skipped the cell outright: no row in e(attgt), no warning, and the
*      aggregations then averaged over the surviving cells -- i.e. dropmissing,
*      applied silently, where the same command refuses with r(498) as soon as
*      one unit makes the pair representable.
*
*   B. bal(full) with NO never-treated group. R deletes the periods at or
*      beyond latest_g - anticipation and recomputes tlist
*      (pre_process_did.R:263/:270) BEFORE it coerces the balanced panel
*      (:437-446), so completeness is judged on the surviving grid. csdid balanced
*      over the raw grid, deleting units that are complete over every period it
*      then estimates on -- a different estimation sample and different numbers
*      on the default path.
*
*   D. The three data-shape refusals are decided on the sample BEFORE bal(full).
*      R checks irreversible treatment, duplicate (id, time) and time-varying
*      cluster variables in validate_args() (pre_process_did2.R:72-109, called
*      at :736) and only then balances the panel inside did_standardization()
*      (:763, balancing at :331-390). csdid read its flags after balancing, so a
*      violation confined to a unit that bal(full) drops was never refused: R
*      stopped and csdid estimated the survivors.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define pcbo_assert_log
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
        local body `"`body'`clean' "'
        file read `fh' line
    }
    file close `fh'
    local found = strpos(subinstr(`"`body'"', " ", "", .), subinstr(`"`message'"', " ", "", .)) > 0
    if "`omit'" == "" assert `found'
    else assert !`found'
end

* -----------------------------------------------------------------------
* A. bal(pair): the empty pair is still a cell.
*
* Never-treated ids 1-6 are seen in periods {1,2,3} and ids 7-12 in {1,3,4};
* cohort g=3 splits the same way. Cell (3,4) has base period 2, so its pair is
* (2,4) and NO unit at all is observed in both periods -- the pair is empty
* while (3,2) and (3,3) are estimable.
* -----------------------------------------------------------------------
clear
set obs 72
generate long id = .
generate byte g = .
generate int t = .
local r = 0
foreach block in "1 6 0 1 2 3" "7 12 0 1 3 4" "21 26 3 1 2 3" "27 32 3 1 3 4" {
    local lo : word 1 of `block'
    local hi : word 2 of `block'
    local gv : word 3 of `block'
    forvalues i = `lo'/`hi' {
        forvalues k = 4/6 {
            local tv : word `k' of `block'
            local ++r
            quietly replace id = `i' in `r'
            quietly replace g  = `gv' in `r'
            quietly replace t  = `tv' in `r'
        }
    }
}
assert `r' == _N
generate double y = mod(id, 7)/3 + 0.4*t + 0.5*(g == 3 & t >= 3) + 0.1*mod(id*t, 5)
sort id t

csdid y, ivar(id) time(t) gvar(g) method(reg) bal(pair) nofast rseed(12345)

tempname A
matrix `A' = e(attgt)
assert rowsof(`A') == 4
local row34 = 0
forvalues i = 1/4 {
    if `A'[`i',1] == 3 & `A'[`i',2] == 4 local row34 = `i'
}
assert `row34' > 0
* att, se and all four unit counts are the standard blank-cell row
assert `A'[`row34',4] >= . & `A'[`row34',5] >= .
forvalues c = 6/9 {
    assert `A'[`row34',`c'] == 0
}

* the missing cell must reach the aggregations, not vanish from them
capture noisily csdid_stats simple
assert _rc == 498
capture noisily csdid_stats event
assert _rc == 498
csdid_stats simple, dropmissing
tempname AGG
matrix `AGG' = e(aggte)
assert reldif(`AGG'[1,2], 0.5) < 1e-10

* -----------------------------------------------------------------------
* B. bal(full), no never-treated group: 60 units over periods {1,2,3},
* cohorts 2 and 3, and 10 of the g==2 units observed only in {1,2}. The kernel
* deletes t >= 3 (latest_g - anticipation), so those 10 units are complete over
* the grid the estimator uses and R keeps all 60.
* -----------------------------------------------------------------------
clear
set obs 180
generate long id = ceil(_n/3)
generate int t = mod(_n - 1, 3) + 1
generate byte g = cond(mod(id, 2) == 1, 2, 3)
generate double y = 0.25*id + 0.2*t + 0.5*(t >= g) + mod(id*7 + t*13, 11)/11
quietly drop if g == 2 & t == 3 & id <= 20
sort id t

tempfile balog
log using "`balog'", replace text
csdid y, ivar(id) time(t) gvar(g) analytical
log close

assert e(N_units) == 60
assert e(N) == 120
pcbo_assert_log using "`balog'", message("are not observed in all") omit
tempname B0 V0
matrix `B0' = e(b)
matrix `V0' = e(V)

* R's step order applied by hand, and bal(none), must both land on the same
* estimates: the ordering is the only thing that was in question.
tempname B1 V1
preserve
quietly drop if t >= 3
csdid y, ivar(id) time(t) gvar(g) analytical
matrix `B1' = e(b)
matrix `V1' = e(V)
assert mreldif(`B1', `B0') < 1e-12 & mreldif(`V1', `V0') < 1e-12
restore
csdid y, ivar(id) time(t) gvar(g) analytical bal(none)
matrix `B1' = e(b)
matrix `V1' = e(V)
assert mreldif(`B1', `B0') < 1e-12 & mreldif(`V1', `V0') < 1e-12

* A unit incomplete over the SURVIVING grid is still dropped, and the message
* names that grid rather than the raw one.
quietly drop if id == 41 & t == 2
tempfile droplog
log using "`droplog'", replace text
csdid y, ivar(id) time(t) gvar(g) analytical
log close
assert e(N_units) == 59
pcbo_assert_log using "`droplog'", message("1 unit(s) are not observed in all 2 periods")

* -----------------------------------------------------------------------
* C. The announced drop count is R's count. A unit whose every row lies at or
* beyond the cutoff is removed by R's period filter before uid/n.old exist
* (pre_process_did.R:263/:270 then :437-446), so it is never a balance drop
* for R and R prints no warning for it. csdid still marks it -- the kernel's
* own cutoff excludes those rows anyway -- so the sample is unchanged and only
* the sentence differs. Both panel layouts are covered: id-major takes the
* grouped branch of the prescan, time-major the interleaved one.
* -----------------------------------------------------------------------
foreach layout in "id t" "t id" {
    clear
    set obs 180
    generate long id = ceil(_n/3)
    generate int t = mod(_n - 1, 3) + 1
    generate byte g = cond(mod(id, 2) == 1, 2, 3)
    generate double y = 0.25*id + 0.2*t + 0.5*(t >= g) + mod(id*7 + t*13, 11)/11
    quietly drop if g == 2 & t == 3 & id <= 20
    * id 41 survives only at t == 3, which the cutoff deletes
    quietly drop if id == 41 & t <= 2
    sort `layout'

    tempfile cutlog
    log using "`cutlog'", replace text
    csdid y, ivar(id) time(t) gvar(g) analytical
    log close
    assert e(N_units) == 59
    assert e(N) == 118
    pcbo_assert_log using "`cutlog'", message("are not observed in all") omit

    * and the count is reduced, not switched off: id 43 is incomplete over the
    * surviving grid and is still announced, alone.
    quietly drop if id == 43 & t == 2
    tempfile mixlog
    log using "`mixlog'", replace text
    csdid y, ivar(id) time(t) gvar(g) analytical
    log close
    assert e(N_units) == 58
    assert e(N) == 116
    pcbo_assert_log using "`mixlog'", ///
        message("1 unit(s) are not observed in all 2 periods; the panel is being balanced by dropping them (2 observation(s))")
}

* -----------------------------------------------------------------------
* D. A violation confined to a unit bal(full) drops still refuses.
*
* 12 units over periods {1,2,3}, six never-treated and six in cohort 3. Unit 1
* is incomplete -- so bal(full) removes it and the other 11 units form a clean
* balanced panel -- and carries one violation at a time. did 2.5.1 stops on all
* three designs (verified against the pinned 2.5.1 clone), with the messages
* quoted beside each. Qualification: all three return rc 0 with e(N_units) 11
* against the pre-fix tree (commit da42eca).
*
* The refusal is also raised in FRONT of the balance block, which is where R
* raises it: validate_args() runs before did_standardization() balances
* anything, and R prints nothing before it stops. Refusing afterwards meant
* csdid announced "the panel is being balanced by dropping them" on a run that
* then estimated nothing -- a balancing that decided nothing. Qualification:
* the three omit-assertions below fail against the pre-hoist tree (e4b8de6),
* where the warning is in the log ahead of the refusal, and the 2000/459 pair
* at the end of this section is the same fix seen from the other side.
* -----------------------------------------------------------------------
program define pcbo_base12
    version 15
    clear
    set obs 36
    generate long id = ceil(_n/3)
    generate int  t  = mod(_n - 1, 3) + 1
    generate byte g  = cond(id <= 6, 0, 3)
    generate byte cl = ceil(id/3)
    generate double y = 0.3*id + 0.2*t + 0.5*(g == 3 & t >= 3) + mod(id*7 + t*13, 11)/11
end

* Each design is run under a log, because the ORDER is part of the contract:
* the refusal comes out in front of the balance block, so the run must NOT
* first announce a balancing that decides nothing. R stops inside
* validate_args and prints nothing at all.

* "The value of idname must be unique (by tname)."
pcbo_base12
quietly drop if id == 1 & t > 1
quietly expand 2 if id == 1
sort id t
tempfile duplog
log using "`duplog'", replace text
capture noisily csdid y, ivar(id) time(t) gvar(g) method(reg) analytical
local dup_rc = _rc
log close
assert `dup_rc' == 459
pcbo_assert_log using "`duplog'", ///
    message("The value of ivar() must be unique within time().")
pcbo_assert_log using "`duplog'", message("is being balanced by dropping") omit

* "The value of gname must be the same across all periods for each unit."
pcbo_base12
quietly drop if id == 1 & t == 3
quietly replace g = 3 if id == 1 & t == 2
sort id t
tempfile gvarylog
log using "`gvarylog'", replace text
capture noisily csdid y, ivar(id) time(t) gvar(g) method(reg) analytical
local gvary_rc = _rc
log close
assert `gvary_rc' == 459
pcbo_assert_log using "`gvarylog'", ///
    message("gvar() must be time-invariant within ivar()")
pcbo_assert_log using "`gvarylog'", message("is being balanced by dropping") omit

* "Time-varying cluster variables are not supported."
pcbo_base12
quietly drop if id == 1 & t == 3
quietly replace cl = 99 if id == 1 & t == 2
sort id t
tempfile cvarylog
log using "`cvarylog'", replace text
capture noisily csdid y, ivar(id) time(t) gvar(g) method(reg) cluster(cl) analytical
local cvary_rc = _rc
log close
assert `cvary_rc' == 459
pcbo_assert_log using "`cvarylog'", ///
    message("cluster() must be time-invariant within ivar()")
pcbo_assert_log using "`cvarylog'", message("is being balanced by dropping") omit

* The same incomplete unit with NO violation is dropped and the run proceeds,
* so it is the violation that refuses and not the incompleteness -- and the
* balance warning is what a run that really balances still prints.
pcbo_base12
quietly drop if id == 1 & t == 3
sort id t
tempfile cleanlog
log using "`cleanlog'", replace text
csdid y, ivar(id) time(t) gvar(g) method(reg) cluster(cl) analytical
log close
assert e(N_units) == 11
pcbo_assert_log using "`cleanlog'", message("is being balanced by dropping")

* The intersection, and the one case whose CLASS changes: a violation in a
* panel that bal(full) balances down to NOTHING. Every unit is missing one
* period, a different one, so the grid is still {1,2,3} and no unit is complete
* over it; unit 1 additionally reverses its cohort. Validating first is what R
* does, so the answer is the shape refusal (459) and not the empty-sample
* message (2000) the balance block would otherwise reach -- R never gets as far
* as its own balancing step on this design.
pcbo_base12
quietly drop if t == mod(id, 3) + 1
quietly replace g = 3 if id == 1 & t == 3
sort id t
tempfile bothlog
log using "`bothlog'", replace text
capture noisily csdid y, ivar(id) time(t) gvar(g) method(reg) analytical
local both_rc = _rc
log close
assert `both_rc' == 459
pcbo_assert_log using "`bothlog'", ///
    message("gvar() must be time-invariant within ivar()")
pcbo_assert_log using "`bothlog'", message("balancing the panel left no observations") omit
pcbo_assert_log using "`bothlog'", message("is being balanced by dropping") omit

* and the same design WITHOUT the reversal still reports the empty sample, so
* it is the violation that changed the answer and not the design. Measured on
* the pre-hoist tree (e4b8de6): BOTH of these exit 2000.
pcbo_base12
quietly drop if t == mod(id, 3) + 1
sort id t
capture csdid y, ivar(id) time(t) gvar(g) method(reg) analytical
assert _rc == 2000

display as text "test-pair-cell-and-balance-order: all assertions passed"
