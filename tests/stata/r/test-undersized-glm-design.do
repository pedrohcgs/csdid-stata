* RT076 -- GLM dimensions, normalized RC support and square controls.
version 15
clear all
set more off
set linesize 255
args engine_source
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local fx "`root'/tests/fixtures/parity/rt076"
if `"`engine_source'"' != "" quietly do "`engine_source'"
else _csdid_engine_load
quietly mata: csdid__globals_init()

mata:
// Assemble the panel DR kernel's precomputed nuisance inputs on the fixture.
// The independent expected numbers and complete IF vectors come from DRDID.
real colvector rt076_dr_panel(real colvector y1, real colvector y0,
    real colvector d, real matrix x, real colvector raw)
{
    real scalar n
    real matrix hi, xi
    real colvector w, ps, wt, wc, keep, b
    n = rows(d)
    if (csdid__rcond_fail(x, d, raw)) return(. \ J(n, 1, .) \ 2)
    if (sum(d :== 0) < cols(x)) return(. \ J(n, 1, .) \ 7)
    w = csdid__normalize_weights(raw)
    b = csdid__logit_fit(d, x, w)
    if (hasmissing(b)) return(. \ J(n, 1, .) \ 2)
    ps = csdid__cap_ps_rc(csdid__invlogit(x*b))
    if (max(ps) >= .999) return(. \ J(n, 1, .) \ 1)
    xi = csdid__inv_r_parity(quadcross(x, w :* (1 :- d), x))
    if (!csdid__valid_inverse(xi)) return(. \ J(n, 1, .) \ 4)
    hi = csdid__hessinv_r_parity(quadcross(x, ps :* (1 :- ps) :* w, x), n)
    if (hasmissing(hi)) return(. \ J(n, 1, .) \ 2)
    keep = (d :== 1) :| (ps :< .995)
    wt = keep :* w :* d
    wc = keep :* w :* ps :* (1 :- d) :/ (1 :- ps)
    return(csdid__dr_panel_fit_precomputed(y1, y0, d, x, wt, wc,
        w :* (d :- ps), x * (xi * quadcross(x, wt)),
        x * (xi * quadcross(x, wc)), mean(wt), mean(wc), hi,
        w :* (1 :- d)))
}
void rt076_fit()
{
    real matrix z, x
    real colvector got
    string scalar mode, method
    z = st_data(., ("y", "y0", "y1", "d", "post", "w", "x1", "x2", "x3"))
    x = J(rows(z), 1, 1), z[., 7..9]
    mode = st_local("mode")
    method = st_local("method")
    if (mode == "rc") {
        if (method == "reg") got = csdid__reg_rc_fit(z[.,1], z[.,5], z[.,4], x, z[.,6])
        else if (method == "dr") got = csdid__dr_rc_fit(z[.,1], z[.,5], z[.,4], x, z[.,6], .995)
        else got = csdid__ipw_rc_fit(z[.,1], z[.,5], z[.,4], x, z[.,6], .995)
    }
    else {
        if (method == "reg") got = csdid__reg_panel_fit(z[.,3], z[.,2], z[.,4], x, z[.,6])
        else if (method == "dr") got = rt076_dr_panel(z[.,3], z[.,2], z[.,4], x, z[.,6])
        else got = csdid__ipw_panel_fit(z[.,3], z[.,2], z[.,4], x, z[.,6], .995)
    }
    assert(rows(got) == rows(z) + 2)
    st_numscalar("rt076_att", got[1])
    st_numscalar("rt076_status", got[rows(got)])
    got = got[2::(rows(got)-1)]
    st_matrix("rt076_if", got)
    st_numscalar("rt076_se", sqrt(quadcross(got :- mean(got), got :- mean(got))) / rows(z))
}
void rt076_wide_fit()
{
    real matrix z, x
    real colvector f, d, pre, post
    z = st_data(., ("t", "g", "y", "w", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8"))
    x = J(rows(z), 1, 1), z[., 5..12]
    d = (z[., 2] :== 2)
    if (st_local("mode") == "rc") {
        f = csdid__ipw_rc_fit(z[., 3], z[., 1] :- 1, d, x, z[., 4], .995)
    }
    else {
        pre = selectindex(z[., 1] :== 1)
        post = selectindex(z[., 1] :== 2)
        f = csdid__ipw_panel_fit(z[post, 3], z[pre, 3], d[pre], x[pre, .], z[pre, 4], .995)
    }
    assert(all(f[1::(rows(f)-1)] :>= .))
    st_numscalar("rt076_status", f[rows(f)])
}
end

import delimited using "`fx'/inputs/scenarios.csv", clear asdouble varnames(1)
assert _N == 162
tempfile specs
save `specs'
import delimited using "`fx'/expected/r/fits.csv", clear asdouble varnames(1)
isid scenario method
tempfile expected
save `expected'
import delimited using "`fx'/expected/r/inffunc.csv", clear asdouble varnames(1)
isid scenario method id
tempfile expected_if
save `expected_if'
import delimited using "`fx'/expected/r/warnings.csv", clear asdouble varnames(1)
tempfile expected_warnings
save `expected_warnings'
scalar rt076_n = 0
scalar rt076_maxatt = 0
scalar rt076_maxse = 0
scalar rt076_maxif = 0
forvalues k = 1/162 {
    use `specs', clear
    local scenario = scenario[`k']
    local mode = mode[`k']
    local method = method[`k']
    local good = good[`k']
    local physical = physical[`k']
    local guard_status = guard_status[`k']
    display as text "RT076 case `k': `scenario' method(`method') good=`good' physical=`physical'"
    use `expected' if scenario == "`scenario'" & method == "`method'", clear
    assert _N == 1
    local want_att = att[1]
    local want_se = se[1]
    import delimited using "`fx'/inputs/`scenario'.csv", clear asdouble varnames(1)
    mata: rt076_fit()
    display as text "RT076 status=" rt076_status " ATT=" %21.16g rt076_att " RATT=" %21.16g `want_att' " SE=" %21.16g rt076_se " RSE=" %21.16g `want_se'
    if `good' {
        assert rt076_status == 0
        assert abs(rt076_att - `want_att') <= 1e-10 * (1 + abs(`want_att'))
        assert abs(rt076_se - `want_se') <= 1e-10 * (1 + abs(`want_se'))
        scalar rt076_maxatt = max(rt076_maxatt, abs(rt076_att - `want_att'))
        scalar rt076_maxse = max(rt076_maxse, abs(rt076_se - `want_se'))
        use `expected_if' if scenario == "`scenario'" & method == "`method'", clear
        sort id
        assert _N == rowsof(rt076_if)
        generate double got = .
        mata: st_store(., "got", st_matrix("rt076_if"))
        generate double gap = abs(got - value)
        assert gap <= 1e-8 * (1 + abs(value))
        quietly summarize gap, meanonly
        scalar rt076_maxif = max(rt076_maxif, r(max))
    }
    else {
        assert missing(rt076_att)
        assert rt076_status != 0
    }
    if `physical' {
        * The current did RC guard names positive normalized support and
        * precedes overlap and pooled rank, including square physical blocks.
        assert rt076_status == `guard_status'
        use `expected_warnings' if scenario == "`scenario'" & method == "`method'", clear
        assert _N == 2
        assert message[1] == message[2]
        local wanted = message[1]
        import delimited using "`fx'/inputs/`scenario'.csv", clear asdouble varnames(1)
        generate double t = post + 1
        generate double g = d * 2
        tempfile lg
        log using "`lg'", text replace name(rt076)
        capture noisily csdid y x1 x2 x3 [iw=w], rcs time(t) gvar(g) ///
            method(`method') nevertreated base_period(universal) analytical pointwise
        local rc = _rc
        log close rt076
        assert `rc' == 0
        tempname fh
        local body ""
        file open `fh' using "`lg'", read text
        file read `fh' line
        while r(eof) == 0 {
            local body `"`body' `line'"'
            file read `fh' line
        }
        file close `fh'
        assert strpos(`"`body'"', `"`wanted'"') > 0
    }
    scalar rt076_n = rt076_n + 1
}
assert rt076_n == 162

* Total IPW design dimensions: preserve the preliminary overlap diagnostic.
import delimited using "`fx'/inputs/wide-scenarios.csv", clear asdouble varnames(1)
assert _N == 12
tempfile wide_specs
save `wide_specs'
import delimited using "`fx'/expected/r/wide-warnings.csv", clear asdouble varnames(1)
assert _N == 24
tempfile wide_warnings
save `wide_warnings'
import delimited using "`fx'/expected/r/wide-attgt.csv", clear asdouble varnames(1)
assert _N == 48
isid scenario faster_mode group time
tempfile wide_expected
save `wide_expected'
forvalues k = 1/12 {
    use `wide_specs', clear
    local scenario = scenario[`k']
    local mode = mode[`k']
    local want_status = want_status[`k']
    display as text "RT076 wide case `k': `scenario' status=`want_status'"
    use `wide_warnings' if scenario == "`scenario'", clear
    assert _N == 2
    assert message[1] == message[2]
    local wanted = message[1]
    use `wide_expected' if scenario == "`scenario'" & faster_mode == 0, clear
    assert _N == 2
    sort group time
    mkmat group time att se, matrix(R_A)
    import delimited using "`fx'/inputs/`scenario'.csv", clear asdouble varnames(1)
    mata: rt076_wide_fit()
    display as text "RT076 wide measured status=" rt076_status
    assert rt076_status == `want_status'
    local structure "rcs"
    if "`mode'" == "panel" local structure "ivar(id)"
    tempfile lg
    log using "`lg'", text replace name(rt076wide)
    capture noisily csdid y x1-x8 [iw=w], `structure' time(t) gvar(g) ///
        method(ipw) base_period(universal) analytical pointwise
    local rc = _rc
    log close rt076wide
    assert `rc' == 0
    matrix A = e(attgt)
    assert rowsof(A) == 2
    forvalues j = 1/2 {
        assert A[`j', colnumb(A,"group")] == R_A[`j',1]
        assert A[`j', colnumb(A,"time")] == R_A[`j',2]
        assert missing(A[`j', colnumb(A,"att")]) == missing(R_A[`j',3])
        assert missing(A[`j', colnumb(A,"se")]) == missing(R_A[`j',4])
        if !missing(R_A[`j',3]) assert A[`j',colnumb(A,"att")] == R_A[`j',3]
        if A[`j', colnumb(A,"time")] == 2 {
            assert missing(A[`j', colnumb(A,"att")])
            assert missing(A[`j', colnumb(A,"se")])
        }
    }
    tempname fh
    local body ""
    file open `fh' using "`lg'", read text
    file read `fh' line
    while r(eof) == 0 {
        local body `"`body' `line'"'
        file read `fh' line
    }
    file close `fh'
    assert strpos(`"`body'"', `"`wanted'"') > 0
}

display as text "RT076 max |dATT|=" %12.5g rt076_maxatt " max |dSE|=" %12.5g rt076_maxse " max |dIF|=" %12.5g rt076_maxif
display as text "test-undersized-glm-design: 162 rank-boundary fits and full IFs plus 12 wide IPW refusals match; exact warnings match both oracle routes"
