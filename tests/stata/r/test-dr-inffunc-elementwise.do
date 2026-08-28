* ---------------------------------------------------------------------------
* rt035: the covariate-adjusted DR influence functions, element by element,
* against R did 2.5.1 on the two routes that share the repeated-cross-section
* kernel -- a genuine repeated cross section and an unbalanced panel on the
* allow-unbalanced route. Cell-level ATT/SE parity cannot see a defect that
* leaves the point estimate unchanged while corrupting the influence
* function (a sign flip inside one estimation-effect correction, for
* example): this file pins the inference chain -- analytic SEs, clustering,
* the multiplier bootstrap, every aggregation -- at its source. The R
* oracle's repeated-cross-section influence-function rows are keyed by
* original row index in att_gt's rownames, not data order; the generator
* re-sorts them into data order, so the comparison here is plain
* row-by-row. Reference matrices from
* tools/parity/generators/rt035/generate.R.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

local fixture "`root'/tests/fixtures/parity/rt035"
confirm file "`fixture'/inputs/dr-rcs.csv"
confirm file "`fixture'/expected/r/rcs-inffunc.csv"
confirm file "`fixture'/expected/r/unbalanced-inffunc.csv"

program define rt035_assert_if_matches_r
    version 15
    syntax, EXPECTED(string) [UNITKEYED]

    tempname IFS
    matrix `IFS' = e(inffunc)
    preserve
    import delimited using "`expected'", clear asdouble
    assert _N == rowsof(`IFS')
    local kcols = colsof(`IFS')
    local sign_flips 0
    local worst = 0
    forvalues j = 1/`kcols' {
        capture confirm variable if`j'
        assert _rc == 0
        forvalues i = 1/`=_N' {
            local rv = if`j'[`i']
            local sv = `IFS'[`i', `j']
            if !missing(`rv') | !missing(`sv') {
                assert !missing(`rv') & !missing(`sv')
                local dev = abs(`rv' - `sv') / (1 + abs(`rv'))
                if `dev' > `worst' local worst = `dev'
                if sign(`rv') != sign(`sv') & abs(`rv') > 1e-8 local ++sign_flips
            }
        }
    }
    assert `worst' < 1e-8
    assert `sign_flips' == 0
    restore
end

* --- route 1: genuine repeated cross section, covariates, method(dr)
import delimited using "`fixture'/inputs/dr-rcs.csv", clear asdouble
quietly csdid y x1 x2, time(t) gvar(g) method(dr) nevertreated base_period(varying) analytical pointwise storeall
tempname A
matrix `A' = e(attgt)
preserve
import delimited using "`fixture'/expected/r/rcs-attgt.csv", clear asdouble
forvalues i = 1/`=_N' {
    local found 0
    forvalues r = 1/`=rowsof(`A')' {
        if `A'[`r', 1] == group[`i'] & `A'[`r', 2] == time[`i'] {
            assert abs(`A'[`r', 4] - att[`i']) <= 1e-10 + 1e-10 * abs(att[`i'])
            assert abs(`A'[`r', 5] - se[`i']) <= 1e-8 + 1e-8 * abs(se[`i'])
            local found 1
        }
    }
    assert `found' == 1
}
restore
rt035_assert_if_matches_r, expected("`fixture'/expected/r/rcs-inffunc.csv")

* --- route 2: unbalanced panel, allow-unbalanced (bal(none)) route
import delimited using "`fixture'/inputs/dr-unbalanced.csv", clear asdouble
quietly csdid y x1 x2, ivar(id) time(t) gvar(g) method(dr) nevertreated base_period(varying) analytical pointwise bal(none) storeall
rt035_assert_if_matches_r, expected("`fixture'/expected/r/unbalanced-inffunc.csv") unitkeyed

display as text "test-dr-inffunc-elementwise: covariate DR influence functions match R element by element on the RCS and allow-unbalanced routes"
