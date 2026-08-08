*! csgvar 2.0.0 30jul2026
* Cohort ("gvar") variable from a binary treatment indicator, command form.
*
* The implementation lives in _gcsgvar.ado, which is also Stata's egen entry
* point for `egen g = csgvar(treated), tvar() ivar()'. Forwarding is what
* keeps the two routes identical: they were previously the same 29 lines
* twice, so every guard and every message had to be fixed in both files or
* they diverged.
program csgvar, sortpreserve
	version 14
	syntax newvarname =/exp [if] [in], tvar(varname) ivar(varname)
	_gcsgvar `typlist' `varlist' = (`exp') `if' `in', tvar(`tvar') ivar(`ivar')
end
