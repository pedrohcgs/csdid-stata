* Under lean storage the influence functions stay in the Mata engine and e()
* carries only a token that says which estimation they belong to. Everything
* the postestimation layer does with that cache rests on the token being a name
* for ONE estimation. It was not: it was a per-session counter, so the first
* lean csdid of every session was token 1, and the guard that exists to stop
* one run's influence functions being read against another run's results
* compared 1 with 1 and let it through.
*
* The workflow that reaches it is documented and ordinary. Estimate, `estimates
* save'; another day, estimate something else, `estimates use' the saved run,
* aggregate. The aggregation returned 0, printed the saved run's point
* estimates, and put the OTHER estimation's standard errors under them.
*
* Five arms, and the first is the reason this file launches processes:
*
*   1  two Stata processes, .ster written in one and read in the other. Nothing
*      inside a single session can stage a collision between two sessions'
*      first estimations.
*   4  storeall, the control, across the same process boundary: its influence
*      functions travel inside the .ster, so the restored session must
*      reproduce the saved session's aggregation exactly. A fix that refused
*      here would have broken the workflow instead of the defect.
*   5  the legitimate lean workflows, which must be untouched: aggregate after
*      estimating, and aggregate after `estimates store'/`restore' in the same
*      session.
*   2  the same collision reached with `mata clear' between the two runs of one
*      session, which is the other way a session gets a second engine.
*   3  the token forced to collide on purpose, which is the only way to put the
*      content check on trial by itself: with the token matching and the
*      dimensions matching, what refuses is the ATT(g,t) table comparison and
*      nothing else.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local data "`root'/tests/fixtures/parity/f034/inputs/input.csv"
confirm file "`data'"
confirm file "`root'/tests/stata/cache-token-session-child.do"

tempfile stub
local scratch "`stub'-cachetoken"
mkdir "`scratch'"
display as text "test-cache-token-session: staging under `scratch'"

program define ct_stage_clean
    version 15
    args scratch

    foreach f in A.csv B.csv lean.ster full.ster cache-token-session-child.log {
        capture erase "`scratch'/`f'"
    }
    capture rmdir "`scratch'"
end

* The value one process recorded, or a named failure. A missing observation
* must not read as a passing assertion.
program define ct_value, rclass
    version 15
    syntax , ARM(string) KEY(string)

    quietly levelsof value if arm == "`arm'" & key == "`key'", local(v) clean
    if `"`v'"' == "" {
        display as error "test-cache-token-session: process `arm' recorded no `key'"
        exit 9
    }
    return local txt `"`v'"'
    return scalar num = real(`"`v'"')
end

* Did the command say the thing a refusal is required to say? A bare return
* code is not the message the user has to act on.
program define ct_says
    version 15
    syntax using/, MESSAGE(string)

    tempname lh
    local body ""
    file open `lh' using `"`using'"', read text
    file read `lh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body'`clean' "'
        file read `lh' line
    }
    file close `lh'
    local hay = subinstr(`"`body'"', " ", "", .)
    local needle = subinstr(`"`message'"', " ", "", .)
    assert strpos(`"`hay'"', `"`needle'"') > 0
end

* The saving session's aggregation, against which the wrong answer is reported
* and the legitimate arms are judged. Read out of the csv into a matrix while
* the csv is still in memory, because every arm below loads the estimation data
* over it.
program define ct_truth
    version 15
    args k

    tempname T
    matrix `T' = J(2, `k', .)
    forvalues j = 1/`k' {
        ct_value, arm(A) key(truth_b_`j')
        matrix `T'[1, `j'] = r(num)
        ct_value, arm(A) key(truth_se_`j')
        matrix `T'[2, `j'] = r(num)
    }
    matrix CT_TRUTH = `T'
end

* One aggregation column against the saving session's. Missing is a value here:
* the base period's standard error is missing on both sides and must compare
* equal rather than being skipped.
program define ct_agrees
    version 15
    args got truth

    assert (missing(`got') & missing(`truth')) | reldif(`got', `truth') < 1e-14
end

capture noisily {

    * -----------------------------------------------------------------------
    * ARM 1 and ARM 4 -- two processes, one .ster.
    * -----------------------------------------------------------------------
    local child "`root'/tests/stata/cache-token-session-child.do"
    shell cd "`scratch'" && stata-mp -b do "`child'" "`root'" A "`data'" "`scratch'" > /dev/null 2>&1
    capture confirm file "`scratch'/A.csv"
    if _rc {
        display as error "the saving session wrote no results"
        exit 9
    }
    shell cd "`scratch'" && stata-mp -b do "`child'" "`root'" B "`data'" "`scratch'" > /dev/null 2>&1
    capture confirm file "`scratch'/B.csv"
    if _rc {
        display as error "the restoring session wrote no results"
        exit 9
    }

    import delimited using "`scratch'/A.csv", clear varnames(nonames) stringcols(_all)
    rename (v1 v2) (key value)
    generate str1 arm = "A"
    tempfile Adta
    quietly save "`Adta'"
    import delimited using "`scratch'/B.csv", clear varnames(nonames) stringcols(_all)
    rename (v1 v2) (key value)
    generate str1 arm = "B"
    append using "`Adta'"

    ct_value, arm(A) key(lean_est_rc)
    assert r(num) == 0
    ct_value, arm(A) key(full_est_rc)
    assert r(num) == 0
    ct_value, arm(A) key(truth_agg_rc)
    assert r(num) == 0
    ct_value, arm(B) key(own_est_rc)
    assert r(num) == 0

    ct_value, arm(A) key(truth_k)
    local truth_k = r(num)
    ct_truth `truth_k'

    * The two sessions really are the shape the collision needs: the restored
    * results carry the same unit count and the same number of ATT(g,t) cells
    * as the estimation standing in the engine. Without this the refusal below
    * could be the dimension check firing and would prove nothing about the
    * token.
    ct_value, arm(B) key(lean_restore_n_units)
    local restored_units = r(num)
    ct_value, arm(B) key(lean_restore_n_attgt)
    local restored_cells = r(num)
    assert `restored_units' > 0 & `restored_cells' > 0

    ct_value, arm(B) key(lean_agg_rc)
    local lean_rc = r(num)
    if `lean_rc' == 0 {
        * Say what the green run produced, because the number IS the finding:
        * the saved run's point estimates carrying the other run's inference.
        display as error "test-cache-token-session: the restoring session aggregated a cache that belongs to another estimation"
        forvalues j = 1/`truth_k' {
            ct_value, arm(B) key(lean_b_`j')
            local b_got = r(num)
            ct_value, arm(B) key(lean_se_`j')
            local se_got = r(num)
            display as error "  column `j': att " %14.9f CT_TRUTH[1, `j'] " -> " %14.9f `b_got' ///
                "    se " %14.9f CT_TRUTH[2, `j'] " -> " %14.9f `se_got' ///
                "    se ratio " %12.9f (`se_got' / CT_TRUTH[2, `j'])
        }
    }
    assert `lean_rc' == 498
    ct_value, arm(B) key(lean_agg_said)
    assert r(num) == 1

    * ARM 4. Same two processes, same .ster boundary, storeall.
    ct_value, arm(B) key(full_agg_rc)
    assert r(num) == 0
    ct_value, arm(B) key(full_k)
    assert r(num) == `truth_k'
    forvalues j = 1/`truth_k' {
        ct_value, arm(A) key(truth_b_`j')
        local b_truth `"`r(txt)'"'
        ct_value, arm(B) key(full_b_`j')
        assert `"`r(txt)'"' == `"`b_truth'"'
        ct_value, arm(A) key(truth_se_`j')
        local se_truth `"`r(txt)'"'
        ct_value, arm(B) key(full_se_`j')
        assert `"`r(txt)'"' == `"`se_truth'"'
    }
    display as text "test-cache-token-session: a lean estimation restored from a .ster written by another Stata process refuses the cache standing in this one, and the storeall artifact reproduces the saving session exactly"

    * -----------------------------------------------------------------------
    * ARM 5 -- the workflows that must keep working, run before anything
    * disturbs this session's engine.
    * -----------------------------------------------------------------------
    import delimited using "`data'", clear asdouble
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical pointwise notyet
    csdid_estat event
    tempname LIVE
    matrix `LIVE' = r(table)
    assert colsof(`LIVE') == `truth_k'
    forvalues j = 1/`truth_k' {
        ct_agrees `=`LIVE'[1, `j']' `=CT_TRUTH[1, `j']'
        ct_agrees `=`LIVE'[2, `j']' `=CT_TRUTH[2, `j']'
    }
    capture noisily csdid_stats, type(group)
    assert _rc == 0

    estimates store ct_live
    quietly summarize y
    estimates restore ct_live
    csdid_estat event
    tempname RESTORED
    matrix `RESTORED' = r(table)
    assert mreldif(`RESTORED', `LIVE') == 0
    display as text "test-cache-token-session: estimating then aggregating, and aggregating after estimates store/restore in the same session, are unchanged"

    * -----------------------------------------------------------------------
    * ARM 2 -- one session, two engines. `mata clear' discards the engine, the
    * next csdid builds another, and under the counter that second engine
    * handed out the token the first one had already used.
    *
    * BOTH runs start from a cleared Mata, which is what puts them in the same
    * position: each is the first estimation its engine ever numbered. Clearing
    * only between them would leave the saved run holding whatever number this
    * session had reached by then, and the arm would pass on the defect.
    * -----------------------------------------------------------------------
    mata: mata clear
    import delimited using "`data'", clear asdouble
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical pointwise notyet
    estimates store ct_first
    mata: mata clear
    import delimited using "`data'", clear asdouble
    quietly replace y = y * 10
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical pointwise notyet
    estimates restore ct_first
    tempname AFTERCLEAR
    tempfile clearlog
    log using "`clearlog'", replace text name(ctclear)
    capture noisily csdid_estat event
    local clear_rc = _rc
    if `clear_rc' == 0 matrix `AFTERCLEAR' = r(table)
    log close ctclear
    if `clear_rc' == 0 {
        display as error "test-cache-token-session: a second engine in the same session reissued the first engine's token"
        forvalues j = 1/`truth_k' {
            display as error "  column `j': se " %14.9f CT_TRUTH[2, `j'] " -> " %14.9f `AFTERCLEAR'[2, `j']
        }
    }
    assert `clear_rc' == 498
    ct_says using "`clearlog'", ///
        message("the stored results do not match the last csdid run")

    * -----------------------------------------------------------------------
    * ARM 3 -- the content check on trial by itself. The token is forced to the
    * saved run's value, so it matches; the unit count and the cell count match
    * because the two designs have the same shape. Everything the guard had
    * before this change now agrees, and the only thing left that can refuse is
    * the comparison of the ATT(g,t) table the cache was filled beside against
    * the one the caller is holding.
    * -----------------------------------------------------------------------
    import delimited using "`data'", clear asdouble
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical pointwise notyet
    estimates store ct_saved
    local saved_token = e(mata_cache_token)
    import delimited using "`data'", clear asdouble
    quietly replace y = y * 10
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(dripw) analytical pointwise notyet
    assert e(mata_cache_token) != `saved_token'
    assert e(N_units) == `restored_units' & e(N_attgt) == `restored_cells'
    mata: CSDID_ENGINE.token = `saved_token'
    estimates restore ct_saved
    tempname FORCED
    tempfile forcedlog
    log using "`forcedlog'", replace text name(ctforced)
    capture noisily csdid_estat event
    local forced_rc = _rc
    if `forced_rc' == 0 matrix `FORCED' = r(table)
    log close ctforced
    if `forced_rc' == 0 {
        display as error "test-cache-token-session: a colliding token was accepted on shape alone"
        forvalues j = 1/`truth_k' {
            display as error "  column `j': se " %14.9f CT_TRUTH[2, `j'] " -> " %14.9f `FORCED'[2, `j']
        }
    }
    assert `forced_rc' == 498
    ct_says using "`forcedlog'", ///
        message("the stored results do not match the last csdid run")
    display as text "test-cache-token-session: a second engine in one session does not reissue the first engine's token, and a token forced to collide is still refused on the ATT(g,t) table"

    * -----------------------------------------------------------------------
    * ARM 6 -- what the token base is NOT allowed to cost.
    *
    * A session-unique number is the kind of thing a random draw is usually
    * good for, and here it must not be one: Mata's generator IS the
    * bootstrap's generator, so a token that drew from it would advance the
    * stream once per engine and silently move every unseeded bootstrap in the
    * session. The base is built from a temporary filename and the clock
    * instead, and this arm is the measurement rather than the assurance.
    *
    * First directly: build an engine with nothing else running, and the
    * generator's state must be the same afterwards, character for character.
    * Then end to end: the same unseeded bootstrap from the same seed, once in
    * a session whose engine already exists and once in a session that builds
    * one immediately before, must produce the same draws to the bit.
    * -----------------------------------------------------------------------
    import delimited using "`data'", clear asdouble
    set seed 20260816
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(reg) notyet wboot(reps(40))
    tempname RNGDRAWS RNGATT
    matrix `RNGDRAWS' = e(boot_draws)
    matrix `RNGATT' = e(attgt)
    local rng_after "`c(rngstate)'"

    set seed 20260816
    local rng_before "`c(rngstate)'"
    mata: mata clear
    quietly _csdid_engine_load
    tempname ct_engine_probe
    mata: st_numscalar("`ct_engine_probe'", csdid_cache_agg_token())
    assert scalar(`ct_engine_probe') == 0
    assert "`c(rngstate)'" == "`rng_before'"

    import delimited using "`data'", clear asdouble
    csdid y x1 x2, ivar(id) time(time) gvar(g) method(reg) notyet wboot(reps(40))
    assert mreldif(e(boot_draws), `RNGDRAWS') == 0
    assert mreldif(e(attgt), `RNGATT') == 0
    assert "`c(rngstate)'" == "`rng_after'"
    display as text "test-cache-token-session: building an engine leaves the random-number state where it found it, and an unseeded bootstrap draws the same numbers on either side of one"

    display as text "test-cache-token-session passed"

}
local staged_rc = _rc
capture matrix drop CT_TRUTH
ct_stage_clean "`scratch'"
if `staged_rc' exit `staged_rc'
