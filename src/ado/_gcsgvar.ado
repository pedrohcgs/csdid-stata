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
	* The cohort code is a value on the TIME axis, so it is computed in double
	* and only then stored in the type the caller asked for. Both intermediate
	* egens used to take egen's default type, which is float: a %tc axis or an
	* epoch second exceeds float's 24-bit mantissa, so a cohort code above
	* 16,777,216 was rounded on the way through and the rounded gvar was what
	* the user handed to csdid. `typlist' was parsed and then discarded --
	* `egen double g = csgvar(...)' produced a float -- so there was no way to
	* ask for anything else either. The store follows the _gmean.ado idiom:
	* build in a tempvar, `generate `typlist'' into the caller's variable.
	qui: {
		tempvar aux csg_gvar
		bysort `touse' `ivar' `exp': egen double `aux' = min(`tvar')
		replace `aux' = 0 if `exp' == 0
		by     `touse' `ivar': egen double `csg_gvar' = max(`aux')
		replace `csg_gvar' = . if `exp' == . | !`touse'
		generate `typlist' `varlist' = `csg_gvar'
	}

	* Honouring the type means saying so when it cannot be honoured. A narrow
	* type that rounds the cohort code is the failure this whole block is
	* about, and it must not be the quiet one: the rounded gvar goes straight
	* into csdid, where it is a wrong estimation sample reported with rc 0.
	quietly count if `varlist' != `csg_gvar'
	local csg_lost = r(N)
	if `csg_lost' > 0 {
		* On the egen route `varlist' is egen's own temporary and goes when
		* this program does; on the command route it is the user's new
		* variable, and a refusal must not leave a half-made one behind.
		capture drop `varlist'
		* Under egen dispatch `varlist' holds egen's internal tempvar, not the
		* name the user typed, so the message names no variable at all rather
		* than print __000000 at the user.
		display as error "the cohort code does not fit in a `typlist' variable: `csg_lost' value(s) would be rounded, and a rounded cohort is a different treatment group. Ask for a wider type: egen double gvar = csgvar(...), or csgvar double gvar = ..., and rerun"
		exit 198
	}

	label var `varlist' "Group Variable based on `exp'"
end
