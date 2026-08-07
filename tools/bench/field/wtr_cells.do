* Can wtr() isolate individual ATT(g,t) cells from did_imputation?
* Truth for cell (g,t) is (g-2) + 0.5*(t-g).
clear all
set more off
quietly do "simdgp.do"
quietly sim_dgp, n(4000) seed(90001) regime(balanced)

quietly {
    gen double c33 = 0
    gen double c45 = 0
    gen double c57 = 0
    * one indicator per (g,t) cell, normalised to average within the cell
    foreach spec in 3_3 4_5 5_7 {
        local g = substr("`spec'",1,1)
        local t = substr("`spec'",3,1)
        count if gvar==`g' & time==`t'
        local n = r(N)
        replace c`g'`t' = 1/`n' if gvar==`g' & time==`t'
    }
}
di "--- cell sizes and weight totals ---"
foreach v in c33 c45 c57 {
    quietly summarize `v', meanonly
    di "   `v' sums to " %6.4f r(sum)
}
di ""
di "--- did_imputation with cell-isolating wtr() ---"
capture noisily did_imputation y id time gvar_miss, wtr(c33 c45 c57) autosample
matrix W = r(table)
local cw : colnames W
foreach pair in tau_c33:1.0 tau_c45:2.5 tau_c57:4.0 {
    local nm = substr("`pair'",1,strpos("`pair'",":")-1)
    local tr = substr("`pair'",strpos("`pair'",":")+1,.)
    local p : list posof "`nm'" in cw
    if `p' > 0 di "   `nm'  est=" %9.5f W[1,`p'] "   truth=`tr'   diff=" %9.5f W[1,`p']-`tr'
}
