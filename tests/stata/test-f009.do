* ---------------------------------------------------------------------------
* F009, fixture family anticipation: anticipation(0) and anticipation(1) on the
* same 300-row panel, merged 1:1 against R did 2.5.1's anticipation grid on
* (anticipation, group, time), ATT to 1e-10 and se to 1e-8. Anticipation moves
* the base period back and shrinks the usable comparison window, so the (3,3)
* cell under anticipation(1) is asserted on its own. A negative anticipation
* must exit 198: it is not a permitted lead, and accepting it would produce
* numbers with no estimand behind them.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

tempfile allactual
local first 1
foreach anticipation in 0 1 {
    import delimited using "`root'/tests/fixtures/parity/f009/inputs/input.csv", clear asdouble
    csdid y, ivar(id) time(time) gvar(g) method(reg) anticipation(`anticipation') analytical nevertreated base_period(varying) bal(none)
    matrix A = e(attgt)
    clear
    svmat double A, names(col)
    gen byte anticipation = `anticipation'
    rename (att se) (att_stata se_stata)
    keep anticipation group time event_time att_stata se_stata
    if `first' {
        save "`allactual'", replace
        local first 0
    }
    else {
        append using "`allactual'"
        save "`allactual'", replace
    }
}

import delimited using "`root'/tests/fixtures/parity/f009/expected/r/anticipation-grid.csv", clear asdouble
merge 1:1 anticipation group time using "`allactual'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
assert abs(se - se_stata) < 1e-8 if !missing(se) & !missing(se_stata)
assert abs(att - att_stata) < 1e-10 if anticipation == 1 & group == 3 & time == 3

import delimited using "`root'/tests/fixtures/parity/f009/inputs/input.csv", clear asdouble
capture noisily csdid y, ivar(id) time(time) gvar(g) anticipation(-1) analytical nevertreated base_period(varying) bal(none)
assert _rc == 198
