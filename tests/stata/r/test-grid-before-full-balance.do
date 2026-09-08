* RT040: full balancing retains the reference's already fixed cohort grid.
* Every cell, IF entry, sample key and aggregation verdict/value is compared.
* Default reference refusals remain refusals; no slow-only grid is substituted.
version 15
clear all
set more off
set linesize 240
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt040"
scalar rt040_maxatt = 0
scalar rt040_maxse = 0
scalar rt040_maxif = 0
scalar rt040_maxagg = 0
scalar rt040_natt = 0
scalar rt040_nif = 0
scalar rt040_nagg = 0
scalar rt040_nverdict = 0
scalar rt040_nrefused = 0

import delimited using "`fx'/expected/r/attgt.csv", clear asdouble
isid scenario group time
assert _N == 269
import delimited using "`fx'/expected/r/inffunc.csv", clear asdouble
isid scenario unit_index group time
assert _N == 8180
import delimited using "`fx'/expected/r/sample.csv", clear asdouble
isid scenario id time
assert _N == 3620
import delimited using "`fx'/expected/r/aggte.csv", clear asdouble
isid scenario type na_rm seq
assert _N == 372
import delimited using "`fx'/expected/r/aggregation_status.csv", clear asdouble
isid scenario type na_rm
assert _N == 256
import delimited using "`fx'/expected/r/meta.csv", clear asdouble
isid scenario
assert _N == 32

mata:
void rt040_compare_if()
{
    real matrix a, inf, ref
    real scalar i, j, unit, want, got, gap, worst
    real colvector hit
    a = st_matrix("A")
    inf = st_matrix("IF")
    ref = st_data(., ("unit_index", "group", "time", "value"))
    assert(rows(ref) == rows(inf) * cols(inf))
    worst = 0
    for (i = 1; i <= rows(ref); i++) {
        unit = ref[i, 1]
        hit = selectindex((a[., 1] :== ref[i, 2]) :& (a[., 2] :== ref[i, 3]))
        assert(rows(hit) == 1)
        j = hit[1]
        assert(unit >= 1 & unit <= rows(inf))
        want = ref[i, 4]
        got = inf[unit, j]
        assert((want >= .) == (got >= .))
        if (want >= .) continue
        gap = abs(got - want)
        assert(gap <= 1e-8 + 1e-8 * abs(want))
        worst = max((worst, gap))
    }
    st_numscalar("rt040_maxif", max((st_numscalar("rt040_maxif"), worst)))
    st_numscalar("rt040_nif", st_numscalar("rt040_nif") + rows(ref))
}
end

program define rt040_log_has, rclass
    version 15
    syntax using/, MESSAGE(string)
    tempname fh
    local found 0
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        if strpos(`"`macval(line)'"', `"`message'"') local found 1
        file read `fh' line
    }
    file close `fh'
    return scalar found = `found'
end

import delimited using "`fx'/inputs/scenarios.csv", clear asdouble
isid scenario
assert _N == 60
levelsof scenario, local(scenarios)
tempfile scenario_table actual_sample refusal_log
save "`scenario_table'", replace
foreach mode in auto off {
    foreach s of local scenarios {
        use "`scenario_table'", clear
        keep if scenario == "`s'"
        assert _N == 1
        local options = stata_options[1]
        local refused = refused[1] == "TRUE"
        local covars ""
        if covariate[1] == "TRUE" local covars "x"
        local weight ""
        if weighted[1] == "TRUE" local weight "[iw=w]"
        local route ""
        if "`mode'" == "off" local route "nofast"
        import delimited using "`fx'/inputs/`s'.csv", clear asdouble
        if `refused' {
            quietly regress y id
            tempname prior_b
            matrix `prior_b' = e(b)
            log using "`refusal_log'", text replace name(rt040refusal)
            capture noisily csdid y `covars' `weight', ivar(id) time(time) gvar(g) method(reg) ///
                `options' `route' analytical pointwise storeall
            local actual_rc = _rc
            log close rt040refusal
            assert `actual_rc' == 459
            assert "`e(cmd)'" == "regress"
            mata: assert(mreldif(st_matrix("e(b)"), st_matrix("`prior_b'")) == 0)
            rt040_log_has using "`refusal_log'", message("bal(full) removed every unit from treated cohort(s)")
            assert r(found)
            preserve
            import delimited using "`fx'/expected/r/estimation_status.csv", clear asdouble
            keep if scenario == "`s'"
            assert _N == 1
            assert failed == 1
            assert strpos(message, "not found in cohort_vec") > 0
            restore
            scalar rt040_nrefused = rt040_nrefused + 1
            continue
        }
        quietly csdid y `covars' `weight', ivar(id) time(time) gvar(g) method(reg) ///
            `options' `route' analytical pointwise storeall
        matrix A = e(attgt)
        matrix IF = e(inffunc)
        local nobs = e(N)
        local nunits = e(N_units)
        local ntime = e(N_time)
        local wald = e(wald_stat)
        local wald_pval = e(wald_pvalue)
        assert rowsof(IF) == `nunits'
        assert colsof(IF) == rowsof(A)
        preserve
        keep if e(sample)
        keep id time
        isid id time
        save "`actual_sample'", replace
        import delimited using "`fx'/expected/r/sample.csv", clear asdouble
        keep if scenario == "`s'"
        drop scenario
        merge 1:1 id time using "`actual_sample'"
        assert _merge == 3
        assert _N == `nobs'
        restore
        preserve
        import delimited using "`fx'/expected/r/meta.csv", clear asdouble
        keep if scenario == "`s'"
        assert _N == 1
        assert n_obs == `nobs'
        assert n_units == `nunits'
        assert n_time == `ntime'
        assert n_cells == rowsof(A)
        assert missing(wald) == missing(`wald')
        assert missing(wald_pval) == missing(`wald_pval')
        assert missing(wald) | abs(wald - `wald') <= 1e-8 + 1e-8 * abs(wald)
        assert missing(wald_pval) | abs(wald_pval - `wald_pval') <= 1e-10
        restore
        preserve
        import delimited using "`fx'/expected/r/attgt.csv", clear asdouble
        keep if scenario == "`s'"
        assert _N == rowsof(A)
        sort group time
        forvalues i = 1/`=_N' {
            assert A[`i', 1] == group[`i']
            assert A[`i', 2] == time[`i']
            assert missing(A[`i', 4]) == missing(att[`i'])
            assert missing(A[`i', 5]) == missing(se[`i'])
            if !missing(att[`i']) {
                assert abs(A[`i', 4] - att[`i']) <= 1e-10 + 1e-10 * abs(att[`i'])
                scalar rt040_maxatt = max(rt040_maxatt, abs(A[`i', 4] - att[`i']))
            }
            if !missing(se[`i']) {
                assert abs(A[`i', 5] - se[`i']) <= 1e-10 + 1e-10 * abs(se[`i'])
                scalar rt040_maxse = max(rt040_maxse, abs(A[`i', 5] - se[`i']))
            }
            scalar rt040_natt = rt040_natt + 1
        }
        restore
        preserve
        import delimited using "`fx'/expected/r/inffunc.csv", clear asdouble
        keep if scenario == "`s'"
        isid unit_index group time
        mata: rt040_compare_if()
        restore
        foreach agg in simple group calendar dynamic {
            forvalues na = 0/1 {
                preserve
                import delimited using "`fx'/expected/r/aggregation_status.csv", clear asdouble
                keep if scenario == "`s'" & type == "`agg'" & na_rm == `na'
                assert _N == 1
                local failed = failed[1]
                restore
                local missingopt ""
                if `na' local missingopt "dropmissing"
                capture quietly csdid_stats, type(`agg') `missingopt'
                local rc = _rc
                assert `rc' == cond(`failed', 498, 0)
                scalar rt040_nverdict = rt040_nverdict + 1
                if !`failed' {
                    matrix G = e(aggte)
                    preserve
                    import delimited using "`fx'/expected/r/aggte.csv", clear asdouble
                    keep if scenario == "`s'" & type == "`agg'" & na_rm == `na'
                    assert _N == rowsof(G)
                    sort seq
                    local j 0
                    foreach v in egt att se overall_att overall_se {
                        local ++j
                        forvalues i = 1/`=_N' {
                            assert missing(G[`i', `j']) == missing(`v'[`i'])
                            if !missing(`v'[`i']) {
                                assert abs(G[`i', `j'] - `v'[`i']) <= 1e-10 + 1e-10 * abs(`v'[`i'])
                                scalar rt040_maxagg = max(rt040_maxagg, abs(G[`i', `j'] - `v'[`i']))
                            }
                        }
                    }
                    scalar rt040_nagg = rt040_nagg + _N
                    restore
                }
            }
        }
    }
}
assert rt040_natt == 538
assert rt040_nif == 16360
assert rt040_nagg == 744
assert rt040_nverdict == 512
assert rt040_nrefused == 56

* Missing rows and the complete companion rows removed by balancing have
* separate, observable counts even under quietly.
tempfile evidence_log
import delimited using "`fx'/inputs/covariate_missing_varying_notyet.csv", clear asdouble
log using "`evidence_log'", text replace name(rt040log)
quietly csdid y x, ivar(id) time(time) gvar(g) method(reg) notyet ///
    bal(full) base_period(varying) analytical pointwise
log close rt040log
rt040_log_has using "`evidence_log'", message("missing or non-finite data (10 observation(s))")
assert r(found)
rt040_log_has using "`evidence_log'", message("10 unit(s) are not observed in all 4 periods")
assert r(found)
rt040_log_has using "`evidence_log'", message("dropping them (30 observation(s))")
assert r(found)

* D026 keeps its exact pre-generic-balance screen. A unit removed for a
* covariate miss is excluded there; an absent-row unit still participates.
foreach shape in covariate_missing row_absent mixed_shapes {
    clear
    set obs 40
    generate int id = _n
    generate int g = cond(id <= 20, 0, 3)
    expand 4
    bysort id: generate int time = _n
    generate double x = mod(id + time, 7) / 8
    generate double y = 7
    replace y = 8 if id == 1 & time == 2
    if inlist("`shape'", "covariate_missing", "mixed_shapes") replace x = . if id == 1 & time == 1
    if "`shape'" == "row_absent" drop if id == 1 & time == 1
    if "`shape'" == "mixed_shapes" {
        replace y = 8 if id == 2 & time == 2
        drop if id == 2 & time == 1
    }
    foreach control in notyet nevertreated {
        log using "`evidence_log'", text replace name(rt040log)
        capture noisily csdid y x, ivar(id) time(time) gvar(g) bal(full) ///
            method(reg) `control' analytical pointwise
        local actual_rc = _rc
        log close rt040log
        assert `actual_rc' == cond("`shape'" == "covariate_missing", 459, 0)
        if "`shape'" == "covariate_missing" {
            rt040_log_has using "`evidence_log'", message("y takes the same value (7)")
            assert r(found)
        }
    }
}
display as text "RT040 max |dATT| = " %12.5g rt040_maxatt " max |dSE| = " %12.5g rt040_maxse " max |dIF| = " %12.5g rt040_maxif " max |dAgg| = " %12.5g rt040_maxagg
display as text "test-grid-before-full-balance: 60 scenarios pass on both routes: 32 reference-defined grids and 28 explicit refusals, including all sample keys and aggregation verdicts"
