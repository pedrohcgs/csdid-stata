version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

tempfile allactual
local first 1
foreach control_group in nevertreated notyettreated {
    import delimited using "`root'/tests/fixtures/parity/f008/inputs/input.csv", clear asdouble
    local notyetopt ""
    if "`control_group'" == "notyettreated" local notyetopt "notyet"
    csdid y, ivar(id) time(time) gvar(g) method(reg) `notyetopt' analytical
    assert "`e(control_group)'" == "`control_group'"
    matrix A = e(attgt)
    clear
    svmat double A, names(col)
    gen str16 control_group = "`control_group'"
    rename (att se) (att_stata se_stata)
    keep control_group group time event_time att_stata se_stata
    if `first' {
        save "`allactual'", replace
        local first 0
    }
    else {
        append using "`allactual'"
        save "`allactual'", replace
    }
}

import delimited using "`root'/tests/fixtures/parity/f008/expected/r/control-group-grid.csv", clear asdouble
merge 1:1 control_group group time using "`allactual'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
assert abs(se - se_stata) < 1e-8 if !missing(se) & !missing(se_stata)
assert abs(att - att_stata) < 1e-10 if control_group == "notyettreated" & group == 3 & time == 3
