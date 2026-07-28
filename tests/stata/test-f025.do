version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define _f025_repost_csdid, eclass
    version 15
    ereturn matrix attgt = A
    ereturn matrix inffunc = IF
    ereturn matrix group_prob = GP
    ereturn matrix unit_group = UG
    ereturn local cmd "csdid"
end

tempfile actual part
local first 1

foreach scenario in dynamic_window dynamic_balance simple_maxe group_maxe calendar_ignored {
    import delimited using "`root'/tests/fixtures/parity/f025/inputs/input.csv", clear asdouble
    csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
    if "`scenario'" == "dynamic_window" {
        csdid_stats, type(dynamic) min_e(-1) max_e(0)
    }
    else if "`scenario'" == "dynamic_balance" {
        csdid_stats, type(dynamic) balance_e(1)
    }
    else if "`scenario'" == "simple_maxe" {
        csdid_stats, type(simple) max_e(0)
    }
    else if "`scenario'" == "group_maxe" {
        csdid_stats, type(group) max_e(0)
    }
    else if "`scenario'" == "calendar_ignored" {
        csdid_stats, type(calendar) min_e(-1) max_e(0) balance_e(1)
    }
    matrix M = e(aggte)
    preserve
    clear
    svmat double M, names(col)
    gen str32 scenario = "`scenario'"
    gen seq = _n
    save "`part'", replace
    restore
    if `first' {
        use "`part'", clear
        save "`actual'", replace
        local first 0
    }
    else {
        use "`actual'", clear
        append using "`part'"
        save "`actual'", replace
    }
}

import delimited using "`root'/tests/fixtures/parity/f025/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
matrix A = e(attgt)
matrix IF = e(inffunc)
matrix GP = e(group_prob)
matrix UG = e(unit_group)
matrix A[1,4] = .
matrix IF[1,1] = .
_f025_repost_csdid
capture noisily csdid_stats, type(dynamic)
assert _rc == 498
csdid_stats, type(dynamic) na_rm
matrix M = e(aggte)
preserve
clear
svmat double M, names(col)
gen str32 scenario = "dynamic_na_rm"
gen seq = _n
save "`part'", replace
restore
use "`actual'", clear
append using "`part'"
save "`actual'", replace

import delimited using "`root'/tests/fixtures/parity/f025/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
matrix A = e(attgt)
matrix IF = e(inffunc)
matrix GP = e(group_prob)
matrix UG = e(unit_group)
forvalues i = 1/`=rowsof(A)' {
    if A[`i',1] == 3 & A[`i',2] == 3 {
        matrix A[`i',4] = .
        forvalues r = 1/`=rowsof(IF)' {
            matrix IF[`r',`i'] = .
        }
    }
}
_f025_repost_csdid
csdid_stats, type(group) max_e(0) na_rm
matrix M = e(aggte)
preserve
clear
svmat double M, names(col)
gen str32 scenario = "group_na_rm_maxe"
gen seq = _n
save "`part'", replace
restore
use "`actual'", clear
append using "`part'"
save "`actual'", replace

rename (egt att se overall_att overall_se) ///
       (egt_stata att_stata se_stata overall_att_stata overall_se_stata)
sort scenario egt_stata
by scenario: replace seq = _n
save "`actual'", replace

import delimited using "`root'/tests/fixtures/parity/f025/expected/r/aggte-windows.csv", clear asdouble
sort scenario egt
by scenario: gen seq = _n
merge 1:1 scenario seq using "`actual'", nogen assert(match)
assert missing(egt) == missing(egt_stata) if missing(egt) | missing(egt_stata)
assert egt == egt_stata if !missing(egt) & !missing(egt_stata)
assert abs(att - att_stata) < 1e-10
assert abs(overall_att - overall_att_stata) < 1e-10
assert missing(se) == missing(se_stata) if missing(se) | missing(se_stata)
assert abs(se - se_stata) < 1e-10 if !missing(se) & !missing(se_stata)
assert missing(overall_se) == missing(overall_se_stata) if missing(overall_se) | missing(overall_se_stata)
assert abs(overall_se - overall_se_stata) < 1e-10 if !missing(overall_se) & !missing(overall_se_stata)
assert missing(egt) == missing(egt_stata) if missing(egt) | missing(egt_stata)
assert abs(egt - egt_stata) < 1e-10 if !missing(egt) & !missing(egt_stata)
