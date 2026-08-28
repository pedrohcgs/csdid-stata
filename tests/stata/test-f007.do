* ---------------------------------------------------------------------------
* F007, fixture family base-period: base_period(varying) and base_period
* (universal) are estimated on the same 192-row panel, stacked, and merged 1:1
* against R did 2.5.1's base-period grid on (base_period, group, time) -- so
* the two arms are pinned both to the oracle and, implicitly, to differing from
* each other exactly where R differs. ATT to 1e-10, se to 1e-8. The file closes
* by requiring base_period(bad) to exit 198 rather than falling through to a
* default, which would make the option look supported and silently ignored.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

tempfile allactual
local first 1
foreach base_period in varying universal {
    import delimited using "`root'/tests/fixtures/parity/f007/inputs/input.csv", clear asdouble
    csdid y, ivar(id) time(time) gvar(g) method(reg) base_period(`base_period') analytical nevertreated bal(none)
    matrix A = e(attgt)
    clear
    svmat double A, names(col)
    gen str12 base_period = "`base_period'"
    rename (att se) (att_stata se_stata)
    keep base_period group time event_time att_stata se_stata
    if `first' {
        save "`allactual'", replace
        local first 0
    }
    else {
        append using "`allactual'"
        save "`allactual'", replace
    }
}

import delimited using "`root'/tests/fixtures/parity/f007/expected/r/base-period-grid.csv", clear asdouble
merge 1:1 base_period group time using "`allactual'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
assert abs(se - se_stata) < 1e-8 if !missing(se) & !missing(se_stata)

import delimited using "`root'/tests/fixtures/parity/f007/inputs/input.csv", clear asdouble
capture noisily csdid y, ivar(id) time(time) gvar(g) base_period(bad) analytical nevertreated bal(none)
assert _rc == 198
