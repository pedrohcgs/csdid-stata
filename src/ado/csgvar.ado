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
	* Whether the user asked for a storage type has to be read off the command
	* line, the way egen reads it, and before `syntax' runs: `syntax
	* newvarname' fills `typlist' from `set type' when no type was given, so
	* afterwards "no type" and "float" are the same string. The default here
	* is double rather than `set type', because a cohort code is a value on
	* the time axis -- a %tc axis or an epoch second exceeds float's 24-bit
	* mantissa and would be rounded into a different treatment group.
	gettoken csg_first : 0, parse(" =")
	local csg_asked ""
	if inlist("`csg_first'", "byte", "int", "long", "float", "double") ///
		local csg_asked "`csg_first'"
	syntax newvarname =/exp [if] [in], tvar(varname) ivar(varname)
	if "`csg_asked'" == "" local typlist double
	_gcsgvar `typlist' `varlist' = (`exp') `if' `in', tvar(`tvar') ivar(`ivar')
end
