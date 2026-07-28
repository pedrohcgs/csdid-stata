version 15
clear
set more off
set seed 20202

set obs 900
generate long id = ceil(_n / 6)
bysort id: generate int year = _n
generate int first_treat = cond(id <= 45, 0, cond(id <= 90, 3, cond(id <= 125, 4, 5)))
generate int state = mod(id, 15) + 1
generate double w = .5 + mod(id, 7) / 6 + year / 30
generate double x1 = sin(id / 11) + year / 8
generate double x2 = cos(id / 17) + mod(id, 3)
generate double treated = first_treat > 0 & year >= first_treat
generate double y = 2 + .2 * x1 - .1 * x2 + .05 * year + .35 * treated + rnormal()

drop if mod(id, 19) == 0 & inlist(year, 2, 5)
drop if mod(id, 23) == 0 & year == 4

tempfile plotdata

csdid y x1 x2 [iw=w], id(id) time(year) gvar(first_treat) method(dr) vce(cluster state)
csdid_stats event, window(-3 3) dropmissing
csdid_plot, saving("`plotdata'") replace
