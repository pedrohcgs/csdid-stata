version 15
clear all
set more off

args root
if `"`root'"' == "" local root "`c(pwd)'"

quietly do "`root'/src/build.do"
adopath ++ "`root'/build"

capture mkdir "`root'/build"
capture mkdir "`root'/build/hotpath-profile"

tempfile profile_rows
tempname profile_post
postfile `profile_post' str48 scenario str24 phase double total_seconds ///
    phase_seconds calls work using `profile_rows', replace

program define _csdid_profile_post
    version 15
    syntax, SCENARIO(string) TOTAL(real) HANDLE(name)

    tempname profile
    matrix `profile' = e(profile)
    local phases setup cell_extract model_fit if_assembly cache_post cluster bootstrap aggregation
    local row 0
    foreach phase of local phases {
        local ++row
        post `handle' ("`scenario'") ("`phase'") (`total') ///
            (`profile'[`row', 1]) (`profile'[`row', 2]) (`profile'[`row', 3])
    }

    capture confirm matrix e(bootstrap_profile)
    if !_rc {
        matrix `profile' = e(bootstrap_profile)
        local phases input_reorder cluster_reduce active_scan multiplier_draws summarize_cband result_post
        local row 0
        foreach phase of local phases {
            local ++row
            post `handle' ("`scenario'") ("boot_`phase'") (`total') ///
                (`profile'[`row', 1]) (`profile'[`row', 2]) (`profile'[`row', 3])
        }
    }

    capture confirm matrix e(bootstrap_kernel_profile)
    if !_rc {
        matrix `profile' = e(bootstrap_kernel_profile)
        local phases rng_twist rng_temper bit_expand reshape_trim matrix_multiply
        local row 0
        foreach phase of local phases {
            local ++row
            post `handle' ("`scenario'") ("kernel_`phase'") (`total') ///
                (`profile'[`row', 1]) (`profile'[`row', 2]) (`profile'[`row', 3])
        }
    }
end

local balanced "`root'/tests/fixtures/parity/f049/inputs/medium-panel.csv"
local unbalanced "`root'/tests/fixtures/parity/f049/inputs/medium-unbalanced.csv"

import delimited using "`balanced'", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
timer clear 1
timer on 1
forvalues repetition = 1/5 {
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) analytical
}
timer off 1
quietly timer list 1
local elapsed = r(t1) / 5
_csdid_profile_post, scenario("balanced_reg") total(`elapsed') handle(`profile_post')

import delimited using "`balanced'", clear asdouble
quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) analytical
timer clear 1
timer on 1
forvalues repetition = 1/5 {
    quietly csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) analytical
}
timer off 1
quietly timer list 1
local elapsed = r(t1) / 5
_csdid_profile_post, scenario("balanced_covariate_dr") total(`elapsed') handle(`profile_post')

import delimited using "`balanced'", clear asdouble
quietly csdid y [iw=wt], ivar(id) time(time) gvar(g) method(ipw) analytical
timer clear 1
timer on 1
forvalues repetition = 1/5 {
    quietly csdid y [iw=wt], ivar(id) time(time) gvar(g) method(ipw) analytical
}
timer off 1
quietly timer list 1
local elapsed = r(t1) / 5
_csdid_profile_post, scenario("balanced_weighted_ipw") total(`elapsed') handle(`profile_post')

import delimited using "`balanced'", clear asdouble
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) analytical
timer clear 1
timer on 1
forvalues repetition = 1/5 {
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) analytical
}
timer off 1
quietly timer list 1
local elapsed = r(t1) / 5
_csdid_profile_post, scenario("balanced_clustered_reg") total(`elapsed') handle(`profile_post')

import delimited using "`balanced'", clear asdouble
timer clear 1
timer on 1
forvalues repetition = 1/3 {
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
        wboot(reps(1000) rseed(20260628)) pointwise
}
timer off 1
quietly timer list 1
local elapsed = r(t1) / 3
_csdid_profile_post, scenario("balanced_reg_bootstrap") total(`elapsed') handle(`profile_post')

import delimited using "`balanced'", clear asdouble
timer clear 1
timer on 1
forvalues repetition = 1/3 {
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) ///
        wboot(reps(1000) rseed(20260628))
}
timer off 1
quietly timer list 1
local elapsed = r(t1) / 3
_csdid_profile_post, scenario("balanced_reg_cband") total(`elapsed') handle(`profile_post')

import delimited using "`balanced'", clear asdouble
timer clear 1
timer on 1
forvalues repetition = 1/3 {
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg)
}
timer off 1
quietly timer list 1
local elapsed = r(t1) / 3
_csdid_profile_post, scenario("balanced_reg_default_bootstrap") ///
    total(`elapsed') handle(`profile_post')

import delimited using "`unbalanced'", clear asdouble
quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) ///
    method(dr) allow_unbalanced analytical
timer clear 1
timer on 1
forvalues repetition = 1/3 {
    quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) ///
        method(dr) allow_unbalanced analytical
}
timer off 1
quietly timer list 1
local elapsed = r(t1) / 3
_csdid_profile_post, scenario("unbalanced_cov_weight_dr") total(`elapsed') handle(`profile_post')

import delimited using "`unbalanced'", clear asdouble
timer clear 1
timer on 1
forvalues repetition = 1/3 {
    quietly csdid y x1 x2 [iw=wt], ivar(id) time(time) gvar(g) ///
        method(dr) allow_unbalanced wboot(reps(1000) rseed(20260628)) pointwise
}
timer off 1
quietly timer list 1
local elapsed = r(t1) / 3
_csdid_profile_post, scenario("unbalanced_cov_weight_dr_bootstrap") ///
    total(`elapsed') handle(`profile_post')

postclose `profile_post'
use `profile_rows', clear
sort scenario phase
export delimited using "`root'/build/hotpath-profile/results.csv", replace
list, noobs abbreviate(32)

exit 0
