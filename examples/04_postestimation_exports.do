version 14
clear
set more off
set seed 40404

set obs 600
generate long id = ceil(_n / 5)
bysort id: generate int year = _n
generate int first_treat = cond(id <= 40, 0, cond(id <= 75, 3, 4))
generate double x1 = sin(id / 10) + year / 10
generate double x2 = cos(id / 12)
generate double treated = first_treat > 0 & year >= first_treat
generate double y = 1 + .2 * x1 - .1 * x2 + .1 * year + .4 * treated + rnormal()

tempfile rif tidy glance plotdata

csdid y x1 x2, id(id) time(year) gvar(first_treat) saverif("`rif'") replace
estat event, window(-2 3) post
estat tidy, saving("`tidy'") replace
estat glance, saving("`glance'") replace

csdid_stats using "`rif'", type(dynamic) window(-2 3) dropmissing
csdid_plot, saving("`plotdata'") replace
