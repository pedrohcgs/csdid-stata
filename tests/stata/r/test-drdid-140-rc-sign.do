* RT075: corrected pre-period OR influence signs, through all three RC routes.
* Each scenario compares every cell and influence entry, the covariance and
* Wald test, and all four aggregations. The 2x2 derivative target is independent
* of the R influence formula. Seeded chains keep R's aggregation call order.
version 15
clear all
set more off
set linesize 200
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt075"
foreach metric in att se if v agg wald crit fd {
    scalar RT075_max_`metric' = 0
    scalar RT075_n_`metric' = 0
}

mata:
void rt075_compare(real matrix actual, real matrix expected, real scalar tolerance, string scalar metric)
{
    real matrix valid, delta
    real scalar worst, absolute
    if (rows(actual) != rows(expected) | cols(actual) != cols(expected)) {
        errprintf("RT075 dimensions: actual %g x %g, reference %g x %g\n", rows(actual), cols(actual), rows(expected), cols(expected))
        _error(9)
    }
    if (any((actual :>= .) :!= (expected :>= .))) {
        errprintf("RT075 missing-value patterns differ\n")
        _error(9)
    }
    valid = expected :< .
    delta = select(vec(abs(actual - expected) :/ (1 :+ abs(expected))), vec(valid))
    worst = rows(delta) ? max(delta) : 0
    if (metric != "") {
        absolute = rows(delta) ? max(select(vec(abs(actual - expected)), vec(valid))) : 0
        st_numscalar("RT075_max_" + metric, max((st_numscalar("RT075_max_" + metric), absolute)))
        st_numscalar("RT075_n_" + metric, st_numscalar("RT075_n_" + metric) + sum(valid))
    }
    if (worst > tolerance) {
        errprintf("RT075 max scaled difference %21.15g exceeds %g\n", worst, tolerance)
        _error(9)
    }
}
end

program define rt075_matrix
    version 15
    syntax using/, MATRIX(name) [TOLERANCE(real 1e-8) KEYS(name) METRIC(string)]
    preserve
    import delimited using "`using'", clear asdouble varnames(1)
    if "`keys'" != "" {
        mata: rt075_compare(st_matrix("`keys'")[., 1], st_data(., "unit"), 0, "")
    }
    unab vars : v*
    mata: rt075_compare(st_matrix("`matrix'"), st_data(., tokens("`vars'")), `tolerance', "`metric'")
    restore
end

program define rt075_cells
    version 15
    syntax using/
    tempname A
    matrix `A' = e(attgt)
    preserve
    import delimited using "`using'", clear asdouble varnames(1)
    mata: rt075_compare(st_matrix("`A'")[., (1, 2)], st_data(., ("group", "time")), 0, "")
    mata: rt075_compare(st_matrix("`A'")[., 4], st_data(., "att"), 1e-10, "att")
    mata: rt075_compare(st_matrix("`A'")[., 5], st_data(., "se"), 1e-10, "se")
    restore
end

program define rt075_diagnostics
    version 15
    syntax using/, SCENARIO(string) [BOOT]
    local has_wald 0
    capture confirm scalar e(wald_stat)
    if !_rc {
        local has_wald 1
        local wald = e(wald_stat)
        local pvalue = e(wald_pvalue)
    }
    local crit = e(crit_val)
    preserve
    import delimited using "`using'", clear asdouble varnames(1)
    keep if scenario == "`scenario'"
    assert _N == 1
    assert missing(wald) == !`has_wald'
    if `has_wald' {
        assert abs(`wald' - wald) <= 1e-10 * (1 + abs(wald))
        assert abs(`pvalue' - pvalue) <= 1e-10 * (1 + abs(pvalue))
        mata: rt075_compare((`wald', `pvalue'), st_data(., ("wald", "pvalue")), 1e-10, "wald")
    }
    assert abs(`crit' - crit) <= 1e-10 * (1 + abs(crit))
    mata: rt075_compare(`crit', st_data(., "crit"), 1e-10, "crit")
    restore
end

program define rt075_aggs
    version 15
    syntax, FIXTURE(string) STEM(string) [USINGFILE(string) BOOT]
    foreach type in dynamic group calendar simple {
        if "`usingfile'" == "" quietly csdid_stats, type(`type')
        else quietly csdid_stats using "`usingfile'", type(`type')
        tempname A IF
        matrix `A' = e(aggte)
        matrix `IF' = e(agg_inffunc)
        rt075_matrix using "`fixture'/expected/r/`stem'-`type'.csv", matrix(`A') tolerance(1e-10) metric(agg)
        * The saved RIF loader may keep its unit map in a different stored
        * result, so the original run checks the key and the saved run checks
        * every already-ordered influence value.
        rt075_matrix using "`fixture'/expected/r/`stem'-`type'-if.csv", matrix(`IF') metric(if)
        if "`boot'" != "" {
            local crit = e(crit_val)
            preserve
            import delimited using "`fixture'/expected/r/`stem'-`type'-crit.csv", clear asdouble varnames(1)
            assert _N == 1
            assert abs(`crit' - crit) <= 1e-10 * (1 + abs(crit))
            mata: rt075_compare(`crit', st_data(., "crit"), 1e-10, "crit")
            restore
        }
    }
end

import delimited using "`fx'/inputs/scenarios.csv", clear asdouble varnames(1)
assert _N == 39
tempfile specs
save `specs'
local cases = _N
forvalues k = 1/`cases' {
    use `specs', clear
    local scenario = scenario[`k']
    local route = route[`k']
    local input = input[`k']
    local weight = weight[`k']
    local base = base[`k']
    local control = control[`k']
    local method = method[`k']
    local boot = bootstrap[`k']
    local cluster ""
    if cluster[`k'] local cluster "cluster(cl)"
    local wt ""
    if "`weight'" != "none" local wt "[iw=`weight']"
    local panel ""
    if "`route'" == "unbal" local panel "ivar(id) bal(none)"
    if "`route'" == "vary" local panel "ivar(id) fix_weights(varying)"
    local ctrl ""
    if "`control'" == "nevertreated" local ctrl "nevertreated"
    local opts "time(time) gvar(g) method(`method') base_period(`base') `ctrl' `panel' `cluster' storeall"
    import delimited using "`fx'/inputs/`input'.csv", clear asdouble varnames(1)
    tempfile rif
    local saveopt ""
    if `boot' local saveopt "saverif(`rif') replace"
    quietly csdid y x x2 `wt', `opts' analytical pointwise `saveopt'
    rt075_cells using "`fx'/expected/r/`scenario'-attgt.csv"
    tempname IF UG V
    matrix `IF' = e(inffunc)
    matrix `UG' = e(unit_group)
    matrix `V' = e(V)
    rt075_matrix using "`fx'/expected/r/`scenario'-if.csv", matrix(`IF') keys(`UG') metric(if)
    rt075_matrix using "`fx'/expected/r/`scenario'-v.csv", matrix(`V') metric(v)
    rt075_diagnostics using "`fx'/expected/r/diagnostics.csv", scenario("`scenario'")
    rt075_aggs, fixture("`fx'") stem("`scenario'")
    if `boot' {
        * Saved artifacts carry the corrected IF into a fresh engine state.
        csdid reset
        rt075_aggs, fixture("`fx'") stem("`scenario'") usingfile("`rif'")
        import delimited using "`fx'/inputs/`input'.csv", clear asdouble varnames(1)
        quietly csdid y x x2 `wt', `opts' rseed(20261025) reps(199)
        rt075_cells using "`fx'/expected/r/`scenario'_boot-attgt.csv"
        matrix `IF' = e(inffunc)
        matrix `UG' = e(unit_group)
        rt075_matrix using "`fx'/expected/r/`scenario'_boot-if.csv", matrix(`IF') keys(`UG') metric(if)
        rt075_diagnostics using "`fx'/expected/r/diagnostics.csv", scenario("`scenario'_boot") boot
        rt075_aggs, fixture("`fx'") stem("`scenario'_boot") boot
    }
    display as text "RT075 `scenario': every ATT/IF/V/Wald and all four aggregations match"
}

* A second source of evidence: numerical observation-weight derivatives of
* the ATT, extrapolated from h=.01 and h=.005 independently of either IF.
foreach weight in none w wzero {
    import delimited using "`fx'/inputs/finite-difference.csv", clear asdouble varnames(1)
    generate double weight = 1
    if "`weight'" != "none" replace weight = w
    if "`weight'" == "wzero" replace weight = 0 if mod(_n, 11) == 0
    tempname IF
    mata: rt075_fit = csdid__dr_rc_fit(st_data(., "y"), st_data(., "post"), st_data(., "d"), (J(st_nobs(), 1, 1), st_data(., ("x", "x2"))), st_data(., "weight"), 1)
    mata: st_matrix("`IF'", rt075_fit[2::(st_nobs() + 1)])
    import delimited using "`fx'/expected/r/finite-difference.csv", clear asdouble varnames(1)
    keep if weight == "`weight'"
    assert _N == 8
    mata: rt075_compare(st_matrix("`IF'")[st_data(., "row")], st_data(., "if_value"), 1e-8, "if")
    mata: rt075_compare(st_matrix("`IF'")[st_data(., "row")], st_data(., "derivative"), 1e-8, "fd")
}

foreach metric in att se if v agg wald crit fd {
    display as text "RT075 max |d`metric'| = " %21.15g scalar(RT075_max_`metric') " across " %12.0f scalar(RT075_n_`metric') " values"
}

display as text "test-drdid-140-rc-sign: 39 adversarial scenarios, six seeded chains and saved-RIF roundtrips, independent IF derivatives match"
