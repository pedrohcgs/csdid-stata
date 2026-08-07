clear all
set more off
* rebuild part 2/3's small panel state
set seed 20260805
quietly set obs 200
generate long id = _n
quietly generate byte gtrue = cond(mod(_n, 4) == 0, 0, 3 + mod(_n, 3))
quietly generate double a_i = rnormal()
quietly expand 6
quietly bysort id: generate byte t = _n
quietly generate byte d = (gtrue > 0 & t >= gtrue)
quietly generate double y = a_i + 0.25*t + d*(1 + 0.3*(t - gtrue)) + rnormal()
xtset id t

* A: usercohort on the FULL balanced panel, never = missing
quietly generate double gm = cond(gtrue == 0, ., gtrue)
capture quietly xthdidregress ra (y) (d), group(id) usercohort(gm)
display "A full panel, never=missing:  rc = " _rc

* B: full panel, never = 0
capture quietly xthdidregress ra (y) (d), group(id) usercohort(gtrue)
display "B full panel, never=0:        rc = " _rc

* C: one row deleted (unit 1, t=4), never = missing
quietly drop if id == 1 & t == 4
capture quietly xthdidregress ra (y) (d), group(id) usercohort(gm)
display "C deleted row, never=missing: rc = " _rc

* D: deleted row, never = 0
capture quietly xthdidregress ra (y) (d), group(id) usercohort(gtrue)
display "D deleted row, never=0:       rc = " _rc

* E: deleted row, usercohort = the DERIVED cohort (should match default)
gencohort gder, treat(d) time(t) group(id)
capture quietly xthdidregress ra (y) (d), group(id) usercohort(gder)
display "E deleted row, derived:       rc = " _rc
