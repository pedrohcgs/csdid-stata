* F053 -- saving() on every estat subcommand.
*
* Owner-directed contract: saving() is how Stata writes a result to a file, so
* it is an option on the thing being computed rather than a separate export
* command. Every subcommand takes it, and each writes the result it displayed.
*
* Before this, saving() worked on tidy and glance only. estat attgt refused it,
* and the five aggregation subcommands PARSED it and then ignored it -- so
* `estat event, saving(f)' returned rc 0 and wrote no file. Silence is the
* failure mode this test exists to prevent, so every assertion below checks
* that a file was actually written and that its contents are the right ones.
*
* tidy and glance keep working and are undocumented. They are pinned here
* against the new spellings so the two paths cannot drift apart.

* Note: Stata appends .dta only to names without an extension. tempfile names
* look like St12345.000001, so the dot reads as an extension and nothing is
* appended -- always refer to the bare macro, never `macro'.dta.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f053_assert_same
    version 15
    * Two saved datasets must agree on shape, variable names and every value.
    syntax , LEFT(string) RIGHT(string)

    use "`left'", clear
    quietly describe
    local n_l = r(N)
    local k_l = r(k)
    quietly ds
    local vars "`r(varlist)'"
    rename * l_*
    generate long _row = _n
    tempfile lhs
    quietly save "`lhs'"

    use "`right'", clear
    quietly describe
    assert r(N) == `n_l'
    assert r(k) == `k_l'
    quietly ds
    assert "`r(varlist)'" == "`vars'"

    generate long _row = _n
    quietly merge 1:1 _row using "`lhs'", nogen assert(match)
    foreach v of local vars {
        capture confirm numeric variable `v'
        if !_rc {
            assert (`v' == l_`v') | (missing(`v') & missing(l_`v'))
        }
        else {
            assert `v' == l_`v'
        }
    }
end

import delimited using "`root'/tests/fixtures/parity/f053/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical ///
    nevertreated base_period(varying) bal(none)

* -----------------------------------------------------------------------
* 1. estat attgt, saving() writes the ATT(g,t) table, and writes the same
*    file estat tidy writes when no aggregation is active.
* -----------------------------------------------------------------------
tempfile via_attgt via_tidy
quietly estat attgt, saving("`via_attgt'") replace
confirm file "`via_attgt'"
quietly estat tidy, saving("`via_tidy'") replace
f053_assert_same, left("`via_attgt'") right("`via_tidy'")

* The file must actually hold the cells, not merely exist.
use "`via_attgt'", clear
confirm variable estimate
assert _N > 0
quietly count if !missing(estimate)
assert r(N) == _N

* -----------------------------------------------------------------------
* 2. Each aggregation writes the aggregation it displayed. Before this
*    change every one of these returned rc 0 and wrote nothing.
* -----------------------------------------------------------------------
foreach agg in event dynamic simple group calendar {
    import delimited using "`root'/tests/fixtures/parity/f053/inputs/input.csv", clear asdouble
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical ///
        nevertreated base_period(varying) bal(none)

    tempfile out_`agg' tidy_`agg'
    quietly estat `agg', saving("`out_`agg''") replace
    * The file exists at all -- this is the assertion the old behaviour failed.
    confirm file "`out_`agg''"

    * And it carries the same aggregation estat tidy would export next.
    quietly estat tidy, saving("`tidy_`agg''") replace
    f053_assert_same, left("`out_`agg''") right("`tidy_`agg''")

    use "`out_`agg''", clear
    assert _N > 0
}

* -----------------------------------------------------------------------
* 3. attgt still refuses the options that were accepted and then ignored.
* -----------------------------------------------------------------------
import delimited using "`root'/tests/fixtures/parity/f053/inputs/input.csv", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical ///
    nevertreated base_period(varying) bal(none)
foreach bad in "post" "window(-2 2)" "level(90)" "dropmissing" {
    capture estat attgt, `bad'
    assert _rc == 198
}

* With no saving() it redisplays, as before.
capture estat attgt
assert _rc == 0

* -----------------------------------------------------------------------
* 4. tidy and glance keep working. They are undocumented, not removed.
* -----------------------------------------------------------------------
tempfile still_tidy still_glance
capture quietly estat tidy, saving("`still_tidy'") replace
assert _rc == 0
confirm file "`still_tidy'"
capture quietly estat glance, saving("`still_glance'") replace
assert _rc == 0
confirm file "`still_glance'"

use "`still_glance'", clear
assert _N == 1

display as text "test-f053 passed"
