version 15
clear
set more off
set seed 50505

set obs 720
generate long id = ceil(_n / 6)
bysort id: generate int year = _n
generate int first_treat = cond(id <= 35, 0, cond(id <= 75, 3, cond(id <= 105, 4, 5)))
generate double x1 = sin(id / 9)
generate double treated = first_treat > 0 & year >= first_treat
generate double y = 1 + .3 * x1 + .1 * year + .45 * treated + rnormal()

drop if mod(id, 16) == 0 & year == 2

csdid y x1, id(id) time(year) gvar(first_treat) allowunbalanced
csdid_stats event, window(-3 3)

csdid y x1, id(id) time(year) gvar(first_treat) baseperiod(universal)
estat event, window(-3 3)

csdid y x1, id(id) time(year) gvar(first_treat) storeall
matrix list e(attgt)
