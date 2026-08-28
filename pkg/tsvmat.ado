*! tsvmat 2.0.0 28aug2026

*capture program drop tsvmat
program define tsvmat, return
        * 14 is the package floor; nothing else in csdid runs under an older
        * interpreter, so nothing here may promise one.
        version 14
    * DEPRECATED in csdid 2.0.0. Shipped only so existing do-files keep
    * running; it is not covered by the parity suite and will be removed in
    * a future release. Replacement: no replacement; it was never part of the documented surface.
    display as text "note: tsvmat is deprecated and will be removed in a future release of csdid; see {help csdid_legacy}"

        syntax anything, name(string)
		 
        local nx = rowsof(matrix(`anything'))
        local nc = colsof(matrix(`anything'))
        ***************************************
        // here is where the safegards will be done.
        * EVERY refusal fires before the dataset changes (cold-audit LEG-3):
        * the legacy code appended observations and generated the early
        * columns before a bad or colliding name stopped it, leaving the
        * data partly rewritten under a nonzero return. Asking for more
        * names than the matrix has columns is refused for the same reason;
        * fewer names than columns keeps the legacy meaning (the extra
        * columns are simply not materialized).
        if `: word count `name'' > `nc' {
            display as error "name() lists `: word count `name'' names but the matrix has only `nc' columns"
            exit 198
        }
        local _tsv_seen ""
        foreach i in `name' {
            confirm new variable `i'
            if `: list i in _tsv_seen' {
                display as error "name() lists `i' more than once"
                exit 198
            }
            local _tsv_seen "`_tsv_seen' `i'"
        }
        if _N<`nx' {
            display as text "Expanding observations to `nx'"
                set obs `nx'
        }
        // here we create all variables
        * double, not `set type': a Stata matrix holds doubles, so anything
        * narrower silently truncates the values this command exists to carry
        * into the data. (The type used to be read from an undeclared `type'
        * macro, which expanded to nothing, so every run produced floats.)
        local j 0
        foreach i in `name' {
			local j = `j'+1
			qui:gen double `i'=matrix(`anything'[_n,`j'])
        }
        // here is where they are renamed.

end
