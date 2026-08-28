* ---------------------------------------------------------------------------
* F008, fixture family control-group: the never-treated and not-yet-treated
* comparison groups estimated on the same panel and merged 1:1 against R did
* 2.5.1's control-group grid on (control_group, group, time), ATT to 1e-10 and
* se to 1e-8. Each arm NAMES its comparison group rather than leaning on the
* omitted-option default, so the test measures the option and not the default.
* e(control_group) is asserted per arm, and the (3,3) cell -- where the two
* control groups genuinely disagree -- is checked explicitly, so an arm that
* quietly estimated the other one's comparison set cannot pass.
* ---------------------------------------------------------------------------

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
    * The never-treated arm must name its comparison group rather than relying
    * on the omitted-option default, which is now not-yet-treated.
    local notyetopt "nevertreated"
    if "`control_group'" == "notyettreated" local notyetopt "notyet"
    csdid y, ivar(id) time(time) gvar(g) method(reg) `notyetopt' analytical base_period(varying) bal(none)
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
