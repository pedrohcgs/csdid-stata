version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

mata:
void rt007_all_targets(string scalar ifname, string scalar cvname, string scalar outname)
{
    real matrix inf, sc, out
    real colvector cv, levels
    real scalar n, k, g, i, j

    inf = st_matrix(ifname)
    cv = st_matrix(cvname)
    n = rows(inf)
    k = cols(inf)
    levels = uniqrows(cv)
    g = rows(levels)
    sc = J(g, k, 0)
    for (i = 1; i <= g; i++) {
        for (j = 1; j <= n; j++) {
            if (cv[j] == levels[i]) sc[i, .] = sc[i, .] + inf[j, .]
        }
    }
    out = (sqrt(colsum(sc:^2))' :/ n, J(k, 1, n), J(k, 1, g))
    st_matrix(outname, out)
}
end

program define rt007_save_attgt_targets
    version 15
    syntax, SCENARIO(string) OUTFILE(string)

    matrix A = e(attgt)
    matrix IF = e(inffunc)
    matrix CV = e(cluster_vec)
    mata: rt007_all_targets("IF", "CV", "T")
    matrix colnames T = target_se_stata inffunc_n_stata n_clusters_stata

    preserve
    clear
    svmat double A, names(col)
    svmat double T, names(col)
    rename (att se) (att_stata se_stata)
    gen str40 scenario = "`scenario'"
    keep scenario group time event_time att_stata se_stata target_se_stata ///
        inffunc_n_stata n_clusters_stata
    save "`outfile'", replace
    restore
end

program define rt007_assert_analytical
    version 15
    syntax, SCENARIO(string) INPUT(string) TARGETS(string) [IDVAR(string) FAST]

    local ivaropt ""
    if "`idvar'" != "" local ivaropt "ivar(`idvar')"
    local fastopt ""
    if "`fast'" != "" local fastopt "fast"

    tempfile actual
    import delimited using "`input'", clear asdouble
    csdid y, `ivaropt' time(t) gvar(g) method(dr) cluster(cl) base_period(varying) `fastopt' analytical
    assert "`e(clustervar)'" == "cl"
    assert e(N_clusters) > 0
    assert e(fast_requested) == ("`fast'" != "")
    rt007_save_attgt_targets, scenario("`scenario'") outfile("`actual'")

    import delimited using "`targets'", clear asdouble
    keep if scenario == "`scenario'"
    merge 1:1 scenario group time using "`actual'", nogen assert(match)
    foreach v in att se target_se {
        assert missing(`v') == missing(`v'_stata) if missing(`v') | missing(`v'_stata)
        assert abs(`v' - `v'_stata) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v') & !missing(`v'_stata)
    }
    assert cluster_vector_n == inffunc_n_stata
    assert inffunc_n == inffunc_n_stata
    assert n_clusters == n_clusters_stata
end

program define rt007_assert_iid_contrast
    version 15
    syntax, INPUT(string) EXPECTED(string)

    tempfile iid cl
    import delimited using "`input'", clear asdouble
    csdid y, ivar(id) time(t) gvar(g) method(dr) base_period(varying) analytical
    matrix A = e(attgt)
    preserve
    clear
    svmat double A, names(col)
    keep if group == 2 & time == 2
    keep group time se
    rename se se_iid_stata
    save "`iid'", replace
    restore

    import delimited using "`input'", clear asdouble
    csdid y, ivar(id) time(t) gvar(g) method(dr) cluster(cl) base_period(varying) analytical
    matrix C = e(attgt)
    preserve
    clear
    svmat double C, names(col)
    keep if group == 2 & time == 2
    keep group time se
    rename se se_cluster_stata
    save "`cl'", replace
    restore

    import delimited using "`expected'", clear asdouble
    merge 1:1 group time using "`iid'", nogen assert(match)
    merge 1:1 group time using "`cl'", nogen assert(match)
    assert abs(se_iid - se_iid_stata) < 1e-8
    assert abs(se_cluster - se_cluster_stata) < 1e-8
    generate double rel_gap_stata = abs(se_cluster_stata - se_iid_stata) / se_iid_stata
    assert rel_gap > .05
    assert rel_gap_stata > .05
end

program define rt007_assert_bootstrap
    version 15
    syntax, INPUT(string) BITERS(integer) SEED(integer) IQRRTOL(real) ///
        [IDVAR(string) FAST SDRTOL(real -1)]

    local ivaropt ""
    if "`idvar'" != "" local ivaropt "ivar(`idvar')"
    local fastopt ""
    if "`fast'" != "" local fastopt "fast"

    import delimited using "`input'", clear asdouble
    csdid y, `ivaropt' time(t) gvar(g) method(dr) cluster(cl) base_period(varying) ///
        wboot(reps(`biters') rseed(`seed')) pointwise `fastopt'
    assert e(bstrap) == 1
    assert e(biters) == `biters'
    assert e(cband) == 0
    assert e(fast_requested) == ("`fast'" != "")
    confirm matrix e(boot_draws)

    matrix B = e(boot_attgt)
    matrix D = e(boot_draws)
    matrix IF = e(inffunc)
    assert rowsof(D) == `biters'
    assert colsof(D) == rowsof(B)

    local k 0
    forvalues i = 1/`=rowsof(B)' {
        if B[`i', 1] == 2 & B[`i', 2] == 2 {
            local k `i'
        }
    }
    assert `k' > 0
    local se_boot = B[`k', 5]
    local se_analytic = B[`k', 6]
    assert `se_boot' > 0
    assert `se_analytic' > 0
    assert abs(`se_boot' - `se_analytic') / `se_analytic' < `iqrrtol'

    if `sdrtol' >= 0 {
        local n_if = rowsof(IF)
        local n_clusters = e(N_clusters)
        mata: st_numscalar("rt007_sd_se", sqrt(variance(st_matrix("D")[., `k'])) * sqrt(`n_clusters') / `n_if')
        scalar rt007_rel_sd = abs(rt007_sd_se - `se_analytic') / `se_analytic'
        assert rt007_rel_sd < `sdrtol'
    }
end

program define rt007_assert_aggte
    version 15
    syntax, INPUT(string) EXPECTED(string)

    tempfile cl iid actual
    import delimited using "`input'", clear asdouble
    csdid y, ivar(id) time(t) gvar(g) method(dr) cluster(cl) base_period(varying) analytical
    foreach type in simple group dynamic {
        csdid_stats, type(`type')
        matrix G = e(aggte)
        preserve
        clear
        svmat double G, names(col)
        gen str16 type = "`type'"
        keep in 1
        keep type overall_att overall_se
        rename (overall_att overall_se) (overall_att_stata overall_se_cluster_stata)
        if "`type'" == "simple" {
            save "`cl'", replace
        }
        else {
            append using "`cl'"
            save "`cl'", replace
        }
        restore
    }

    import delimited using "`input'", clear asdouble
    csdid y, ivar(id) time(t) gvar(g) method(dr) base_period(varying) analytical
    foreach type in simple group dynamic {
        csdid_stats, type(`type')
        matrix G = e(aggte)
        preserve
        clear
        svmat double G, names(col)
        gen str16 type = "`type'"
        keep in 1
        keep type overall_se
        rename overall_se overall_se_iid_stata
        if "`type'" == "simple" {
            save "`iid'", replace
        }
        else {
            append using "`iid'"
            save "`iid'", replace
        }
        restore
    }

    use "`cl'", clear
    merge 1:1 type using "`iid'", nogen assert(match)
    save "`actual'", replace

    import delimited using "`expected'", clear asdouble
    merge 1:1 type using "`actual'", nogen assert(match)
    assert abs(overall_att - overall_att_stata) < 1e-8
    assert abs(overall_se_cluster - overall_se_cluster_stata) < 1e-8
    assert abs(overall_se_iid - overall_se_iid_stata) < 1e-8
    generate double rel_gap_stata = abs(overall_se_cluster_stata - overall_se_iid_stata) / overall_se_iid_stata
    assert rel_gap > .02
    assert rel_gap_stata > .02
end

confirm file "`root'/tests/fixtures/parity/rt007/inputs/clustered-shocks-404.csv"
confirm file "`root'/tests/fixtures/parity/rt007/inputs/clustered-shocks-505.csv"
confirm file "`root'/tests/fixtures/parity/rt007/inputs/panel-between-11.csv"
confirm file "`root'/tests/fixtures/parity/rt007/inputs/panel-within-11.csv"
confirm file "`root'/tests/fixtures/parity/rt007/inputs/rcs-909.csv"
confirm file "`root'/tests/fixtures/parity/rt007/inputs/rcs-909-id.csv"
confirm file "`root'/tests/fixtures/parity/rt007/inputs/rcs-910.csv"
confirm file "`root'/tests/fixtures/parity/rt007/expected/r/analytical-targets.csv"
confirm file "`root'/tests/fixtures/parity/rt007/expected/r/cluster-iid-contrast.csv"
confirm file "`root'/tests/fixtures/parity/rt007/expected/r/aggte-overall.csv"
confirm file "`root'/tests/fixtures/parity/rt007/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt007/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt007/expected/contract/bootstrap-scenarios.csv"
confirm file "`root'/tests/fixtures/parity/rt007/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt007/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 13
quietly count if coverage_status == "mapped"
assert r(N) == 13

rt007_assert_analytical, ///
    scenario(panel_404_regular) ///
    input("`root'/tests/fixtures/parity/rt007/inputs/clustered-shocks-404.csv") ///
    targets("`root'/tests/fixtures/parity/rt007/expected/r/analytical-targets.csv") ///
    idvar(id)
rt007_assert_analytical, ///
    scenario(panel_404_fast) ///
    input("`root'/tests/fixtures/parity/rt007/inputs/clustered-shocks-404.csv") ///
    targets("`root'/tests/fixtures/parity/rt007/expected/r/analytical-targets.csv") ///
    idvar(id) fast
rt007_assert_iid_contrast, ///
    input("`root'/tests/fixtures/parity/rt007/inputs/clustered-shocks-404.csv") ///
    expected("`root'/tests/fixtures/parity/rt007/expected/r/cluster-iid-contrast.csv")

rt007_assert_bootstrap, ///
    input("`root'/tests/fixtures/parity/rt007/inputs/panel-between-11.csv") ///
    biters(3000) seed(20260701) iqrrtol(.15) sdrtol(.06) idvar(id)
rt007_assert_bootstrap, ///
    input("`root'/tests/fixtures/parity/rt007/inputs/panel-within-11.csv") ///
    biters(3000) seed(20260702) iqrrtol(.15) sdrtol(.06) idvar(id)

rt007_assert_analytical, ///
    scenario(rcs_909_omitted_regular) ///
    input("`root'/tests/fixtures/parity/rt007/inputs/rcs-909.csv") ///
    targets("`root'/tests/fixtures/parity/rt007/expected/r/analytical-targets.csv")
rt007_assert_analytical, ///
    scenario(rcs_909_omitted_fast) ///
    input("`root'/tests/fixtures/parity/rt007/inputs/rcs-909.csv") ///
    targets("`root'/tests/fixtures/parity/rt007/expected/r/analytical-targets.csv") ///
    fast
rt007_assert_analytical, ///
    scenario(rcs_909_id_regular) ///
    input("`root'/tests/fixtures/parity/rt007/inputs/rcs-909-id.csv") ///
    targets("`root'/tests/fixtures/parity/rt007/expected/r/analytical-targets.csv") ///
    idvar(uid)
rt007_assert_analytical, ///
    scenario(rcs_909_id_fast) ///
    input("`root'/tests/fixtures/parity/rt007/inputs/rcs-909-id.csv") ///
    targets("`root'/tests/fixtures/parity/rt007/expected/r/analytical-targets.csv") ///
    idvar(uid) fast

rt007_assert_bootstrap, ///
    input("`root'/tests/fixtures/parity/rt007/inputs/rcs-910.csv") ///
    biters(5000) seed(20260703) iqrrtol(.12)
rt007_assert_bootstrap, ///
    input("`root'/tests/fixtures/parity/rt007/inputs/rcs-910.csv") ///
    biters(5000) seed(20260704) iqrrtol(.12) fast

rt007_assert_aggte, ///
    input("`root'/tests/fixtures/parity/rt007/inputs/clustered-shocks-505.csv") ///
    expected("`root'/tests/fixtures/parity/rt007/expected/r/aggte-overall.csv")
