* An analytical aggregation's simultaneous band is bootstrapped from the
* session's random-number stream, so set seed reproduces it -- and storeall,
* which only decides where the influence functions are kept, must not move
* it. The default path puts the cached influence functions in the draw order
* before drawing; the storeall path drew over the stored matrix as it stands,
* so the same seed assigned the multipliers to different units and reported a
* different band. Clustered designs were never affected (cluster sums do not
* depend on row order). Balanced panel, unbalanced panel under bal(none), and
* repeated cross sections.
version 15
clear all
set more off
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local mpdta "`root'/examples/data/mpdta.csv"

foreach design in bal unbal rcs {
    local crit_lean = .
    foreach st in "" storeall {
        import delimited using "`mpdta'", clear asdouble varnames(1)
        local opts "ivar(countyreal)"
        if "`design'" == "unbal" {
            drop if mod(countyreal, 7) == 0 & year == 2005
            local opts "ivar(countyreal) bal(none)"
        }
        if "`design'" == "rcs" local opts ""
        quietly csdid lemp lpop, `opts' time(year) gvar(first_treat) method(dr) notyet analytical `st'
        set seed 11
        quietly csdid_stats event
        assert e(agg_cband) == 1
        local crit = e(crit_val)
        display as text "`design' [`st']: crit " %20.17f `crit'
        if "`st'" == "" local crit_lean = `crit'
        else assert `crit' == `crit_lean'
    }
}

display as text "test-analytical-band-storage: storeall leaves the analytical band where set seed put it"
