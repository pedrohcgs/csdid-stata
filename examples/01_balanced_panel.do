version 15
clear
set more off
set seed 10101

set obs 720
generate long id = ceil(_n / 6)
bysort id: generate int year = _n
generate int first_treat = cond(id <= 35, 0, cond(id <= 70, 3, cond(id <= 100, 4, 5)))
generate double x1 = sin(id / 9) + year / 10
generate double x2 = cos(id / 13) + mod(id, 4) / 4
generate double treated = first_treat > 0 & year >= first_treat
generate double y = 1 + .25 * x1 - .15 * x2 + .08 * year + .45 * treated + rnormal()

csdid y x1 x2, id(id) time(year) gvar(first_treat)
estat event, window(-3 3)
csdid_stats simple
