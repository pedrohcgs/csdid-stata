* RT050 -- the aggregation simultaneous band keeps a column whose bootstrap
* scale is positive but at or below sqrt(epsilon)*10. R's aggregation band
* drops a column only on its sum of squared draws and divides by its IQR scale
* as it stands; only the ATT(g,t) band blanks a small scale. Event time 2 is
* supported by a two-unit cohort whose never-treated comparisons differ by
* about 1e-9, so at seed 1 the band draws of that column have a scale of a few
* 1e-10, the column dominates the sup-t maximum, and the critical value is very
* large with a warning. Seed 2 is the ordinary case. Both engines.
version 15
clear all
set more off
set linesize 250
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt050"

import delimited using "`fx'/expected/r/aggte_crit.csv", clear asdouble varnames(1)
assert _N == 2
forvalues i = 1/2 {
    local seed`i' = seed[`i']
    local crit`i' = crit_val[`i']
    local warn`i' = very_large_warning[`i']
}
assert `warn1' == 1 & `warn2' == 0

import delimited using "`fx'/inputs/small_scale_column.csv", clear asdouble varnames(1)
foreach eng in plugin mata {
    if "`eng'" == "mata" global CSDID_BOOT_PLUGIN_DISABLE 1
    else global CSDID_BOOT_PLUGIN_DISABLE
    forvalues i = 1/2 {
        quietly csdid y, ivar(id) time(t) gvar(g) method(reg) never ///
            base_period(universal) rseed(`seed`i'') reps(1000)
        tempfile lg
        log using "`lg'", text replace name(rt050)
        estat event
        log close rt050
        local crit = e(crit_val)
        * seed 1 is a ratio over a scale of a few 1e-10: the draws' rounding
        * reaches it at a relative 3e-6, so TOL003 applies there
        local tol = cond(`warn`i'', 5e-4, 1e-10)
        display as text "RT050 `eng' seed `seed`i'': crit " %21.15g `crit' "  R " %21.15g `crit`i''
        assert reldif(`crit', `crit`i'') < `tol'
        tempname fh
        local body ""
        file open `fh' using "`lg'", read text
        file read `fh' line
        while r(eof) == 0 {
            local body `"`body' `line'"'
            file read `fh' line
        }
        file close `fh'
        assert (strpos(`"`body'"', "simultaneous critical value is very large") > 0) == `warn`i''
    }
}
global CSDID_BOOT_PLUGIN_DISABLE

display as text "test-agg-band-small-scale: the aggregation band follows R on a small-scale column"
