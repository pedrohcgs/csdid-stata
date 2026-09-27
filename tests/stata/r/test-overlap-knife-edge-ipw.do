* RT053 -- method(ipw) without covariates at a treated share inside the
* knife-edge band below the overlap cut (4994/4999 = 0.9989998). R defers to
* a fit whose fitted value is the share and passes the overlap guard, for ipw
* as for dr. csdid's classifier took the maximum over the empty design ipw
* without covariates passes, got missing, and refused every such cell as an
* overlap violation: with pscoretrim(1) dr estimated and ipw refused, and at
* the default trim ipw named the wrong cause.
version 15
clear all
set more off
set linesize 250
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt053"

import delimited using "`fx'/expected/r/attgt.csv", clear asdouble varnames(1) stringcols(1 2)
assert _N == 4
assert overlap_check_fail == 0
assert missing(att) if route == "att_gt"
forvalues i = 1/4 {
    if route[`i'] == "drdid" local r_`=method[`i']' = att[`i']
}

foreach m in ipw dr {
    foreach trim in "" "pscoretrim(1)" {
        import delimited using "`fx'/inputs/knife_edge_share.csv", clear asdouble varnames(1)
        tempfile lg
        log using "`lg'", text replace name(rt053)
        capture noisily csdid y, ivar(id) time(t) gvar(g) method(`m') nevertreated ///
            base_period(universal) analytical `trim'
        log close rt053
        tempname fh
        local body ""
        file open `fh' using "`lg'", read text
        file read `fh' line
        while r(eof) == 0 {
            local body `"`body' `line'"'
            file read `fh' line
        }
        file close `fh'
        matrix A = e(attgt)
        local att = A[2, colnumb(A, "att")]
        assert strpos(`"`body'"', "overlap condition violated") == 0
        if "`trim'" == "" {
            assert missing(`att')
            assert strpos(`"`body'"', "no effective comparison mass") > 0
        }
        else {
            display as text "RT053 `m' pscoretrim(1): att " %20.17f `att' "  DRDID " %20.17f `r_`m''
            assert reldif(`att', `r_`m'') < 1e-10
        }
    }
}

display as text "test-overlap-knife-edge-ipw: ipw and dr classify the knife-edge cell as R does"
