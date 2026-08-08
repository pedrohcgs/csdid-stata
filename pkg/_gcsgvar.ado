*! _gcsgvar 2.0.0 30jul2026
* Cohort ("gvar") variable from a binary treatment indicator.
*
* This file holds the single implementation. `_g<name>' is Stata's egen entry
* point, so this is what `egen g = csgvar(treated), tvar() ivar()' dispatches
* to; csgvar.ado is the command form and forwards here, so the two routes
* cannot drift. (They used to be the same 29 lines twice, differing only in
* the program name, with the help asserting a call relationship that did not
* exist in either direction.)
program _gcsgvar, sortpreserve
	version 14
	syntax newvarname =/exp [if] [in], tvar(varname) ivar(varname)
	local exp = subinstr("`exp'","(","",.)
	local exp = subinstr("`exp'",")","",.)
	tempvar touse
	qui:gen byte `touse'=0
	qui:replace `touse'=1 `if' `in'
	qui:replace `touse'=0 if `tvar'==. | `ivar'==. | `exp'==.

	tempvar vals
	bys `touse' `exp' : gen byte `vals' = (_n == 1) * `touse'
	su `vals' if `touse', meanonly
	local csg_n = r(sum)
	* r(sum) is MISSING when no observation is in the sample, and in Stata
	* missing > 2 is true, so an empty or all-missing sample used to be
	* reported as a value-count problem it does not have.
	if mi(`csg_n') | `csg_n' == 0 {
		display as error "no observations: `exp', `tvar' and `ivar' are jointly missing on every observation in the sample"
		exit 2000
	}
	if `csg_n' > 2 {
		* Was: `display in r "display More than 2 values..."' -- the word
		* `display' was inside the string, so the user read "display More
		* than 2 values detected in treated." -- followed by `error 4444',
		* a code Stata has no message for. 459 is the code the rest of the
		* package uses when the DATA violates a property the command
		* requires, and it is documented in help csdid_legacy.
		display as error "`exp' takes `csg_n' distinct values in the selected sample; csgvar needs a treatment indicator taking at most two, with 0 for the untreated state"
		exit 459
	}
	* The command's semantics live entirely in the `replace ... if `exp'==0'
	* below: that line, and only that line, is what makes a never-treated
	* unit come out as cohort 0. A two-valued indicator coded {1,2}, {-1,1}
	* or {1,2} from a recoded factor passed the count guard, never triggered
	* that line, and every unit came back with a positive cohort -- a gvar
	* with no never-treated units at all, handed straight to csdid, which
	* then silently coerced the latest treated cohort into the comparison
	* group. Silent wrong sample, rc 0.
	*
	* The requirement is NOT that the values be {0,1}: {0,5} works correctly
	* today and legacy do-files may rely on it. What is required is that the
	* untreated state be coded 0, so that is what is checked.
	if `csg_n' == 2 {
		tempvar csg_expv
		qui generate double `csg_expv' = `exp' if `touse'
		qui levelsof `csg_expv' if `touse', local(csg_vals)
		local csg_haszero 0
		foreach csg_v of local csg_vals {
			if `csg_v' == 0 local csg_haszero 1
		}
		if !`csg_haszero' {
			display as error "`exp' takes the two values `csg_vals' in the selected sample, neither of which is 0. csgvar reads 0 as the untreated state, so with this coding every unit would be given a positive cohort and the result would have no never-treated units. Recode the untreated state to 0 -- for example -generate byte treat01 = (`exp' == `: word 2 of `csg_vals'')- -- and rerun."
			exit 459
		}
	}
	qui: {
		tempvar aux
		bysort `touse' `ivar' `exp':egen `aux'=min(`tvar')
		replace `aux'=0 if `exp'==0
		by     `touse' `ivar':egen `varlist'=max(`aux')
		replace `varlist'=. if `exp'==. | !`touse'
	}

	label var `varlist' "Group Variable based on `exp'"
end
