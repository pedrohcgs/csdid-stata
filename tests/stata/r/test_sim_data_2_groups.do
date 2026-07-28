* RT031: inherit R did tests/testthat/test_sim_data_2_groups.R
*
* Upstream asserts an invariance rather than a value: with only two groups (one
* treated cohort plus never-treated), the never-treated and not-yet-treated
* control sets coincide, so all four combinations of control group x base period
* must agree, and the first post-treatment cell must recover the true effect
* of 3. Upstream checks that loosely (tol .1 against truth, .0001 across
* specifications) because it has no external reference.
*
* We inherit the scenario and compare against R's own ATT and SE, which is the
* stronger claim: it pins the numbers, not just their agreement. The invariance
* is asserted as well, so a change that broke it would fail here even if every
* specification drifted together.
version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

confirm file "`root'/tests/fixtures/parity/rt031/inputs/two-groups.csv"
confirm file "`root'/tests/fixtures/parity/rt031/expected/r/attgt.csv"

tempfile actual
tempname A

capture program drop rt031_run
program define rt031_run
    args tag ctrl bp
    local root "`c(pwd)'"
    quietly import delimited using "`root'/tests/fixtures/parity/rt031/inputs/two-groups.csv", clear asdouble
    local opts ""
    if "`ctrl'" == "notyet" local opts "notyet"
    quietly csdid y, ivar(id) time(t) gvar(g) method(reg) base_period(`bp') `opts' analytical
end

* collect every specification into one long file keyed by spec/group/time
quietly {
    clear
    set obs 0
    gen str16 spec = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`actual'", replace emptyok
}

foreach s in "nt_varying nevertreated varying" "nt_universal nevertreated universal" ///
             "nyt_varying notyet varying" "nyt_universal notyet universal" {
    local tag  : word 1 of `s'
    local ctrl : word 2 of `s'
    local bp   : word 3 of `s'
    rt031_run "`tag'" "`ctrl'" "`bp'"
    matrix `A' = e(attgt)
    local nr = rowsof(`A')
    preserve
    quietly {
        clear
        set obs `nr'
        gen str16 spec = "`tag'"
        gen double group = .
        gen double time = .
        gen double att_stata = .
        gen double se_stata = .
        forvalues i = 1/`nr' {
            replace group     = `A'[`i',1] in `i'
            replace time      = `A'[`i',2] in `i'
            replace att_stata = `A'[`i',4] in `i'
            replace se_stata  = `A'[`i',5] in `i'
        }
        append using "`actual'"
        save "`actual'", replace
    }
    restore
}

* compare against R
import delimited using "`root'/tests/fixtures/parity/rt031/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 spec group time using "`actual'", assert(match) nogen

quietly count
assert r(N) == 14

quietly gen double d_att = abs(att - att_stata)
quietly gen double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-10
quietly summarize d_se, meanonly
assert r(max) < 1e-10

* the upstream invariance: all four specifications agree on the post cell
quietly levelsof att_stata if group == 3 & time == 3, local(posts)
local nposts : word count `posts'
assert `nposts' == 1

* and it recovers the true effect of 3, as upstream requires
quietly summarize att_stata if group == 3 & time == 3, meanonly
assert abs(r(mean) - 3) < .1

display "RT031 OK: 14 cells x 4 specifications match R to <1e-10; invariance holds"
