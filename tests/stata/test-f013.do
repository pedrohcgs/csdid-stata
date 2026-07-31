version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

mata:
real scalar f013__sd(real colvector v)
{
    real scalar n, m

    n = rows(v)
    if (n <= 1) return(.)
    m = mean(v)
    return(sqrt(quadcrossdev(v, m, v, m) / (n - 1)))
}

void f013__summarize_if(string scalar attname, string scalar ifname, string scalar outname)
{
    real matrix att, inf, out
    real colvector v
    real scalar k, n, sumsq

    att = st_matrix(attname)
    inf = st_matrix(ifname)
    out = J(cols(inf), 15, .)
    for (k = 1; k <= cols(inf); k++) {
        v = inf[., k]
        n = rows(v)
        sumsq = quadcross(v, v)
        out[k, .] = (
            att[k, 1], att[k, 2], att[k, 3], k, n,
            mean(v), f013__sd(v), sum(abs(v)), sqrt(sumsq),
            min(v), max(v), sum(abs(v) :> 1e-12), sum(v),
            sumsq, sqrt(sumsq) / n
        )
    }
    st_matrix(outname, out)
}
end

tempfile allatt allif
local first_att 1
local first_if 1

foreach scenario in panel_reg panel_cov_dr rc_reg {
    import delimited using "`root'/tests/fixtures/parity/f013/inputs/input.csv", clear asdouble
    if "`scenario'" == "panel_reg" {
        csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none) storeall
    }
    else if "`scenario'" == "panel_cov_dr" {
        csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) analytical nevertreated base_period(varying) bal(none) storeall
    }
    else {
        csdid y, time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none) storeall
    }

    matrix A = e(attgt)
    matrix IF = e(inffunc)
    assert colsof(IF) == rowsof(A)
    if "`scenario'" == "rc_reg" {
        assert rowsof(IF) == e(N)
        assert "`e(panel_mode)'" == "repeated-cross-section"
    }
    else {
        assert rowsof(IF) == e(N_units)
        assert "`e(panel_mode)'" == "panel"
    }

    preserve
    clear
    svmat double A, names(col)
    gen str24 scenario = "`scenario'"
    rename (att se) (att_stata se_stata)
    keep scenario group time event_time att_stata se_stata
    if `first_att' {
        save "`allatt'", replace
        local first_att 0
    }
    else {
        append using "`allatt'"
        save "`allatt'", replace
    }
    restore

    mata: f013__summarize_if("A", "IF", "S")
    matrix colnames S = group time event_time inffunc_col n_rows mean sd l1_norm l2_norm min max nonzero_count sum sumsq se_from_if

    preserve
    clear
    svmat double S, names(col)
    gen str24 scenario = "`scenario'"
    rename (n_rows mean sd l1_norm l2_norm min max nonzero_count sum sumsq se_from_if) ///
           (n_rows_stata mean_stata sd_stata l1_norm_stata l2_norm_stata min_stata max_stata nonzero_count_stata sum_stata sumsq_stata se_from_if_stata)
    if `first_if' {
        save "`allif'", replace
        local first_if 0
    }
    else {
        append using "`allif'"
        save "`allif'", replace
    }
    restore
}

import delimited using "`root'/tests/fixtures/parity/f013/expected/r/attgt.csv", clear asdouble
merge 1:1 scenario group time using "`allatt'", nogen assert(match)
assert abs(att - att_stata) < 1e-10
assert !missing(se)
assert abs(se - se_stata) < 1e-8

import delimited using "`root'/tests/fixtures/parity/f013/expected/r/inffunc-summary.csv", clear asdouble
merge 1:1 scenario group time inffunc_col using "`allif'", nogen assert(match)
foreach v in n_rows nonzero_count {
    assert `v' == `v'_stata
}
foreach v in mean sd l1_norm l2_norm min max sum sumsq se_from_if {
    assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v')
}
