* Every finite positive standard error survives outcome rescaling.
* Exactly zero or nonfinite inference remains unavailable.
version 15
clear all
set more off
set linesize 250
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local mpdta "`root'/examples/data/mpdta.csv"

import delimited using "`mpdta'", clear asdouble varnames(1)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
matrix A0 = e(attgt)
local c_se = colnumb(A0, "se")

* Every standard error scales with the outcome.
import delimited using "`mpdta'", clear asdouble varnames(1)
quietly replace lemp = lemp * 1e-4
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
matrix A4 = e(attgt)
forvalues i = 1/`=rowsof(A0)' {
    if !missing(A0[`i', `c_se']) assert reldif(A4[`i', `c_se'], 1e-4 * A0[`i', `c_se']) < 1e-8
}

* Small outcome units retain every standard error and the covariance pattern.
foreach scale in 1e-6 1e-10 1e-100 {
    import delimited using "`mpdta'", clear asdouble varnames(1)
    quietly replace lemp = lemp * `scale'
    quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical pointwise
    matrix AS = e(attgt)
    forvalues i = 1/`=rowsof(A0)' {
        assert missing(AS[`i', `c_se']) == missing(A0[`i', `c_se'])
        if !missing(A0[`i', `c_se']) assert abs(AS[`i', `c_se']/`scale' - A0[`i', `c_se']) < 1e-8
    }
    quietly csdid_stats event
    matrix AG=e(aggte)
    assert !missing(AG[1,5])
}
display as text "test-small-scale-se: finite positive standard errors survive outcome rescaling"
