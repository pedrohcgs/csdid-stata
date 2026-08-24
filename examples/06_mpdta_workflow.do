version 14
clear all
set more off

local datafile "`c(pwd)'/examples/data/mpdta.csv"
capture confirm file "`datafile'"
if _rc {
    local datafile "`c(pwd)'/data/mpdta.csv"
}
confirm file "`datafile'"

import delimited using "`datafile'", clear asdouble

csdid lemp lpop, id(countyreal) time(year) gvar(first_treat)
estat event, window(-3 3)

csdid_stats simple
csdid_stats group
csdid_stats calendar
csdid_stats event, window(-3 3) dropmissing

tempfile mpdta_plot
csdid_plot, saving("`mpdta_plot'") replace
confirm file "`mpdta_plot'"
