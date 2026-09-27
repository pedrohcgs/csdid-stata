*! csdid_table 2.0.0 27sep2026
program csdid_table, rclass
	version 14
    * DEPRECATED in csdid 2.0.0. Shipped only so existing do-files keep
    * running; it is not covered by the parity suite and will be removed in
    * a future release. Replacement: the table csdid prints directly, or estat tidy, saving().

	* level(), noci, cformat() and sformat() were parsed and then never
	* consulted: the table's number formats are hardcoded below, the CI
	* columns are always printed, and the bounds come from e(cband), which
	* was banded at whatever level csdid was run with. So `csdid_table,
	* level(90)' printed "[90% conf. interval]" over bounds computed at some
	* other level -- silently mislabelled numbers, which is worse than a
	* refused option. This command is frozen, so the honest form is to refuse
	* what it cannot honour rather than accept and drop it.
	* level() is parsed as a string so that an EXPLICIT level() -- even one
	* equal to the session default, which an int-with-default parse cannot
	* distinguish from omission -- is refused as the help promises
	* (cold-audit N1). The numeric value used below stays c(level), and the
	* cband branches overwrite it with e(level) provenance where stored.
	* CSDIDRIFCALL is internal: csdid_rif redisplays through this command, and
	* its user already saw csdid_rif's own deprecation note
	syntax [, Level(string) noci cformat(string) sformat(string) CSDIDRIFCALL *]
	if "`csdidrifcall'" == "" {
		display as text "note: csdid_table is deprecated and will be removed in a future release of csdid; see {help csdid_legacy}"
	}
	local ct_bad ""
	if `"`level'"' != "" local ct_bad "`ct_bad' level()"
	local level = c(level)
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
	* The refusal above already tells the user this table belongs to csdid
	* or csdid_rif; the code now enforces what the message promises
	* (cold-audit LEG-6). Without this, any e-class result carrying an e(b)
	* was reformatted as a csdid table -- plausible numbers under the wrong
	* headline.
	if !inlist("`e(cmd)'", "csdid", "csdid_rif") {
		display as error "csdid_table displays csdid or csdid_rif results; the estimates in memory are from `e(cmd)'. Run csdid or csdid_rif first, then csdid_table."
		exit 459
	}
*set trace on
	_get_diopts diopts rest, `options'
	* anything that is not a display option was dropped without a word
	if `"`rest'"' != "" {
		display as error `"csdid_table does not take: `rest'"'
		exit 198
	}

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
        tempname ct_b ct_v ct_se ct_crit ctb ctv ct_sep
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
			* The stored bounds were computed at e(level); the header must
			* say so even when c(level) has changed since (cold-audit
			* LEG-2). csdid_rif posts e(level) for exactly this read.
			if !missing(e(level)) local level = e(level)
		}
		else {
			* Rebuilt from the same quantities csdid itself printed: e(b), the
			* square root of the e(V) diagonal, and e(crit_val) -- the critical
			* value csdid used for its own bands, so these bounds are the bounds
			* csdid reported. The header level follows e(level) for the same
			* reason: a band drawn at e(level) must not be captioned c(level).
			* e(crit_val) is whatever the last aggregation left there, so
			* ATT(g,t) cells are banded where csdid_plot and estat tidy read
			* their band: e(boot_attgt)'s crit_val, else the normal quantile at
			* e(level). A posted aggregation keeps e(crit_val) for its effects,
			* and its overall column is banded pointwise at e(agg_level), as
			* estat prints it.
			local ct_first : word 1 of `namelist'
			local ct_attgt = ("`e(cmd)'" == "csdid" & regexm("`ct_first'", "^(g.*___|att_[0-9]+$)"))
			local ct_agg = ("`e(cmd)'" == "csdid" & !`ct_attgt')
			matrix `ctb' = e(b)
			matrix `ctv' = e(V)
			scalar `ct_crit' = .
			if `ct_attgt' {
				capture confirm matrix e(boot_attgt)
				if !_rc {
					tempname ct_ba
					matrix `ct_ba' = e(boot_attgt)
					local ct_cc = colnumb(`ct_ba', "crit_val")
					if !missing(`ct_cc') scalar `ct_crit' = `ct_ba'[1, `ct_cc']
				}
			}
			else if `ct_agg' {
				* the band recorded when these coefficients were posted: a
				* later aggregation overwrites e(crit_val) and e(agg_level)
				capture confirm scalar e(post_crit_val)
				if _rc {
					display as error "csdid_table cannot tell which band the posted aggregation was reported with; redisplay it with estat `e(agg_type)', post"
					exit 459
				}
				scalar `ct_crit' = e(post_crit_val)
			}
			else scalar `ct_crit' = e(crit_val)
			local ct_point = .
			if `ct_agg' local ct_point = e(post_point_crit_val)
			if missing(`ct_crit') {
				local ct_level = e(level)
				if `ct_agg' local ct_level = e(post_level)
				if missing(`ct_level') local ct_level = `level'
				scalar `ct_crit' = invnormal(1 - (100 - `ct_level') / 200)
			}
			if !missing(e(level)) local level = e(level)
			if `ct_agg' local level = e(post_level)
			matrix `cimat' = J(`k', 5, .)
			forvalues i = 1/`k' {
				local ct_name : word `i' of `namelist'
				local ct_c = `ct_crit'
				if inlist("`ct_name'", "Post_avg", "Overall", "ATT") & !missing(`ct_point') local ct_c = `ct_point'
				scalar `ct_b'  = `ctb'[1,`i']
				scalar `ct_v'  = `ctv'[`i',`i']
				* a coefficient posted with variance 0 has no standard error
				* (the reference period, a cell whose SE is missing): missing,
				* as estat reports it, not a zero-width interval
				scalar `ct_se' = cond(!missing(`ct_v') & `ct_v' > 0, sqrt(`ct_v'), .)
				matrix `cimat'[`i',1] = `ct_b'
				matrix `cimat'[`i',2] = `ct_se'
				matrix `cimat'[`i',3] = cond(!missing(`ct_se') & `ct_se' > 0, `ct_b'/`ct_se', .)
				matrix `cimat'[`i',4] = `ct_b' - `ct_c' * `ct_se'
				matrix `cimat'[`i',5] = `ct_b' + `ct_c' * `ct_se'
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
        * the level as a number reads, not its binary expansion: 90.1, not
        * 90.09999999999999
        local level : display %9.0g `level'
        local level = strtrim("`level'")
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
				* the column r(table) carries, not _se[], which prints 0 for
				* a coefficient posted with variance 0
				scalar `ct_sep' = `cimat'[`i',2]
                .`mytab'.row    "`name'"                ///
                                `beq'_b[`name']         ///
                                `ct_sep'                ///
                                `t'                     /// `p'  ///
                                `ll' `ul'
        }
        .`mytab'.sep, bottom
		return matrix table = `rtab'
end
