*! csdid_table 2.0.0 24aug2026
program csdid_table, rclass
	version 14
    * DEPRECATED in csdid 2.0.0. Shipped only so existing do-files keep
    * running; it is not covered by the parity suite and will be removed in
    * a future release. Replacement: the table csdid prints directly, or estat tidy, saving().
    display as text "note: csdid_table is deprecated and will be removed in a future release of csdid; see {help csdid_legacy}"

	* level(), noci, cformat() and sformat() were parsed and then never
	* consulted: the table's number formats are hardcoded below, the CI
	* columns are always printed, and the bounds come from e(cband), which
	* was banded at whatever level csdid was run with. So `csdid_table,
	* level(90)' printed "[90% conf. interval]" over bounds computed at some
	* other level -- silently mislabelled numbers, which is worse than a
	* refused option. This command is frozen, so the honest form is to refuse
	* what it cannot honour rather than accept and drop it.
	syntax [, level(int `c(level)') noci cformat(string) sformat(string) *]
	local ct_bad ""
	if `level' != `c(level)' local ct_bad "`ct_bad' level()"
	if "`ci'" != "" local ct_bad "`ct_bad' noci"
	if `"`cformat'"' != "" local ct_bad "`ct_bad' cformat()"
	if `"`sformat'"' != "" local ct_bad "`ct_bad' sformat()"
	if "`ct_bad'" != "" {
		display as error "csdid_table is a frozen Version 1.82 helper and does not honour:`ct_bad'. Its confidence bounds come from e(cband) at the level csdid was run with, and its number formats are fixed. Use the table csdid prints, or estat tidy, saving(), for control over either."
		exit 198
	}
	* Every column below is read out of e(b) -- the coefficient names, the
	* column count, the coefficients themselves. With no e(b) there is nothing
	* to tabulate, and each subscript would resolve to missing under a filled-in
	* header: a table of blanks labelled as results.
	capture confirm matrix e(b)
	if _rc {
		display as error "csdid_table found no coefficients to tabulate: e(b) does not exist. Run csdid or csdid_rif first, then csdid_table."
		exit 459
	}
*set trace on
	_get_diopts diopts rest, `options'

	local cf %9.0g  
	local pf %5.3f
	local sf %7.2f

	if ("`cformat'"!="") {
			local cf `cformat'
	}
	if ("`sformat'"!="") {
			local sf `sformat'
	}
***hack to get max
 local namelist : colname e(b)
 local wdt=0
 foreach i of local namelist {
 	if length("`i'")>`wdt' local wdt = length("`i'")+3
 }
 if `wdt'<15 local wdt = 12
***
        tempname mytab z t  ll ul cimat rtab
        tempname ct_b ct_v ct_se ct_crit ctb ctv
        .`mytab' = ._tab.new, col(6) lmargin(0)
        .`mytab'.width    `wdt'   |12    12     8         12    12
        .`mytab'.titlefmt  .     .     .   %6s       %24s     .
        .`mytab'.pad       .     2     1     0          3     3
        .`mytab'.numfmt    . %9.0g %9.0g %7.2f    %9.0g %9.0g
        /*if "`e(df_r)'" != "" {
                local stat t
                scalar `z' = invttail(e(df_r),(100-`level')/200)
        }
        else {
                local stat z
                scalar `z' = invnormal((100+`level')/200)
        }*/
		
		local stat t 
		
        local namelist : colname e(b)
        local eqlist : coleq e(b)
        local k : word count `namelist'
		local knew = `k'
		matrix `rtab' = J(9, `k', .)
		* `cimat' is k x 5: b, se, t, ll, ul. It comes straight out of e(cband)
		* only where e(cband) IS that matrix -- the csdid_rif weighted-bootstrap
		* route, which is what this frozen helper was written against. csdid
		* 2.0.0 posts e(cband) as a SCALAR flag, so reading it as a matrix gave a
		* 1x1 object and every subscript past row 1 resolved to missing: blank t
		* and confidence-interval columns and an all-missing r(table), at rc 0.
		* The branch keys on the TYPE of e(cband), not on which command ran, so
		* both routes keep working.
		capture confirm matrix e(cband)
		if _rc == 0 {
			matrix `cimat' = e(cband)
		}
		else {
			* Rebuilt from the same quantities csdid itself printed: e(b), the
			* square root of the e(V) diagonal, and e(crit_val) -- the critical
			* value csdid used for its own bands, so these bounds are the bounds
			* csdid reported. The header level follows e(level) for the same
			* reason: a band drawn at e(level) must not be captioned c(level).
			matrix `ctb' = e(b)
			matrix `ctv' = e(V)
			scalar `ct_crit' = e(crit_val)
			if missing(`ct_crit') {
				local ct_level = e(level)
				if missing(`ct_level') local ct_level = `level'
				scalar `ct_crit' = invnormal(1 - (100 - `ct_level') / 200)
			}
			if !missing(e(level)) local level = e(level)
			matrix `cimat' = J(`k', 5, .)
			forvalues i = 1/`k' {
				scalar `ct_b'  = `ctb'[1,`i']
				scalar `ct_v'  = `ctv'[`i',`i']
				scalar `ct_se' = cond(!missing(`ct_v') & `ct_v' >= 0, sqrt(`ct_v'), .)
				matrix `cimat'[`i',1] = `ct_b'
				matrix `cimat'[`i',2] = `ct_se'
				matrix `cimat'[`i',3] = cond(!missing(`ct_se') & `ct_se' > 0, `ct_b'/`ct_se', .)
				matrix `cimat'[`i',4] = `ct_b' - `ct_crit' * `ct_se'
				matrix `cimat'[`i',5] = `ct_b' + `ct_crit' * `ct_se'
			}
		}
		* pvalue
		matrix rownames `rtab' = b se t p ll ul df crit eform
		matrix colnames `rtab' = `namelist'
		forvalues i = 1/`k' {
		    local kxc: word `i' of `eqlist'
			if ("`kxc'"=="wgt") {
				local knew = `knew' -1
			}
			matrix `rtab'[1,`i'] = `cimat'[`i',1]
			matrix `rtab'[2,`i'] = `cimat'[`i',2]
			matrix `rtab'[3,`i'] = `cimat'[`i',3]
			matrix `rtab'[5,`i'] = `cimat'[`i',4]
			matrix `rtab'[6,`i'] = `cimat'[`i',5]
			matrix `rtab'[9,`i'] = 0
		}
        .`mytab'.sep, top
        if `:word count `e(depvar)'' == 1 {
                local depvar "`e(depvar)'"
        }
        .`mytab'.titles "`depvar'"                      /// 1
                        " Coefficient"                  /// 2
                        "Std. err."                     /// 3
                        "`stat'"                        /// 4   "P>|`stat'|"                    /// 5
                        "[`level'% conf. interval]" ""  //  6 7
						
        forvalues i = 1/`knew' {
                local name : word `i' of `namelist'
                local eq   : word `i' of `eqlist'
                if ("`eq'" != "_") {
                        if "`eq'" != "`eq0'" {
                                .`mytab'.sep
                                local eq0 `"`eq'"'
                                .`mytab'.strcolor result  .  .  .  .    .
                                .`mytab'.strfmt    %-12s  .  .  .  .    .
                                .`mytab'.row      "`eq'" "" "" "" ""  ""
                                .`mytab'.strcolor   text  .  .  .  .    .
                                .`mytab'.strfmt     %12s  .  .  .  .    .
                        }
                        local beq "[`eq']"
                }
                else if `i' == 1 {
                        local eq
                        .`mytab'.sep
                }
                scalar `t' = `cimat'[`i',3]
                /*if "`e(df_r)'" != "" {
                        scalar `p' = 2*ttail(e(df_r),abs(`t'))
                }*/
                *scalar `p' = 2*normal(-abs(`t'))
				
				scalar `ll'   = `cimat'[`i',4]
				scalar `ul'   = `cimat'[`i',5]
                .`mytab'.row    "`name'"                ///
                                `beq'_b[`name']         ///
                                `beq'_se[`name']        ///
                                `t'                     /// `p'  ///
                                `ll' `ul'
        }
        .`mytab'.sep, bottom
		return matrix table = `rtab'
end
