* Migrating a Version 1.82 do-file.
*
* Each pair below shows a legacy spelling first -- which still runs, and says
* what it is -- and then the modern line that replaces it. Run the file and
* read the messages: the legacy lines are the ones that print something.

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

* ---------------------------------------------------------------------------
* 1. id() -> ivar(), and the unbalanced panel is now an explicit choice.
*
* id() is the Version 1.82 spelling of ivar() and is still accepted. The
* default for an unbalanced panel changed: 1.82 balanced each 2x2 silently,
* while 2.0.0 balances the whole panel with bal(full) and reports how many
* units that dropped. Say bal(none) to keep every unit, or bal(pair) to
* reproduce what 1.82 did.
* ---------------------------------------------------------------------------
csdid y x1, id(id) time(year) gvar(first_treat) bal(none)

csdid y x1, ivar(id) time(year) gvar(first_treat) bal(none)
csdid_stats event, window(-3 3)

* ---------------------------------------------------------------------------
* 2. long -> nothing to type.
*
* long and long2 asked for the legacy event-study layout, which they got by
* implying baseperiod(universal). That is now the default, so the modern line
* is the same command with the option removed. long still works and warns.
* ---------------------------------------------------------------------------
csdid y x1, ivar(id) time(year) gvar(first_treat) long

csdid y x1, ivar(id) time(year) gvar(first_treat)
estat event, window(-3 3)

* ---------------------------------------------------------------------------
* 3. never -> nevertreated, and it is no longer the default.
*
* never is the legacy spelling of nevertreated. It is not a no-op: 2.0.0
* defaults to the not-yet-treated comparison group, so asking for never-treated
* comparison units changes the comparison group and therefore the estimand.
* ---------------------------------------------------------------------------
csdid y x1, ivar(id) time(year) gvar(first_treat) never

csdid y x1, ivar(id) time(year) gvar(first_treat) nevertreated
display "comparison group: " e(control_group)

* ---------------------------------------------------------------------------
* 4. csdid_rif -> take the results as a dataset.
*
* storeall puts the influence functions in e() for custom work; estat attgt,
* saving() writes the ATT(g,t) table itself as a dataset you can table, merge
* or plot.
* ---------------------------------------------------------------------------
csdid y x1, ivar(id) time(year) gvar(first_treat) storeall
matrix list e(attgt)

tempfile attgt_results
estat attgt, saving("`attgt_results'") replace
preserve
    use "`attgt_results'", clear
    list in 1/5
restore
