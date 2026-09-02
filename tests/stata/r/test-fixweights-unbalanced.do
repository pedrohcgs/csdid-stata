* ---------------------------------------------------------------------------
* RT038 -- fix_weights() must not be inert on the one route that skipped it.
*
* fix_weights(base) freezes each unit's weight at the base period and DROPS the
* units that period does not observe. That drop applies whether or not a weight
* variable was supplied: the weight defaults to 1, and the per-unit lookup
* still fails for a unit that is absent from the target period.
*
* On an unbalanced panel with method(reg), no covariates, no weights and the
* never-treated comparison group, the cells took a four-means closed form that
* does not implement the lookup at all, so the drop never happened. The table
* that came back was complete and plausible -- all six controls, no warning --
* and simply answered a different question. Every neighbouring combination (any
* covariate, any weight, notyettreated, method(dr), method(ipw)) routes to the
* fitted path and already agreed, which is why nothing else in the suite saw it.
*
* Both channels are checked. The numbers alone cannot tell the two samples
* apart at a glance, so the warning is compared too.
* ---------------------------------------------------------------------------
version 15
clear all
set more off
set linesize 250

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local FX "`root'/tests/fixtures/parity/rt038"

program define fw_log_count, rclass
    version 15
    syntax using/, PHRASE(string)
    tempname fh
    local body ""
    file open `fh' using "`using'", read text
    file read `fh' line
    while r(eof) == 0 {
        * Stata wraps log lines; join them so a phrase split across the wrap
        * is still found, and strip the continuation marker it inserts.
        local l = strtrim(`"`macval(line)'"')
        if substr(`"`l'"', 1, 2) == "> " local l = substr(`"`l'"', 3, .)
        local body `"`body' `l'"'
        file read `fh' line
    }
    file close `fh'
    local n = 0
    local rest `"`body'"'
    local p = strpos(`"`rest'"', `"`phrase'"')
    while `p' > 0 {
        local ++n
        local rest = substr(`"`rest'"', `p' + length(`"`phrase'"'), .)
        local p = strpos(`"`rest'"', `"`phrase'"')
    }
    return scalar count = `n'
end

* -- run the fixture design ---------------------------------------------
import delimited using "`FX'/inputs/panel.csv", clear asdouble varnames(1)
quietly count
assert r(N) == 35

tempfile lg
log using "`lg'", text replace name(fw1)
quietly csdid y, ivar(id) time(t) gvar(g) method(reg) nevertreated ///
    analytical bal(none) fixweights(base)
log close fw1

assert "`e(fix_weights)'" == "base_period"
matrix A = e(attgt)
assert rowsof(A) == 3

* -- channel 1: the ATT(g,t) values ------------------------------------
preserve
import delimited using "`FX'/expected/r/attgt.csv", clear asdouble varnames(1)
quietly count
assert r(N) == 3
local ncmp = 0
forvalues i = 1/3 {
    local rg = group[`i']
    local rt = time[`i']
    local ra = att[`i']
    local rs = se[`i']
    * find the matching row of e(attgt) rather than assuming the order
    local hit = 0
    forvalues j = 1/3 {
        if A[`j', 1] == `rg' & A[`j', 2] == `rt' {
            local hit = `j'
        }
    }
    assert `hit' > 0
    assert reldif(A[`hit', 4], `ra') < 1e-10 | (missing(A[`hit', 4]) & missing(`ra'))
    if !missing(`rs') {
        assert reldif(A[`hit', 5], `rs') < 1e-10
        local ++ncmp
    }
    else assert missing(A[`hit', 5])
}
* the normalised base cell carries no se, so exactly two rows compare one
assert `ncmp' == 2
restore

* -- channel 2: the drop announced itself, as many times as it happened -
fw_log_count using "`lg'", phrase("not observed in base_period")
local got = r(count)
preserve
import delimited using "`FX'/expected/r/warnings.csv", clear varnames(1)
local want = n_drop_warnings[1]
restore
assert `want' == 2
assert `got' == `want'

* -- and the sample that produced them: the absent unit is gone from the
*    control side of every cell whose base period it misses ---------------
assert A[1, 8] == 5
assert A[3, 8] == 5

display as text "test-fixweights-unbalanced: fix_weights drops the unit and says so, on the reg route too"
