version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rt017_assert_log_contains
    version 15
    syntax using/, MESSAGE(string)

    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    local compact_body = subinstr(`"`body'"', " ", "", .)
    local compact_message = subinstr(`"`message'"', " ", "", .)
    local found = strpos(`"`body'"', `"`message'"') > 0 | strpos(`"`compact_body'"', `"`compact_message'"') > 0
    assert `found'
end

mata:
void rt017_cluster_targets(string scalar ifname, string scalar cvname, real scalar k, string scalar outname)
{
    real matrix inf
    real colvector cv, levels, sc, nc
    real scalar n, g, i, j, target_sum, target_mean

    inf = st_matrix(ifname)
    cv = st_matrix(cvname)
    n = rows(inf)
    levels = uniqrows(cv)
    g = rows(levels)
    sc = J(g, 1, 0)
    nc = J(g, 1, 0)
    for (i = 1; i <= g; i++) {
        for (j = 1; j <= n; j++) {
            if (cv[j] == levels[i]) {
                sc[i] = sc[i] + inf[j, k]
                nc[i] = nc[i] + 1
            }
        }
    }
    target_sum = sqrt(sum(sc:^2)) / n
    target_mean = sqrt(sum((sc:/nc):^2)) / g
    st_matrix(outname, (target_sum, target_mean, n, g, k, abs(target_sum - target_mean) / target_mean))
}
end

program define rt017_assert_bootstrap_target
    version 15
    syntax, SCENARIO(string) INPUT(string) TARGETS(string) BITERS(integer) SEED(integer) ///
        [BALANCED UNBALANCED]

    import delimited using "`input'", clear asdouble
    csdid y, ivar(id) time(t) gvar(g) method(reg) base_period(varying) ///
        wboot(reps(`biters') cluster(cl) rseed(`seed')) pointwise
    assert e(bstrap) == 1
    assert e(biters) == `biters'
    assert e(cband) == 0
    assert e(N_clusters) == 40
    assert "`e(clustervar)'" == "cl"
    assert "`e(boot_dist)'" == "rademacher"
    assert "`e(boot_seed)'" == "`seed'"

    matrix ATT = e(attgt)
    matrix BOOT = e(boot_attgt)
    matrix IF = e(inffunc)
    matrix CV = e(cluster_vec)
    assert rowsof(CV) == rowsof(IF)
    assert colsof(IF) == rowsof(ATT)
    assert rowsof(BOOT) == rowsof(ATT)

    local k 0
    forvalues i = 1/`=rowsof(ATT)' {
        if ATT[`i', 1] == 2 & ATT[`i', 2] == 2 {
            local k `i'
        }
    }
    assert `k' > 0
    mata: rt017_cluster_targets("IF", "CV", `k', "TG")

    local target_sum_stata = TG[1, 1]
    local target_mean_stata = TG[1, 2]
    local inffunc_n_stata = TG[1, 3]
    local n_clusters_stata = TG[1, 4]
    local k_stata = TG[1, 5]
    local rel_gap_stata = TG[1, 6]
    local se_boot_stata = BOOT[`k', 5]

    assert `se_boot_stata' > 0
    assert abs(ATT[`k', 5] - `se_boot_stata') < 1e-12
    assert abs(`se_boot_stata' - `target_sum_stata') / `target_sum_stata' < .08

    preserve
    import delimited using "`targets'", clear asdouble
    keep if scenario == "`scenario'"
    assert _N == 1
    assert k == `k_stata'
    assert inffunc_n == `inffunc_n_stata'
    assert cluster_vector_n == `inffunc_n_stata'
    assert n_clusters == `n_clusters_stata'
    assert abs(target_sum - `target_sum_stata') < 1e-8
    assert abs(target_mean - `target_mean_stata') < 1e-8
    assert abs(att - ATT[`k', 4]) < 1e-8
    if "`unbalanced'" != "" {
        assert rel_sum_mean_gap > .05
        assert `rel_gap_stata' > .05
        assert abs(`se_boot_stata' - `target_mean_stata') / `target_mean_stata' > .05
    }
    if "`balanced'" != "" {
        assert abs(target_sum - target_mean) < 1e-8
        assert abs(`target_sum_stata' - `target_mean_stata') < 1e-8
    }
    restore
end

confirm file "`root'/tests/fixtures/parity/rt017/inputs/clustered-unbalanced.csv"
confirm file "`root'/tests/fixtures/parity/rt017/inputs/clustered-balanced.csv"
confirm file "`root'/tests/fixtures/parity/rt017/inputs/clustered-invalid.csv"
confirm file "`root'/tests/fixtures/parity/rt017/expected/r/cluster-targets.csv"
confirm file "`root'/tests/fixtures/parity/rt017/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt017/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt017/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/rt017/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt017/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 3
quietly count if coverage_status == "mapped"
assert r(N) == 3
quietly count if source_test == "clustered mboot SE matches the cluster-sum (Remark 10) for UNBALANCED clusters"
assert r(N) == 1
quietly count if source_test == "clustered mboot SE is unchanged for BALANCED clusters (cluster-sum == cluster-mean)"
assert r(N) == 1
quietly count if source_test == "clustering validation is preserved (at most one cluster variable beyond idname)"
assert r(N) == 1

rt017_assert_bootstrap_target, ///
    scenario(unbalanced_cluster_sum_target) ///
    input("`root'/tests/fixtures/parity/rt017/inputs/clustered-unbalanced.csv") ///
    targets("`root'/tests/fixtures/parity/rt017/expected/r/cluster-targets.csv") ///
    biters(5000) seed(20261701) unbalanced

rt017_assert_bootstrap_target, ///
    scenario(balanced_cluster_sum_equals_mean) ///
    input("`root'/tests/fixtures/parity/rt017/inputs/clustered-balanced.csv") ///
    targets("`root'/tests/fixtures/parity/rt017/expected/r/cluster-targets.csv") ///
    biters(5000) seed(20261702) balanced

import delimited using "`root'/tests/fixtures/parity/rt017/inputs/clustered-invalid.csv", clear asdouble
tempfile evlog
capture log close rt017event
log using "`evlog'", text replace name(rt017event)
capture noisily csdid y, ivar(id) time(t) gvar(g) method(reg) base_period(varying) ///
    wboot(reps(99) cluster(cl cl2) rseed(20261703)) pointwise
local rc = _rc
log close rt017event
assert `rc' == 198
rt017_assert_log_contains using "`evlog'", message("wboot(cluster()) accepts one numeric cluster variable")
