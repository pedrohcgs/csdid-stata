*! tsvmat 2.0.0 30jul2026

*capture program drop tsvmat
program define tsvmat, return
    * DEPRECATED in csdid 2.0.0. Shipped only so existing do-files keep
    * running; it is not covered by the parity suite and will be removed in
    * a future release. Replacement: no replacement; it was never part of the documented surface.
    display as text "note: tsvmat is deprecated and will be removed in a future release of csdid; see {help csdid_legacy}"

        version 7
        syntax anything, name(string)
		 
        local nx = rowsof(matrix(`anything'))
        local nc = colsof(matrix(`anything'))
        ***************************************
        // here is where the safegards will be done.
        if _N<`nx' {
            display as result "Expanding observations to `nx'"
                set obs `nx'
        }
        // here we create all variables
        foreach i in `name' {
			local j = `j'+1
			qui:gen `type' `i'=matrix(`anything'[_n,`j'])			
        }
        // here is where they are renamed.

end
