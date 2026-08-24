version 14
clear
set more off
set seed 30303

set obs 1200
generate int year = 1 + mod(_n - 1, 6)
generate int cohort = ceil(_n / 200)
generate int first_treat = cond(cohort <= 2, 0, cond(cohort <= 4, 3, 5))
generate double x1 = rnormal() + year / 10
generate double x2 = runiform()
generate double w = .75 + runiform()
generate double treated = first_treat > 0 & year >= first_treat
generate double y = 1 + .3 * x1 + .2 * x2 + .1 * year + .5 * treated + rnormal()

csdid y x1 x2 [iw=w], time(year) gvar(first_treat) method(ipw)
csdid_stats group
csdid_stats calendar
