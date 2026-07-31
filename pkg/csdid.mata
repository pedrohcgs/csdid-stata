version 14
mata:
// matastrict is deliberately NOT set here. This file is do-ed at runtime on
// the source-fallback path, and setting it left matastrict ON in the user's
// session after csdid returned -- breaking any non-strict Mata they or
// another package later compiled, csdid_rif included. src/build.do sets it
// before compiling, which is where strictness belongs; the source below
// satisfies it either way.

real scalar csdid__mean(real colvector x)
{
    if (rows(x) == 0) return(.)
    return(mean(x))
}

real scalar csdid__variance(real colvector x)
{
    real scalar n
    n = rows(x)
    if (n <= 1) return(.)
    return(quadcrossdev(x, mean(x), x, mean(x)) / (n - 1))
}

real scalar csdid__previous_time(real rowvector tlist, real scalar t)
{
    real scalar i, prev
    prev = .
    for (i = 1; i <= cols(tlist); i++) {
        if (tlist[i] < t) prev = tlist[i]
    }
    return(prev)
}

real matrix csdid__rowmult(real matrix x, real colvector w)
{
    return(x :* (w * J(1, cols(x), 1)))
}

void csdid__profile_reset()
{
    external real matrix CSDID_PROFILE

    CSDID_PROFILE = J(8, 3, 0)
}

real scalar csdid__profile_start()
{
    return(now())
}

void csdid__profile_add(real scalar phase, real scalar started, real scalar work)
{
    external real matrix CSDID_PROFILE

    if (rows(CSDID_PROFILE) < 8 | cols(CSDID_PROFILE) < 3) {
        CSDID_PROFILE = J(8, 3, 0)
    }
    if (phase < 1 | phase > rows(CSDID_PROFILE)) return
    CSDID_PROFILE[phase, 1] = CSDID_PROFILE[phase, 1] + (now() - started) / 1000
    CSDID_PROFILE[phase, 2] = CSDID_PROFILE[phase, 2] + 1
    CSDID_PROFILE[phase, 3] = CSDID_PROFILE[phase, 3] + work
}

void csdid__boot_profile_reset()
{
    external real matrix CSDID_BOOT_PROFILE

    CSDID_BOOT_PROFILE = J(6, 3, 0)
}

void csdid__boot_profile_add(real scalar phase, real scalar started, real scalar work)
{
    external real matrix CSDID_BOOT_PROFILE

    if (rows(CSDID_BOOT_PROFILE) < 6 | cols(CSDID_BOOT_PROFILE) < 3) {
        CSDID_BOOT_PROFILE = J(6, 3, 0)
    }
    if (phase < 1 | phase > rows(CSDID_BOOT_PROFILE)) return
    CSDID_BOOT_PROFILE[phase, 1] = CSDID_BOOT_PROFILE[phase, 1] + (now() - started) / 1000
    CSDID_BOOT_PROFILE[phase, 2] = CSDID_BOOT_PROFILE[phase, 2] + 1
    CSDID_BOOT_PROFILE[phase, 3] = CSDID_BOOT_PROFILE[phase, 3] + work
}

void csdid__boot_kernel_profile_reset()
{
    external real matrix CSDID_BOOT_KERNEL_PROFILE

    CSDID_BOOT_KERNEL_PROFILE = J(5, 3, 0)
}

void csdid__boot_kernel_profile_add(real scalar phase, real scalar started, real scalar work)
{
    external real matrix CSDID_BOOT_KERNEL_PROFILE

    if (rows(CSDID_BOOT_KERNEL_PROFILE) < 5 | cols(CSDID_BOOT_KERNEL_PROFILE) < 3) {
        CSDID_BOOT_KERNEL_PROFILE = J(5, 3, 0)
    }
    if (phase < 1 | phase > rows(CSDID_BOOT_KERNEL_PROFILE)) return
    CSDID_BOOT_KERNEL_PROFILE[phase, 1] = CSDID_BOOT_KERNEL_PROFILE[phase, 1] + (now() - started) / 1000
    CSDID_BOOT_KERNEL_PROFILE[phase, 2] = CSDID_BOOT_KERNEL_PROFILE[phase, 2] + 1
    CSDID_BOOT_KERNEL_PROFILE[phase, 3] = CSDID_BOOT_KERNEL_PROFILE[phase, 3] + work
}

void csdid__agg_boot_profile_reset()
{
    external real matrix CSDID_AGG_BOOT_PROFILE

    CSDID_AGG_BOOT_PROFILE = J(3, 3, 0)
}

void csdid__agg_boot_profile_add(real scalar phase, real scalar started, real scalar work)
{
    external real matrix CSDID_AGG_BOOT_PROFILE

    if (rows(CSDID_AGG_BOOT_PROFILE) < 3 | cols(CSDID_AGG_BOOT_PROFILE) < 3) {
        CSDID_AGG_BOOT_PROFILE = J(3, 3, 0)
    }
    if (phase < 1 | phase > rows(CSDID_AGG_BOOT_PROFILE)) return
    CSDID_AGG_BOOT_PROFILE[phase, 1] = CSDID_AGG_BOOT_PROFILE[phase, 1] + (now() - started) / 1000
    CSDID_AGG_BOOT_PROFILE[phase, 2] = CSDID_AGG_BOOT_PROFILE[phase, 2] + 1
    CSDID_AGG_BOOT_PROFILE[phase, 3] = CSDID_AGG_BOOT_PROFILE[phase, 3] + work
}

real scalar csdid__find_row(
    real colvector id,
    real colvector tt,
    real colvector use,
    real scalar idval,
    real scalar tval)
{
    real scalar r

    for (r = 1; r <= rows(id); r++) {
        if (use[r] != 0 & id[r] == idval & tt[r] == tval) return(r)
    }
    return(.)
}

real scalar csdid__sorted_col_index(real colvector values, real scalar target)
{
    real scalar lo, hi, mid

    lo = 1
    hi = rows(values)
    while (lo <= hi) {
        mid = floor((lo + hi) / 2)
        if (values[mid] == target) return(mid)
        if (values[mid] < target) {
            lo = mid + 1
        }
        else {
            hi = mid - 1
        }
    }
    return(.)
}

real scalar csdid__time_index(real rowvector tlist, real scalar tval)
{
    real scalar i

    for (i = 1; i <= cols(tlist); i++) {
        if (tlist[i] == tval) return(i)
    }
    return(.)
}

real colvector csdid__invlogit(real colvector eta)
{
    real colvector p
    real colvector e2, t

    // F-023 fix: replicate R stats::binomial()$linkinv exactly
    // (src/library/stats/src/family.c, logit_linkinv), which is what
    // DRDID's fastglm_fit(..., stats::binomial(), ...) calls. R thresholds
    // on ETA at +/-30 and uses DBL_EPSILON / 1-DBL_EPSILON, not a direct
    // clamp on p at [1e-8, 1-1e-8]. The post-fit cap at 1-1e-6 (l212)
    // already matches DRDID's pmin and is left alone.
    e2 = eta
    e2 = e2 :+ (e2 :< -30) :* (-30 :- e2)
    e2 = e2 :- (e2 :>  30) :* (e2 :- 30)
    t  = exp(e2)
    t  = t :+ (eta :< -30) :* (epsilon(1) :- t)
    t  = t :+ (eta :>  30) :* (1 / epsilon(1) :- t)
    p  = t :/ (1 :+ t)
    return(p)
}

real colvector csdid__normalize_weights(real colvector w)
{
    real scalar mw

    mw = mean(w)
    if (mw <= 0 | mw >= .) return(J(rows(w), 1, .))
    return(w / mw)
}

real scalar csdid__nonconstant_weights(real colvector w)
{
    return(max(abs(w :- 1)) > 1e-10)
}

real scalar csdid__valid_inverse(real matrix a)
{
    if (sum(a :>= .) > 0) return(0)
    if (rows(a) == cols(a) & diag0cnt(a) > 0) return(0)
    return(1)
}

real matrix csdid__inv_r_parity(real matrix a)
{
    // R parity (F-005): invsym() drops near-collinear columns at its own
    // sweep tolerance, refusing cells R computes. Once the R-side rcond
    // guard has passed, fall back to LU inversion so Stata computes exactly
    // where R computes; a truly singular matrix still yields missings and
    // the caller's csdid__valid_inverse check refuses as before.
    real matrix ai

    ai = invsym(a)
    if (csdid__valid_inverse(ai)) return(ai)
    ai = luinv(a)
    if (hasmissing(ai)) return(J(rows(a), cols(a), .))
    return(ai)
}

real colvector csdid__cap_ps_rc(real colvector ps)
{
    ps = ps :- (ps :> 1 - 1e-6) :* (ps :- (1 - 1e-6))
    return(ps)
}

real colvector csdid__logit_fit_init(real colvector d, real matrix x, real colvector w, real colvector b0)
{
    // F-002: bit-faithful replica of R DRDID's propensity-score fitter,
    // fastglmPure(family = binomial, method = 3, tol = 1e-8, maxit = 100):
    // GLM-style IRLS with mustart = (w*d + 0.5)/(w + 1), working-response
    // WLS steps, and the glm deviance stopping rule
    // |dev - dev_old| / (|dev| + 0.1) < 1e-8. Parity requires replicating
    // the trajectory AND the stopping point, so fits are always cold-started
    // (the b0 warm start is deliberately ignored; validated bit-exact vs
    // fastglmPure at 1e-16 with identical iteration counts).
    real scalar iter, pbar, dev, dev_old
    real colvector b, mu, eta, z, ww
    real matrix h, h_inv

    if (cols(x) == 1) {
        pbar = mean(w :* d) / mean(w)
        if (pbar < 1e-8) pbar = 1e-8
        if (pbar > 1 - 1e-8) pbar = 1 - 1e-8
        return(log(pbar / (1 - pbar)))
    }

    mu = (w :* d :+ 0.5) :/ (w :+ 1)
    eta = log(mu :/ (1 :- mu))
    dev_old = 1e308
    b = J(cols(x), 1, .)
    for (iter = 1; iter <= 100; iter++) {
        ww = w :* mu :* (1 :- mu)
        z = eta :+ (d :- mu) :/ (mu :* (1 :- mu))
        h = quadcross(x, ww, x)
        h_inv = invsym(h)
        if (csdid__valid_inverse(h_inv)) {
            b = h_inv * quadcross(x, ww :* z)
        }
        else {
            b = qrsolve(h, quadcross(x, ww :* z))
        }
        if (sum(b :>= .) > 0) return(J(cols(x), 1, .))
        eta = x * b
        mu = csdid__invlogit(eta)
        dev = -2 * quadsum(w :* (d :* log(mu) :+ (1 :- d) :* log(1 :- mu)))
        if (abs(dev - dev_old) / (abs(dev) + 0.1) < 1e-8) break
        dev_old = dev
    }
    return(b)
}

real colvector csdid__logit_fit(real colvector d, real matrix x, real colvector w)
{
    return(csdid__logit_fit_init(d, x, w, J(cols(x), 1, 0)))
}

real scalar csdid__overlap_status(real matrix x, real colvector d)
{
    // F-040: one classifier for the two distinct reasons R refuses a
    // propensity-score cell before estimating it, so that the warning the user
    // reads names the cause R names. Return codes are the fit_status codes
    // csdid__fit_status_warning() maps to text:
    //
    //   1 = did::overlap_check_fail() -- the fitted propensity reaches 0.999,
    //       i.e. the overlap condition is violated. R runs this guard on an
    //       UNWEIGHTED logit of D on the cohort design, so it fires identically
    //       with and without iweights;
    //   2 = the propensity fit cannot be computed at all, which is DRDID's
    //       separate "coefficients have NA components / multicollinearity"
    //       refusal (the F-013 singular-design branch);
    //   0 = design usable.
    //
    // This extends the F-013 singular-vs-overlap split to the weighted
    // branches. Those previously collapsed both reasons onto 2, so a user who
    // supplied iweights was told that a pure overlap violation -- the same
    // design R warns about with "overlap condition violated" -- was a singular
    // covariate matrix.
    external real matrix CSDID_OVL_X
    external real colvector CSDID_OVL_D
    external real scalar CSDID_OVL_STATUS
    real colvector beta, ps
    real scalar pbar, status

    if (rows(d) == 0) return(2)

    // PERF: this is a PURE function of (x, d) -- an unweighted logit and a
    // threshold on its fitted values -- and it is called once per 2x2 cell from
    // every estimator path, so it was running one full IRLS per cell on top of
    // the estimation fit (measured: 15 of the 30 logit fits on a 15-cell run).
    // On a balanced panel the overlap design is invariant in t for a fixed
    // cohort and control set, so consecutive cells present identical (x, d).
    //
    // The memo key is EXACT ELEMENTWISE EQUALITY of the inputs, not a hash and
    // not a derived key: if (x, d) are identical then the returned status is by
    // construction the one this function would have recomputed, so the result
    // is bit-identical and no staleness across runs is possible. The comparison
    // is O(n*k) against an IRLS costing several passes of transcendentals over
    // the same data, so a miss is cheap and a hit removes the whole fit.
    if (rows(CSDID_OVL_D) == rows(d) & rows(CSDID_OVL_X) == rows(x) &
        cols(CSDID_OVL_X) == cols(x)) {
        if (CSDID_OVL_D == d & CSDID_OVL_X == x) return(CSDID_OVL_STATUS)
    }

    status = 0
    if (cols(x) == 1) {
        pbar = mean(d)
        if (abs(pbar - 0.999) > 1e-6 & pbar >= 0.999) status = 1
    }
    if (status == 0) {
        beta = csdid__logit_fit(d, x, J(rows(d), 1, 1))
        if (sum(beta :>= .) > 0) {
            status = 2
        }
        else {
            ps = csdid__invlogit(x * beta)
            if (max(ps) >= 0.999) status = 1
        }
    }

    CSDID_OVL_X = x
    CSDID_OVL_D = d
    CSDID_OVL_STATUS = status
    return(status)
}

real scalar csdid__rcond1(real matrix a)
{
    // F-005: exact 1-norm reciprocal condition number 1/(||A||_1 ||A^-1||_1),
    // matching R's rcond() (LAPACK dgecon 1-norm estimate; the estimator
    // attains the exact norm for these small blocks except on knife-edge
    // inputs — divergence registry). Returns 0 for singular/invalid input.
    real matrix ai
    real scalar n1a, n1ai

    n1a = max(colsum(abs(a)))
    if (n1a >= . | n1a == 0) return(0)
    ai = luinv(a)
    if (hasmissing(ai)) return(0)
    n1ai = max(colsum(abs(ai)))
    if (n1ai >= . | n1ai == 0) return(0)
    return(1 / (n1a * n1ai))
}

real scalar csdid__rcond_fail(real matrix x, real colvector d)
{
    real matrix xc

    if (cols(x) == 1) return(sum(d :== 0) == 0)
    xc = select(x, d :== 0)
    if (rows(xc) == 0) return(1)
    // F-005 R parity: did 2.5.1 rcond_check_fail tests
    //   rcond(crossprod(control_covs)) < .Machine$double.eps
    // (a rank() test disagrees with it in both directions: misses extreme
    // column-scale disparity; fires on benign near-collinearity R accepts).
    // crossprod in double precision (cross, not quadcross) to match R.
    return(csdid__rcond1(cross(xc, xc)) < 2.220446049250313e-16)
}

void csdid__fit_status_warning(
    real scalar fit_status,
    string scalar method,
    real scalar has_x,
    real scalar g,
    real scalar t)
{
    // Single source of truth for the per-cell refusal warnings; the three
    // 2x2 routes in csdid_basic_attgt used to carry byte-identical copies.
    if (fit_status == 1) {
        printf("warning: overlap condition violated for group %g in time period %g\n", g, t)
        return
    }
    if (fit_status != 2) return
    // DS-04b: the covariate wordings below name a covariate matrix the user
    // never supplied when the model has no covariates. Only R's covariate
    // texts are reproduced when covariates exist; otherwise the message names
    // the actual cause, a degenerate comparison group.
    if (!has_x) {
        printf("warning: no usable comparison units for group %g in time period %g; ATT(g,t) is not estimable\n", g, t)
        return
    }
    if (method == "ipw") {
        // F-013 R parity: ipw singular-design refusals were misrouted through
        // the overlap warning; R's run_DRDID ipw rcond stop uses the ps-design
        // wording.
        printf("warning: The propensity score design matrix is singular for group %g in time period %g. Consider removing some covariates.\n", g, t)
        return
    }
    if (method == "dr" | method == "reg") {
        printf("warning: Covariate matrix for control units is singular or numerically ill-conditioned for group %g in time period %g; consider centering/rescaling covariates or removing collinear terms\n", g, t)
    }
}

real matrix csdid__hessinv_r_parity(real matrix a, real scalar n)
{
    // R parity (F-005): DRDID inverts the pscore hessian XtWX.ps via
    // chol2inv(chol(.)) after guarding rcond(XtWX.ps) < eps (stop()).
    // invsym's sweep instead ZEROES the near-null direction, which rewrites
    // the IF estimation-correction term by O(1) on ill-conditioned designs
    // while atts/SEs barely move. Mirror R: refuse where R stops, otherwise
    // Cholesky-based inverse. Missing return -> caller's existing refusal.
    if (csdid__rcond1(a) < 2.220446049250313e-16) return(J(rows(a), cols(a), .))
    return(cholinv(a) * n)
}

real scalar csdid__cross_rank_fail(real matrix xx)
{
    if (rows(xx) == 0 | cols(xx) == 0) return(1)
    return(rank(xx) < cols(xx))
}

real colvector csdid__reg_panel_fit(
    real colvector y1,
    real colvector y0,
    real colvector d,
    real matrix x,
    real colvector wraw)
{
    real scalar n, mw_treat, mw_cont, eta_treat, eta_cont, att
    real matrix xtwx, xtwx_inv, xpx_inv
    real colvector dy, w, beta, out_delta, w_treat, w_cont
    real colvector reg_att_treat, reg_att_cont, weights_ols
    real colvector inf_treat, inf_cont_1, inf_cont_2, inf_control, inf
    real colvector m1, gamma_ols, ols_resid

    n = rows(d)
    dy = y1 :- y0
    w = csdid__normalize_weights(wraw)
    if (sum(w :>= .) > 0) return(. \ J(n, 1, .) \ 3)
    // DS-04: no `n_control <= cols(x)' pre-test here. R did 2.5.1 gates this
    // cell on rcond_check_fail() ALONE, so a comparison group with exactly one
    // unit (or with as many units as regressors) is estimated by R and must be
    // estimated here too. csdid__rcond_fail() already refuses every design R
    // refuses -- including the zero-control case (cols(x)==1 branch) and the
    // rank-deficient control design -- so the extra count test only produced
    // missing ATT/SE where R returns finite values.
    if (csdid__rcond_fail(x, d)) return(. \ J(n, 1, .) \ 2)  // F-005: R rcond_check_fail on the control design

    weights_ols = w :* (1 :- d)
    xtwx = quadcross(x, weights_ols, x)
    xtwx_inv = csdid__inv_r_parity(xtwx)  // F-005: R-parity inverse
    if (!csdid__valid_inverse(xtwx_inv)) return(. \ J(n, 1, .) \ 2)
    beta = xtwx_inv * quadcross(x, weights_ols :* dy)
    out_delta = x * beta

    w_treat = w :* d
    w_cont = w :* d
    mw_treat = mean(w_treat)
    mw_cont = mean(w_cont)
    reg_att_treat = w_treat :* dy
    reg_att_cont = w_cont :* out_delta
    eta_treat = mean(reg_att_treat) / mw_treat
    eta_cont = mean(reg_att_cont) / mw_cont
    att = eta_treat - eta_cont

    xpx_inv = n * xtwx_inv
    ols_resid = weights_ols :* (dy :- out_delta)

    inf_treat = (reg_att_treat :- w_treat * eta_treat) / mw_treat
    inf_cont_1 = reg_att_cont :- w_cont * eta_cont
    m1 = quadcross(x, w_cont) / n
    gamma_ols = xpx_inv * m1
    inf_cont_2 = ols_resid :* (x * gamma_ols)
    inf_control = (inf_cont_1 + inf_cont_2) / mw_cont
    inf = inf_treat - inf_control

    return(att \ inf \ 0)
}

real colvector csdid__ipw_panel_fit(
    real colvector y1,
    real colvector y0,
    real colvector d,
    real matrix x,
    real colvector wraw,
    real scalar trim_level)
{
    real scalar n, mw_treat, mw_cont, eta_treat, eta_cont, att, nonconstant_w, pbar, hscalar, keep_control
    real scalar mean_w, mean_wd, mean_w0, treat_moment, cont_moment, cont_factor, m2_scalar
    real scalar overlap_status
    real matrix h
    real colvector dy, beta, ps, trim, w, w_treat, w_cont, att_treat, att_cont
    real colvector inf_treat, inf_cont_1, inf_cont_2, inf_control, inf
    real colvector m2, gamma_ps

    n = rows(d)
    dy = y1 :- y0
    w = csdid__normalize_weights(wraw)
    if (sum(w :>= .) > 0) return(. \ J(n, 1, .) \ 3)
    nonconstant_w = csdid__nonconstant_weights(w)
    if (cols(x) == 1) {
        pbar = mean(w :* d) / mean(w)
        if (pbar < 1e-8) pbar = 1e-8
        if (pbar >= 0.999) return(. \ J(n, 1, .) \ 1)
        if (pbar > 1 - 1e-8) pbar = 1 - 1e-8
        keep_control = (pbar < trim_level)
        mean_w = mean(w)
        mean_wd = quadcross(w, d) / n
        mean_w0 = mean_w - mean_wd
        cont_factor = keep_control * pbar / (1 - pbar)
        mw_treat = mean_wd
        mw_cont = cont_factor * mean_w0
        if (min((mw_treat, mw_cont)) <= 0) return(. \ J(n, 1, .) \ 3)
        treat_moment = quadcross(w, d :* dy) / n
        cont_moment = cont_factor * quadcross(w, (1 :- d) :* dy) / n
        eta_treat = treat_moment / mw_treat
        eta_cont = cont_moment / mw_cont
        att = eta_treat - eta_cont
        m2_scalar = cont_moment - mw_cont * eta_cont
        hscalar = 1 / (pbar * (1 - pbar))
        inf = (w :* d :* (dy :- eta_treat)) / mw_treat :-
            ((cont_factor * w :* (1 :- d) :* (dy :- eta_cont)) :+
            (w :* (d :- pbar)) * (hscalar * m2_scalar)) / mw_cont
        return(att \ inf \ 0)
    }
    if (nonconstant_w) {
        // F-040: classify the pre-estimation refusal the way R does. The guard
        // itself is unchanged (same unweighted fit, same 0.999 cut-off, same
        // set of refused cells); only the reported cause changes, so an
        // overlap violation under iweights no longer reaches the user as a
        // singular-covariate-matrix message.
        overlap_status = csdid__overlap_status(x, d)
        if (overlap_status) return(. \ J(n, 1, .) \ overlap_status)
    }
    // csdid__logit_fit_init() documents that its warm start is deliberately
    // ignored (parity requires cold starts), so dropping the discarded
    // beta_start argument leaves the fit bit-identical.
    beta = csdid__logit_fit(d, x, w)
    if (sum(beta :>= .) > 0) return(. \ J(n, 1, .) \ 2)  // F-013: singular ps design -> fit_status 2 (R rcond stop), not overlap
    // DRDID::ipw_did_panel / drdid_panel apply pmin(ps.fit, 1 - 1e-06) before
    // forming the control weight ps/(1-ps) and the Hessian weight ps*(1-ps).
    // The RC paths already used csdid__cap_ps_rc(); the panel paths did not, so
    // an uncapped ps could reach 1-2.2e-16 and blow the control weight up to
    // ~4.5e15 where R caps it at ~1e6. Unreachable at the 0.995 default (such
    // controls are trimmed), but reachable now that pscoretrim() >= 1 (no
    // trimming) is accepted, so cap here exactly as DRDID does.
    ps = csdid__cap_ps_rc(csdid__invlogit(x * beta))
    if (!nonconstant_w & max(ps) >= 0.999) return(. \ J(n, 1, .) \ 1)
    trim = J(n, 1, 1)
    trim = trim :* ((d :== 1) :| (ps :< trim_level))

    w_treat = trim :* w :* d
    w_cont = trim :* w :* ps :* (1 :- d) :/ (1 :- ps)
    mw_treat = mean(w_treat)
    mw_cont = mean(w_cont)
    att_treat = w_treat :* dy
    att_cont = w_cont :* dy
    eta_treat = mean(att_treat) / mw_treat
    eta_cont = mean(att_cont) / mw_cont
    att = eta_treat - eta_cont

    h = quadcross(x, ps :* (1 :- ps) :* w, x)
    h = csdid__hessinv_r_parity(h, n)  // F-005: R chol2inv(chol()) after the rcond guard
    if (sum(h :>= .) > 0) return(. \ J(n, 1, .) \ 2)  // F-013: singular ps design -> fit_status 2 (R rcond stop), not overlap

    inf_treat = (att_treat :- w_treat * eta_treat) / mw_treat
    inf_cont_1 = att_cont :- w_cont * eta_cont
    m2 = quadcross(x, w_cont :* (dy :- eta_cont)) / n
    gamma_ps = h * m2
    inf_cont_2 = (w :* (d :- ps)) :* (x * gamma_ps)
    inf_control = (inf_cont_1 + inf_cont_2) / mw_cont
    inf = inf_treat - inf_control

    return(att \ inf \ 0)
}

real colvector csdid__dr_panel_fit(
    real colvector y1,
    real colvector y0,
    real colvector d,
    real matrix x,
    real colvector wraw,
    real scalar trim_level)
{
    real scalar n, mw_treat, mw_cont, eta_treat, eta_cont, att, nonconstant_w, overlap_status
    real matrix xtwx, xtwx_inv, xpx_inv, h
    real colvector dy, w, beta_or, beta_ps, ps, trim, out_delta, w_treat, w_cont
    real colvector dr_treat, dr_cont, weights_ols
    real colvector inf_treat_1, inf_treat_2, inf_treat
    real colvector inf_cont_1, inf_cont_2, inf_cont_3, inf_control, inf
    real colvector m1, m2, m3, gamma_ols, gamma_ps, ols_resid

    n = rows(d)
    dy = y1 :- y0
    w = csdid__normalize_weights(wraw)
    if (sum(w :>= .) > 0) return(. \ J(n, 1, .) \ 3)
    nonconstant_w = csdid__nonconstant_weights(w)
    if (nonconstant_w) {
        // F-040: see csdid__ipw_panel_fit -- same guard, R's classification.
        overlap_status = csdid__overlap_status(x, d)
        if (overlap_status) return(. \ J(n, 1, .) \ overlap_status)
    }
    beta_ps = csdid__logit_fit(d, x, w)
    if (sum(beta_ps :>= .) > 0) return(. \ J(n, 1, .) \ 2)  // F-013: singular ps design -> fit_status 2 (R rcond stop), not overlap
    // See csdid__ipw_panel_fit: DRDID::drdid_panel caps ps at 1 - 1e-06 before
    // the control weight and Hessian weight are formed; match it here too.
    ps = csdid__cap_ps_rc(csdid__invlogit(x * beta_ps))
    if (!nonconstant_w & max(ps) >= 0.999) return(. \ J(n, 1, .) \ 1)
    trim = J(n, 1, 1)
    trim = trim :* ((d :== 1) :| (ps :< trim_level))

    // DS-04: see csdid__reg_panel_fit -- R gates on rcond_check_fail() alone,
    // so one-control-unit comparison groups are estimated, not blanked.
    if (csdid__rcond_fail(x, d)) return(. \ J(n, 1, .) \ 2)  // F-005: R rcond_check_fail on the control design
    weights_ols = w :* (1 :- d)
    xtwx = quadcross(x, weights_ols, x)
    xtwx_inv = csdid__inv_r_parity(xtwx)  // F-005: R-parity inverse
    if (!csdid__valid_inverse(xtwx_inv)) return(. \ J(n, 1, .) \ 2)
    beta_or = xtwx_inv * quadcross(x, weights_ols :* dy)
    out_delta = x * beta_or

    w_treat = trim :* w :* d
    w_cont = trim :* w :* ps :* (1 :- d) :/ (1 :- ps)
    mw_treat = mean(w_treat)
    mw_cont = mean(w_cont)
    dr_treat = w_treat :* (dy :- out_delta)
    dr_cont = w_cont :* (dy :- out_delta)
    eta_treat = mean(dr_treat) / mw_treat
    eta_cont = mean(dr_cont) / mw_cont
    att = eta_treat - eta_cont

    xpx_inv = n * xtwx_inv
    ols_resid = weights_ols :* (dy :- out_delta)

    h = quadcross(x, ps :* (1 :- ps) :* w, x)
    h = csdid__hessinv_r_parity(h, n)  // F-005: R chol2inv(chol()) after the rcond guard
    if (sum(h :>= .) > 0) return(. \ J(n, 1, .) \ 2)  // F-013: singular ps design -> fit_status 2 (R rcond stop), not overlap

    inf_treat_1 = dr_treat :- w_treat * eta_treat
    m1 = quadcross(x, w_treat) / n
    gamma_ols = xpx_inv * m1
    inf_treat_2 = ols_resid :* (x * gamma_ols)
    inf_treat = (inf_treat_1 - inf_treat_2) / mw_treat

    inf_cont_1 = dr_cont :- w_cont * eta_cont
    m2 = quadcross(x, w_cont :* (dy :- out_delta :- eta_cont)) / n
    gamma_ps = h * m2
    inf_cont_2 = (w :* (d :- ps)) :* (x * gamma_ps)
    m3 = quadcross(x, w_cont) / n
    gamma_ols = xpx_inv * m3
    inf_cont_3 = ols_resid :* (x * gamma_ols)
    inf_control = (inf_cont_1 + inf_cont_2 - inf_cont_3) / mw_cont
    inf = inf_treat - inf_control

    return(att \ inf \ 0)
}

real colvector csdid__dr_panel_fit_precomputed(
    real colvector y1,
    real colvector y0,
    real colvector d,
    real matrix x,
    real colvector w,
    real colvector ps,
    real colvector trim,
    real colvector w_treat,
    real colvector w_cont,
    real colvector score_ps,
    real colvector xgamma_treat_ols,
    real colvector xgamma_cont_ols,
    real scalar mw_treat,
    real scalar mw_cont,
    real matrix xtwx_inv,
    real matrix xpx_inv,
    real matrix h,
    real colvector weights_ols)
{
    real scalar n, eta_treat, eta_cont, att
    real colvector dy, beta_or, out_delta, dr_treat, dr_cont, ols_resid
    real colvector inf_treat_1, inf_treat_2, inf_treat
    real colvector inf_cont_1, inf_cont_2, inf_cont_3, inf_control, inf
    real colvector m2, gamma_ps

    n = rows(d)
    dy = y1 :- y0
    beta_or = xtwx_inv * quadcross(x, weights_ols :* dy)
    out_delta = x * beta_or

    dr_treat = w_treat :* (dy :- out_delta)
    dr_cont = w_cont :* (dy :- out_delta)
    eta_treat = mean(dr_treat) / mw_treat
    eta_cont = mean(dr_cont) / mw_cont
    att = eta_treat - eta_cont

    ols_resid = weights_ols :* (dy :- out_delta)

    inf_treat_1 = dr_treat :- w_treat * eta_treat
    inf_treat_2 = ols_resid :* xgamma_treat_ols
    inf_treat = (inf_treat_1 - inf_treat_2) / mw_treat

    inf_cont_1 = dr_cont :- w_cont * eta_cont
    m2 = quadcross(x, w_cont :* (dy :- out_delta :- eta_cont)) / n
    gamma_ps = h * m2
    inf_cont_2 = score_ps :* (x * gamma_ps)
    inf_cont_3 = ols_resid :* xgamma_cont_ols
    inf_control = (inf_cont_1 + inf_cont_2 - inf_cont_3) / mw_cont
    inf = inf_treat - inf_control

    return(att \ inf \ 0)
}

real colvector csdid__reg_rc_fit(
    real colvector y,
    real colvector post,
    real colvector d,
    real matrix x,
    real colvector wraw)
{
    real scalar n, eta_treat_pre, eta_treat_post, eta_cont, att
    real scalar mw_treat_pre, mw_treat_post, mw_cont
    real matrix xpre, xpost, xtwx_pre, xtwx_post, xtwx_inv_pre, xtwx_inv_post, xpx_inv_pre, xpx_inv_post
    real colvector w, beta_pre, beta_post, out_pre, out_post
    real colvector w_treat_pre, w_treat_post, w_cont, reg_treat_pre, reg_treat_post, reg_cont
    real colvector weights_ols_pre, weights_ols_post
    real colvector inf_treat_pre, inf_treat_post, inf_treat
    real colvector inf_cont_1, inf_cont_2_pre, inf_cont_2_post, inf_control, inf
    real colvector m1, gamma_ols, ols_resid_pre, ols_resid_post

    n = rows(d)
    w = csdid__normalize_weights(wraw)
    if (sum(w :>= .) > 0) return(. \ J(n, 1, .) \ 3)

    xpre = select(x, (d :== 0) :& (post :== 0))
    xpost = select(x, (d :== 0) :& (post :== 1))
    if (rows(xpre) <= cols(x) | rows(xpost) <= cols(x)) return(. \ J(n, 1, .) \ 2)
    if (csdid__rcond_fail(x, d)) return(. \ J(n, 1, .) \ 2)  // F-005: R rcond_check_fail on the control design
    xtwx_pre = quadcross(xpre, select(w, (d :== 0) :& (post :== 0)), xpre)
    xtwx_post = quadcross(xpost, select(w, (d :== 0) :& (post :== 1)), xpost)
    xtwx_inv_pre = csdid__inv_r_parity(xtwx_pre)  // F-005: R-parity inverse
    xtwx_inv_post = csdid__inv_r_parity(xtwx_post)  // F-005: R-parity inverse
    if (!csdid__valid_inverse(xtwx_inv_pre) | !csdid__valid_inverse(xtwx_inv_post)) return(. \ J(n, 1, .) \ 2)
    beta_pre = xtwx_inv_pre * quadcross(xpre, select(w :* y, (d :== 0) :& (post :== 0)))
    beta_post = xtwx_inv_post * quadcross(xpost, select(w :* y, (d :== 0) :& (post :== 1)))
    out_pre = x * beta_pre
    out_post = x * beta_post

    w_treat_pre = w :* d :* (1 :- post)
    w_treat_post = w :* d :* post
    w_cont = w :* d
    mw_treat_pre = mean(w_treat_pre)
    mw_treat_post = mean(w_treat_post)
    mw_cont = mean(w_cont)
    if (min((mw_treat_pre, mw_treat_post, mw_cont)) <= 0) return(. \ J(n, 1, .) \ 3)

    reg_treat_pre = w_treat_pre :* y
    reg_treat_post = w_treat_post :* y
    reg_cont = w_cont :* (out_post :- out_pre)
    eta_treat_pre = mean(reg_treat_pre) / mw_treat_pre
    eta_treat_post = mean(reg_treat_post) / mw_treat_post
    eta_cont = mean(reg_cont) / mw_cont
    att = (eta_treat_post - eta_treat_pre) - eta_cont

    weights_ols_pre = w :* (1 :- d) :* (1 :- post)
    xpx_inv_pre = n * xtwx_inv_pre
    ols_resid_pre = weights_ols_pre :* (y :- out_pre)
    weights_ols_post = w :* (1 :- d) :* post
    xpx_inv_post = n * xtwx_inv_post
    ols_resid_post = weights_ols_post :* (y :- out_post)

    inf_treat_pre = (reg_treat_pre :- w_treat_pre * eta_treat_pre) / mw_treat_pre
    inf_treat_post = (reg_treat_post :- w_treat_post * eta_treat_post) / mw_treat_post
    inf_treat = inf_treat_post - inf_treat_pre
    inf_cont_1 = reg_cont :- w_cont * eta_cont
    m1 = quadcross(x, w_cont) / n
    gamma_ols = xpx_inv_post * m1
    inf_cont_2_post = ols_resid_post :* (x * gamma_ols)
    gamma_ols = xpx_inv_pre * m1
    inf_cont_2_pre = ols_resid_pre :* (x * gamma_ols)
    inf_control = (inf_cont_1 + inf_cont_2_post - inf_cont_2_pre) / mw_cont
    inf = inf_treat - inf_control

    return(att \ inf \ 0)
}

real colvector csdid__ipw_rc_fit(
    real colvector y,
    real colvector post,
    real colvector d,
    real matrix x,
    real colvector wraw,
    real scalar trim_level)
{
    real scalar n, att, att_treat_pre, att_treat_post, att_cont_pre, att_cont_post, nonconstant_w, pbar, hscalar, keep_control
    real scalar mw_treat_pre, mw_treat_post, mw_cont_pre, mw_cont_post, overlap_status
    real matrix h
    real colvector w, beta, ps, trim, W
    real colvector w_treat_pre, w_treat_post, w_cont_pre, w_cont_post
    real colvector eta_treat_pre, eta_treat_post, eta_cont_pre, eta_cont_post
    real colvector inf_treat_pre, inf_treat_post, inf_treat
    real colvector inf_cont_pre, inf_cont_post, inf_cont, inf_cont_ps, inf
    real colvector m2_pre, m2_post, gamma_ps

    n = rows(d)
    w = csdid__normalize_weights(wraw)
    if (sum(w :>= .) > 0) return(. \ J(n, 1, .) \ 3)
    nonconstant_w = csdid__nonconstant_weights(w)
    if (cols(x) == 1) {
        pbar = mean(w :* d) / mean(w)
        if (pbar < 1e-8) pbar = 1e-8
        if (pbar >= 0.999) return(. \ J(n, 1, .) \ 1)
        if (pbar > 1 - 1e-8) pbar = 1 - 1e-8
        keep_control = (pbar < trim_level)
        w_treat_pre = w :* d :* (1 :- post)
        w_treat_post = w :* d :* post
        w_cont_pre = keep_control * w :* pbar :* (1 :- d) :* (1 :- post) :/ (1 - pbar)
        w_cont_post = keep_control * w :* pbar :* (1 :- d) :* post :/ (1 - pbar)
        mw_treat_pre = mean(w_treat_pre)
        mw_treat_post = mean(w_treat_post)
        mw_cont_pre = mean(w_cont_pre)
        mw_cont_post = mean(w_cont_post)
        if (min((mw_treat_pre, mw_treat_post, mw_cont_pre, mw_cont_post)) <= 0) return(. \ J(n, 1, .) \ 3)
        att_treat_pre = mean(w_treat_pre :* y) / mw_treat_pre
        att_treat_post = mean(w_treat_post :* y) / mw_treat_post
        att_cont_pre = mean(w_cont_pre :* y) / mw_cont_pre
        att_cont_post = mean(w_cont_post :* y) / mw_cont_post
        att = (att_treat_post - att_treat_pre) - (att_cont_post - att_cont_pre)
        inf_treat_pre = (w_treat_pre :* y :- w_treat_pre * att_treat_pre) / mw_treat_pre
        inf_treat_post = (w_treat_post :* y :- w_treat_post * att_treat_post) / mw_treat_post
        inf_treat = inf_treat_post - inf_treat_pre
        inf_cont_pre = (w_cont_pre :* y :- w_cont_pre * att_cont_pre) / mw_cont_pre
        inf_cont_post = (w_cont_post :* y :- w_cont_post * att_cont_post) / mw_cont_post
        inf_cont = inf_cont_post - inf_cont_pre
        m2_pre = mean(w_cont_pre :* (y :- att_cont_pre)) / mw_cont_pre
        m2_post = mean(w_cont_post :* (y :- att_cont_post)) / mw_cont_post
        hscalar = 1 / (pbar * (1 - pbar))
        inf_cont_ps = (w :* (d :- pbar)) :* (hscalar * (m2_post - m2_pre))
        inf_cont = inf_cont + inf_cont_ps
        inf = inf_treat - inf_cont
        return(att \ inf \ 0)
    }
    if (nonconstant_w) {
        // F-040: see csdid__ipw_panel_fit -- same guard, R's classification.
        overlap_status = csdid__overlap_status(x, d)
        if (overlap_status) return(. \ J(n, 1, .) \ overlap_status)
    }
    beta = csdid__logit_fit(d, x, w)
    if (sum(beta :>= .) > 0) return(. \ J(n, 1, .) \ 2)  // F-013: singular ps design -> fit_status 2 (R rcond stop), not overlap
    ps = csdid__cap_ps_rc(csdid__invlogit(x * beta))
    if (!nonconstant_w & max(ps) >= 0.999) return(. \ J(n, 1, .) \ 1)
    W = ps :* (1 :- ps) :* w
    trim = J(n, 1, 1)
    trim = trim :* ((d :== 1) :| (ps :< trim_level))

    w_treat_pre = trim :* w :* d :* (1 :- post)
    w_treat_post = trim :* w :* d :* post
    w_cont_pre = trim :* w :* ps :* (1 :- d) :* (1 :- post) :/ (1 :- ps)
    w_cont_post = trim :* w :* ps :* (1 :- d) :* post :/ (1 :- ps)
    mw_treat_pre = mean(w_treat_pre)
    mw_treat_post = mean(w_treat_post)
    mw_cont_pre = mean(w_cont_pre)
    mw_cont_post = mean(w_cont_post)
    if (min((mw_treat_pre, mw_treat_post, mw_cont_pre, mw_cont_post)) <= 0) return(. \ J(n, 1, .) \ 3)

    eta_treat_pre = w_treat_pre :* y / mw_treat_pre
    eta_treat_post = w_treat_post :* y / mw_treat_post
    eta_cont_pre = w_cont_pre :* y / mw_cont_pre
    eta_cont_post = w_cont_post :* y / mw_cont_post
    att_treat_pre = mean(eta_treat_pre)
    att_treat_post = mean(eta_treat_post)
    att_cont_pre = mean(eta_cont_pre)
    att_cont_post = mean(eta_cont_post)
    att = (att_treat_post - att_treat_pre) - (att_cont_post - att_cont_pre)

    h = quadcross(x, W, x)
    h = csdid__hessinv_r_parity(h, n)  // F-005: R chol2inv(chol()) after the rcond guard
    if (sum(h :>= .) > 0) return(. \ J(n, 1, .) \ 2)  // F-013: singular ps design -> fit_status 2 (R rcond stop), not overlap

    inf_treat_pre = eta_treat_pre :- w_treat_pre * att_treat_pre / mw_treat_pre
    inf_treat_post = eta_treat_post :- w_treat_post * att_treat_post / mw_treat_post
    inf_treat = inf_treat_post - inf_treat_pre
    inf_cont_pre = eta_cont_pre :- w_cont_pre * att_cont_pre / mw_cont_pre
    inf_cont_post = eta_cont_post :- w_cont_post * att_cont_post / mw_cont_post
    inf_cont = inf_cont_post - inf_cont_pre
    m2_pre = quadcross(x, w_cont_pre :* (y :- att_cont_pre)) / n / mw_cont_pre
    m2_post = quadcross(x, w_cont_post :* (y :- att_cont_post)) / n / mw_cont_post
    gamma_ps = h * (m2_post - m2_pre)
    inf_cont_ps = (w :* (d :- ps)) :* (x * gamma_ps)
    inf_cont = inf_cont + inf_cont_ps
    inf = inf_treat - inf_cont

    return(att \ inf \ 0)
}

real colvector csdid__dr_rc_fit(
    real colvector y,
    real colvector post,
    real colvector d,
    real matrix x,
    real colvector wraw,
    real scalar trim_level)
{
    real scalar n, att, mw_treat_pre, mw_treat_post, mw_cont_pre, mw_cont_post, nonconstant_w
    real scalar mw_d, mw_dt1, mw_dt0, overlap_status
    real scalar att_treat_pre, att_treat_post, att_cont_pre, att_cont_post
    real scalar att_d_post, att_dt1_post, att_d_pre, att_dt0_pre
    real matrix xcp, xct, xtp, xtt, h
    real matrix xtwx_c_pre, xtwx_c_post, xtwx_t_pre, xtwx_t_post
    real matrix xtwx_inv_c_pre, xtwx_inv_c_post, xtwx_inv_t_pre, xtwx_inv_t_post
    real matrix xpx_inv_pre, xpx_inv_post, xpx_inv_pre_treat, xpx_inv_post_treat
    real colvector w, beta_ps, ps, W, trim, post0, d0, wd, wc, wy, psratio
    real colvector m_c_pre, m_c_post, m_t_pre, m_t_post
    real colvector beta_c_pre, beta_c_post, beta_t_pre, beta_t_post
    real colvector out_c_pre, out_c_post, out_c, out_t_pre, out_t_post
    real colvector w_treat_pre, w_treat_post, w_cont_pre, w_cont_post, w_d, w_dt1, w_dt0
    real colvector eta_treat_pre, eta_treat_post, eta_cont_pre, eta_cont_post
    real colvector eta_d_post, eta_dt1_post, eta_d_pre, eta_dt0_pre
    real colvector weights_ols_pre, weights_ols_post, weights_ols_pre_treat, weights_ols_post_treat
    real colvector inf_treat_pre, inf_treat_post, inf_treat, inf_cont_pre, inf_cont_post, inf_cont
    real colvector inf_treat_or_post, inf_treat_or_pre, inf_cont_or_post, inf_cont_or_pre
    real colvector inf_treat_or, inf_cont_or, inf_cont_ps, inf_eff, inf_or, inf
    real colvector inf_eff1, inf_eff2, inf_eff3, inf_eff4, inf_or_post, inf_or_pre
    real colvector m1_post, m1_pre, m2_post, m2_pre, m3_post, m3_pre, mom_post, mom_pre
    real colvector ols_res_pre, ols_res_post, ols_res_pre_treat, ols_res_post_treat
    real colvector gamma_ols, gamma_ps

    n = rows(d)
    w = csdid__normalize_weights(wraw)
    if (sum(w :>= .) > 0) return(. \ J(n, 1, .) \ 3)
    nonconstant_w = csdid__nonconstant_weights(w)
    if (nonconstant_w) {
        // F-040: see csdid__ipw_panel_fit -- same guard, R's classification.
        overlap_status = csdid__overlap_status(x, d)
        if (overlap_status) return(. \ J(n, 1, .) \ overlap_status)
    }
    beta_ps = csdid__logit_fit(d, x, w)
    if (sum(beta_ps :>= .) > 0) return(. \ J(n, 1, .) \ 2)  // F-013: singular ps design -> fit_status 2 (R rcond stop), not overlap
    ps = csdid__cap_ps_rc(csdid__invlogit(x * beta_ps))
    if (!nonconstant_w & max(ps) >= 0.999) return(. \ J(n, 1, .) \ 1)
    W = ps :* (1 :- ps) :* w
    trim = J(n, 1, 1)
    trim = trim :* ((d :== 1) :| (ps :< trim_level))
    post0 = 1 :- post
    d0 = 1 :- d
    wd = w :* d
    wc = w :* d0
    wy = w :* y
    psratio = ps :/ (1 :- ps)

    m_c_pre = d0 :& post0
    m_c_post = d0 :& post
    m_t_pre = d :& post0
    m_t_post = d :& post
    xcp = select(x, m_c_pre)
    xct = select(x, m_c_post)
    xtp = select(x, m_t_pre)
    xtt = select(x, m_t_post)
    if (rows(xcp) <= cols(x) | rows(xct) <= cols(x) | rows(xtp) <= cols(x) | rows(xtt) <= cols(x)) return(. \ J(n, 1, .) \ 2)
    if (csdid__rcond_fail(x, d)) return(. \ J(n, 1, .) \ 2)  // F-005: R rcond_check_fail on the control design
    xtwx_c_pre = quadcross(xcp, select(w, m_c_pre), xcp)
    xtwx_c_post = quadcross(xct, select(w, m_c_post), xct)
    xtwx_t_pre = quadcross(xtp, select(w, m_t_pre), xtp)
    xtwx_t_post = quadcross(xtt, select(w, m_t_post), xtt)
    xtwx_inv_c_pre = csdid__inv_r_parity(xtwx_c_pre)  // F-005: R-parity inverse
    xtwx_inv_c_post = csdid__inv_r_parity(xtwx_c_post)  // F-005: R-parity inverse
    xtwx_inv_t_pre = csdid__inv_r_parity(xtwx_t_pre)  // F-005: R-parity inverse
    xtwx_inv_t_post = csdid__inv_r_parity(xtwx_t_post)  // F-005: R-parity inverse
    if (!csdid__valid_inverse(xtwx_inv_c_pre) | !csdid__valid_inverse(xtwx_inv_c_post) | !csdid__valid_inverse(xtwx_inv_t_pre) | !csdid__valid_inverse(xtwx_inv_t_post)) return(. \ J(n, 1, .) \ 2)

    beta_c_pre = xtwx_inv_c_pre * quadcross(xcp, select(wy, m_c_pre))
    beta_c_post = xtwx_inv_c_post * quadcross(xct, select(wy, m_c_post))
    beta_t_pre = xtwx_inv_t_pre * quadcross(xtp, select(wy, m_t_pre))
    beta_t_post = xtwx_inv_t_post * quadcross(xtt, select(wy, m_t_post))

    out_c_pre = x * beta_c_pre
    out_c_post = x * beta_c_post
    out_c = post :* out_c_post + post0 :* out_c_pre
    out_t_pre = x * beta_t_pre
    out_t_post = x * beta_t_post

    w_treat_pre = trim :* wd :* post0
    w_treat_post = trim :* wd :* post
    w_cont_pre = trim :* wc :* psratio :* post0
    w_cont_post = trim :* wc :* psratio :* post
    w_d = trim :* wd
    w_dt1 = trim :* wd :* post
    w_dt0 = trim :* wd :* post0
    mw_treat_pre = mean(w_treat_pre)
    mw_treat_post = mean(w_treat_post)
    mw_cont_pre = mean(w_cont_pre)
    mw_cont_post = mean(w_cont_post)
    mw_d = mean(w_d)
    mw_dt1 = mean(w_dt1)
    mw_dt0 = mean(w_dt0)
    if (min((mw_treat_pre, mw_treat_post, mw_cont_pre, mw_cont_post, mw_d, mw_dt1, mw_dt0)) <= 0) return(. \ J(n, 1, .) \ 3)

    eta_treat_pre = w_treat_pre :* (y :- out_c) / mw_treat_pre
    eta_treat_post = w_treat_post :* (y :- out_c) / mw_treat_post
    eta_cont_pre = w_cont_pre :* (y :- out_c) / mw_cont_pre
    eta_cont_post = w_cont_post :* (y :- out_c) / mw_cont_post
    eta_d_post = w_d :* (out_t_post :- out_c_post) / mw_d
    eta_dt1_post = w_dt1 :* (out_t_post :- out_c_post) / mw_dt1
    eta_d_pre = w_d :* (out_t_pre :- out_c_pre) / mw_d
    eta_dt0_pre = w_dt0 :* (out_t_pre :- out_c_pre) / mw_dt0
    att_treat_pre = mean(eta_treat_pre)
    att_treat_post = mean(eta_treat_post)
    att_cont_pre = mean(eta_cont_pre)
    att_cont_post = mean(eta_cont_post)
    att_d_post = mean(eta_d_post)
    att_dt1_post = mean(eta_dt1_post)
    att_d_pre = mean(eta_d_pre)
    att_dt0_pre = mean(eta_dt0_pre)
    att = (att_treat_post - att_treat_pre) - (att_cont_post - att_cont_pre) + (att_d_post - att_dt1_post) - (att_d_pre - att_dt0_pre)

    weights_ols_pre = wc :* post0
    xpx_inv_pre = n * xtwx_inv_c_pre
    ols_res_pre = weights_ols_pre :* (y :- out_c_pre)
    weights_ols_post = wc :* post
    xpx_inv_post = n * xtwx_inv_c_post
    ols_res_post = weights_ols_post :* (y :- out_c_post)
    weights_ols_pre_treat = wd :* post0
    xpx_inv_pre_treat = n * xtwx_inv_t_pre
    ols_res_pre_treat = weights_ols_pre_treat :* (y :- out_t_pre)
    weights_ols_post_treat = wd :* post
    xpx_inv_post_treat = n * xtwx_inv_t_post
    ols_res_post_treat = weights_ols_post_treat :* (y :- out_t_post)

    h = quadcross(x, W, x)
    h = csdid__hessinv_r_parity(h, n)  // F-005: R chol2inv(chol()) after the rcond guard
    if (sum(h :>= .) > 0) return(. \ J(n, 1, .) \ 2)  // F-013: singular ps design -> fit_status 2 (R rcond stop), not overlap

    inf_treat_pre = eta_treat_pre :- w_treat_pre * att_treat_pre / mw_treat_pre
    inf_treat_post = eta_treat_post :- w_treat_post * att_treat_post / mw_treat_post
    m1_post = -quadcross(x, w_treat_post) / n / mw_treat_post
    m1_pre = -quadcross(x, w_treat_pre) / n / mw_treat_pre
    gamma_ols = xpx_inv_post * m1_post
    inf_treat_or_post = ols_res_post :* (x * gamma_ols)
    gamma_ols = xpx_inv_pre * m1_pre
    inf_treat_or_pre = ols_res_pre :* (x * gamma_ols)
    inf_cont_pre = eta_cont_pre :- w_cont_pre * att_cont_pre / mw_cont_pre
    inf_cont_post = eta_cont_post :- w_cont_post * att_cont_post / mw_cont_post
    m2_pre = quadcross(x, w_cont_pre :* (y :- out_c :- att_cont_pre)) / n / mw_cont_pre
    m2_post = quadcross(x, w_cont_post :* (y :- out_c :- att_cont_post)) / n / mw_cont_post
    gamma_ps = h * (m2_post - m2_pre)
    inf_cont_ps = (w :* (d :- ps)) :* (x * gamma_ps)
    m3_post = -quadcross(x, w_cont_post) / n / mw_cont_post
    m3_pre = -quadcross(x, w_cont_pre) / n / mw_cont_pre
    gamma_ols = xpx_inv_post * m3_post
    inf_cont_or_post = ols_res_post :* (x * gamma_ols)
    gamma_ols = xpx_inv_pre * m3_pre
    inf_cont_or_pre = ols_res_pre :* (x * gamma_ols)
    inf_eff1 = eta_d_post :- w_d * att_d_post / mw_d
    inf_eff2 = eta_dt1_post :- w_dt1 * att_dt1_post / mw_dt1
    inf_eff3 = eta_d_pre :- w_d * att_d_pre / mw_d
    inf_eff4 = eta_dt0_pre :- w_dt0 * att_dt0_pre / mw_dt0
    inf_eff = (inf_eff1 - inf_eff2) - (inf_eff3 - inf_eff4)
    mom_post = quadcross(x, (w_d / mw_d - w_dt1 / mw_dt1)) / n
    mom_pre = quadcross(x, (w_d / mw_d - w_dt0 / mw_dt0)) / n
    gamma_ols = xpx_inv_post_treat * mom_post
    inf_or_post = ols_res_post_treat :* (x * gamma_ols)
    gamma_ols = xpx_inv_post * mom_post
    inf_or_post = inf_or_post :- ols_res_post :* (x * gamma_ols)
    gamma_ols = xpx_inv_pre_treat * mom_pre
    inf_or_pre = ols_res_pre_treat :* (x * gamma_ols)
    gamma_ols = xpx_inv_pre * mom_pre
    inf_or_pre = inf_or_pre :- ols_res_pre :* (x * gamma_ols)
    inf_treat_or = inf_treat_or_post + inf_treat_or_pre
    inf_cont_or = inf_cont_or_post + inf_cont_or_pre
    inf_or = inf_or_post - inf_or_pre
    inf_treat = inf_treat_post - inf_treat_pre + inf_treat_or
    inf_cont = inf_cont_post - inf_cont_pre + inf_cont_ps + inf_cont_or
    inf = (inf_treat - inf_cont) + inf_eff + inf_or

    return(att \ inf \ 0)
}


// ---------------------------------------------------------------------------
// One-pass pre-estimation scan. Replaces, in a single st_data load and linear
// scans, what the ado layer previously assembled from two bysorts, two
// levelsofs, two summarizes, a tempvar generate/replace pair and several
// counts - each a full pass over the data. Pure bookkeeping: every output
// feeds the same guards, messages and locals as before; nothing here touches
// estimate arithmetic.
//   - time/gvar min-max, ascending level lists and per-level "gsmall" counts
//     (gsmall = gvar with cohorts beyond max_time + anticipation folded to 0,
//     exactly the old tempvar's definition);
//   - the bal(full) balance verdict: units observed in fewer than n_time
//     periods, via a runs-scan over id in data order (grouped data needs no
//     sort; interleaved data falls back to one Mata sort), writing a 0/1 drop
//     marker only when incomplete units exist.
// Level lists use a bounded-range histogram when the value range is small
// (every ordinary time axis) and uniqrows otherwise, so a pathological axis
// cannot allocate absurd memory here - it is refused by the name-width guard
// downstream exactly as before.
// ---------------------------------------------------------------------------
void csdid__prescan(
    string scalar idname,
    string scalar timename,
    string scalar gname,
    string scalar tousename,
    real scalar anticipation,
    real scalar want_balance,
    string scalar dropmarkname,
    string scalar gcountname)
{
    real colvector tv, gv, idv, rowsel, runlen, runstart, runheads, gsmall
    real colvector tlev, glev, tcnt, gcnt, hist, ord, badunit
    real scalar n, i, r0, nrun, tmin, tmax, gmin, gmax, span, nt, cutoff
    real scalar never_ct, firstper_ct, n_units, inc_units, inc_obs, grouped
    string scalar tlist, glist

    rowsel = selectindex(st_data(., tousename) :!= 0)
    n = rows(rowsel)
    tv = st_data(., timename)[rowsel]
    gv = st_data(., gname)[rowsel]

    tmin = min(tv); tmax = max(tv)
    gmin = min(gv); gmax = max(gv)

    // ---- time levels (ascending) via one sort + vectorized run bounds ----
    ord = sort(tv, 1)
    if (n > 1) runstart = selectindex((1 :: n) :== 1 :| (ord :!= (ord[1] \ ord[|1 \ n - 1|])))
    else runstart = J(1, 1, 1)
    tlev = ord[runstart]
    nt = rows(tlev)
    tlist = ""
    for (i = 1; i <= nt; i++) tlist = tlist + (i > 1 ? " " : "") + strofreal(tlev[i], "%21.0g")

    // ---- gsmall levels and per-level row counts ----
    cutoff = tmax + anticipation
    gsmall = gv :* (gv :<= cutoff)          // cohorts beyond the horizon fold to 0
    ord = sort(gsmall, 1)
    if (n > 1) runstart = selectindex((1 :: n) :== 1 :| (ord :!= (ord[1] \ ord[|1 \ n - 1|])))
    else runstart = J(1, 1, 1)
    glev = ord[runstart]
    if (rows(runstart) > 1) gcnt = (runstart[|2 \ rows(runstart)|] \ (n + 1)) :- runstart
    else gcnt = J(1, 1, n)
    // keep the treated levels only; the zero bucket becomes never_ct
    // selectindex on a 1x1 input returns a 1x0 ROWVECTOR, so an emptiness
    // guard on rows() passes and the subscript aborts with 3301 - length()
    // is orientation-proof (caught by the single-period refusal fixture)
    ord = selectindex(glev :> 0)
    if (length(ord) > 0) {
        glev = glev[ord]
        gcnt = gcnt[ord]
    }
    else {
        glev = J(0, 1, .)
        gcnt = J(0, 1, .)
    }
    never_ct = n - sum(gcnt)
    firstper_ct = 0
    for (i = 1; i <= rows(glev); i++) {
        if (glev[i] <= tmin + anticipation) firstper_ct = firstper_ct + gcnt[i]
    }
    // the counts matrix mirrors csdid__value_counts over the old gsmall
    // tempvar: ascending values, 0 first when present
    if (never_ct > 0) st_matrix(gcountname, (0, never_ct \ (glev, gcnt)))
    else st_matrix(gcountname, (glev, gcnt))

    st_numscalar("__csdid_ps_tmin", tmin)
    st_numscalar("__csdid_ps_tmax", tmax)
    st_numscalar("__csdid_ps_gmin", gmin)
    st_numscalar("__csdid_ps_gmax", gmax)
    st_numscalar("__csdid_ps_ntime", nt)
    st_numscalar("__csdid_ps_never", never_ct)
    st_numscalar("__csdid_ps_firstper", firstper_ct)
    st_local("__csdid_ps_tlevels", tlist)
    glist = ""
    for (i = 1; i <= rows(glev); i++) glist = glist + (i > 1 ? " " : "") + strofreal(glev[i], "%21.0g")
    st_local("__csdid_ps_glevels", glist)

    // ---- balance verdict ----
    n_units = .
    inc_units = 0
    inc_obs = 0
    if (want_balance & idname != "" & n > 0) {
        idv = st_data(., idname)[rowsel]
        // runs in data order (n == 1 and single-run panels need their own
        // ranges: a [|2 \ 1|] subscript is an error, not an empty vector)
        if (n == 1) runstart = 1
        else runstart = selectindex((1 :: n) :== 1 :| (idv :!= (idv[1] \ idv[|1 \ n - 1|])))
        nrun = rows(runstart)
        if (nrun > 1) runlen = (runstart[|2 \ nrun|] \ (n + 1)) :- runstart
        else runlen = J(1, 1, n)
        runheads = idv[runstart]
        grouped = 1
        if (nrun > 1) {
            ord = sort(runheads, 1)
            for (i = 2; i <= nrun; i++) {
                if (ord[i] == ord[i - 1]) {
                    grouped = 0
                    break
                }
            }
        }
        if (grouped) {
            n_units = nrun
            badunit = selectindex(runlen :< nt)
            inc_units = rows(badunit)
            if (inc_units > 0) {
                for (i = 1; i <= inc_units; i++) {
                    r0 = badunit[i]
                    inc_obs = inc_obs + runlen[r0]
                    st_store(rowsel[|runstart[r0] \ runstart[r0] + runlen[r0] - 1|], dropmarkname, J(runlen[r0], 1, 1))
                }
            }
        }
        else {
            // interleaved panel: fall back to one sort by id
            ord = order(idv, 1)
            i = 1
            n_units = 0
            while (i <= n) {
                r0 = i
                while (i < n) {
                    if (idv[ord[i + 1]] != idv[ord[r0]]) break
                    i = i + 1
                }
                n_units = n_units + 1
                if (i - r0 + 1 < nt) {
                    inc_units = inc_units + 1
                    inc_obs = inc_obs + (i - r0 + 1)
                    st_store(rowsel[ord[|r0 \ i|]], dropmarkname, J(i - r0 + 1, 1, 1))
                }
                i = i + 1
            }
        }
    }
    st_numscalar("__csdid_ps_nunits", n_units)
    st_numscalar("__csdid_ps_incunits", inc_units)
    st_numscalar("__csdid_ps_incobs", inc_obs)
}

real colvector csdid__rc_slice(
    real colvector srows,
    real matrix lut,
    real scalar nbt,
    real scalar bg,
    real scalar tid)
{
    real scalar key, st, ct

    if (bg >= . | tid >= .) return(J(0, 1, .))
    key = (bg - 1) * nbt + tid
    st = lut[key, 1]
    ct = lut[key, 2]
    if (ct <= 0) return(J(0, 1, .))
    return(srows[|st \ st + ct - 1|])
}

void csdid_basic_attgt(
    string scalar yname,
    string scalar tname,
    string scalar gname,
    string scalar idname,
    string scalar xnames,
    string scalar wname,
    string scalar method,
    string scalar tousename,
    string scalar clustername,
    string scalar notyet,
    string scalar base_period,
    string scalar balance_mode,
    string scalar fix_weights,
    real scalar anticipation,
    real scalar trim_level,
    real scalar fast_flag,
    string scalar fastusedname,
    string scalar balancedname,
    string scalar ntimename,
    real scalar store_large,
    string scalar outname,
    string scalar ifname,
    string scalar gprobname,
    string scalar unitgroupname,
    string scalar cachetokenname)
{
    external real matrix CSDID_LAST_ATTGT, CSDID_LAST_INFFUNC, CSDID_LAST_GROUP_PROB, CSDID_LAST_UNIT_GROUP
    external real matrix CSDID_LAST_UNIT_ROW, CSDID_LAST_ROW_UNIT
    external real matrix CSDID_LAST_CLUSTER_VEC
    external real scalar CSDID_LAST_TOKEN, CSDID_TOKEN_COUNTER
    real colvector y, tt, gg, geff, id, ww, cl, touse, use, glevels, tlevels, idlevels, unit_if, unit_group, unit_weight
    real colvector wsum_vec, wcount_vec, first_weight, unit_weight_ref
    real colvector row_unit_index, unit_first_row, unit_cluster, unit_raw_group
    real colvector use_rows, id_use, tt_use, time_rows, time_uids
    real colvector y1_cell, y0_cell, d_cell, w_cell, w1_cell, w0_cell, valid_uid, fit, covrow
    real colvector treat_uid, control_uid, dy_treat, dy_control
    real colvector beta_ps_cell, dr_cache_w, dr_cache_ps, dr_cache_trim
    real colvector dr_cache_w_treat, dr_cache_w_cont, dr_cache_weights_ols
    real colvector dr_cache_score_ps, dr_cache_xgamma_treat, dr_cache_xgamma_cont
    real colvector y_rc, post_rc, d_rc, w_rc, fit_if, uid_vec, uid_sums
    real colvector dy_fast, treat_fast, control_fast, eligible_vec, uid_seq, drop_ids, unit_p1, p1_present, wpos  // F-001/F-022: first-appearance period sweep
    real colvector pair_obs_ok
    real scalar pair_mode
    real colvector row_treat_t, row_treat_pre, row_control_t, row_control_pre
    real matrix out, ifmat, group_prob_mat, unit_group_mat, x, x_cell, x_rc, row_index, y_fast
    real matrix uid_fit, uid_info
    real matrix dr_cache_xtwx_inv, dr_cache_xpx_inv, dr_cache_h
    real matrix y_panel, w_panel, x_panel, gg_panel, cl_panel
    real matrix id_panel, tt_panel
    real scalar i, j, k, r, uid_k, g, t, pret, event_time, uid_index, has_x, has_w, has_cluster, covt
    real scalar row_t, row_pre, row_x, row_w, row_w_time, eligible, dval, n1, fit_status
    real scalar balanced_panel, fast_eligible, fast_used, tidx_t, tidx_pre, tidx_x, tidx_w, rowpos
    real scalar sorted_unit_scan, sorted_balanced_layout, last_id, nt, weight_varying
    real scalar kx, xstart, xend
    real scalar max_cells, cell_ix
    real scalar mt1, mt0, mc1, mc0, vt1, vt0, vc1, vc0
    real scalar nt1, nt0, nc1, nc0, att, se, n_units, if_value, if_ss, wsum, wcount
    real scalar reqsize, never_units
    real scalar max_t, first_t, first_treated, has_never, latest_g, cutoff_t, control_time
    real scalar exclude_latest_g
    real scalar prof_t0, prof_fit_t0
    real scalar dr_cache_valid, dr_cache_g, dr_cache_tidx_x, dr_cache_tidx_w
    real scalar dr_cache_control_key, dr_control_key, dr_cache_status, dr_cache_nonconstant
    real scalar dr_cache_n
    real scalar dr_cache_mw_treat, dr_cache_mw_cont
    real colvector idx_t1, idx_t0, idx_c1, idx_c0, idx_rc, valid_rows, valid_rc, dropped_ids
    real colvector rc_rowsel, rc_gcats, rc_gidx, rc_tidxv, rc_bid, rc_ord, rc_sorted_rows
    real colvector rc_treat_t, rc_treat_pre, rc_ctrl_t, rc_ctrl_pre
    real matrix rc_binfo, rc_lut
    real scalar rc_built, rc_nbg, rc_nbt, rc_bg, rc_b, rc_c, rc_tid_t, rc_tid_pre, rr
    real colvector rc_mask

    csdid__profile_reset()
    prof_t0 = csdid__profile_start()

    y = st_data(., yname)
    tt = st_data(., tname)
    gg = st_data(., gname)
    if (idname == "") {
        id = (1::rows(y))
    }
    else {
        id = st_data(., idname)
    }
    has_w = (strlen(strtrim(wname)) > 0)
    if (has_w) {
        ww = st_data(., wname)
    }
    else {
        ww = J(rows(y), 1, 1)
    }
    has_x = (strlen(strtrim(xnames)) > 0)
    if (has_x) {
        x = J(rows(y), 1, 1), st_data(., tokens(xnames))
    }
    else if (method == "reg" & !has_w) {
        x = J(rows(y), 0, .)
    }
    else {
        x = J(rows(y), 1, 1)
    }
    touse = st_data(., tousename)
    has_cluster = (strlen(strtrim(clustername)) > 0)
    if (has_cluster) {
        cl = st_data(., clustername)
    }
    else {
        cl = J(0, 1, .)
    }

    use = touse
    tlevels = uniqrows(select(tt, use :!= 0))'
    max_t = max(tlevels)
    first_t = min(tlevels)
    geff = gg :- ((use :!= 0) :& (gg :> max_t + anticipation)) :* gg
    has_never = (sum((use :!= 0) :& (geff :== 0)) > 0)
    drop_ids = select(geff, (use :!= 0) :& (geff :> 0))
    latest_g = .
    if (rows(drop_ids) > 0) latest_g = max(drop_ids)
    exclude_latest_g = .
    if (!has_never & latest_g < .) {
        cutoff_t = latest_g - anticipation
        for (r = 1; r <= rows(geff); r++) {
            if (use[r] == 0) continue
            if (tt[r] >= cutoff_t) use[r] = 0
        }
        if (notyet == "") {
            for (r = 1; r <= rows(geff); r++) {
                if (use[r] == 0) continue
                if (geff[r] == latest_g) geff[r] = 0
            }
        }
        else {
            exclude_latest_g = latest_g
        }
    }
    if (idname == "") {
        for (r = 1; r <= rows(geff); r++) {
            if (use[r] == 0) continue
            first_treated = (geff[r] > 0) & (geff[r] <= first_t + anticipation)
            if (first_treated) use[r] = 0
        }
    }
    else {
        drop_ids = uniqrows(select(id, (use :!= 0) :& (geff :> 0) :& (geff :<= first_t + anticipation)))
        if (rows(drop_ids) > 0) {
            for (r = 1; r <= rows(id); r++) {
                if (use[r] == 0) continue
                if (csdid__sorted_col_index(drop_ids, id[r]) < .) use[r] = 0
            }
        }
    }

    tlevels = uniqrows(select(tt, use :!= 0))'
    glevels = uniqrows(select(geff, (use :!= 0) :& (geff :> 0)))'
    if (exclude_latest_g < .) glevels = select(glevels, glevels :< exclude_latest_g)
    sorted_unit_scan = 0
    sorted_balanced_layout = 0
    nt = cols(tlevels)
    idlevels = J(0, 1, .)
    n_units = 0
    if (idname != "" & nt > 0) {
        use_rows = select((1::rows(id)), use :!= 0)
        if (rows(use_rows) > 0 & mod(rows(use_rows), nt) == 0) {
            n_units = rows(use_rows) / nt
            id_use = id[use_rows]
            tt_use = tt[use_rows]
            id_panel = rowshape(id_use, n_units)
            tt_panel = rowshape(tt_use, n_units)
            idlevels = id_panel[., 1]
            sorted_balanced_layout = 1
            if (n_units > 1) {
                if (min(idlevels[2..n_units] :> idlevels[1..(n_units - 1)]) == 0) {
                    sorted_balanced_layout = 0
                }
            }
            if (sorted_balanced_layout &
                (sum(id_panel :!= idlevels * J(1, nt, 1)) > 0 |
                 sum(tt_panel :!= J(n_units, 1, 1) * tlevels) > 0)) {
                sorted_balanced_layout = 0
            }
            if (sorted_balanced_layout) sorted_unit_scan = 1
        }
    }
    if (!sorted_balanced_layout) {
        idlevels = uniqrows(select(id, use :!= 0))
        n_units = rows(idlevels)
    }
    // DS-01: a panel whose ivar() resolves to a single unit used to abort with
    // a raw r(3200) conformability error and a Mata traceback (the per-unit
    // vectors collapse to 1x1, and Mata orients a 1x1 as a ROW vector when it
    // is subscripted by a column index, so the time-invariance checks below
    // stopped conforming). No 2x2 comparison can be formed from one unit, so
    // refuse here with the same clean 459 class the other data-shape checks
    // use, before any of those checks can misfire.
    if (idname != "" & n_units == 1) {
        errprintf("ivar() identifies only one unit in the estimation sample; csdid needs at least two units (a treated unit and a comparison unit) to form a 2x2 comparison. Check that ivar() names the panel identifier and is not constant.\n")
        _error(459)
    }
    kx = (has_x ? cols(x) : 1)
    row_index = J(0, 0, .)
    y_panel = J(0, 0, .)
    w_panel = J(0, 0, .)
    x_panel = J(0, 0, .)
    balanced_panel = (idname != "")
    if (idname != "") {
        row_index = J(n_units, cols(tlevels), .)
        y_panel = J(n_units, cols(tlevels), .)
        if (has_w) w_panel = J(n_units, cols(tlevels), .)
        if (has_x) x_panel = J(n_units, kx * cols(tlevels), .)
    }
    unit_group = J(n_units, 1, .)
    unit_weight = J(n_units, 1, .)
    wsum_vec = J(n_units, 1, 0)
    wcount_vec = J(n_units, 1, 0)
    first_weight = J(n_units, 1, .)
    unit_weight_ref = J(n_units, 1, .)
    unit_first_row = J(n_units, 1, .)
    unit_cluster = J(n_units, 1, .)
    unit_raw_group = J(n_units, 1, .)
    row_unit_index = J(rows(id), 1, .)

    weight_varying = 0
    last_id = .
    k = 0
    // PERF: this run-length unit scan needs only a sorted id column, not an
    // ivar(). It used to be gated on idname != "", which excluded repeated
    // cross sections -- where id is the synthesized (1::rows(y)) and is
    // therefore strictly increasing, i.e. the single cheapest case there is.
    // RCS consequently fell through to the per-row scalar loop below and paid
    // a binary search per observation. Ungating it lets RCS reach the
    // vectorized panelsetup()/panelsum() branch. Downstream readers of
    // sorted_unit_scan all sit inside branches that already require
    // idname != "", so nothing else changes behaviour.
    if (!sorted_balanced_layout) {
        use_rows = select((1::rows(id)), use :!= 0)
        id_use = id[use_rows]
        sorted_unit_scan = (rows(id_use) > 0)
        if (rows(id_use) > 1 & min(id_use[2..rows(id_use)] :>= id_use[1..(rows(id_use) - 1)]) == 0) {
            sorted_unit_scan = 0
        }
        if (sorted_unit_scan) {
            uid_vec = J(rows(id_use), 1, 1)
            if (rows(id_use) > 1) {
                uid_vec[2..rows(id_use)] = (id_use[2..rows(id_use)] :!= id_use[1..(rows(id_use) - 1)])
            }
            uid_vec = runningsum(uid_vec)
            row_unit_index[use_rows] = uid_vec
            k = uid_vec[rows(uid_vec)]
        }
        if (k != n_units) sorted_unit_scan = 0
        if (!sorted_unit_scan) row_unit_index = J(rows(id), 1, .)
    }

    if (sorted_balanced_layout) {
        row_index = rowshape(use_rows, n_units)
        y_panel = rowshape(y[use_rows], n_units)
        if (has_w) w_panel = rowshape(ww[use_rows], n_units)
        if (has_x) x_panel = rowshape(x[use_rows, .], n_units)
        unit_first_row = row_index[., 1]
        unit_group = geff[unit_first_row]
        unit_raw_group = gg[unit_first_row]
        gg_panel = rowshape(gg[use_rows], n_units)
        if (sum(gg_panel :!= unit_raw_group * J(1, nt, 1)) > 0) {
            errprintf("gvar() must be time-invariant within ivar(); treatment timing must be irreversible\n")
            _error(459)
        }
        if (has_w) {
            wsum_vec = w_panel * J(nt, 1, 1)
            wcount_vec = J(n_units, 1, nt)
            first_weight = w_panel[., 1]
            unit_weight_ref = first_weight
            if (max(abs(w_panel :- unit_weight_ref * J(1, nt, 1))) > 1e-12) {
                weight_varying = 1
            }
        }
        else {
            wsum_vec = J(n_units, 1, nt)
            wcount_vec = J(n_units, 1, nt)
            first_weight = J(n_units, 1, 1)
            unit_weight_ref = first_weight
        }
        row_unit_index[use_rows] = rowshape((1::n_units) * J(1, nt, 1), n_units * nt)
        if (has_cluster) {
            unit_cluster = cl[unit_first_row]
            cl_panel = rowshape(cl[use_rows], n_units)
            if (sum(cl_panel :!= unit_cluster * J(1, nt, 1)) > 0) {
                errprintf("cluster() must be time-invariant within ivar()\n")
                _error(459)
            }
        }
    }
    else if (sorted_unit_scan) {
        id_use = id[use_rows]
        uid_info = panelsetup(id_use, 1)
        unit_first_row = use_rows[uid_info[., 1]]
        idlevels = id[unit_first_row]
        unit_group = geff[unit_first_row]
        unit_raw_group = gg[unit_first_row]
        uid_vec = row_unit_index[use_rows]
        if (sum(gg[use_rows] :!= unit_raw_group[uid_vec]) > 0) {
            errprintf("gvar() must be time-invariant within ivar(); treatment timing must be irreversible\n")
            _error(459)
        }

        wsum_vec = panelsum(ww[use_rows], uid_info)
        wcount_vec = uid_info[., 2] :- uid_info[., 1] :+ 1
        unit_weight_ref = ww[unit_first_row]
        if (has_w & max(abs(ww[use_rows] :- unit_weight_ref[uid_vec])) > 1e-12) {
            weight_varying = 1
        }
        if (has_cluster) {
            unit_cluster = cl[unit_first_row]
            if (sum(cl[use_rows] :!= unit_cluster[uid_vec]) > 0) {
                errprintf("cluster() must be time-invariant within ivar()\n")
                _error(459)
            }
        }

        // The wide panel layout (row_index/y_panel/w_panel/x_panel) exists only
        // when ivar() was supplied -- those matrices are left 0x0 otherwise --
        // and first_weight is likewise a panel-only concept. The scalar loop
        // this branch replaces guarded all of it behind idname != "", so the
        // repeated-cross-section path must skip it too.
        if (idname != "") {
            for (j = 1; j <= cols(tlevels); j++) {
                time_rows = select(use_rows, tt[use_rows] :== tlevels[j])
                if (rows(time_rows) == 0) continue
                time_uids = row_unit_index[time_rows]
                if (rows(uniqrows(time_uids)) != rows(time_uids)) {
                    errprintf("The value of ivar() must be unique within time(). Some units are observed more than once in a period.\n")
                    _error(459)
                }
                row_index[time_uids, j] = time_rows
                y_panel[time_uids, j] = y[time_rows]
                if (has_w) w_panel[time_uids, j] = ww[time_rows]
                if (has_x) {
                    xstart = (j - 1) * kx + 1
                    xend = j * kx
                    x_panel[time_uids, xstart..xend] = x[time_rows, .]
                }
                if (tlevels[j] == first_t) first_weight[time_uids] = ww[time_rows]
            }
        }
    }
    else {
        for (r = 1; r <= rows(id); r++) {
            if (use[r] == 0) continue
            if (row_unit_index[r] < .) {
                k = row_unit_index[r]
            }
            else {
                k = csdid__sorted_col_index(idlevels, id[r])
                if (k < .) row_unit_index[r] = k
            }
            if (k >= .) continue
            if (unit_group[k] >= .) {
                unit_group[k] = geff[r]
                unit_raw_group[k] = gg[r]
            }
            else if (gg[r] != unit_raw_group[k]) {
                errprintf("gvar() must be time-invariant within ivar(); treatment timing must be irreversible\n")
                _error(459)
            }
            if (unit_first_row[k] >= .) unit_first_row[k] = r
            if (has_cluster) {
                if (unit_cluster[k] >= .) {
                    unit_cluster[k] = cl[r]
                }
                else if (cl[r] != unit_cluster[k]) {
                    errprintf("cluster() must be time-invariant within ivar()\n")
                    _error(459)
                }
            }
            wsum_vec[k] = wsum_vec[k] + ww[r]
            wcount_vec[k] = wcount_vec[k] + 1
            if (has_w & idname != "") {
                if (unit_weight_ref[k] >= .) {
                    unit_weight_ref[k] = ww[r]
                }
                else if (abs(ww[r] - unit_weight_ref[k]) > 1e-12) {
                    weight_varying = 1
                }
            }
            if (idname != "") {
                rowpos = csdid__time_index(tlevels, tt[r])
                if (rowpos < .) {
                    if (row_index[k, rowpos] < .) {
                        errprintf("The value of ivar() must be unique within time(). Some units are observed more than once in a period.\n")
                        _error(459)
                    }
                    row_index[k, rowpos] = r
                    y_panel[k, rowpos] = y[r]
                    if (has_w) w_panel[k, rowpos] = ww[r]
                    if (has_x) {
                        xstart = (rowpos - 1) * kx + 1
                        xend = rowpos * kx
                        x_panel[k, xstart..xend] = x[r, .]
                    }
                }
                if (tt[r] == first_t) first_weight[k] = ww[r]
            }
        }
    }
    if (has_w & idname != "" & weight_varying) {
        // EUX-008: R's own text ends "Use the 'fix_weights' argument ... See
        // ?att_gt for details.", which points a Stata user at R help syntax and
        // at an R argument. The leading sentences (which tests and the frozen
        // f012 parity fixture key on) are unchanged; only the trailing pointer
        // is restated in the spellings src/help/csdid.sthlp documents.
        printf("Time-varying weights detected. For balanced panel data, the default behavior uses the weight from the earlier of the two time periods in each 2x2 comparison (the base period for post-treatment cells). Use the fix_weights() option to control this behavior; see help csdid.\n")
    }

    pair_mode = (balance_mode == "pair" & idname != "")
    if (idname != "") {
        balanced_panel = (sum(row_index :>= .) == 0)
    }
    fast_used = (fast_flag != 0)
    fast_eligible = (fast_flag != 0) & balanced_panel & !pair_mode & !has_w & !has_x & (method == "reg") & (fix_weights == "")
    y_fast = J(0, 0, .)
    if (fast_eligible) {
        y_fast = y_panel
    }
    uid_seq = (1::n_units)
    // PERF: this was a scalar loop over n_units that re-tested two
    // loop-invariant conditions (including a string comparison) on every
    // iteration. The two are exact complements, so exactly one fired per unit
    // and the whole thing vectorizes with element-for-element identical
    // arithmetic -- no summation is reordered. Costly precisely where n_units
    // is largest, i.e. repeated cross sections (one unit per observation).
    if (idname != "" & balanced_panel) {
        unit_weight = first_weight
    }
    else {
        wpos = selectindex(wcount_vec :> 0)
        if (rows(wpos) > 0) unit_weight[wpos] = wsum_vec[wpos] :/ wcount_vec[wpos]
    }
    unit_weight = editmissing(unit_weight, 1)
    if (notyet == "") {
        never_units = sum(unit_group :== 0)
        reqsize = kx + 4
        if (never_units > 0 & never_units < reqsize) {
            errprintf("The never-treated group is too small to serve as a reliable control. Try specifying notyet to include not-yet-treated units as controls.\n")
            _error(459)
        }
    }
    group_prob_mat = J(cols(glevels), 3, .)
    for (i = 1; i <= cols(glevels); i++) {
        g = glevels[i]
        group_prob_mat[i, .] = (g, sum(unit_weight :* (unit_group :== g)) / n_units, n_units)
    }
    // F-001/F-022 (repaired): on the allow_unbalanced path, append each
    // unit's FIRST-APPEARANCE PERIOD as unit_group column 4 so every
    // bootstrap consumer can reproduce R's draw order (see
    // csdid__boot_order_unbal). Computed here, in a single descending
    // column sweep of the already-built row_index map — scanning periods
    // last-to-first leaves the earliest present period in unit_p1 — so it
    // is O(rows), not the donor's O(units x rows) per-unit scan, and it
    // reaches BOTH storage channels (st_matrix under full storage,
    // CSDID_LAST_UNIT_GROUP under lean) with no separate augmentation call.
    // The 4th column is the unbalanced discriminator every consumer keys on
    // (cols(unit_group) >= 4), so it is appended on exactly the predicate
    // the ado exposes as e(panel_balanced): producer and consumers cannot
    // disagree.
    if (idname != "" & !balanced_panel) {
        unit_p1 = J(n_units, 1, .)
        for (j = cols(tlevels); j >= 1; j--) {
            p1_present = selectindex(row_index[., j] :< .)
            if (rows(p1_present) > 0) unit_p1[p1_present] = J(rows(p1_present), 1, tlevels[j])
        }
        unit_group_mat = idlevels, unit_group, unit_weight, unit_p1  // F-001/F-022
    }
    else {
        unit_group_mat = idlevels, unit_group, unit_weight
    }
    max_cells = cols(glevels) * cols(tlevels)
    cell_ix = 0
    out = J(max_cells, 9, .)
    ifmat = J(n_units, max_cells, .)
    csdid__profile_add(1, prof_t0, rows(y))
    // ------------------------------------------------------------------
    // One-time (cohort-value, period) row buckets for the repeated-cross-
    // section / allow_unbalanced cell route. The per-cell boolean masks
    // this replaces cost some twenty O(N) vector passes per cell; the
    // buckets cost one O(N log N) sort once, and every cell then assembles
    // exactly the same rows in exactly the same ascending order from a few
    // slice lookups. Same rows, same order, same arithmetic - the change
    // is where the rows come from, never what is computed on them.
    // ------------------------------------------------------------------
    rc_built = 0
    rc_nbg = 0
    rc_nbt = 0
    // Shape gate, measured 2026-07-30: buckets win on repeated cross
    // sections (one row per unit; 6.41 -> 5.64s at 1M rows) and LOSE on
    // panel-shaped data (many rows per unit; 3.71 -> 4.23s at 850k rows,
    // slice concatenation outgrows the mask savings). Panels keep the
    // original mask path verbatim below.
    if (!balanced_panel & !pair_mode & idname == "") {
        prof_t0 = csdid__profile_start()
        rc_rowsel = selectindex(use :!= 0)
        if (rows(rc_rowsel) > 0) {
            rc_gcats = uniqrows(geff[rc_rowsel])
            rc_nbg = rows(rc_gcats)
            rc_nbt = cols(tlevels)
            rc_gidx = J(rows(rc_rowsel), 1, .)
            for (rc_b = 1; rc_b <= rc_nbg; rc_b++) {
                rc_ord = selectindex(geff[rc_rowsel] :== rc_gcats[rc_b])
                if (length(rc_ord) > 0) rc_gidx[rc_ord] = J(length(rc_ord), 1, rc_b)
            }
            rc_tidxv = J(rows(rc_rowsel), 1, .)
            for (rc_b = 1; rc_b <= rc_nbt; rc_b++) {
                rc_ord = selectindex(tt[rc_rowsel] :== tlevels[rc_b])
                if (length(rc_ord) > 0) rc_tidxv[rc_ord] = J(length(rc_ord), 1, rc_b)
            }
            rc_bid = (rc_gidx :- 1) :* rc_nbt :+ rc_tidxv
            rc_ord = order((rc_bid, rc_rowsel), (1, 2))
            rc_sorted_rows = rc_rowsel[rc_ord]
            rc_bid = rc_bid[rc_ord]
            rc_binfo = panelsetup(rc_bid, 1)
            rc_lut = J(rc_nbg * rc_nbt, 2, 0)
            for (rc_b = 1; rc_b <= rows(rc_binfo); rc_b++) {
                rc_lut[rc_bid[rc_binfo[rc_b, 1]], 1] = rc_binfo[rc_b, 1]
                rc_lut[rc_bid[rc_binfo[rc_b, 1]], 2] = rc_binfo[rc_b, 2] - rc_binfo[rc_b, 1] + 1
            }
            rc_built = 1
            rc_mask = J(rows(y), 1, 0)
        }
        csdid__profile_add(2, prof_t0, rows(rc_rowsel))
    }
    dr_cache_valid = 0
    dr_cache_g = .
    dr_cache_tidx_x = .
    dr_cache_tidx_w = .
    dr_cache_control_key = .
    dr_cache_status = .
    dr_cache_n = .
    dr_cache_mw_treat = .
    dr_cache_mw_cont = .
    dr_cache_w = J(0, 1, .)
    dr_cache_ps = J(0, 1, .)
    dr_cache_trim = J(0, 1, .)
    dr_cache_w_treat = J(0, 1, .)
    dr_cache_w_cont = J(0, 1, .)
    dr_cache_weights_ols = J(0, 1, .)
    dr_cache_score_ps = J(0, 1, .)
    dr_cache_xgamma_treat = J(0, 1, .)
    dr_cache_xgamma_cont = J(0, 1, .)
    dr_cache_xtwx_inv = J(0, 0, .)
    dr_cache_xpx_inv = J(0, 0, .)
    dr_cache_h = J(0, 0, .)

    for (i = 1; i <= cols(glevels); i++) {
        g = glevels[i]
        for (j = 1; j <= cols(tlevels); j++) {
            t = tlevels[j]
            if (t >= g) {
                pret = csdid__previous_time(tlevels, g - anticipation)
            }
            else if (base_period == "universal") {
                pret = csdid__previous_time(tlevels, g - anticipation)
            }
            else {
                pret = csdid__previous_time(tlevels, t)
            }
            if (pret >= .) continue
            control_time = max((t, pret))

            if (fast_eligible) {
                tidx_t = csdid__time_index(tlevels, t)
                tidx_pre = csdid__time_index(tlevels, pret)
                if (tidx_t >= . | tidx_pre >= .) continue
                dy_fast = y_fast[., tidx_t] :- y_fast[., tidx_pre]
                treat_fast = (unit_group :== g)
                if (notyet != "") {
                    control_fast = (unit_group :!= g) :& ((unit_group :== 0) :| (unit_group :> control_time + anticipation))
                }
                else {
                    control_fast = (unit_group :== 0)
                }
                treat_uid = select(uid_seq, treat_fast)
                control_uid = select(uid_seq, control_fast)
                nt1 = rows(treat_uid)
                nt0 = nt1
                nc1 = rows(control_uid)
                nc0 = nc1
                if (min((nt1, nt0, nc1, nc0)) <= 0) {
                    if (nt1 <= 0) printf("warning: No units in group %g in time period %g\n", g, t)
                    event_time = t - g
                    cell_ix = cell_ix + 1
                    out[cell_ix, .] = (g, t, event_time, ., ., nt1, nt0, nc1, nc0)
                    ifmat[., cell_ix] = J(n_units, 1, .)
                    continue
                }
                if (base_period == "universal" & t == pret) {
                    event_time = t - g
                    cell_ix = cell_ix + 1
                    out[cell_ix, .] = (g, t, event_time, 0, ., nt1, nt0, nc1, nc0)
                    ifmat[., cell_ix] = J(n_units, 1, 0)
                    continue
                }
                dy_treat = dy_fast[treat_uid]
                dy_control = dy_fast[control_uid]
                mt1 = mean(dy_treat)
                mc1 = mean(dy_control)
                att = mt1 - mc1
                unit_if = J(n_units, 1, 0)
                unit_if[treat_uid] = (n_units / nt1) :* (dy_treat :- mt1)
                unit_if[control_uid] = -(n_units / nc1) :* (dy_control :- mc1)
                if_ss = quadcross(unit_if, unit_if)
                if (if_ss <= epsilon(1) * 100) {
                    se = .
                }
                else {
                    se = sqrt(if_ss) / n_units
                }
                event_time = t - g
                cell_ix = cell_ix + 1
                out[cell_ix, .] = (g, t, event_time, att, se, nt1, nt0, nc1, nc0)
                ifmat[., cell_ix] = unit_if
                continue
            }

            // bal(pair) balances each 2x2 on its own, so it uses the panel
            // branch: that branch already selects a per-cell unit set and
            // scales the influence function by n_units / n1 with zeros
            // elsewhere, so restricting the set further is the whole change.
            // balanced_panel itself stays truthful -- weight handling, the
            // unbalanced paths and e(panel_balanced) all read it.
            if (balanced_panel | pair_mode) {
                covt = min((pret, t))
                tidx_t = csdid__time_index(tlevels, t)
                tidx_pre = csdid__time_index(tlevels, pret)
                tidx_x = csdid__time_index(tlevels, covt)
                if (fix_weights == "base_period") {
                    row_w_time = csdid__previous_time(tlevels, g - anticipation)
                }
                else if (fix_weights == "first_period") {
                    row_w_time = first_t
                }
                else {
                    row_w_time = covt
                }
                tidx_w = csdid__time_index(tlevels, row_w_time)
                if (tidx_t >= . | tidx_pre >= . | tidx_x >= . | tidx_w >= .) continue
                treat_fast = (unit_group :== g)
                if (notyet != "") {
                    control_fast = (unit_group :!= g) :& ((unit_group :== 0) :| (unit_group :> control_time + anticipation))
                }
                else {
                    control_fast = (unit_group :== 0)
                }
                eligible_vec = treat_fast :| control_fast
                // bal(pair): keep only the units this comparison can actually
                // use -- observed in BOTH of its periods, and wherever the
                // covariates and weights are read from. row_index is missing
                // exactly where a unit-period has no row, which is what makes
                // this a lookup rather than a search.
                if (pair_mode) {
                    pair_obs_ok = (row_index[., tidx_t] :< .) :& (row_index[., tidx_pre] :< .)
                    if (has_x) pair_obs_ok = pair_obs_ok :& (row_index[., tidx_x] :< .)
                    if (has_w) pair_obs_ok = pair_obs_ok :& (row_index[., tidx_w] :< .)
                    eligible_vec = eligible_vec :& pair_obs_ok
                }
                n1 = sum(eligible_vec)
                if (n1 == 0) continue
                valid_uid = select(uid_seq, eligible_vec)
                y1_cell = y_panel[valid_uid, tidx_t]
                y0_cell = y_panel[valid_uid, tidx_pre]
                d_cell = treat_fast[valid_uid]
                if (!has_w) {
                    w_cell = J(n1, 1, 1)
                    w1_cell = w_cell
                    w0_cell = w_cell
                }
                else if (fix_weights == "varying") {
                    w_cell = w_panel[valid_uid, tidx_x]
                    w1_cell = w_panel[valid_uid, tidx_t]
                    w0_cell = w_panel[valid_uid, tidx_pre]
                }
                else {
                    w_cell = w_panel[valid_uid, tidx_w]
                    w1_cell = w_panel[valid_uid, tidx_t]
                    w0_cell = w_panel[valid_uid, tidx_pre]
                }
                if (has_x) {
                    xstart = (tidx_x - 1) * kx + 1
                    xend = tidx_x * kx
                    x_cell = x_panel[valid_uid, xstart..xend]
                }
                else if (method == "ipw") {
                    x_cell = J(0, 1, .)
                }
                else {
                    x_cell = J(n1, 1, 1)
                }
                nt1 = sum(d_cell :== 1)
                nt0 = nt1
                nc1 = sum(d_cell :== 0)
                nc0 = nc1
                if (min((nt1, nt0, nc1, nc0)) <= 0) {
                    if (nt1 <= 0) printf("warning: No units in group %g in time period %g\n", g, t)
                    event_time = t - g
                    cell_ix = cell_ix + 1
                    out[cell_ix, .] = (g, t, event_time, ., ., nt1, nt0, nc1, nc0)
                    ifmat[., cell_ix] = J(n_units, 1, .)
                    continue
                }
                if (base_period == "universal" & t == pret) {
                    event_time = t - g
                    cell_ix = cell_ix + 1
                    out[cell_ix, .] = (g, t, event_time, 0, ., nt1, nt0, nc1, nc0)
                    ifmat[., cell_ix] = J(n_units, 1, 0)
                    continue
                }

                prof_fit_t0 = csdid__profile_start()
                if (fix_weights == "varying" & has_w) {
                    y_rc = y0_cell \ y1_cell
                    post_rc = J(n1, 1, 0) \ J(n1, 1, 1)
                    d_rc = d_cell \ d_cell
                    w_rc = w0_cell \ w1_cell
                    if (method == "ipw") {
                        if (has_x) {
                            x_rc = x_cell \ x_cell
                        }
                        else {
                            x_rc = J(0, 1, .)
                        }
                        fit = csdid__ipw_rc_fit(y_rc, post_rc, d_rc, x_rc, w_rc, trim_level)
                    }
                    else if (method == "dr") {
                        x_rc = x_cell \ x_cell
                        fit = csdid__dr_rc_fit(y_rc, post_rc, d_rc, x_rc, w_rc, trim_level)
                    }
                    else {
                        x_rc = x_cell \ x_cell
                        fit = csdid__reg_rc_fit(y_rc, post_rc, d_rc, x_rc, w_rc)
                    }
                }
                else {
                    if (method == "ipw") {
                        fit = csdid__ipw_panel_fit(y1_cell, y0_cell, d_cell, x_cell, w_cell, trim_level)
                    }
                    else if (method == "dr") {
                        if (notyet != "") {
                            dr_control_key = control_time
                        }
                        else {
                            dr_control_key = 0
                        }
                        if (!(dr_cache_valid &
                              dr_cache_g == g &
                              dr_cache_tidx_x == tidx_x &
                              dr_cache_tidx_w == tidx_w &
                              dr_cache_control_key == dr_control_key &
                              dr_cache_n == n1)) {
                            dr_cache_valid = 1
                            dr_cache_g = g
                            dr_cache_tidx_x = tidx_x
                            dr_cache_tidx_w = tidx_w
                            dr_cache_control_key = dr_control_key
                            dr_cache_n = n1
                            dr_cache_status = 0
                            dr_cache_w = csdid__normalize_weights(w_cell)
                            if (sum(dr_cache_w :>= .) > 0) {
                                dr_cache_status = 3
                            }
                            else {
                                dr_cache_nonconstant = csdid__nonconstant_weights(dr_cache_w)
                                if (dr_cache_nonconstant) {
                                    // F-040: this precomputed path must agree
                                    // with csdid__dr_panel_fit on WHY a cell was
                                    // refused, not only that it was. It used to
                                    // report every weighted-branch refusal as an
                                    // overlap violation while the direct path
                                    // reported every one of them as a singular
                                    // design; csdid__overlap_status() is now the
                                    // single classifier for both.
                                    dr_cache_status = csdid__overlap_status(x_cell, d_cell)
                                }
                                if (dr_cache_status == 0) {
                                    beta_ps_cell = csdid__logit_fit(d_cell, x_cell, dr_cache_w)
                                    if (sum(beta_ps_cell :>= .) > 0) {
                                        // F-013/F-040: an uncomputable propensity
                                        // fit is DRDID's singular-design refusal
                                        // (status 2), as in csdid__dr_panel_fit.
                                        dr_cache_status = 2
                                    }
                                    else {
                                        dr_cache_ps = csdid__invlogit(x_cell * beta_ps_cell)
                                        if (!dr_cache_nonconstant & max(dr_cache_ps) >= 0.999) {
                                            dr_cache_status = 1
                                        }
                                    }
                                }
                            }
                            if (dr_cache_status == 0) {
                                dr_cache_trim = J(n1, 1, 1)
                                dr_cache_trim = dr_cache_trim :* ((d_cell :== 1) :| (dr_cache_ps :< trim_level))
                                // DS-04: the `n_control <= cols(x)' pre-test was
                                // dropped here as well; R gates on
                                // rcond_check_fail() alone (see
                                // csdid__reg_panel_fit) and this precomputed
                                // path must agree with csdid__dr_panel_fit.
                            }
                            if (dr_cache_status == 0) {
                                // F-005: R-parity conditioning guard must also
                                // cover this precomputed fast path.
                                if (csdid__rcond_fail(x_cell, d_cell)) {
                                    dr_cache_status = 2
                                }
                            }
                            if (dr_cache_status == 0) {
                                dr_cache_weights_ols = dr_cache_w :* (1 :- d_cell)
                                dr_cache_xtwx_inv = csdid__inv_r_parity(quadcross(x_cell, dr_cache_weights_ols, x_cell))  // F-005: R-parity inverse
                                if (!csdid__valid_inverse(dr_cache_xtwx_inv)) {
                                    dr_cache_status = 2
                                }
                            }
                            if (dr_cache_status == 0) {
                                dr_cache_xpx_inv = n1 * dr_cache_xtwx_inv
                                dr_cache_h = csdid__hessinv_r_parity(quadcross(x_cell, dr_cache_ps :* (1 :- dr_cache_ps) :* dr_cache_w, x_cell), n1)  // F-005: R chol2inv(chol()) after the rcond guard
                                if (sum(dr_cache_h :>= .) > 0) {
                                    // F-013/F-040: R's rcond stop on the
                                    // propensity hessian is a singular-design
                                    // refusal (status 2), as in
                                    // csdid__dr_panel_fit; it is not an overlap
                                    // violation.
                                    dr_cache_status = 2
                                }
                            }
                            if (dr_cache_status == 0) {
                                dr_cache_w_treat = dr_cache_trim :* dr_cache_w :* d_cell
                                dr_cache_w_cont = dr_cache_trim :* dr_cache_w :* dr_cache_ps :* (1 :- d_cell) :/ (1 :- dr_cache_ps)
                                dr_cache_mw_treat = mean(dr_cache_w_treat)
                                dr_cache_mw_cont = mean(dr_cache_w_cont)
                                dr_cache_score_ps = dr_cache_w :* (d_cell :- dr_cache_ps)
                                dr_cache_xgamma_treat = x_cell * (dr_cache_xpx_inv * (quadcross(x_cell, dr_cache_w_treat) / n1))
                                dr_cache_xgamma_cont = x_cell * (dr_cache_xpx_inv * (quadcross(x_cell, dr_cache_w_cont) / n1))
                            }
                        }
                        if (dr_cache_status != 0) {
                            fit = . \ J(n1, 1, .) \ dr_cache_status
                        }
                        else {
                            fit = csdid__dr_panel_fit_precomputed(
                                y1_cell, y0_cell, d_cell, x_cell,
                                dr_cache_w, dr_cache_ps, dr_cache_trim,
                                dr_cache_w_treat, dr_cache_w_cont,
                                dr_cache_score_ps, dr_cache_xgamma_treat,
                                dr_cache_xgamma_cont,
                                dr_cache_mw_treat, dr_cache_mw_cont,
                                dr_cache_xtwx_inv, dr_cache_xpx_inv,
                                dr_cache_h, dr_cache_weights_ols)
                        }
                    }
                    else {
                        fit = csdid__reg_panel_fit(y1_cell, y0_cell, d_cell, x_cell, w_cell)
                    }
                }
                csdid__profile_add(3, prof_fit_t0, n1)
                att = fit[1]
                fit_status = fit[rows(fit)]
                if (att >= .) {
                    csdid__fit_status_warning(fit_status, method, has_x, g, t)
                }
                unit_if = J(n_units, 1, 0)
                if (att < .) {
                    if (fix_weights == "varying" & has_w) {
                        unit_if[valid_uid] = (n_units / n1) * (fit[2..(n1 + 1)] + fit[(n1 + 2)..(2 * n1 + 1)]) / 2
                    }
                    else {
                        unit_if[valid_uid] = (n_units / n1) * fit[2..(n1 + 1)]
                    }
                }
                else {
                    unit_if = J(n_units, 1, .)
                }
                if_ss = quadcross(unit_if, unit_if)
                if (if_ss <= epsilon(1) * 100 | att >= .) {
                    se = .
                }
                else {
                    se = sqrt(if_ss) / n_units
                }
                event_time = t - g
                cell_ix = cell_ix + 1
                out[cell_ix, .] = (g, t, event_time, att, se, nt1, nt0, nc1, nc0)
                ifmat[., cell_ix] = unit_if
                continue
            }

            if (!balanced_panel & idname != "" & (has_w | has_x | notyet != "") & fix_weights == "") {
                tidx_t = csdid__time_index(tlevels, t)
                tidx_pre = csdid__time_index(tlevels, pret)
                if (tidx_t >= . | tidx_pre >= .) continue
                treat_fast = (unit_group :== g)
                if (notyet != "") {
                    control_fast = (unit_group :!= g) :& ((unit_group :== 0) :| (unit_group :> control_time + anticipation))
                }
                else {
                    control_fast = (unit_group :== 0)
                }
                treat_uid = select(uid_seq, treat_fast)
                control_uid = select(uid_seq, control_fast)
                if (rows(treat_uid) > 0) {
                    row_treat_t = row_index[treat_uid, tidx_t]
                    row_treat_pre = row_index[treat_uid, tidx_pre]
                    row_treat_t = select(row_treat_t, row_treat_t :< .)
                    row_treat_pre = select(row_treat_pre, row_treat_pre :< .)
                }
                else {
                    row_treat_t = J(0, 1, .)
                    row_treat_pre = J(0, 1, .)
                }
                if (rows(control_uid) > 0) {
                    row_control_t = row_index[control_uid, tidx_t]
                    row_control_pre = row_index[control_uid, tidx_pre]
                    row_control_t = select(row_control_t, row_control_t :< .)
                    row_control_pre = select(row_control_pre, row_control_pre :< .)
                }
                else {
                    row_control_t = J(0, 1, .)
                    row_control_pre = J(0, 1, .)
                }

                nt1 = rows(row_treat_t)
                nt0 = rows(row_treat_pre)
                nc1 = rows(row_control_t)
                nc0 = rows(row_control_pre)
                if (min((nt1, nt0, nc1, nc0)) <= 0) {
                    if (nt1 <= 0) printf("warning: No units in group %g in time period %g\n", g, t)
                    event_time = t - g
                    cell_ix = cell_ix + 1
                    out[cell_ix, .] = (g, t, event_time, ., ., nt1, nt0, nc1, nc0)
                    ifmat[., cell_ix] = J(n_units, 1, .)
                    continue
                }
                if (base_period == "universal" & t == pret) {
                    event_time = t - g
                    cell_ix = cell_ix + 1
                    out[cell_ix, .] = (g, t, event_time, 0, ., nt1, nt0, nc1, nc0)
                    ifmat[., cell_ix] = J(n_units, 1, 0)
                    continue
                }

                if (sorted_unit_scan) {
                    valid_rows = J(0, 1, .)
                    if (rows(treat_uid) > 0) {
                        valid_rows = valid_rows \ rowshape(row_index[treat_uid, (tidx_pre, tidx_t)], rows(treat_uid) * 2)
                    }
                    if (rows(control_uid) > 0) {
                        valid_rows = valid_rows \ rowshape(row_index[control_uid, (tidx_pre, tidx_t)], rows(control_uid) * 2)
                    }
                    valid_rows = select(valid_rows, valid_rows :< .)
                }
                else {
                    valid_rows = sort(row_treat_pre \ row_treat_t \ row_control_pre \ row_control_t, 1)
                }
                n1 = rows(valid_rows)
                y_rc = y[valid_rows]
                post_rc = (tt[valid_rows] :== t)
                d_rc = (geff[valid_rows] :== g)
                w_rc = ww[valid_rows]
                if (method == "reg" & !has_x) {
                    x_rc = J(n1, 1, 1)
                }
                else {
                    x_rc = x[valid_rows, .]
                }

                prof_fit_t0 = csdid__profile_start()
                if (method == "ipw") {
                    fit = csdid__ipw_rc_fit(y_rc, post_rc, d_rc, x_rc, w_rc, trim_level)
                }
                else if (method == "dr") {
                    fit = csdid__dr_rc_fit(y_rc, post_rc, d_rc, x_rc, w_rc, trim_level)
                }
                else {
                    fit = csdid__reg_rc_fit(y_rc, post_rc, d_rc, x_rc, w_rc)
                }
                csdid__profile_add(3, prof_fit_t0, n1)
                att = fit[1]
                fit_status = fit[rows(fit)]
                if (att >= .) {
                    csdid__fit_status_warning(fit_status, method, has_x, g, t)
                }
                unit_if = J(n_units, 1, 0)
                if (att < .) {
                    fit_if = (n_units / n1) * fit[2..(n1 + 1)]
                    uid_vec = row_unit_index[valid_rows]
                    if (idname != "" & sorted_unit_scan & sum(uid_vec :>= .) == 0) {
                        uid_fit = uid_vec, fit_if
                        uid_info = panelsetup(uid_fit, 1)
                        uid_sums = panelsum(uid_fit[., 2], uid_info)
                        unit_if[uid_fit[uid_info[., 1], 1]] = uid_sums
                    }
                    else {
                        for (k = 1; k <= n1; k++) {
                            r = valid_rows[k]
                            uid_index = row_unit_index[r]
                            if (uid_index >= .) uid_index = csdid__sorted_col_index(idlevels, id[r])
                            if (uid_index < .) unit_if[uid_index] = unit_if[uid_index] + fit_if[k]
                        }
                    }
                }
                else {
                    unit_if = J(n_units, 1, .)
                }
                if_ss = quadcross(unit_if, unit_if)
                if (if_ss <= epsilon(1) * 100 | att >= .) {
                    se = .
                }
                else {
                    se = sqrt(if_ss) / n_units
                }
                event_time = t - g
                cell_ix = cell_ix + 1
                out[cell_ix, .] = (g, t, event_time, att, se, nt1, nt0, nc1, nc0)
                ifmat[., cell_ix] = unit_if
                continue
            }

            if (rc_built) {
                // bucket-slice assembly: the same rows, in the same ascending
                // order, that the boolean masks select - at O(rows in the
                // cell) instead of O(N) per mask. The control condition
                // deliberately has no g-exclusion, exactly like the masks.
                rc_tid_t = csdid__time_index(tlevels, t)
                rc_tid_pre = csdid__time_index(tlevels, pret)
                rc_bg = .
                for (rc_b = 1; rc_b <= rc_nbg; rc_b++) {
                    if (rc_gcats[rc_b] == g) rc_bg = rc_b
                }
                rc_treat_t = csdid__rc_slice(rc_sorted_rows, rc_lut, rc_nbt, rc_bg, rc_tid_t)
                rc_treat_pre = csdid__rc_slice(rc_sorted_rows, rc_lut, rc_nbt, rc_bg, rc_tid_pre)
                rc_ctrl_t = J(0, 1, .)
                rc_ctrl_pre = J(0, 1, .)
                for (rc_c = 1; rc_c <= rc_nbg; rc_c++) {
                    if (notyet != "") {
                        if (!(rc_gcats[rc_c] == 0 | rc_gcats[rc_c] > control_time + anticipation)) continue
                    }
                    else {
                        if (rc_gcats[rc_c] != 0) continue
                    }
                    rc_ctrl_t = rc_ctrl_t \ csdid__rc_slice(rc_sorted_rows, rc_lut, rc_nbt, rc_c, rc_tid_t)
                    rc_ctrl_pre = rc_ctrl_pre \ csdid__rc_slice(rc_sorted_rows, rc_lut, rc_nbt, rc_c, rc_tid_pre)
                }
                nt1 = rows(rc_treat_t); nt0 = rows(rc_treat_pre)
                nc1 = rows(rc_ctrl_t); nc0 = rows(rc_ctrl_pre)
            }
            else {
                // panel-shaped data: the original mask path, verbatim
                idx_t1 = (use :!= 0) :& (geff :== g) :& (tt :== t)
                idx_t0 = (use :!= 0) :& (geff :== g) :& (tt :== pret)
                if (notyet != "") {
                    idx_c1 = (use :!= 0) :& ((geff :== 0) :| (geff :> control_time + anticipation)) :& (tt :== t)
                    idx_c0 = (use :!= 0) :& ((geff :== 0) :| (geff :> control_time + anticipation)) :& (tt :== pret)
                }
                else {
                    idx_c1 = (use :!= 0) :& (geff :== 0) :& (tt :== t)
                    idx_c0 = (use :!= 0) :& (geff :== 0) :& (tt :== pret)
                }
                nt1 = sum(idx_t1); nt0 = sum(idx_t0); nc1 = sum(idx_c1); nc0 = sum(idx_c0)
            }
            if (min((nt1, nt0, nc1, nc0)) <= 0) {
                if (nt1 <= 0) printf("warning: No units in group %g in time period %g\n", g, t)
                event_time = t - g
                cell_ix = cell_ix + 1
                out[cell_ix, .] = (g, t, event_time, ., ., nt1, nt0, nc1, nc0)
                ifmat[., cell_ix] = J(n_units, 1, .)
                continue
            }
            if (base_period == "universal" & t == pret) {
                event_time = t - g
                cell_ix = cell_ix + 1
                out[cell_ix, .] = (g, t, event_time, 0, ., nt1, nt0, nc1, nc0)
                ifmat[., cell_ix] = J(n_units, 1, 0)
                continue
            }

            if (!balanced_panel & (has_w | has_x | notyet != "")) {
                if (rc_built) {
                    // union of the four slices, deduplicated and ascending -
                    // identical to select() over the OR of the masks; the
                    // reusable 0/1 buffer needs no per-cell sort
                    if (rows(rc_treat_t)) rc_mask[rc_treat_t] = J(rows(rc_treat_t), 1, 1)
                    if (rows(rc_treat_pre)) rc_mask[rc_treat_pre] = J(rows(rc_treat_pre), 1, 1)
                    if (rows(rc_ctrl_t)) rc_mask[rc_ctrl_t] = J(rows(rc_ctrl_t), 1, 1)
                    if (rows(rc_ctrl_pre)) rc_mask[rc_ctrl_pre] = J(rows(rc_ctrl_pre), 1, 1)
                    valid_rows = selectindex(rc_mask)
                    if (rows(valid_rows)) rc_mask[valid_rows] = J(rows(valid_rows), 1, 0)
                }
                else {
                    idx_rc = idx_t0 :| idx_t1 :| idx_c0 :| idx_c1
                    valid_rows = select((1::rows(y)), idx_rc)
                }
                n1 = rows(valid_rows)
                dropped_ids = J(0, 1, .)
                if (fix_weights == "base_period") {
                    row_w_time = csdid__previous_time(tlevels, g - anticipation)
                }
                else if (fix_weights == "first_period") {
                    row_w_time = first_t
                }
                else {
                    row_w_time = .
                }
                if (row_w_time >= .) {
                    y_rc = y[valid_rows]
                    post_rc = (tt[valid_rows] :== t)
                    d_rc = (geff[valid_rows] :== g)
                    w_rc = ww[valid_rows]
                    if (method == "reg" & !has_x) {
                        x_rc = J(n1, 1, 1)
                    }
                    else {
                        x_rc = x[valid_rows, .]
                    }
                }
                else {
                    y_rc = J(n1, 1, .)
                    post_rc = J(n1, 1, .)
                    d_rc = J(n1, 1, .)
                    w_rc = J(n1, 1, .)
                    if (method == "reg" & !has_x) {
                        x_rc = J(n1, 1, 1)
                    }
                    else {
                        x_rc = J(n1, cols(x), .)
                    }
                    tidx_w = csdid__time_index(tlevels, row_w_time)
                    for (k = 1; k <= n1; k++) {
                        r = valid_rows[k]
                        uid_index = row_unit_index[r]
                        if (uid_index >= .) uid_index = csdid__sorted_col_index(idlevels, id[r])
                        if (uid_index < . & tidx_w < .) {
                            row_w = row_index[uid_index, tidx_w]
                        }
                        else {
                            row_w = .
                        }
                        if (row_w >= .) {
                            dropped_ids = dropped_ids \ id[r]
                            continue
                        }
                        y_rc[k] = y[r]
                        post_rc[k] = (tt[r] == t)
                        d_rc[k] = (geff[r] == g)
                        w_rc[k] = ww[row_w]
                        if (!(method == "reg" & !has_x)) {
                            x_rc[k, .] = x[r, .]
                        }
                    }
                    if (rows(dropped_ids) > 0) {
                        printf("warning: Some units not observed in %s (period %g) for group %g in time period %g. These units are excluded.\n", fix_weights, row_w_time, g, t)
                    }
                    valid_rc = y_rc :< .
                    valid_rows = select(valid_rows, valid_rc)
                    y_rc = select(y_rc, valid_rc)
                    post_rc = select(post_rc, valid_rc)
                    d_rc = select(d_rc, valid_rc)
                    w_rc = select(w_rc, valid_rc)
                    x_rc = select(x_rc, valid_rc)
                }
                n1 = rows(y_rc)
                nt1 = sum((d_rc :== 1) :& (post_rc :== 1))
                nt0 = sum((d_rc :== 1) :& (post_rc :== 0))
                nc1 = sum((d_rc :== 0) :& (post_rc :== 1))
                nc0 = sum((d_rc :== 0) :& (post_rc :== 0))
                if (min((nt1, nt0, nc1, nc0)) <= 0) {
                    if (nt1 <= 0) printf("warning: No units in group %g in time period %g\n", g, t)
                    event_time = t - g
                    cell_ix = cell_ix + 1
                    out[cell_ix, .] = (g, t, event_time, ., ., nt1, nt0, nc1, nc0)
                    ifmat[., cell_ix] = J(n_units, 1, .)
                    continue
                }
                prof_fit_t0 = csdid__profile_start()
                if (method == "ipw") {
                    fit = csdid__ipw_rc_fit(y_rc, post_rc, d_rc, x_rc, w_rc, trim_level)
                }
                else if (method == "dr") {
                    fit = csdid__dr_rc_fit(y_rc, post_rc, d_rc, x_rc, w_rc, trim_level)
                }
                else {
                    fit = csdid__reg_rc_fit(y_rc, post_rc, d_rc, x_rc, w_rc)
                }
                csdid__profile_add(3, prof_fit_t0, n1)
                att = fit[1]
                fit_status = fit[rows(fit)]
                if (att >= .) {
                    csdid__fit_status_warning(fit_status, method, has_x, g, t)
                }
                unit_if = J(n_units, 1, 0)
                if (att < .) {
                    fit_if = (n_units / n1) * fit[2..(n1 + 1)]
                    uid_vec = row_unit_index[valid_rows]
                    if (idname != "" & sorted_unit_scan & sum(uid_vec :>= .) == 0) {
                        uid_fit = uid_vec, fit_if
                        uid_info = panelsetup(uid_fit, 1)
                        uid_sums = panelsum(uid_fit[., 2], uid_info)
                        unit_if[uid_fit[uid_info[., 1], 1]] = uid_sums
                    }
                    else {
                        for (k = 1; k <= n1; k++) {
                            r = valid_rows[k]
                            uid_index = row_unit_index[r]
                            if (uid_index >= .) uid_index = csdid__sorted_col_index(idlevels, id[r])
                            if (uid_index < .) unit_if[uid_index] = unit_if[uid_index] + fit_if[k]
                        }
                    }
                }
                else {
                    unit_if = J(n_units, 1, .)
                }
                if_ss = quadcross(unit_if, unit_if)
                if (if_ss <= epsilon(1) * 100 | att >= .) {
                    se = .
                }
                else {
                    se = sqrt(if_ss) / n_units
                }
                event_time = t - g
                cell_ix = cell_ix + 1
                out[cell_ix, .] = (g, t, event_time, att, se, nt1, nt0, nc1, nc0)
                ifmat[., cell_ix] = unit_if
                continue
            }

            if (rc_built) {
                mt1 = csdid__mean(y[rc_treat_t])
                mt0 = csdid__mean(y[rc_treat_pre])
                mc1 = csdid__mean(y[rc_ctrl_t])
                mc0 = csdid__mean(y[rc_ctrl_pre])
            }
            else {
                mt1 = csdid__mean(select(y, idx_t1))
                mt0 = csdid__mean(select(y, idx_t0))
                mc1 = csdid__mean(select(y, idx_c1))
                mc0 = csdid__mean(select(y, idx_c0))
            }
            att = (mt1 - mt0) - (mc1 - mc0)
            unit_if = J(n_units, 1, 0)
            if (rc_built) {
                // the same if-value chain, evaluated only on the union rows
                // (ascending = original scan order); conditions and their
                // overwrite priority untouched
                if (rows(rc_treat_t)) rc_mask[rc_treat_t] = J(rows(rc_treat_t), 1, 1)
                if (rows(rc_treat_pre)) rc_mask[rc_treat_pre] = J(rows(rc_treat_pre), 1, 1)
                if (rows(rc_ctrl_t)) rc_mask[rc_ctrl_t] = J(rows(rc_ctrl_t), 1, 1)
                if (rows(rc_ctrl_pre)) rc_mask[rc_ctrl_pre] = J(rows(rc_ctrl_pre), 1, 1)
                valid_rows = selectindex(rc_mask)
                if (rows(valid_rows)) rc_mask[valid_rows] = J(rows(valid_rows), 1, 0)
                for (rr = 1; rr <= rows(valid_rows); rr++) {
                    r = valid_rows[rr]
                    if_value = 0
                    if (geff[r] == g & tt[r] == t) if_value = n_units / nt1 * (y[r] - mt1)
                    if (geff[r] == g & tt[r] == pret) if_value = -n_units / nt0 * (y[r] - mt0)
                    if (notyet != "") {
                        if ((geff[r] == 0 | geff[r] > control_time + anticipation) & tt[r] == t) if_value = -n_units / nc1 * (y[r] - mc1)
                        if ((geff[r] == 0 | geff[r] > control_time + anticipation) & tt[r] == pret) if_value = n_units / nc0 * (y[r] - mc0)
                    }
                    else {
                        if (geff[r] == 0 & tt[r] == t) if_value = -n_units / nc1 * (y[r] - mc1)
                        if (geff[r] == 0 & tt[r] == pret) if_value = n_units / nc0 * (y[r] - mc0)
                    }
                    if (if_value != 0) {
                        uid_index = row_unit_index[r]
                        if (uid_index >= .) uid_index = csdid__sorted_col_index(idlevels, id[r])
                        if (uid_index < .) unit_if[uid_index] = unit_if[uid_index] + if_value
                    }
                }
            }
            else {
                for (r = 1; r <= rows(y); r++) {
                    if (use[r] == 0) continue
                    if_value = 0
                    if (idx_t1[r]) if_value = n_units / nt1 * (y[r] - mt1)
                    if (idx_t0[r]) if_value = -n_units / nt0 * (y[r] - mt0)
                    if (idx_c1[r]) if_value = -n_units / nc1 * (y[r] - mc1)
                    if (idx_c0[r]) if_value = n_units / nc0 * (y[r] - mc0)
                    if (if_value != 0) {
                        uid_index = row_unit_index[r]
                        if (uid_index >= .) uid_index = csdid__sorted_col_index(idlevels, id[r])
                        if (uid_index < .) unit_if[uid_index] = unit_if[uid_index] + if_value
                    }
                }
            }
            if_ss = quadcross(unit_if, unit_if)
            if (if_ss <= epsilon(1) * 100) {
                se = .
            }
            else {
                se = sqrt(if_ss) / n_units
            }
            event_time = t - g
            cell_ix = cell_ix + 1
            out[cell_ix, .] = (g, t, event_time, att, se, nt1, nt0, nc1, nc0)
            ifmat[., cell_ix] = unit_if
        }
    }

    if (cell_ix == 0) {
        out = J(0, 9, .)
        ifmat = J(n_units, 0, .)
    }
    else {
        out = out[1..cell_ix, .]
        ifmat = ifmat[., 1..cell_ix]
    }
    prof_t0 = csdid__profile_start()
    if (store_large == 0) {
        CSDID_TOKEN_COUNTER = CSDID_TOKEN_COUNTER + 1
        CSDID_LAST_TOKEN = CSDID_TOKEN_COUNTER
        CSDID_LAST_ATTGT = out
        CSDID_LAST_INFFUNC = ifmat
        CSDID_LAST_GROUP_PROB = group_prob_mat
        CSDID_LAST_UNIT_GROUP = unit_group_mat
        CSDID_LAST_UNIT_ROW = unit_first_row
        CSDID_LAST_ROW_UNIT = row_unit_index
        CSDID_LAST_CLUSTER_VEC = unit_cluster
    }
    else {
        CSDID_LAST_TOKEN = 0
        CSDID_LAST_ATTGT = J(0, 0, .)
        CSDID_LAST_INFFUNC = J(0, 0, .)
        CSDID_LAST_GROUP_PROB = J(0, 0, .)
        CSDID_LAST_UNIT_GROUP = J(0, 0, .)
        CSDID_LAST_UNIT_ROW = unit_first_row
        CSDID_LAST_ROW_UNIT = row_unit_index
        CSDID_LAST_CLUSTER_VEC = unit_cluster
    }
    st_matrix(outname, out)
    if (store_large != 0) st_matrix(ifname, ifmat)
    st_matrix(gprobname, group_prob_mat)
    if (store_large != 0) st_matrix(unitgroupname, unit_group_mat)
    st_numscalar(cachetokenname, CSDID_LAST_TOKEN)
    st_numscalar(fastusedname, fast_used)
    st_numscalar(balancedname, balanced_panel)
    st_numscalar(ntimename, cols(tlevels))
    csdid__profile_add(5, prof_t0, rows(ifmat) * cols(ifmat))
}

void csdid_cache_validate(real scalar expected_token, real scalar n_units, real scalar n_attgt)
{
    external real matrix CSDID_LAST_INFFUNC, CSDID_LAST_UNIT_GROUP
    external real scalar CSDID_LAST_TOKEN

    if (expected_token <= 0 | CSDID_LAST_TOKEN != expected_token) {
        errprintf("the stored influence functions do not match the active csdid results; re-run csdid with the storeall option, or re-run the estimation that produced these results\n")
        _error(498)
    }
    if (rows(CSDID_LAST_INFFUNC) != n_units | cols(CSDID_LAST_INFFUNC) != n_attgt) {
        errprintf("the stored influence functions have the wrong dimensions for the active csdid results; re-run csdid with the storeall option, or re-run the estimation that produced these results\n")
        _error(498)
    }
    if (rows(CSDID_LAST_UNIT_GROUP) != n_units) {
        errprintf("the stored unit map does not match the active csdid results; re-run csdid with the storeall option, or re-run the estimation that produced these results\n")
        _error(498)
    }
}

void csdid_cluster_attgt(
    string scalar clname,
    string scalar idname,
    string scalar tousename,
    string scalar attname,
    string scalar ifname,
    string scalar unitgroupname,
    string scalar nclustername,
    real scalar store_large,
    string scalar clustervecname)
{
    external real matrix CSDID_LAST_INFFUNC, CSDID_LAST_UNIT_GROUP, CSDID_LAST_UNIT_ROW, CSDID_LAST_ROW_UNIT
    external real matrix CSDID_LAST_CLUSTER_VEC
    real colvector cl, id, touse, cluster_vec, unit_id, se, unit_row, row_unit
    real matrix att, inf, unit_group, sc, idcl
    real scalar i, r, n, k, fast_cluster_map, prof_t0

    prof_t0 = csdid__profile_start()
    att = st_matrix(attname)
    inf = st_matrix(ifname)
    unit_group = st_matrix(unitgroupname)
    if ((rows(inf) == 0 | cols(inf) == 0) & rows(CSDID_LAST_INFFUNC) > 0) {
        inf = CSDID_LAST_INFFUNC
    }
    if ((rows(unit_group) == 0 | cols(unit_group) == 0) & rows(CSDID_LAST_UNIT_GROUP) > 0) {
        unit_group = CSDID_LAST_UNIT_GROUP
    }
    n = rows(inf)
    if (n == 0 | cols(inf) == 0) {
        st_numscalar(nclustername, 0)
        return
    }

    cluster_vec = J(n, 1, .)
    if (rows(CSDID_LAST_CLUSTER_VEC) == n & sum(CSDID_LAST_CLUSTER_VEC :>= .) == 0) {
        cluster_vec = CSDID_LAST_CLUSTER_VEC
    }
    else if (idname == "") {
        cl = st_data(., clname)
        for (i = 1; i <= n; i++) {
            r = unit_group[i, 1]
            if (r >= . | r < 1 | r > rows(cl)) {
                errprintf("cluster() could not be aligned with repeated-cross-section influence functions\n")
                _error(498)
            }
            cluster_vec[i] = cl[r]
        }
    }
    else {
        cl = st_data(., clname)
        touse = st_data(., tousename)
        unit_row = CSDID_LAST_UNIT_ROW
        row_unit = CSDID_LAST_ROW_UNIT
        fast_cluster_map = (rows(unit_row) == n & rows(row_unit) == rows(cl))
        if (fast_cluster_map) {
            for (i = 1; i <= n; i++) {
                r = unit_row[i]
                if (r >= . | r < 1 | r > rows(cl)) {
                    errprintf("cluster() could not be aligned with panel influence functions\n")
                    _error(498)
                }
                cluster_vec[i] = cl[r]
            }
            for (r = 1; r <= rows(cl); r++) {
                if (touse[r] == 0) continue
                k = row_unit[r]
                if (k >= . | k < 1 | k > n) continue
                if (cl[r] != cluster_vec[k]) {
                    errprintf("cluster() must be time-invariant within ivar()\n")
                    _error(459)
                }
            }
        }
        else {
            id = st_data(., idname)
            unit_id = unit_group[., 1]
            idcl = select((id, cl), touse :!= 0)
            idcl = sort(idcl, 1)
            r = 1
            for (i = 1; i <= n; i++) {
                while (r <= rows(idcl)) {
                    if (idcl[r, 1] >= unit_id[i]) break
                    r = r + 1
                }
                if (r > rows(idcl)) {
                    errprintf("cluster() could not be aligned with panel influence functions\n")
                    _error(498)
                }
                if (idcl[r, 1] != unit_id[i]) {
                    errprintf("cluster() could not be aligned with panel influence functions\n")
                    _error(498)
                }
                cluster_vec[i] = idcl[r, 2]
                while (r <= rows(idcl)) {
                    if (idcl[r, 1] != unit_id[i]) break
                    if (idcl[r, 2] != cluster_vec[i]) {
                        errprintf("cluster() must be time-invariant within ivar()\n")
                        _error(459)
                    }
                    r = r + 1
                }
            }
        }
    }

    if (sum(cluster_vec :>= .) > 0) {
        errprintf("cluster() contains missing values in the estimation sample\n")
        _error(459)
    }

    sc = csdid__cluster_sums(cluster_vec, inf)
    se = sqrt(colsum(sc:^2))' / n
    for (k = 1; k <= rows(se); k++) {
        if (se[k] <= sqrt(epsilon(1)) * 10) se[k] = .
    }
    att[., 5] = se
    st_matrix(attname, att)
    st_numscalar(nclustername, rows(sc))
    if (store_large != 0) st_matrix(clustervecname, cluster_vec)
    csdid__profile_add(6, prof_t0, n)
}

real rowvector csdid__which(real colvector flag)
{
    real colvector idx

    idx = select((1::rows(flag)), flag)
    if (rows(idx) == 0) return(J(1, 0, .))
    return(idx')
}

real scalar csdid__lookup_prob(real matrix group_prob, real scalar g)
{
    real scalar i

    for (i = 1; i <= rows(group_prob); i++) {
        if (group_prob[i, 1] == g) return(group_prob[i, 2])
    }
    return(.)
}

real colvector csdid__cell_probs(real colvector group, real matrix group_prob)
{
    real colvector pg
    real scalar i

    pg = J(rows(group), 1, .)
    for (i = 1; i <= rows(group); i++) {
        pg[i] = csdid__lookup_prob(group_prob, group[i])
    }
    return(pg)
}

real colvector csdid__take(real colvector x, real rowvector keep)
{
    real colvector out
    real scalar k

    out = J(cols(keep), 1, .)
    for (k = 1; k <= cols(keep); k++) out[k] = x[keep[k]]
    return(out)
}

real scalar csdid__se_from_if(real colvector ifv)
{
    real scalar n, se

    n = rows(ifv)
    if (n == 0) return(.)
    se = sqrt(quadcross(ifv, ifv)) / n
    if (se <= sqrt(epsilon(1)) * 10) return(.)
    return(se)
}

real matrix csdid__cluster_sums(real colvector cluster_vec, real matrix x)
{
    real matrix info
    real colvector ord, sorted_cluster

    if (rows(cluster_vec) != rows(x) | rows(x) == 0) return(J(0, cols(x), .))
    ord = order(cluster_vec, 1)
    sorted_cluster = cluster_vec[ord]
    info = panelsetup(sorted_cluster, 1)
    return(panelsum(x[ord, .], info))
}

real scalar csdid__se_from_if_cluster(real colvector ifv, real colvector cluster_vec)
{
    real matrix sc
    real scalar n, se

    n = rows(ifv)
    if (n == 0) return(.)
    if (rows(cluster_vec) != n) return(csdid__se_from_if(ifv))
    if (sum(cluster_vec :>= .) > 0) return(csdid__se_from_if(ifv))

    sc = csdid__cluster_sums(cluster_vec, ifv)
    se = sqrt(quadcross(sc[., 1], sc[., 1])) / n
    if (se <= sqrt(epsilon(1)) * 10) return(.)
    return(se)
}

real scalar csdid__type1_quantile(real colvector x, real scalar p)
{
    real colvector finite
    real scalar n, idx

    finite = select(x, x :< .)
    n = rows(finite)
    if (n == 0) return(.)
    finite = sort(finite, 1)
    idx = ceil(p * n)
    if (idx < 1) idx = 1
    if (idx > n) idx = n
    return(finite[idx])
}

real scalar csdid__bootstrap_sigma(real colvector bres, real scalar iqr_norm)
{
    real colvector finite
    real scalar n, idx25, idx75, if_ss, bsigma

    if (sum(bres :>= .) == 0) {
        n = rows(bres)
        if_ss = quadcross(bres, bres)
        finite = sort(bres, 1)
    }
    else {
        finite = select(bres, bres :< .)
        n = rows(finite)
        if (n == 0) return(.)
        if_ss = quadcross(finite, finite)
        finite = sort(finite, 1)
    }
    if (if_ss <= sqrt(epsilon(1)) * 10) return(.)
    idx25 = max((1, min((n, ceil(.25 * n)))))
    idx75 = max((1, min((n, ceil(.75 * n)))))
    bsigma = (finite[idx75] - finite[idx25]) / iqr_norm
    if (bsigma <= sqrt(epsilon(1)) * 10) return(.)
    return(bsigma)
}

real scalar csdid__bootstrap_cband_crit(
    real matrix bres,
    real colvector bsigma,
    real scalar alp,
    real scalar pointcrit)
{
    real colvector bT, rowmax, scaled
    real scalar b, j, crit

    crit = pointcrit
    rowmax = J(rows(bres), 1, .)
    for (b = 1; b <= rows(bres); b++) {
        scaled = J(cols(bres), 1, .)
        for (j = 1; j <= cols(bres); j++) {
            if (bsigma[j] < .) scaled[j] = abs(bres[b, j] / bsigma[j])
        }
        scaled = select(scaled, scaled :< .)
        if (rows(scaled) > 0) rowmax[b] = max(scaled)
    }
    bT = select(rowmax, rowmax :< .)
    if (rows(bT) > 0) crit = csdid__type1_quantile(bT, 1 - alp)
    if (crit < pointcrit) crit = pointcrit
    return(crit)
}

void csdid_bootstrap_attgt(
    string scalar attname,
    string scalar ifname,
    real scalar biters,
    real scalar alp,
    real scalar cband,
    string scalar dist,
    string scalar statename,
    string scalar bootname,
    string scalar drawsname,
    string scalar critname,
    string scalar pointcritname)
{
    external real matrix CSDID_LAST_INFFUNC
    real matrix att, inf, bres, bres_active, bootout
    real rowvector rng_state
    real colvector draw, bsigma, seboot, bT, scaled, rowmax, colss, active, seanalytic
    real scalar n, k, b, j, iqr_norm, pointcrit, crit, use_bmisc, prof_t0, zero_tol

    prof_t0 = csdid__profile_start()
    att = st_matrix(attname)
    inf = st_matrix(ifname)
    if ((rows(inf) == 0 | cols(inf) == 0) & rows(CSDID_LAST_INFFUNC) > 0) {
        inf = CSDID_LAST_INFFUNC
    }
    rng_state = J(1, 625, .)
    use_bmisc = (statename != "")
    if (use_bmisc) {
        rng_state = st_matrix(statename)
        if (cols(rng_state) != 625) {
            errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
            _error(498)
        }
    }
    n = rows(inf)
    k = cols(inf)
    if (n == 0 | k == 0 | k != rows(att)) {
        errprintf("stored influence functions do not match ATT(g,t) results\n")
        _error(498)
    }
    if (biters < 1) {
        errprintf("wboot() reps() must be a positive integer\n")
        _error(198)
    }

    zero_tol = sqrt(epsilon(1)) * 10
    colss = diagonal(quadcross(inf, inf))
    active = selectindex(colss :> zero_tol)
    if (rows(active) == k) {
        bres = csdid__bootstrap_auto(inf, biters, dist, rng_state, use_bmisc, cband) / sqrt(n)
    }
    else {
        bres = J(biters, k, 0)
        if (rows(active) > 0) {
            bres_active = csdid__bootstrap_auto(inf[., active], biters, dist, rng_state, use_bmisc, cband) / sqrt(n)
            bres[., active] = bres_active
        }
        else if (use_bmisc) {
            csdid__bmisc_skipboot(n, biters, rng_state)
        }
        else {
            bres = csdid__bootstrap_auto(inf, biters, dist, rng_state, use_bmisc, cband) / sqrt(n)
        }
    }

    iqr_norm = invnormal(.75) - invnormal(.25)
    bsigma = J(k, 1, .)
    seboot = J(k, 1, .)
    seanalytic = att[., 5]
    for (j = 1; j <= k; j++) {
        bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
        if (bsigma[j] < .) {
            seboot[j] = bsigma[j] / sqrt(n)
            att[j, 5] = seboot[j]
        }
    }

    pointcrit = invnormal(1 - alp / 2)
    crit = pointcrit
    if (cband) {
        rowmax = J(biters, 1, .)
        for (b = 1; b <= biters; b++) {
            scaled = J(k, 1, .)
            for (j = 1; j <= k; j++) {
                if (bsigma[j] < .) scaled[j] = abs(bres[b, j] / bsigma[j])
            }
            scaled = select(scaled, scaled :< .)
            if (rows(scaled) > 0) rowmax[b] = max(scaled)
        }
        bT = select(rowmax, rowmax :< .)
        if (rows(bT) > 0) crit = csdid__type1_quantile(bT, 1 - alp)
        if (crit < pointcrit) crit = pointcrit
    }

    bootout = J(k, 12, .)
    for (j = 1; j <= k; j++) {
        bootout[j, .] = (
            att[j, 1], att[j, 2], att[j, 3], att[j, 4],
            seboot[j], seanalytic[j],
            crit,
            att[j, 4] - crit * seboot[j],
            att[j, 4] + crit * seboot[j],
            pointcrit,
            att[j, 4] - pointcrit * seboot[j],
            att[j, 4] + pointcrit * seboot[j]
        )
    }

    st_matrix(attname, att)
    st_matrix(bootname, bootout)
    st_matrix(drawsname, bres)
    if (use_bmisc) st_matrix(statename, rng_state)
    st_numscalar(critname, crit)
    st_numscalar(pointcritname, pointcrit)
    csdid__profile_add(7, prof_t0, n * biters)
}

void csdid_bootstrap_attgt_cluster(
    string scalar attname,
    string scalar ifname,
    string scalar clustervecname,
    real scalar biters,
    real scalar alp,
    real scalar cband,
    string scalar dist,
    string scalar statename,
    string scalar bootname,
    string scalar drawsname,
    string scalar critname,
    string scalar pointcritname)
{
    external real matrix CSDID_LAST_INFFUNC, CSDID_LAST_CLUSTER_VEC
    real matrix att, inf, sc, bres, bres_active, bootout
    real rowvector rng_state
    real colvector cluster_vec, draw, bsigma, seboot, bT, scaled, rowmax, colss, active, seanalytic
    real scalar n, nc, k, b, j, i, iqr_norm, pointcrit, crit, use_bmisc, prof_t0, zero_tol

    prof_t0 = csdid__profile_start()
    att = st_matrix(attname)
    inf = st_matrix(ifname)
    if ((rows(inf) == 0 | cols(inf) == 0) & rows(CSDID_LAST_INFFUNC) > 0) {
        inf = CSDID_LAST_INFFUNC
    }
    if (clustervecname != "") {
        cluster_vec = st_matrix(clustervecname)
    }
    else {
        cluster_vec = CSDID_LAST_CLUSTER_VEC
    }
    rng_state = J(1, 625, .)
    use_bmisc = (statename != "")
    if (use_bmisc) {
        rng_state = st_matrix(statename)
        if (cols(rng_state) != 625) {
            errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
            _error(498)
        }
    }
    n = rows(inf)
    k = cols(inf)
    if (n == 0 | k == 0 | k != rows(att)) {
        errprintf("stored influence functions do not match ATT(g,t) results\n")
        _error(498)
    }
    if (rows(cluster_vec) != n | sum(cluster_vec :>= .) > 0) {
        errprintf("cluster() could not be aligned with bootstrap influence functions\n")
        _error(498)
    }
    if (biters < 1) {
        errprintf("wboot() reps() must be a positive integer\n")
        _error(198)
    }

    sc = csdid__cluster_sums(cluster_vec, inf)
    nc = rows(sc)
    if (nc == 0) {
        errprintf("cluster() has no clusters in the estimation sample\n")
        _error(498)
    }

    zero_tol = sqrt(epsilon(1)) * 10
    colss = diagonal(quadcross(sc, sc))
    active = selectindex(colss :> zero_tol)
    if (rows(active) == k) {
        bres = csdid__bootstrap_auto(sc, biters, dist, rng_state, use_bmisc, cband) / sqrt(nc)
    }
    else {
        bres = J(biters, k, 0)
        if (rows(active) > 0) {
            bres_active = csdid__bootstrap_auto(sc[., active], biters, dist, rng_state, use_bmisc, cband) / sqrt(nc)
            bres[., active] = bres_active
        }
        else if (use_bmisc) {
            csdid__bmisc_skipboot(nc, biters, rng_state)
        }
        else {
            bres = csdid__bootstrap_auto(sc, biters, dist, rng_state, use_bmisc, cband) / sqrt(nc)
        }
    }

    iqr_norm = invnormal(.75) - invnormal(.25)
    bsigma = J(k, 1, .)
    seboot = J(k, 1, .)
    seanalytic = att[., 5]
    for (j = 1; j <= k; j++) {
        bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
        if (bsigma[j] < .) {
            seboot[j] = bsigma[j] * sqrt(nc) / n
            att[j, 5] = seboot[j]
        }
    }

    pointcrit = invnormal(1 - alp / 2)
    crit = pointcrit
    if (cband) {
        rowmax = J(biters, 1, .)
        for (b = 1; b <= biters; b++) {
            scaled = J(k, 1, .)
            for (j = 1; j <= k; j++) {
                if (bsigma[j] < .) scaled[j] = abs(bres[b, j] / bsigma[j])
            }
            scaled = select(scaled, scaled :< .)
            if (rows(scaled) > 0) rowmax[b] = max(scaled)
        }
        bT = select(rowmax, rowmax :< .)
        if (rows(bT) > 0) crit = csdid__type1_quantile(bT, 1 - alp)
        if (crit < pointcrit) crit = pointcrit
    }

    bootout = J(k, 12, .)
    for (j = 1; j <= k; j++) {
        bootout[j, .] = (
            att[j, 1], att[j, 2], att[j, 3], att[j, 4],
            seboot[j], seanalytic[j],
            crit,
            att[j, 4] - crit * seboot[j],
            att[j, 4] + crit * seboot[j],
            pointcrit,
            att[j, 4] - pointcrit * seboot[j],
            att[j, 4] + pointcrit * seboot[j]
        )
    }

    st_matrix(attname, att)
    st_matrix(bootname, bootout)
    st_matrix(drawsname, bres)
    if (use_bmisc) st_matrix(statename, rng_state)
    st_numscalar(critname, crit)
    st_numscalar(pointcritname, pointcrit)
    csdid__profile_add(7, prof_t0, nc * biters)
}

void csdid_bootstrap_attgt_fast(
    string scalar attname,
    string scalar ifname,
    string scalar unitname,
    string scalar timename,
    string scalar clustervecname,
    real scalar biters,
    real scalar alp,
    real scalar cband,
    string scalar dist,
    string scalar statename,
    string scalar bootname,
    string scalar drawsname,
    string scalar critname,
    string scalar pointcritname)
{
    external real matrix CSDID_LAST_INFFUNC, CSDID_LAST_UNIT_GROUP, CSDID_LAST_CLUSTER_VEC
    real matrix att, inf, unit_group, sc, bres, bres_active, bootout
    real rowvector rng_state
    real colvector cluster_vec, ord, tt, group, bsigma, seboot, bT, scaled, rowmaxv, colss, active, seanalytic
    real scalar n, nc, k, b, j, iqr_norm, pointcrit, crit, use_bmisc, prof_t0, boot_t0, zero_tol
    real scalar use_cluster

    prof_t0 = csdid__profile_start()
    csdid__boot_profile_reset()
    csdid__boot_kernel_profile_reset()
    boot_t0 = csdid__profile_start()
    att = st_matrix(attname)
    inf = st_matrix(ifname)
    if ((rows(inf) == 0 | cols(inf) == 0) & rows(CSDID_LAST_INFFUNC) > 0) {
        inf = CSDID_LAST_INFFUNC
    }
    unit_group = st_matrix(unitname)
    if ((rows(unit_group) == 0 | cols(unit_group) == 0) & rows(CSDID_LAST_UNIT_GROUP) > 0) {
        unit_group = CSDID_LAST_UNIT_GROUP
    }
    n = rows(inf)
    k = cols(inf)
    if (n == 0 | k == 0 | k != rows(att)) {
        errprintf("stored influence functions do not match ATT(g,t) results\n")
        _error(498)
    }
    if (rows(unit_group) != n | cols(unit_group) < 2) {
        errprintf("stored unit/group map does not match bootstrap influence functions\n")
        _error(498)
    }
    group = unit_group[., 2]
    if (timename != "") {
        tt = st_data(unit_group[., 1], timename)
        if (rows(tt) != n) {
            errprintf("could not align repeated-cross-section bootstrap rows to time()\n")
            _error(498)
        }
        ord = csdid__boot_order_rc(tt, group)
    }
    else if (cols(unit_group) >= 4) {
        // F-001/F-022: allow_unbalanced path — consume draws in R's unit
        // order (first-appearance period ascending; see
        // csdid__boot_order_unbal).
        ord = csdid__boot_order_unbal(unit_group[., 4], group)
    }
    else {
        ord = csdid__boot_order_panel(group)
    }
    inf = inf[ord, .]
    csdid__boot_profile_add(1, boot_t0, n * k)

    boot_t0 = csdid__profile_start()
    use_cluster = (clustervecname != "")
    cluster_vec = J(0, 1, .)
    if (use_cluster) {
        cluster_vec = st_matrix(clustervecname)
        if ((rows(cluster_vec) == 0 | cols(cluster_vec) == 0) & rows(CSDID_LAST_CLUSTER_VEC) > 0) {
            cluster_vec = CSDID_LAST_CLUSTER_VEC
        }
        if (rows(cluster_vec) != n | sum(cluster_vec :>= .) > 0) {
            errprintf("cluster() could not be aligned with bootstrap influence functions\n")
            _error(498)
        }
        cluster_vec = cluster_vec[ord]
        sc = csdid__cluster_sums(cluster_vec, inf)
        nc = rows(sc)
        if (nc == 0) {
            errprintf("cluster() has no clusters in the estimation sample\n")
            _error(498)
        }
    }
    else {
        sc = inf
        nc = n
    }
    csdid__boot_profile_add(2, boot_t0, nc * k)

    rng_state = J(1, 625, .)
    use_bmisc = (statename != "")
    if (use_bmisc) {
        rng_state = st_matrix(statename)
        if (cols(rng_state) != 625) {
            errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
            _error(498)
        }
    }
    if (biters < 1) {
        errprintf("wboot() reps() must be a positive integer\n")
        _error(198)
    }

    boot_t0 = csdid__profile_start()
    zero_tol = sqrt(epsilon(1)) * 10
    colss = diagonal(quadcross(sc, sc))
    active = selectindex(colss :> zero_tol)
    csdid__boot_profile_add(3, boot_t0, rows(active))
    boot_t0 = csdid__profile_start()
    if (rows(active) == k) {
        bres = csdid__bootstrap_auto(sc, biters, dist, rng_state, use_bmisc, cband) / sqrt(nc)
    }
    else {
        bres = J(biters, k, 0)
        if (rows(active) > 0) {
            bres_active = csdid__bootstrap_auto(sc[., active], biters, dist, rng_state, use_bmisc, cband) / sqrt(nc)
            bres[., active] = bres_active
        }
        else if (use_bmisc) {
            csdid__bmisc_skipboot(nc, biters, rng_state)
        }
        else {
            bres = csdid__bootstrap_auto(sc, biters, dist, rng_state, use_bmisc, cband) / sqrt(nc)
        }
    }
    csdid__boot_profile_add(4, boot_t0, nc * biters)

    boot_t0 = csdid__profile_start()
    iqr_norm = invnormal(.75) - invnormal(.25)
    bsigma = J(k, 1, .)
    seboot = J(k, 1, .)
    seanalytic = att[., 5]
    for (j = 1; j <= k; j++) {
        bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
        if (bsigma[j] < . & use_cluster) {
            seboot[j] = bsigma[j] * sqrt(nc) / n
            att[j, 5] = seboot[j]
        }
        else if (bsigma[j] < .) {
            seboot[j] = bsigma[j] / sqrt(n)
            att[j, 5] = seboot[j]
        }
    }

    pointcrit = invnormal(1 - alp / 2)
    crit = pointcrit
    if (cband) {
        active = selectindex(bsigma :< .)
        if (rows(active) > 0) {
            scaled = J(biters, 1, 1) * bsigma[active]'
            scaled = abs(bres[., active] :/ scaled)
            rowmaxv = rowmax(scaled)
            bT = select(rowmaxv, rowmaxv :< .)
            if (rows(bT) > 0) crit = csdid__type1_quantile(bT, 1 - alp)
        }
        // F-011 R parity: att_gt-level cband crit is the raw type-1 quantile
        // of max-|t| (did::att_gt l240-266, no pointwise floor); only the
        // AGGREGATION level clamps to pointwise (compute.aggte l242-246),
        // which csdid__bootstrap_cband_crit — used only by agg kernels — keeps.
    }
    csdid__boot_profile_add(5, boot_t0, biters * k)

    boot_t0 = csdid__profile_start()
    bootout = J(k, 12, .)
    for (j = 1; j <= k; j++) {
        bootout[j, .] = (
            att[j, 1], att[j, 2], att[j, 3], att[j, 4],
            seboot[j], seanalytic[j],
            crit,
            att[j, 4] - crit * seboot[j],
            att[j, 4] + crit * seboot[j],
            pointcrit,
            att[j, 4] - pointcrit * seboot[j],
            att[j, 4] + pointcrit * seboot[j]
        )
    }

    st_matrix(attname, att)
    st_matrix(bootname, bootout)
    st_matrix(drawsname, bres)
    if (use_bmisc) st_matrix(statename, rng_state)
    st_numscalar(critname, crit)
    st_numscalar(pointcritname, pointcrit)
    csdid__boot_profile_add(6, boot_t0, biters * k)
    csdid__profile_add(7, prof_t0, nc * biters)
}

void csdid_boot_plugin_prepare(
    string scalar attname,
    string scalar ifname,
    string scalar unitname,
    string scalar timename,
    string scalar clustervecname,
    string scalar inputvars,
    string scalar nname,
    string scalar ncname,
    string scalar clustername,
    string scalar startedname)
{
    external real matrix CSDID_LAST_INFFUNC, CSDID_LAST_UNIT_GROUP, CSDID_LAST_CLUSTER_VEC
    external real scalar CSDID_BOOT_PLUGIN_PROFILE_START
    real matrix att, inf, unit_group, sc
    real colvector cluster_vec, ord, tt, group, colss, active
    string rowvector scratchvars
    real scalar n, nc, k, use_cluster, prof_t0, boot_t0, zero_tol

    prof_t0 = csdid__profile_start()
    CSDID_BOOT_PLUGIN_PROFILE_START = prof_t0
    csdid__boot_profile_reset()
    csdid__boot_kernel_profile_reset()

    boot_t0 = csdid__profile_start()
    att = st_matrix(attname)
    inf = st_matrix(ifname)
    if ((rows(inf) == 0 | cols(inf) == 0) & rows(CSDID_LAST_INFFUNC) > 0) {
        inf = CSDID_LAST_INFFUNC
    }
    unit_group = st_matrix(unitname)
    if ((rows(unit_group) == 0 | cols(unit_group) == 0) & rows(CSDID_LAST_UNIT_GROUP) > 0) {
        unit_group = CSDID_LAST_UNIT_GROUP
    }
    n = rows(inf)
    k = cols(inf)
    if (n == 0 | k == 0 | k != rows(att)) {
        errprintf("stored influence functions do not match ATT(g,t) results\n")
        _error(498)
    }
    if (rows(unit_group) != n | cols(unit_group) < 2) {
        errprintf("stored unit/group map does not match bootstrap influence functions\n")
        _error(498)
    }
    group = unit_group[., 2]
    if (timename != "") {
        tt = st_data(unit_group[., 1], timename)
        if (rows(tt) != n) {
            errprintf("could not align repeated-cross-section bootstrap rows to time()\n")
            _error(498)
        }
        ord = csdid__boot_order_rc(tt, group)
    }
    else if (cols(unit_group) >= 4) {
        // F-001/F-022: allow_unbalanced path — consume draws in R's unit
        // order (first-appearance period ascending; see
        // csdid__boot_order_unbal).
        ord = csdid__boot_order_unbal(unit_group[., 4], group)
    }
    else {
        ord = csdid__boot_order_panel(group)
    }
    inf = inf[ord, .]
    csdid__boot_profile_add(1, boot_t0, n * k)

    boot_t0 = csdid__profile_start()
    use_cluster = (clustervecname != "")
    cluster_vec = J(0, 1, .)
    if (use_cluster) {
        cluster_vec = st_matrix(clustervecname)
        if ((rows(cluster_vec) == 0 | cols(cluster_vec) == 0) & rows(CSDID_LAST_CLUSTER_VEC) > 0) {
            cluster_vec = CSDID_LAST_CLUSTER_VEC
        }
        if (rows(cluster_vec) != n | sum(cluster_vec :>= .) > 0) {
            errprintf("cluster() could not be aligned with bootstrap influence functions\n")
            _error(498)
        }
        cluster_vec = cluster_vec[ord]
        sc = csdid__cluster_sums(cluster_vec, inf)
        nc = rows(sc)
        if (nc == 0) {
            errprintf("cluster() has no clusters in the estimation sample\n")
            _error(498)
        }
    }
    else {
        sc = inf
        nc = n
    }
    csdid__boot_profile_add(2, boot_t0, nc * k)

    boot_t0 = csdid__profile_start()
    zero_tol = sqrt(epsilon(1)) * 10
    colss = diagonal(quadcross(sc, sc))
    active = selectindex(colss :> zero_tol)
    csdid__boot_profile_add(3, boot_t0, rows(active))

    scratchvars = tokens(inputvars)
    if (cols(scratchvars) != k | st_nobs() < nc) {
        errprintf("the fast bootstrap could not be set up for these influence functions; re-run csdid with the nofast option\n")
        _error(498)
    }
    boot_t0 = csdid__profile_start()
    st_store((1::nc), scratchvars, sc)
    csdid__boot_profile_add(1, boot_t0, nc * k)
    st_numscalar(nname, n)
    st_numscalar(ncname, nc)
    st_numscalar(clustername, use_cluster)
    st_numscalar(startedname, csdid__profile_start())
}

void csdid_boot_plugin_record(
    string scalar startedname,
    real scalar nc,
    real scalar biters)
{
    real scalar started

    started = st_numscalar(startedname)
    csdid__boot_profile_add(4, started, nc * biters)
}

void csdid_boot_plugin_finish(
    string scalar attname,
    string scalar bresname,
    real scalar n,
    real scalar nc,
    real scalar use_cluster,
    real scalar biters,
    real scalar alp,
    real scalar cband,
    string scalar bootname,
    string scalar drawsname,
    string scalar critname,
    string scalar pointcritname)
{
    external real scalar CSDID_BOOT_PLUGIN_PROFILE_START
    real matrix att, bres, bootout
    real colvector bsigma, seboot, seanalytic, active, scaled, rowmaxv, bT
    real scalar k, j, iqr_norm, pointcrit, crit, boot_t0

    att = st_matrix(attname)
    bres = st_matrix(bresname)
    k = rows(att)
    if (n < 1 | nc < 1 | rows(bres) != biters | cols(bres) != k) {
        errprintf("the fast bootstrap returned results that do not match the ATT(g,t) estimates; re-run csdid with the nofast option\n")
        _error(498)
    }

    boot_t0 = csdid__profile_start()
    iqr_norm = invnormal(.75) - invnormal(.25)
    bsigma = J(k, 1, .)
    seboot = J(k, 1, .)
    seanalytic = att[., 5]
    for (j = 1; j <= k; j++) {
        bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
        if (bsigma[j] < . & use_cluster) {
            seboot[j] = bsigma[j] * sqrt(nc) / n
            att[j, 5] = seboot[j]
        }
        else if (bsigma[j] < .) {
            seboot[j] = bsigma[j] / sqrt(n)
            att[j, 5] = seboot[j]
        }
    }

    pointcrit = invnormal(1 - alp / 2)
    crit = pointcrit
    if (cband) {
        active = selectindex(bsigma :< .)
        if (rows(active) > 0) {
            scaled = J(biters, 1, 1) * bsigma[active]'
            scaled = abs(bres[., active] :/ scaled)
            rowmaxv = rowmax(scaled)
            bT = select(rowmaxv, rowmaxv :< .)
            if (rows(bT) > 0) crit = csdid__type1_quantile(bT, 1 - alp)
        }
        // F-011 R parity: att_gt-level cband crit is the raw type-1 quantile
        // of max-|t| (did::att_gt l240-266, no pointwise floor); only the
        // AGGREGATION level clamps to pointwise (compute.aggte l242-246),
        // which csdid__bootstrap_cband_crit — used only by agg kernels — keeps.
    }
    csdid__boot_profile_add(5, boot_t0, biters * k)

    boot_t0 = csdid__profile_start()
    bootout = J(k, 12, .)
    for (j = 1; j <= k; j++) {
        bootout[j, .] = (
            att[j, 1], att[j, 2], att[j, 3], att[j, 4],
            seboot[j], seanalytic[j],
            crit,
            att[j, 4] - crit * seboot[j],
            att[j, 4] + crit * seboot[j],
            pointcrit,
            att[j, 4] - pointcrit * seboot[j],
            att[j, 4] + pointcrit * seboot[j]
        )
    }

    st_matrix(attname, att)
    st_matrix(bootname, bootout)
    st_matrix(drawsname, bres)
    st_numscalar(critname, crit)
    st_numscalar(pointcritname, pointcrit)
    csdid__boot_profile_add(6, boot_t0, biters * k)
    csdid__profile_add(7, CSDID_BOOT_PLUGIN_PROFILE_START, nc * biters)
}

void csdid_agg_boot_plugin_prepare(
    string scalar ifname,
    string scalar clustervecname,
    string scalar outinputname,
    string scalar nname,
    string scalar ncname,
    string scalar clustername,
    string scalar startedname)
{
    real matrix inf, sc
    real colvector cluster_vec
    real scalar n, nc, use_cluster, phase_t0

    csdid__agg_boot_profile_reset()
    phase_t0 = csdid__profile_start()
    inf = st_matrix(ifname)
    n = rows(inf)
    if (n == 0 | cols(inf) < 2) {
        errprintf("stored aggregate influence functions are invalid\n")
        _error(498)
    }
    use_cluster = (clustervecname != "")
    if (use_cluster) {
        cluster_vec = st_matrix(clustervecname)
        if (rows(cluster_vec) != n | sum(cluster_vec :>= .) > 0) {
            errprintf("cluster() could not be aligned with aggregate influence functions\n")
            _error(498)
        }
        sc = csdid__cluster_sums(cluster_vec, inf)
        st_matrix(outinputname, sc)
    }
    else {
        sc = inf
    }
    nc = rows(sc)
    if (nc == 0) {
        errprintf("the fast bootstrap could not be set up for this aggregation; re-run csdid with the nofast option\n")
        _error(498)
    }
    st_numscalar(nname, n)
    st_numscalar(ncname, nc)
    st_numscalar(clustername, use_cluster)
    csdid__agg_boot_profile_add(1, phase_t0, nc * cols(sc))
    st_numscalar(startedname, csdid__profile_start())
}

void csdid_agg_boot_plugin_finish(
    string scalar aggname,
    string scalar independentname,
    string scalar commonname,
    real scalar n,
    real scalar nc,
    real scalar use_cluster,
    real scalar biters,
    real scalar alp,
    real scalar cband,
    string scalar startedname,
    string scalar bootname,
    string scalar drawsname,
    string scalar critname,
    string scalar pointcritname)
{
    external real matrix CSDID_AGG_BOOT_PROFILE
    real matrix agg, bres, common, bootout
    real colvector bsigma, bsigma_cband, seboot
    real scalar k, k_effects, j, iqr_norm, pointcrit, crit, phase_t0, scale

    CSDID_AGG_BOOT_PROFILE[2, 1] =
        (csdid__profile_start() - st_numscalar(startedname)) / 1000
    agg = st_matrix(aggname)
    bres = st_matrix(independentname)
    common = st_matrix(commonname)
    k_effects = rows(agg)
    k = cols(bres)
    if (n < 1 | nc < 1 | rows(bres) != biters | k != k_effects + 1) {
        errprintf("the fast bootstrap returned results that do not match the aggregation; re-run csdid with the nofast option\n")
        _error(498)
    }
    if (cband & (rows(common) != biters | cols(common) != k_effects)) {
        errprintf("the fast bootstrap returned simultaneous-band results that do not match the aggregation; re-run csdid with the nofast option\n")
        _error(498)
    }
    CSDID_AGG_BOOT_PROFILE[2, 2] = 1
    CSDID_AGG_BOOT_PROFILE[2, 3] = biters * nc * (k + cband * k_effects)

    phase_t0 = csdid__profile_start()
    iqr_norm = invnormal(.75) - invnormal(.25)
    bsigma = J(k, 1, .)
    seboot = J(k, 1, .)
    scale = use_cluster ? sqrt(nc) / n : 1 / sqrt(n)
    for (j = 1; j <= k; j++) {
        bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
        if (bsigma[j] < .) seboot[j] = bsigma[j] * scale
    }

    pointcrit = invnormal(1 - alp / 2)
    crit = pointcrit
    if (cband) {
        bsigma_cband = J(k_effects, 1, .)
        for (j = 1; j <= k_effects; j++) {
            bsigma_cband[j] = csdid__bootstrap_sigma(common[., j], iqr_norm)
        }
        crit = csdid__bootstrap_cband_crit(common, bsigma_cband, alp, pointcrit)
    }
    for (j = 1; j <= k_effects; j++) {
        if (seboot[j] < .) agg[j, 3] = seboot[j]
        if (seboot[k] < .) agg[j, 5] = seboot[k]
    }

    bootout = J(k_effects, 10, .)
    for (j = 1; j <= k_effects; j++) {
        bootout[j, .] = (
            agg[j, 1], agg[j, 2], seboot[j],
            crit,
            agg[j, 2] - crit * seboot[j],
            agg[j, 2] + crit * seboot[j],
            pointcrit,
            agg[j, 2] - pointcrit * seboot[j],
            agg[j, 2] + pointcrit * seboot[j],
            seboot[k]
        )
    }

    st_matrix(aggname, agg)
    st_matrix(bootname, bootout)
    st_matrix(drawsname, bres)
    st_numscalar(critname, crit)
    st_numscalar(pointcritname, pointcrit)
    csdid__agg_boot_profile_add(3, phase_t0, biters * k)
}

real scalar csdid__u32(real scalar x)
{
    real scalar m

    m = 4294967296
    x = x - floor(x / m) * m
    if (x < 0) x = x + m
    return(x)
}

real scalar csdid__u32_rshift(real scalar x, real scalar bits)
{
    return(floor(x / (2 ^ bits)))
}

real scalar csdid__u32_lshift(real scalar x, real scalar bits)
{
    return(csdid__u32(x * (2 ^ bits)))
}

real rowvector csdid__u32v(real rowvector x)
{
    real scalar m

    m = 4294967296
    x = x :- floor(x :/ m) :* m
    return(x :+ (x :< 0) :* m)
}

real rowvector csdid__u32_lshiftv(real rowvector x, real scalar bits)
{
    return(csdid__u32v(x :* (2 ^ bits)))
}

void csdid__rng_tables_init()
{
    external real matrix CSDID_AND8, CSDID_XOR8, CSDID_MT_XOR_MAG
    external real colvector CSDID_AND8F, CSDID_XOR8F, CSDID_MT_TEMPER_LO, CSDID_MT_TEMPER_HI
    external real matrix CSDID_RBITS8
    external real scalar CSDID_RNG_TABLES_READY
    real scalar bi, bj, bk, bp, ba, bb

    if (CSDID_RNG_TABLES_READY) return
    CSDID_AND8 = J(256, 256, 0)
    CSDID_XOR8 = J(256, 256, 0)
    CSDID_AND8F = J(65536, 1, 0)
    CSDID_XOR8F = J(65536, 1, 0)
    CSDID_RBITS8 = J(256, 8, -1)
    CSDID_MT_TEMPER_LO = J(65536, 1, 0)
    CSDID_MT_TEMPER_HI = J(65536, 1, 0)
    CSDID_MT_XOR_MAG = J(65536, 4, 0)
    for (bi = 0; bi < 256; bi++) {
        bp = 128
        for (bk = 1; bk <= 8; bk++) {
            if (mod(floor(bi / bp), 2) == 1) CSDID_RBITS8[bi + 1, bk] = 1
            bp = bp / 2
        }
        for (bj = 0; bj < 256; bj++) {
            bp = 1
            for (bk = 0; bk < 8; bk++) {
                ba = mod(floor(bi / bp), 2)
                bb = mod(floor(bj / bp), 2)
                if (ba == 1 & bb == 1) {
                    CSDID_AND8[bi + 1, bj + 1] = CSDID_AND8[bi + 1, bj + 1] + bp
                }
                if (ba != bb) {
                    CSDID_XOR8[bi + 1, bj + 1] = CSDID_XOR8[bi + 1, bj + 1] + bp
                }
                bp = bp * 2
            }
            CSDID_AND8F[bi * 256 + bj + 1] = CSDID_AND8[bi + 1, bj + 1]
            CSDID_XOR8F[bi * 256 + bj + 1] = CSDID_XOR8[bi + 1, bj + 1]
        }
    }
    CSDID_RNG_TABLES_READY = 1
    csdid__mt_twist_tables_init()
    csdid__mt_temper_tables_init()
}

real scalar csdid__u32_bitand(real scalar a, real scalar b)
{
    external CSDID_AND8
    real scalar out, shift, byte_a, byte_b

    csdid__rng_tables_init()
    a = csdid__u32(a)
    b = csdid__u32(b)
    out = 0
    for (shift = 0; shift <= 24; shift = shift + 8) {
        byte_a = mod(floor(a / (2 ^ shift)), 256)
        byte_b = mod(floor(b / (2 ^ shift)), 256)
        out = out + CSDID_AND8[byte_a + 1, byte_b + 1] * (2 ^ shift)
    }
    return(out)
}

real rowvector csdid__u32_andv(real rowvector a, real rowvector b)
{
    external CSDID_AND8F
    real rowvector out, byte_a, byte_b, idx
    real scalar shift

    csdid__rng_tables_init()
    out = J(1, cols(a), 0)
    for (shift = 0; shift <= 24; shift = shift + 8) {
        byte_a = mod(floor(a :/ (2 ^ shift)), 256)
        byte_b = mod(floor(b :/ (2 ^ shift)), 256)
        idx = byte_a :* 256 :+ byte_b :+ 1
        out = out + CSDID_AND8F[idx]' :* (2 ^ shift)
    }
    return(out)
}

real scalar csdid__u32_bitxor(real scalar a, real scalar b)
{
    external CSDID_XOR8
    real scalar out, shift, byte_a, byte_b

    csdid__rng_tables_init()
    a = csdid__u32(a)
    b = csdid__u32(b)
    out = 0
    for (shift = 0; shift <= 24; shift = shift + 8) {
        byte_a = mod(floor(a / (2 ^ shift)), 256)
        byte_b = mod(floor(b / (2 ^ shift)), 256)
        out = out + CSDID_XOR8[byte_a + 1, byte_b + 1] * (2 ^ shift)
    }
    return(out)
}

real rowvector csdid__u32_xorv(real rowvector a, real rowvector b)
{
    external CSDID_XOR8F
    real rowvector out, byte_a, byte_b, idx
    real scalar shift

    csdid__rng_tables_init()
    out = J(1, cols(a), 0)
    for (shift = 0; shift <= 24; shift = shift + 8) {
        byte_a = mod(floor(a :/ (2 ^ shift)), 256)
        byte_b = mod(floor(b :/ (2 ^ shift)), 256)
        idx = byte_a :* 256 :+ byte_b :+ 1
        out = out + CSDID_XOR8F[idx]' :* (2 ^ shift)
    }
    return(out)
}

real rowvector csdid__u32_xor3v(real rowvector a, real rowvector b, real rowvector c)
{
    external CSDID_XOR8F
    real rowvector out, byte_a, byte_b, byte_c, byte_ab, idx
    real scalar shift

    csdid__rng_tables_init()
    out = J(1, cols(a), 0)
    for (shift = 0; shift <= 24; shift = shift + 8) {
        byte_a = mod(floor(a :/ (2 ^ shift)), 256)
        byte_b = mod(floor(b :/ (2 ^ shift)), 256)
        byte_c = mod(floor(c :/ (2 ^ shift)), 256)
        idx = byte_a :* 256 :+ byte_b :+ 1
        byte_ab = CSDID_XOR8F[idx]'
        idx = byte_ab :* 256 :+ byte_c :+ 1
        out = out + CSDID_XOR8F[idx]' :* (2 ^ shift)
    }
    return(out)
}

real rowvector csdid__mt_twist_xorv(real rowvector source, real rowvector half, real rowvector odd)
{
    external real colvector CSDID_XOR8F
    external real matrix CSDID_MT_XOR_MAG
    real rowvector out, byte_source, byte_half, byte_base, byte_masked, idx
    real scalar byte_position, shift

    csdid__rng_tables_init()
    out = J(1, cols(source), 0)
    byte_position = 0
    for (shift = 0; shift <= 24; shift = shift + 8) {
        byte_position = byte_position + 1
        byte_source = mod(floor(source :/ (2 ^ shift)), 256)
        byte_half = mod(floor(half :/ (2 ^ shift)), 256)
        idx = byte_source :* 256 :+ byte_half :+ 1
        byte_base = CSDID_XOR8F[idx]'
        byte_masked = CSDID_MT_XOR_MAG[idx', byte_position]'
        out = out + (byte_base :+ odd :* (byte_masked :- byte_base)) :* (2 ^ shift)
    }
    return(out)
}

void csdid__mt_twist_tables_init()
{
    external real colvector CSDID_XOR8F
    external real matrix CSDID_MT_XOR_MAG
    real colvector base, idx
    real scalar byte_position, mask_byte, matrix_a, shift

    matrix_a = 2567483615
    idx = (1::65536)
    base = CSDID_XOR8F
    byte_position = 0
    for (shift = 0; shift <= 24; shift = shift + 8) {
        byte_position = byte_position + 1
        mask_byte = mod(floor(matrix_a / (2 ^ shift)), 256)
        CSDID_MT_XOR_MAG[., byte_position] = CSDID_XOR8F[base :* 256 :+ mask_byte :+ 1]
    }
}

real rowvector csdid__mt_temper_reference(real rowvector y)
{
    y = csdid__u32_xorv(y, floor(y :/ (2 ^ 11)))
    y = csdid__u32_xorv(y, csdid__u32_andv(csdid__u32_lshiftv(y, 7), J(1, cols(y), 2636928640)))
    y = csdid__u32_xorv(y, csdid__u32_andv(csdid__u32_lshiftv(y, 15), J(1, cols(y), 4022730752)))
    y = csdid__u32_xorv(y, floor(y :/ (2 ^ 18)))
    return(y)
}

real rowvector csdid__mt_temper_fast(real rowvector y)
{
    external real colvector CSDID_MT_TEMPER_LO, CSDID_MT_TEMPER_HI
    real rowvector lo, hi

    csdid__rng_tables_init()
    lo = mod(y, 65536) :+ 1
    hi = floor(y :/ 65536) :+ 1
    return(csdid__u32_xorv(CSDID_MT_TEMPER_LO[lo']', CSDID_MT_TEMPER_HI[hi']'))
}

real scalar csdid__mt_temper_scalar(real scalar y)
{
    external real colvector CSDID_MT_TEMPER_LO, CSDID_MT_TEMPER_HI
    real scalar lo, hi

    csdid__rng_tables_init()
    lo = mod(y, 65536) + 1
    hi = floor(y / 65536) + 1
    return(csdid__u32_bitxor(CSDID_MT_TEMPER_LO[lo], CSDID_MT_TEMPER_HI[hi]))
}

void csdid__mt_temper_tables_init()
{
    external real colvector CSDID_MT_TEMPER_LO, CSDID_MT_TEMPER_HI
    real rowvector values

    values = (0..65535)
    CSDID_MT_TEMPER_LO = csdid__mt_temper_reference(values)'
    values = (0..65535) :* 65536
    CSDID_MT_TEMPER_HI = csdid__mt_temper_reference(values)'
}

real rowvector csdid__bmisc_rng_init(real scalar seed)
{
    real rowvector state
    real scalar j

    state = J(1, 625, 0)
    seed = csdid__u32(seed)
    for (j = 1; j <= 50; j++) {
        seed = csdid__u32(69069 * seed + 1)
    }
    for (j = 1; j <= 625; j++) {
        seed = csdid__u32(69069 * seed + 1)
        state[j] = seed
    }
    state[1] = 624
    return(state)
}

void csdid__bmisc_rng_twist(real rowvector state)
{
    real scalar kk, y, mag
    real scalar upper_mask, lower_mask, matrix_a

    upper_mask = 2147483648
    lower_mask = 2147483647
    matrix_a = 2567483615

    for (kk = 0; kk < 227; kk++) {
        y = csdid__u32_bitand(state[kk + 2], upper_mask) + csdid__u32_bitand(state[kk + 3], lower_mask)
        mag = 0
        if (mod(y, 2) == 1) mag = matrix_a
        state[kk + 2] = csdid__u32_bitxor(csdid__u32_bitxor(state[kk + 399], csdid__u32_rshift(y, 1)), mag)
    }
    for (kk = 227; kk < 623; kk++) {
        y = csdid__u32_bitand(state[kk + 2], upper_mask) + csdid__u32_bitand(state[kk + 3], lower_mask)
        mag = 0
        if (mod(y, 2) == 1) mag = matrix_a
        state[kk + 2] = csdid__u32_bitxor(csdid__u32_bitxor(state[kk - 225], csdid__u32_rshift(y, 1)), mag)
    }
    y = csdid__u32_bitand(state[625], upper_mask) + csdid__u32_bitand(state[2], lower_mask)
    mag = 0
    if (mod(y, 2) == 1) mag = matrix_a
    state[625] = csdid__u32_bitxor(csdid__u32_bitxor(state[398], csdid__u32_rshift(y, 1)), mag)
    state[1] = 0
}

void csdid__bmisc_rng_twist_fast(real rowvector state)
{
    real rowvector s0, s1, y, half, mag, odd
    real scalar upper_mask, lower_mask, matrix_a

    upper_mask = 2147483648
    lower_mask = 2147483647
    matrix_a = 2567483615

    s0 = state[2..228]
    s1 = state[3..229]
    y = (s0 :>= upper_mask) :* upper_mask :+ s1 :- (s1 :>= upper_mask) :* upper_mask
    half = floor(y :/ 2)
    odd = (mod(y, 2) :== 1)
    state[2..228] = csdid__mt_twist_xorv(state[399..625], half, odd)

    s0 = state[229..455]
    s1 = state[230..456]
    y = (s0 :>= upper_mask) :* upper_mask :+ s1 :- (s1 :>= upper_mask) :* upper_mask
    half = floor(y :/ 2)
    odd = (mod(y, 2) :== 1)
    state[229..455] = csdid__mt_twist_xorv(state[2..228], half, odd)

    s0 = state[456..624]
    s1 = state[457..625]
    y = (s0 :>= upper_mask) :* upper_mask :+ s1 :- (s1 :>= upper_mask) :* upper_mask
    half = floor(y :/ 2)
    odd = (mod(y, 2) :== 1)
    state[456..624] = csdid__mt_twist_xorv(state[229..397], half, odd)

    y = (state[625] >= upper_mask) * upper_mask + state[2] - (state[2] >= upper_mask) * upper_mask
    half = floor(y / 2)
    mag = (mod(y, 2) == 1) * matrix_a
    state[625] = csdid__u32_bitxor(csdid__u32_bitxor(state[398], half), mag)
    state[1] = 0
}

real scalar csdid__bmisc_unif(real rowvector state)
{
    real scalar mti, y, x

    mti = state[1]
    if (mti >= 624) csdid__bmisc_rng_twist_fast(state)
    mti = state[1]
    y = state[mti + 2]
    state[1] = mti + 1

    y = csdid__mt_temper_scalar(y)

    x = y * 2.3283064365386963e-10
    if (x <= 0) return(0.5 * 2.328306437080797e-10)
    if ((1 - x) <= 0) return(1 - 0.5 * 2.328306437080797e-10)
    return(x)
}

real rowvector csdid__bmisc_unif_ints(real scalar n, real rowvector state)
{
    real rowvector out, y
    real scalar pos, mti, take, kernel_t0

    out = J(1, n, .)
    pos = 1
    while (pos <= n) {
        mti = state[1]
        if (mti >= 624) {
            kernel_t0 = csdid__profile_start()
            csdid__bmisc_rng_twist_fast(state)
            csdid__boot_kernel_profile_add(1, kernel_t0, 624)
            mti = state[1]
        }
        take = min((n - pos + 1, 624 - mti))
        y = state[(mti + 2)..(mti + take + 1)]
        state[1] = mti + take

        kernel_t0 = csdid__profile_start()
        y = csdid__mt_temper_fast(y)
        csdid__boot_kernel_profile_add(2, kernel_t0, take)

        out[pos..(pos + take - 1)] = floor((y :* 2.3283064365386963e-10) :* 2147483647) :+ 1
        pos = pos + take
    }
    return(out)
}

real colvector csdid__bmisc_bootstrap_draw(real scalar n, real rowvector state)
{
    external CSDID_RBITS8
    real colvector out
    real rowvector chunk
    real scalar k, i, nints, curr, remaining, take
    real scalar b3, b2, b1, b0

    out = J(n, 1, .)
    nints = ceil(n / 31)
    k = 1
    for (i = 1; i <= nints; i++) {
        curr = floor(csdid__bmisc_unif(state) * 2147483647) + 1
        b3 = floor(curr / (2 ^ 24))
        b2 = mod(floor(curr / (2 ^ 16)), 256)
        b1 = mod(floor(curr / (2 ^ 8)), 256)
        b0 = mod(curr, 256)
        chunk = CSDID_RBITS8[b3 + 1, 2..8], CSDID_RBITS8[b2 + 1, .], CSDID_RBITS8[b1 + 1, .], CSDID_RBITS8[b0 + 1, .]
        remaining = n - k + 1
        take = min((31, remaining))
        out[k..(k + take - 1)] = chunk[1..take]'
        k = k + take
    }
    return(out)
}

real colvector csdid__bootstrap_draw(
    real scalar n,
    string scalar dist,
    real rowvector rng_state,
    real scalar use_bmisc)
{
    real colvector u

    if (dist == "rademacher") {
        if (use_bmisc) return(csdid__bmisc_bootstrap_draw(n, rng_state))
        u = runiform(n, 1)
        return(2 :* (u :>= .5) :- 1)
    }
    if (dist == "normal" | dist == "gaussian") {
        return(rnormal(n, 1, 0, 1))
    }
    errprintf("unsupported bootstrap multiplier distribution: %s\n", dist)
    _error(498)
}

real scalar csdid__native_seed_from_bmisc(real rowvector state)
{
    real scalar seed

    if (cols(state) < 2) return(0)
    seed = mod(abs(state[2]), 2147483646) + 1
    return(floor(seed))
}

real matrix csdid__native_rboot(
    real matrix x,
    real scalar biters,
    real scalar seed)
{
    real matrix draws, out
    string scalar oldstate

    if (seed > 0) {
        oldstate = rngstate()
        uniformseed(seed)
    }
    draws = 2 :* (runiform(biters, rows(x)) :>= .5) :- 1
    out = draws * x
    if (seed > 0) rngstate(oldstate)
    return(out)
}

real matrix csdid__native_rboot_rows(
    real matrix x,
    real scalar biters)
{
    real matrix draws
    real scalar n

    n = rows(x)
    draws = runiform(n * biters, 1)
    draws = 2 :* (draws :>= .5) :- 1
    draws = rowshape(draws, biters)
    return(draws * x)
}

real matrix csdid__native_rboot_indep(
    real matrix x,
    real scalar biters)
{
    real matrix draws, out
    real scalar n, k, j

    n = rows(x)
    k = cols(x)
    out = J(biters, k, .)
    for (j = 1; j <= k; j++) {
        draws = runiform(biters, n)
        draws = 2 :* (draws :>= .5) :- 1
        out[., j] = draws * x[., j]
    }
    return(out)
}

real matrix csdid__bootstrap_auto(
    real matrix x,
    real scalar biters,
    string scalar dist,
    real rowvector rng_state,
    real scalar use_bmisc,
    real scalar cband)
{
    real matrix out
    real colvector draw
    real scalar b, n, seed

    n = rows(x)
    if (dist == "rademacher" & !use_bmisc & n * biters <= 20000000) {
        if (cband) return(csdid__native_rboot_rows(x, biters))
        seed = 0
        out = csdid__native_rboot(x, biters, seed)
        return(out)
    }
    if (use_bmisc) return(csdid__bmisc_bootstrap_auto(x, biters, rng_state))

    out = J(biters, cols(x), .)
    for (b = 1; b <= biters; b++) {
        draw = csdid__bootstrap_draw(n, dist, rng_state, use_bmisc)
        out[b, .] = draw' * x
    }
    return(out)
}

void csdid_boot_reorder_r(
    string scalar unitname,
    string scalar ifname,
    string scalar clustername,
    string scalar outifname,
    string scalar outclustername)
{
    external real matrix CSDID_LAST_INFFUNC, CSDID_LAST_UNIT_GROUP, CSDID_LAST_CLUSTER_VEC
    real matrix inf, unit_group, sorted
    real colvector cluster_vec, ord, id, group, group_key

    inf = st_matrix(ifname)
    if ((rows(inf) == 0 | cols(inf) == 0) & rows(CSDID_LAST_INFFUNC) > 0) {
        inf = CSDID_LAST_INFFUNC
    }
    unit_group = st_matrix(unitname)
    if ((rows(unit_group) == 0 | cols(unit_group) == 0) & rows(CSDID_LAST_UNIT_GROUP) > 0) {
        unit_group = CSDID_LAST_UNIT_GROUP
    }
    if (rows(unit_group) != rows(inf) | cols(unit_group) < 2) {
        errprintf("stored unit/group map does not match bootstrap influence functions\n")
        _error(498)
    }

    group = unit_group[., 2]
    if (cols(unit_group) >= 4) {
        // F-001/F-022: allow_unbalanced — R consumes multiplier draws in its
        // unbalanced unit order (first-appearance period ascending; see
        // csdid__boot_order_unbal) at the aggregation stage as well.
        ord = csdid__boot_order_unbal(unit_group[., 4], group)
    }
    else {
        ord = csdid__boot_order_panel(group)
    }
    st_matrix(outifname, inf[ord, .])

    if (clustername != "") {
        cluster_vec = st_matrix(clustername)
        if ((rows(cluster_vec) == 0 | cols(cluster_vec) == 0) & rows(CSDID_LAST_CLUSTER_VEC) > 0) {
            cluster_vec = CSDID_LAST_CLUSTER_VEC
        }
        if (rows(cluster_vec) != rows(inf)) {
            errprintf("cluster() could not be aligned with bootstrap influence functions\n")
            _error(498)
        }
        st_matrix(outclustername, cluster_vec[ord])
    }
}

real colvector csdid__boot_order_panel(real colvector group)
{
    real colvector glevels, ord, idx
    real scalar j

    glevels = uniqrows(select(group, group :> 0))
    ord = J(0, 1, .)
    for (j = 1; j <= rows(glevels); j++) {
        idx = selectindex(group :== glevels[j])
        if (rows(idx) > 0) ord = ord \ idx
    }
    idx = selectindex(group :== 0)
    if (rows(idx) > 0) ord = ord \ idx
    if (rows(ord) != rows(group)) {
        ord = order(group :+ (group :== 0) :* 1e100, 1)
    }
    return(ord)
}

real colvector csdid__boot_order_rc(real colvector tt, real colvector group)
{
    real colvector tlevels, glevels, ord, idx, at_t
    real scalar i, j

    tlevels = uniqrows(tt)
    glevels = uniqrows(select(group, group :> 0))
    ord = J(0, 1, .)
    for (i = 1; i <= rows(tlevels); i++) {
        at_t = (tt :== tlevels[i])
        for (j = 1; j <= rows(glevels); j++) {
            idx = selectindex(at_t :& (group :== glevels[j]))
            if (rows(idx) > 0) ord = ord \ idx
        }
        idx = selectindex(at_t :& (group :== 0))
        if (rows(idx) > 0) ord = ord \ idx
    }
    if (rows(ord) != rows(group)) {
        ord = order((tt, group :+ (group :== 0) :* 1e100), (1, 2))
    }
    return(ord)
}

real colvector csdid__boot_order_unbal(real colvector p1, real colvector group)
{
    // F-001 / F-022: R did 2.5.1 unit order on the allow_unbalanced path.
    // pre_process_did's pseudo-RC conversion (.rowid = id) processes rows
    // period-major, so the effective unit order is FIRST-APPEARANCE PERIOD
    // ascending, then treated cohorts ascending with never-treated last, then
    // original (id) order within a cell.
    //
    // F-022: this used to key on a BINARY present-in-first-period flag, i.e.
    // one block for present units and one for absent ones. That collapses all
    // absent units into a single block regardless of when they actually enter,
    // and is only equivalent to R when sorting the absent block by (cohort, id)
    // happens to agree with sorting it by (entry period, cohort, id). It does
    // agree on F02 (one entry period) and F25u (no absent units) — and, by
    // coincidence, on F11 — which is why S032/S059/S060/S064/S066/S096/S097 all
    // passed. It does not agree on F27f, where absent units enter at two
    // periods and the permutations differ at 13 of 60 positions: witness S279,
    // att bit-identical but se off by 5.92e-02.
    //
    // p1 now carries the first-appearance PERIOD VALUE, not a flag. Units
    // present in the first period take the minimum value and so still sort
    // first, which makes the present/absent split a special case of the general
    // rule rather than a separate branch.
    real colvector plevels, glevels, ord, idx
    real scalar b, j

    plevels = uniqrows(p1)                   // ascending first-appearance periods
    glevels = uniqrows(select(group, group :> 0))
    ord = J(0, 1, .)
    for (b = 1; b <= rows(plevels); b++) {
        for (j = 1; j <= rows(glevels); j++) {
            idx = selectindex((p1 :== plevels[b]) :& (group :== glevels[j]))
            if (rows(idx) > 0) ord = ord \ idx
        }
        idx = selectindex((p1 :== plevels[b]) :& (group :== 0))
        if (rows(idx) > 0) ord = ord \ idx
    }
    if (rows(ord) != rows(group)) {
        errprintf("unbalanced bootstrap order could not be constructed\n")
        _error(498)
    }
    return(ord)
}

void csdid_boot_reorder_rc_r(
    string scalar timename,
    string scalar unitname,
    string scalar ifname,
    string scalar clustername,
    string scalar outifname,
    string scalar outclustername)
{
    external real matrix CSDID_LAST_INFFUNC, CSDID_LAST_UNIT_GROUP, CSDID_LAST_CLUSTER_VEC
    real matrix inf, unit_group, sorted
    real colvector cluster_vec, ord, id, group, group_key, tt

    inf = st_matrix(ifname)
    if ((rows(inf) == 0 | cols(inf) == 0) & rows(CSDID_LAST_INFFUNC) > 0) {
        inf = CSDID_LAST_INFFUNC
    }
    unit_group = st_matrix(unitname)
    if ((rows(unit_group) == 0 | cols(unit_group) == 0) & rows(CSDID_LAST_UNIT_GROUP) > 0) {
        unit_group = CSDID_LAST_UNIT_GROUP
    }
    if (rows(unit_group) != rows(inf) | cols(unit_group) < 2) {
        errprintf("stored unit/group map does not match bootstrap influence functions\n")
        _error(498)
    }

    group = unit_group[., 2]
    tt = st_data(unit_group[., 1], timename)
    if (rows(tt) != rows(inf)) {
        errprintf("could not align repeated-cross-section bootstrap rows to time()\n")
        _error(498)
    }
    ord = csdid__boot_order_rc(tt, group)
    st_matrix(outifname, inf[ord, .])

    if (clustername != "") {
        cluster_vec = st_matrix(clustername)
        if ((rows(cluster_vec) == 0 | cols(cluster_vec) == 0) & rows(CSDID_LAST_CLUSTER_VEC) > 0) {
            cluster_vec = CSDID_LAST_CLUSTER_VEC
        }
        if (rows(cluster_vec) != rows(inf)) {
            errprintf("cluster() could not be aligned with bootstrap influence functions\n")
            _error(498)
        }
        st_matrix(outclustername, cluster_vec[ord])
    }
}

real rowvector csdid__bmisc_bootstrap_dot(real matrix x, real rowvector state)
{
    external CSDID_RBITS8
    real rowvector out, chunk
    real scalar n, k, start, curr, remaining, take
    real scalar b3, b2, b1, b0

    csdid__rng_tables_init()
    n = rows(x)
    k = cols(x)
    out = J(1, k, 0)
    start = 1
    while (start <= n) {
        curr = floor(csdid__bmisc_unif(state) * 2147483647) + 1
        b3 = floor(curr / (2 ^ 24))
        b2 = mod(floor(curr / (2 ^ 16)), 256)
        b1 = mod(floor(curr / (2 ^ 8)), 256)
        b0 = mod(curr, 256)
        chunk = CSDID_RBITS8[b3 + 1, 2..8], CSDID_RBITS8[b2 + 1, .], CSDID_RBITS8[b1 + 1, .], CSDID_RBITS8[b0 + 1, .]
        remaining = n - start + 1
        take = min((31, remaining))
        out = out + chunk[1..take] * x[start..(start + take - 1), .]
        start = start + take
    }
    return(out)
}

real matrix csdid__bmisc_bootstrap_dense(
    real matrix x,
    real scalar biters,
    real rowvector state)
{
    external CSDID_RBITS8
    real matrix chunks, draws
    real rowvector currs, b3, b2, b1, b0
    real scalar n, nints, kernel_t0

    csdid__rng_tables_init()
    n = rows(x)
    nints = ceil(n / 31)
    currs = csdid__bmisc_unif_ints(biters * nints, state)
    kernel_t0 = csdid__profile_start()
    b3 = floor(currs / (2 ^ 24))
    b2 = mod(floor(currs / (2 ^ 16)), 256)
    b1 = mod(floor(currs / (2 ^ 8)), 256)
    b0 = mod(currs, 256)
    chunks = CSDID_RBITS8[b3' :+ 1, 2..8], CSDID_RBITS8[b2' :+ 1, .], CSDID_RBITS8[b1' :+ 1, .], CSDID_RBITS8[b0' :+ 1, .]
    csdid__boot_kernel_profile_add(3, kernel_t0, biters * n)
    kernel_t0 = csdid__profile_start()
    draws = rowshape(chunks, biters)
    if (cols(draws) > n) draws = draws[., 1..n]
    csdid__boot_kernel_profile_add(4, kernel_t0, biters * n)
    kernel_t0 = csdid__profile_start()
    chunks = draws * x
    csdid__boot_kernel_profile_add(5, kernel_t0, biters * n * cols(x))
    return(chunks)
}

real matrix csdid__bmisc_boot_dense_indep(
    real matrix x,
    real scalar biters,
    real rowvector state)
{
    external CSDID_RBITS8
    real matrix chunks, draws, out
    real rowvector currs, b3, b2, b1, b0
    real scalar n, k, nints, j, r1, r2

    csdid__rng_tables_init()
    n = rows(x)
    k = cols(x)
    nints = ceil(n / 31)
    currs = csdid__bmisc_unif_ints(biters * nints * k, state)
    b3 = floor(currs / (2 ^ 24))
    b2 = mod(floor(currs / (2 ^ 16)), 256)
    b1 = mod(floor(currs / (2 ^ 8)), 256)
    b0 = mod(currs, 256)
    chunks = CSDID_RBITS8[b3' :+ 1, 2..8], CSDID_RBITS8[b2' :+ 1, .], CSDID_RBITS8[b1' :+ 1, .], CSDID_RBITS8[b0' :+ 1, .]
    draws = rowshape(chunks, biters * k)
    if (cols(draws) > n) draws = draws[., 1..n]
    out = J(biters, k, .)
    for (j = 1; j <= k; j++) {
        r1 = (j - 1) * biters + 1
        r2 = j * biters
        out[., j] = draws[r1..r2, .] * x[., j]
    }
    return(out)
}

real matrix csdid__bmisc_bootstrap_matrix(
    real matrix x,
    real scalar biters,
    real rowvector state)
{
    external CSDID_RBITS8
    real matrix out, top, b2tab, b1tab, b0tab, currmat
    real rowvector currs
    real colvector curr, b3, b2, b1, b0
    real scalar n, k, nints, p, start, pos, len

    csdid__rng_tables_init()
    n = rows(x)
    k = cols(x)
    nints = ceil(n / 31)
    out = J(biters, k, 0)
    top = J(nints * 128, k, 0)
    b2tab = J(nints * 256, k, 0)
    b1tab = J(nints * 256, k, 0)
    b0tab = J(nints * 256, k, 0)

    for (p = 1; p <= nints; p++) {
        start = (p - 1) * 31 + 1

        len = min((7, n - start + 1))
        if (len > 0) {
            top[((p - 1) * 128 + 1)..(p * 128), .] =
                CSDID_RBITS8[1..128, 2..(len + 1)] * x[start..(start + len - 1), .]
        }

        pos = start + 7
        len = min((8, n - pos + 1))
        if (len > 0) {
            b2tab[((p - 1) * 256 + 1)..(p * 256), .] =
                CSDID_RBITS8[., 1..len] * x[pos..(pos + len - 1), .]
        }

        pos = start + 15
        len = min((8, n - pos + 1))
        if (len > 0) {
            b1tab[((p - 1) * 256 + 1)..(p * 256), .] =
                CSDID_RBITS8[., 1..len] * x[pos..(pos + len - 1), .]
        }

        pos = start + 23
        len = min((8, n - pos + 1))
        if (len > 0) {
            b0tab[((p - 1) * 256 + 1)..(p * 256), .] =
                CSDID_RBITS8[., 1..len] * x[pos..(pos + len - 1), .]
        }
    }

    currs = csdid__bmisc_unif_ints(biters * nints, state)
    currmat = rowshape(currs, biters)
    for (p = 1; p <= nints; p++) {
        curr = currmat[., p]
        b3 = floor(curr :/ (2 ^ 24))
        b2 = mod(floor(curr :/ (2 ^ 16)), 256)
        b1 = mod(floor(curr :/ (2 ^ 8)), 256)
        b0 = mod(curr, 256)
        out = out + top[(p - 1) * 128 :+ b3 :+ 1, .] +
            b2tab[(p - 1) * 256 :+ b2 :+ 1, .] +
            b1tab[(p - 1) * 256 :+ b1 :+ 1, .] +
            b0tab[(p - 1) * 256 :+ b0 :+ 1, .]
    }
    return(out)
}

real matrix csdid__bmisc_bootstrap_auto(
    real matrix x,
    real scalar biters,
    real rowvector state)
{
    real matrix out
    real scalar b

    if (rows(x) * biters <= 2000000) {
        return(csdid__bmisc_bootstrap_dense(x, biters, state))
    }
    if (biters <= 64) {
        out = J(biters, cols(x), .)
        for (b = 1; b <= biters; b++) {
            out[b, .] = csdid__bmisc_bootstrap_dot(x, state)
        }
        return(out)
    }
    return(csdid__bmisc_bootstrap_matrix(x, biters, state))
}

void csdid__bmisc_skipboot(
    real scalar n,
    real scalar biters,
    real rowvector state)
{
    real scalar remaining, mti, take

    remaining = ceil(n / 31) * biters
    while (remaining > 0) {
        mti = state[1]
        if (mti >= 624) {
            csdid__bmisc_rng_twist_fast(state)
            mti = state[1]
        }
        take = min((remaining, 624 - mti))
        state[1] = mti + take
        remaining = remaining - take
    }
}

void csdid_bmisc_aggskip(
    string scalar ifname,
    real scalar biters,
    real scalar cband,
    string scalar statename)
{
    real matrix inf
    real rowvector rng_state
    real scalar n, k_effects, skip_calls, j

    inf = st_matrix(ifname)
    rng_state = st_matrix(statename)
    if (cols(rng_state) != 625) {
        errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
        _error(498)
    }
    n = rows(inf)
    k_effects = cols(inf) - 1
    if (n == 0 | k_effects < 1 | biters < 1) {
        errprintf("stored aggregate influence functions do not match aggregation results\n")
        _error(498)
    }

    skip_calls = k_effects + 1
    if (cband) skip_calls = skip_calls + 1
    for (j = 1; j <= skip_calls; j++) csdid__bmisc_skipboot(n, biters, rng_state)
    st_matrix(statename, rng_state)
}

void csdid_bmisc_attgtskip(
    string scalar ifname,
    real scalar biters,
    string scalar statename)
{
    external real matrix CSDID_LAST_INFFUNC
    real matrix inf
    real rowvector rng_state
    real scalar n

    inf = st_matrix(ifname)
    if ((rows(inf) == 0 | cols(inf) == 0) & rows(CSDID_LAST_INFFUNC) > 0) {
        inf = CSDID_LAST_INFFUNC
    }
    rng_state = st_matrix(statename)
    if (cols(rng_state) != 625) {
        errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
        _error(498)
    }
    n = rows(inf)
    if (n == 0 | biters < 1) {
        errprintf("stored influence functions do not match bootstrap results\n")
        _error(498)
    }

    csdid__bmisc_skipboot(n, biters, rng_state)
    st_matrix(statename, rng_state)
}

void csdid_bmisc_skipdraws(
    real scalar ndraws,
    string scalar statename)
{
    real rowvector rng_state
    real scalar remaining, mti, take

    rng_state = st_matrix(statename)
    if (cols(rng_state) != 625) {
        errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
        _error(498)
    }
    remaining = ndraws
    while (remaining > 0) {
        mti = rng_state[1]
        if (mti >= 624) {
            csdid__bmisc_rng_twist_fast(rng_state)
            mti = rng_state[1]
        }
        take = min((remaining, 624 - mti))
        rng_state[1] = mti + take
        remaining = remaining - take
    }
    st_matrix(statename, rng_state)
}

void csdid__permute_if_to_data_order(
    string scalar ifname,
    string scalar idname,
    string scalar unitname,
    string scalar outname)
{
    real matrix inf, unit_group
    real colvector data_id, unit_id, seen, order
    real scalar r, idx

    inf = st_matrix(ifname)
    unit_group = st_matrix(unitname)
    data_id = st_data(., idname)
    unit_id = unit_group[., 1]
    seen = J(0, 1, .)
    order = J(0, 1, .)

    for (r = 1; r <= rows(data_id); r++) {
        if (data_id[r] >= .) continue
        if (rows(seen) > 0) {
            if (sum(seen :== data_id[r]) > 0) continue
        }
        seen = seen \ data_id[r]
        idx = csdid__sorted_col_index(unit_id, data_id[r])
        if (idx < .) order = order \ idx
    }

    if (rows(order) != rows(inf)) {
        errprintf("could not align influence functions to data unit order\n")
        _error(498)
    }
    st_matrix(outname, inf[order, .])
}

void csdid_bmisc_labelse(
    string scalar ifname,
    real scalar biters,
    real scalar cband,
    string scalar statename,
    string scalar outname)
{
    real matrix inf, bres
    real rowvector rng_state
    real scalar n, k, k_effects, skip_calls, j, iqr_norm, bsigma, seboot

    inf = st_matrix(ifname)
    rng_state = st_matrix(statename)
    if (cols(rng_state) != 625) {
        errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
        _error(498)
    }
    n = rows(inf)
    k = cols(inf)
    k_effects = k - 1
    if (n == 0 | k_effects < 1 | biters < 1) {
        errprintf("stored aggregate influence functions do not match aggregation results\n")
        _error(498)
    }

    skip_calls = k_effects
    if (cband) skip_calls = skip_calls + 1
    for (j = 1; j <= skip_calls; j++) csdid__bmisc_skipboot(n, biters, rng_state)

    if (n * biters <= 60000000) {
        bres = csdid__bmisc_bootstrap_dense(inf[., k], biters, rng_state) / sqrt(n)
    }
    else {
        bres = csdid__bmisc_bootstrap_auto(inf[., k], biters, rng_state) / sqrt(n)
    }
    iqr_norm = invnormal(.75) - invnormal(.25)
    bsigma = csdid__bootstrap_sigma(bres[., 1], iqr_norm)
    seboot = .
    if (bsigma < .) seboot = bsigma / sqrt(n)
    st_numscalar(outname, seboot)
    st_matrix(statename, rng_state)
}

real matrix csdid__wif(
    real rowvector keep,
    real colvector pg,
    real colvector unit_weight,
    real colvector unit_group,
    real colvector cell_group)
{
    real matrix centered, out
    real colvector row_sum
    real scalar n, k, kk, spg

    n = rows(unit_group)
    k = cols(keep)
    if (k == 0) return(J(n, 0, .))
    spg = 0
    for (kk = 1; kk <= k; kk++) spg = spg + pg[keep[kk]]
    centered = J(n, k, .)
    for (kk = 1; kk <= k; kk++) {
        centered[., kk] = unit_weight :* (unit_group :== cell_group[keep[kk]]) :- pg[keep[kk]]
    }
    row_sum = rowsum(centered)
    out = J(n, k, .)
    for (kk = 1; kk <= k; kk++) {
        out[., kk] = centered[., kk] / spg :- row_sum * (pg[keep[kk]] / (spg ^ 2))
    }
    return(out)
}

real colvector csdid__agg_if(
    real colvector att,
    real matrix inffunc,
    real rowvector keep,
    real colvector weights,
    real matrix wif)
{
    real colvector out
    real scalar k, kk

    k = cols(keep)
    out = J(rows(inffunc), 1, 0)
    for (kk = 1; kk <= k; kk++) {
        out = out + weights[kk] * inffunc[., keep[kk]]
    }
    if (rows(wif) > 0) {
        for (kk = 1; kk <= k; kk++) {
            out = out + att[keep[kk]] * wif[., kk]
        }
    }
    return(out)
}

real colvector csdid__normalized_cell_weights(real rowvector keep, real colvector pg)
{
    real colvector weights
    real scalar kk, spg

    weights = J(cols(keep), 1, .)
    spg = 0
    for (kk = 1; kk <= cols(keep); kk++) {
        weights[kk] = pg[keep[kk]]
        spg = spg + weights[kk]
    }
    return(weights / spg)
}

void csdid_aggte(
    string scalar type,
    real scalar min_e,
    real scalar max_e,
    real scalar balance_e,
    real scalar na_rm,
    real scalar use_cluster,
    real scalar use_cache,
    string scalar outname,
    string scalar ifname,
    real scalar store_large)
{
    external real matrix CSDID_LAST_INFFUNC, CSDID_LAST_UNIT_GROUP, CSDID_LAST_CLUSTER_VEC
    external real matrix CSDID_LAST_AGG_INFFUNC
    external real scalar CSDID_LAST_TOKEN, CSDID_LAST_AGG_TOKEN
    real matrix attgt, inffunc, group_prob, unit_group_mat, out, wif, effect_if
    real matrix effect_if_mat, t_first_mat  // F-009: defensive e(time_first) fetch
    real colvector group, tt, event_time, att, pg, unit_group, unit_weight, glist, pgg, cluster_vec
    real colvector effects, ses, egt, tlist, include_balanced, pos, notmiss
    real colvector weights, overall_weights, overall_if
    real rowvector keep, keep2, keep_notmiss
    real scalar i, k, n_effects, g, e, t, overall_att, overall_se, max_t, pg_g, t_first  // F-009: balance_e truncation needs e(time_first)

    attgt = st_matrix("e(attgt)")
    group_prob = st_matrix("e(group_prob)")
    if (use_cache != 0) {
        inffunc = CSDID_LAST_INFFUNC
        unit_group_mat = CSDID_LAST_UNIT_GROUP
    }
    else {
        inffunc = st_matrix("e(inffunc)")
        unit_group_mat = st_matrix("e(unit_group)")
    }
    cluster_vec = J(0, 1, .)
    if (use_cluster != 0 & st_global("e(clustervar)") != "") {
        if (use_cache != 0 & rows(CSDID_LAST_CLUSTER_VEC) == rows(inffunc)) {
            cluster_vec = CSDID_LAST_CLUSTER_VEC
        }
        else {
            cluster_vec = st_matrix("e(cluster_vec)")
        }
    }

    if (rows(attgt) == 0) {
        errprintf("no ATT(g,t) results available for aggregation\n")
        _error(498)
    }
    if (cols(inffunc) != rows(attgt)) {
        errprintf("stored influence functions do not match ATT(g,t) results\n")
        _error(498)
    }
    if (use_cache != 0 & rows(unit_group_mat) != st_numscalar("e(N_units)")) {
        errprintf("the stored influence functions do not match the active csdid results; re-run csdid before aggregating\n")
        _error(498)
    }

    att = attgt[., 4]
    if (sum(att :>= .) > 0) {
        if (!na_rm) {
            errprintf("missing values found in ATT(g,t) estimates; specify dropmissing to drop them\n")
            _error(498)
        }
        notmiss = (att :< .)
        if (sum(notmiss) == 0) {
            errprintf("all ATT(g,t) estimates are missing; cannot aggregate\n")
            _error(498)
        }
        keep_notmiss = csdid__which(notmiss)
        attgt = attgt[keep_notmiss, .]
        inffunc = inffunc[., keep_notmiss]
    }

    group = attgt[., 1]
    tt = attgt[., 2]
    event_time = attgt[., 3]
    att = attgt[., 4]
    unit_group = unit_group_mat[., 2]
    if (cols(unit_group_mat) >= 3) {
        unit_weight = unit_group_mat[., 3]
    }
    else {
        unit_weight = J(rows(unit_group_mat), 1, 1)
    }
    glist = group_prob[., 1]
    pgg = group_prob[., 2]
    pg = csdid__cell_probs(group, group_prob)
    out = J(0, 5, .)

    if (type == "simple") {
        keep = csdid__which((group :<= tt) :& (tt :<= group :+ max_e))
        if (cols(keep) == 0) {
            errprintf("no valid ATT(g,t) estimates found for simple aggregation\n")
            _error(498)
        }
        weights = csdid__normalized_cell_weights(keep, pg)
        wif = csdid__wif(keep, pg, unit_weight, unit_group, group)
        overall_att = quadcross(weights, csdid__take(att, keep))
        overall_if = csdid__agg_if(att, inffunc, keep, weights, wif)
        overall_se = csdid__se_from_if_cluster(overall_if, cluster_vec)
        out = (., overall_att, overall_se, overall_att, overall_se)
        // The aggregation influence functions are one row per UNIT. Stata's
        // classic-matrix layer is quadratic in a matrix's longest dimension
        // (measured on Stata MP: writing or copying an n x 1 matrix costs
        // 4s at n=25,000, 27s at 50,000, 148s at 100,000 -- independent of
        // orientation and of the number of cells), so an unconditional
        // st_matrix() here made `estat event' after a 400,000-unit estimation
        // hang for hours while csdid itself finished in seconds. The IF
        // therefore always lands in the Mata cache, tagged with the token of
        // the estimation it belongs to, and crosses into a Stata matrix only
        // under full storage -- the same policy the estimator applies to
        // e(inffunc). Consumers fall back to the cache through the same
        // empty-name convention the bootstrap plumbing already uses.
        CSDID_LAST_AGG_INFFUNC = (overall_if, overall_if)
        CSDID_LAST_AGG_TOKEN = CSDID_LAST_TOKEN
        st_matrix(outname, out)
        if (store_large) st_matrix(ifname, CSDID_LAST_AGG_INFFUNC)
        return
    }

    if (type == "group") {
        effects = J(0, 1, .)
        ses = J(0, 1, .)
        egt = J(0, 1, .)
        pgg = J(0, 1, .)
        effect_if_mat = J(rows(inffunc), 0, .)
        for (i = 1; i <= rows(glist); i++) {
            g = glist[i]
            keep = csdid__which((group :== g) :& (group :<= tt) :& (tt :<= group :+ max_e))
            if (cols(keep) == 0) {
                if (na_rm) continue
                errprintf("no valid ATT(g,t) estimates found for group aggregation\n")
                _error(498)
            }
            weights = J(cols(keep), 1, 1 / cols(keep))
            effects = effects \ quadcross(weights, csdid__take(att, keep))
            effect_if = csdid__agg_if(att, inffunc, keep, weights, J(0, 0, .))
            ses = ses \ csdid__se_from_if_cluster(effect_if, cluster_vec)
            effect_if_mat = effect_if_mat, effect_if
            egt = egt \ g
            pg_g = csdid__lookup_prob(group_prob, g)
            pgg = pgg \ pg_g
        }
        n_effects = rows(effects)
        if (n_effects == 0) {
            errprintf("no valid ATT(g,t) estimates found for group aggregation\n")
            _error(498)
        }
        overall_weights = pgg / sum(pgg)
        keep = (1::n_effects)'
        wif = csdid__wif(keep, pgg, unit_weight, unit_group, egt)
        overall_att = quadcross(overall_weights, effects)
        overall_if = csdid__agg_if(effects, effect_if_mat, keep, overall_weights, wif)
        overall_se = csdid__se_from_if_cluster(overall_if, cluster_vec)
        for (i = 1; i <= n_effects; i++) {
            out = out \ (egt[i], effects[i], ses[i], overall_att, overall_se)
        }
        // lean storage: see the note in the simple branch
        CSDID_LAST_AGG_INFFUNC = (effect_if_mat, overall_if)
        CSDID_LAST_AGG_TOKEN = CSDID_LAST_TOKEN
        st_matrix(outname, out)
        if (store_large) st_matrix(ifname, CSDID_LAST_AGG_INFFUNC)
        return
    }

    if (type == "dynamic") {
        include_balanced = J(rows(group), 1, 1)
        if (balance_e >= 0) {
            max_t = max(tt)
            include_balanced = ((max_t :- group) :>= balance_e)
        }
        egt = uniqrows(select(event_time, include_balanced :!= 0))
        if (balance_e >= 0) {
            // R parity (did 2.5.1 compute.aggte): with balance_e set, event
            // times are restricted to [balance_e - (maxT - t_first), balance_e]
            // F-009: fetch defensively. st_numscalar() returns a 0x0 matrix
            // when the scalar is absent, and assigning that into a real scalar
            // aborts with a raw Mata conformability error (rc 3200) BEFORE the
            // refusal below can run. The saved-RIF path posts no e(time_first),
            // so `csdid_stats using <rif>, balance()' hit exactly that.
            t_first_mat = st_numscalar("e(time_first)")
            if (rows(t_first_mat) == 0 | cols(t_first_mat) == 0) {
                errprintf("e(time_first) not found; re-run csdid before using balance()\n")
                _error(498)
            }
            t_first = t_first_mat[1, 1]
            if (t_first >= .) {
                errprintf("e(time_first) not found; re-run csdid before using balance()\n")
                _error(498)
            }
            egt = select(egt, (egt :<= balance_e) :& (egt :>= balance_e - max_t + t_first))  // F-009
        }
        egt = select(egt, (egt :>= min_e) :& (egt :<= max_e))
        if (rows(egt) == 0) {
            errprintf("no event times fall within the requested aggregation window\n")
            _error(498)
        }
        n_effects = rows(egt)
        effects = J(n_effects, 1, .)
        ses = J(n_effects, 1, .)
        effect_if_mat = J(rows(inffunc), n_effects, .)
        for (i = 1; i <= n_effects; i++) {
            e = egt[i]
            keep = csdid__which((event_time :== e) :& (include_balanced :!= 0))
            weights = csdid__normalized_cell_weights(keep, pg)
            wif = csdid__wif(keep, pg, unit_weight, unit_group, group)
            effects[i] = quadcross(weights, csdid__take(att, keep))
            effect_if = csdid__agg_if(att, inffunc, keep, weights, wif)
            ses[i] = csdid__se_from_if_cluster(effect_if, cluster_vec)
            effect_if_mat[., i] = effect_if
        }
        pos = (egt :>= 0)
        if (sum(pos) == 0) {
            errprintf("no post-treatment event times fall within the requested aggregation window\n")
            _error(498)
        }
        overall_att = mean(select(effects, pos))
        keep2 = csdid__which(pos)
        overall_weights = J(cols(keep2), 1, 1 / cols(keep2))
        overall_if = csdid__agg_if(effects, effect_if_mat, keep2, overall_weights, J(0, 0, .))
        overall_se = csdid__se_from_if_cluster(overall_if, cluster_vec)
        for (i = 1; i <= n_effects; i++) {
            out = out \ (egt[i], effects[i], ses[i], overall_att, overall_se)
        }
        // lean storage: see the note in the simple branch
        CSDID_LAST_AGG_INFFUNC = (effect_if_mat, overall_if)
        CSDID_LAST_AGG_TOKEN = CSDID_LAST_TOKEN
        st_matrix(outname, out)
        if (store_large) st_matrix(ifname, CSDID_LAST_AGG_INFFUNC)
        return
    }

    if (type == "calendar") {
        tlist = uniqrows(tt)
        tlist = select(tlist, tlist :>= min(glist))
        effects = J(0, 1, .)
        ses = J(0, 1, .)
        egt = J(0, 1, .)
        effect_if_mat = J(rows(inffunc), 0, .)
        for (i = 1; i <= rows(tlist); i++) {
            t = tlist[i]
            keep = csdid__which((tt :== t) :& (group :<= tt))
            if (cols(keep) == 0) continue
            weights = csdid__normalized_cell_weights(keep, pg)
            wif = csdid__wif(keep, pg, unit_weight, unit_group, group)
            effects = effects \ quadcross(weights, csdid__take(att, keep))
            effect_if = csdid__agg_if(att, inffunc, keep, weights, wif)
            ses = ses \ csdid__se_from_if_cluster(effect_if, cluster_vec)
            effect_if_mat = effect_if_mat, effect_if
            egt = egt \ t
        }
        n_effects = rows(effects)
        if (n_effects == 0) {
            errprintf("no calendar periods have valid post-treatment ATT(g,t) estimates\n")
            _error(498)
        }
        overall_att = mean(effects)
        keep = (1::n_effects)'
        overall_weights = J(n_effects, 1, 1 / n_effects)
        overall_if = csdid__agg_if(effects, effect_if_mat, keep, overall_weights, J(0, 0, .))
        overall_se = csdid__se_from_if_cluster(overall_if, cluster_vec)
        for (i = 1; i <= n_effects; i++) {
            out = out \ (egt[i], effects[i], ses[i], overall_att, overall_se)
        }
        // lean storage: see the note in the simple branch
        CSDID_LAST_AGG_INFFUNC = (effect_if_mat, overall_if)
        CSDID_LAST_AGG_TOKEN = CSDID_LAST_TOKEN
        st_matrix(outname, out)
        if (store_large) st_matrix(ifname, CSDID_LAST_AGG_INFFUNC)
        return
    }
}

void csdid_bootstrap_aggte(
    string scalar aggname,
    string scalar ifname,
    real scalar biters,
    real scalar alp,
    real scalar cband,
    string scalar dist,
    string scalar statename,
    string scalar bootname,
    string scalar drawsname,
    string scalar critname,
    string scalar pointcritname)
{
    real matrix agg, inf, bres, bres_col, bres_cband, bootout
    real rowvector rng_state
    real colvector bsigma, bsigma_cband, seboot
    real scalar n, k_effects, k, j, iqr_norm, pointcrit, crit, use_bmisc, simple_duplicate, phase_t0

    csdid__agg_boot_profile_reset()
    phase_t0 = csdid__profile_start()
    agg = st_matrix(aggname)
    inf = st_matrix(ifname)
    rng_state = J(1, 625, .)
    use_bmisc = (statename != "")
    if (use_bmisc) {
        rng_state = st_matrix(statename)
        if (cols(rng_state) != 625) {
            errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
            _error(498)
        }
    }
    n = rows(inf)
    k_effects = rows(agg)
    k = cols(inf)
    if (n == 0 | k_effects == 0 | k != k_effects + 1) {
        errprintf("stored aggregate influence functions do not match aggregation results\n")
        _error(498)
    }
    if (biters < 1) {
        errprintf("wboot() reps() must be a positive integer\n")
        _error(198)
    }

    iqr_norm = invnormal(.75) - invnormal(.25)
    bsigma = J(k, 1, .)
    seboot = J(k, 1, .)
    pointcrit = invnormal(1 - alp / 2)
    crit = pointcrit
    csdid__agg_boot_profile_add(1, phase_t0, n * k)

    phase_t0 = csdid__profile_start()
    simple_duplicate = (k_effects == 1 & k == 2 & max(abs(inf[., 1] :- inf[., 2])) <= sqrt(epsilon(1)) * 10)
    bres = J(biters, k, .)
    if (simple_duplicate) {
        bres_col = csdid__bootstrap_auto(inf[., 1], biters, dist, rng_state, use_bmisc, cband) / sqrt(n)
        bres[., 1] = bres_col
        bsigma[1] = csdid__bootstrap_sigma(bres_col, iqr_norm)
        if (bsigma[1] < .) seboot[1] = bsigma[1] / sqrt(n)
        bres[., k] = bres[., 1]
        bsigma[k] = bsigma[1]
        seboot[k] = seboot[1]
    }
    else if (!use_bmisc & dist == "rademacher" & !cband & n * biters <= 20000000) {
        bres = csdid__native_rboot_indep(inf, biters) / sqrt(n)
        for (j = 1; j <= k; j++) {
            bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
            if (bsigma[j] < .) seboot[j] = bsigma[j] / sqrt(n)
        }
    }
    else if (use_bmisc & dist == "rademacher" & cband) {
        if (n * biters * k_effects <= 250000000) {
            bres[., 1..k_effects] = csdid__bmisc_boot_dense_indep(inf[., 1..k_effects], biters, rng_state) / sqrt(n)
            for (j = 1; j <= k_effects; j++) {
                bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
                if (bsigma[j] < .) seboot[j] = bsigma[j] / sqrt(n)
            }
        }
        else {
            for (j = 1; j <= k_effects; j++) {
                if (n * biters <= 60000000) {
                    bres_col = csdid__bmisc_bootstrap_dense(inf[., j], biters, rng_state) / sqrt(n)
                }
                else {
                    bres_col = csdid__bmisc_bootstrap_auto(inf[., j], biters, rng_state) / sqrt(n)
                }
                bres[., j] = bres_col
                bsigma[j] = csdid__bootstrap_sigma(bres_col, iqr_norm)
                if (bsigma[j] < .) seboot[j] = bsigma[j] / sqrt(n)
            }
        }
        bres_cband = csdid__bmisc_bootstrap_auto(inf[., 1..k_effects], biters, rng_state) / sqrt(n)
        bsigma_cband = J(k_effects, 1, .)
        for (j = 1; j <= k_effects; j++) {
            bsigma_cband[j] = csdid__bootstrap_sigma(bres_cband[., j], iqr_norm)
        }
        crit = csdid__bootstrap_cband_crit(bres_cband, bsigma_cband, alp, pointcrit)
        if (n * biters <= 60000000) {
            bres_col = csdid__bmisc_bootstrap_dense(inf[., k], biters, rng_state) / sqrt(n)
        }
        else {
            bres_col = csdid__bmisc_bootstrap_auto(inf[., k], biters, rng_state) / sqrt(n)
        }
        bres[., k] = bres_col
        bsigma[k] = csdid__bootstrap_sigma(bres_col, iqr_norm)
        if (bsigma[k] < .) seboot[k] = bsigma[k] / sqrt(n)
    }
    else if (use_bmisc & dist == "rademacher" & !cband & rows(inf) * biters * cols(inf) <= 10000000) {
        bres = csdid__bmisc_boot_dense_indep(inf, biters, rng_state) / sqrt(n)
        for (j = 1; j <= k; j++) {
            bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
            if (bsigma[j] < .) seboot[j] = bsigma[j] / sqrt(n)
        }
    }
    else {
        for (j = 1; j <= k_effects; j++) {
            bres_col = csdid__bootstrap_auto(inf[., j], biters, dist, rng_state, use_bmisc, cband) / sqrt(n)
            bres[., j] = bres_col
            bsigma[j] = csdid__bootstrap_sigma(bres_col, iqr_norm)
            if (bsigma[j] < .) seboot[j] = bsigma[j] / sqrt(n)
        }
        if (cband) {
            bres_cband = csdid__bootstrap_auto(inf[., 1..k_effects], biters, dist, rng_state, use_bmisc, cband) / sqrt(n)
            bsigma_cband = J(k_effects, 1, .)
            for (j = 1; j <= k_effects; j++) {
                bsigma_cband[j] = csdid__bootstrap_sigma(bres_cband[., j], iqr_norm)
            }
            crit = csdid__bootstrap_cband_crit(bres_cband, bsigma_cband, alp, pointcrit)
        }
        bres_col = csdid__bootstrap_auto(inf[., k], biters, dist, rng_state, use_bmisc, cband) / sqrt(n)
        bres[., k] = bres_col
        bsigma[k] = csdid__bootstrap_sigma(bres_col, iqr_norm)
        if (bsigma[k] < .) seboot[k] = bsigma[k] / sqrt(n)
    }
    csdid__agg_boot_profile_add(2, phase_t0, n * biters * k)

    phase_t0 = csdid__profile_start()
    for (j = 1; j <= k_effects; j++) {
        if (seboot[j] < .) agg[j, 3] = seboot[j]
        if (seboot[k] < .) agg[j, 5] = seboot[k]
    }

    bootout = J(k_effects, 10, .)
    for (j = 1; j <= k_effects; j++) {
        bootout[j, .] = (
            agg[j, 1], agg[j, 2], seboot[j],
            crit,
            agg[j, 2] - crit * seboot[j],
            agg[j, 2] + crit * seboot[j],
            pointcrit,
            agg[j, 2] - pointcrit * seboot[j],
            agg[j, 2] + pointcrit * seboot[j],
            seboot[k]
        )
    }

    st_matrix(aggname, agg)
    st_matrix(bootname, bootout)
    st_matrix(drawsname, bres)
    if (use_bmisc) st_matrix(statename, rng_state)
    st_numscalar(critname, crit)
    st_numscalar(pointcritname, pointcrit)
    csdid__agg_boot_profile_add(3, phase_t0, biters * k)
}

void csdid_bootstrap_aggte_cluster(
    string scalar aggname,
    string scalar ifname,
    string scalar clustervecname,
    real scalar biters,
    real scalar alp,
    real scalar cband,
    string scalar dist,
    string scalar statename,
    string scalar bootname,
    string scalar drawsname,
    string scalar critname,
    string scalar pointcritname)
{
    external real matrix CSDID_LAST_CLUSTER_VEC
    real matrix agg, inf, sc, bres, bres_col, bres_cband, bootout
    real rowvector rng_state
    real colvector cluster_vec, bsigma, bsigma_cband, seboot
    real scalar n, nc, k_effects, k, j, iqr_norm, pointcrit, crit, use_bmisc, simple_duplicate, phase_t0

    csdid__agg_boot_profile_reset()
    phase_t0 = csdid__profile_start()
    agg = st_matrix(aggname)
    inf = st_matrix(ifname)
    if (clustervecname != "") {
        cluster_vec = st_matrix(clustervecname)
    }
    else {
        cluster_vec = CSDID_LAST_CLUSTER_VEC
    }
    rng_state = J(1, 625, .)
    use_bmisc = (statename != "")
    if (use_bmisc) {
        rng_state = st_matrix(statename)
        if (cols(rng_state) != 625) {
            errprintf("the bootstrap random-number state is invalid; re-run csdid, specifying rseed() if you need a reproducible draw\n")
            _error(498)
        }
    }
    n = rows(inf)
    k_effects = rows(agg)
    k = cols(inf)
    if (n == 0 | k_effects == 0 | k != k_effects + 1) {
        errprintf("stored aggregate influence functions do not match aggregation results\n")
        _error(498)
    }
    if (rows(cluster_vec) != n | sum(cluster_vec :>= .) > 0) {
        errprintf("cluster() could not be aligned with aggregate influence functions\n")
        _error(498)
    }
    if (biters < 1) {
        errprintf("wboot() reps() must be a positive integer\n")
        _error(198)
    }

    sc = csdid__cluster_sums(cluster_vec, inf)
    nc = rows(sc)
    if (nc == 0) {
        errprintf("cluster() has no clusters in the estimation sample\n")
        _error(498)
    }

    iqr_norm = invnormal(.75) - invnormal(.25)
    bsigma = J(k, 1, .)
    seboot = J(k, 1, .)
    pointcrit = invnormal(1 - alp / 2)
    crit = pointcrit
    csdid__agg_boot_profile_add(1, phase_t0, nc * k)

    phase_t0 = csdid__profile_start()
    simple_duplicate = (k_effects == 1 & k == 2 & max(abs(sc[., 1] :- sc[., 2])) <= sqrt(epsilon(1)) * 10)
    bres = J(biters, k, .)
    if (!simple_duplicate & !use_bmisc & dist == "rademacher" & !cband & nc * biters <= 20000000) {
        bres = csdid__native_rboot_indep(sc, biters) / sqrt(nc)
        for (j = 1; j <= k; j++) {
            bsigma[j] = csdid__bootstrap_sigma(bres[., j], iqr_norm)
            if (bsigma[j] < .) seboot[j] = bsigma[j] * sqrt(nc) / n
        }
    }
    else {
        for (j = 1; j <= k_effects; j++) {
            bres_col = csdid__bootstrap_auto(sc[., j], biters, dist, rng_state, use_bmisc, cband) / sqrt(nc)
            bres[., j] = bres_col
            bsigma[j] = csdid__bootstrap_sigma(bres_col, iqr_norm)
            if (bsigma[j] < .) seboot[j] = bsigma[j] * sqrt(nc) / n
        }
        if (simple_duplicate) {
            bres[., k] = bres[., 1]
            bsigma[k] = bsigma[1]
            seboot[k] = seboot[1]
        }
        else {
            if (cband) {
                bres_cband = csdid__bootstrap_auto(sc[., 1..k_effects], biters, dist, rng_state, use_bmisc, cband) / sqrt(nc)
                bsigma_cband = J(k_effects, 1, .)
                for (j = 1; j <= k_effects; j++) {
                    bsigma_cband[j] = csdid__bootstrap_sigma(bres_cband[., j], iqr_norm)
                }
                crit = csdid__bootstrap_cband_crit(bres_cband, bsigma_cband, alp, pointcrit)
            }
            bres_col = csdid__bootstrap_auto(sc[., k], biters, dist, rng_state, use_bmisc, cband) / sqrt(nc)
            bres[., k] = bres_col
            bsigma[k] = csdid__bootstrap_sigma(bres_col, iqr_norm)
            if (bsigma[k] < .) seboot[k] = bsigma[k] * sqrt(nc) / n
        }
    }
    csdid__agg_boot_profile_add(2, phase_t0, nc * biters * k)

    phase_t0 = csdid__profile_start()
    for (j = 1; j <= k_effects; j++) {
        if (seboot[j] < .) agg[j, 3] = seboot[j]
        if (seboot[k] < .) agg[j, 5] = seboot[k]
    }

    bootout = J(k_effects, 10, .)
    for (j = 1; j <= k_effects; j++) {
        bootout[j, .] = (
            agg[j, 1], agg[j, 2], seboot[j],
            crit,
            agg[j, 2] - crit * seboot[j],
            agg[j, 2] + crit * seboot[j],
            pointcrit,
            agg[j, 2] - pointcrit * seboot[j],
            agg[j, 2] + pointcrit * seboot[j],
            seboot[k]
        )
    }

    st_matrix(aggname, agg)
    st_matrix(bootname, bootout)
    st_matrix(drawsname, bres)
    if (use_bmisc) st_matrix(statename, rng_state)
    st_numscalar(critname, crit)
    st_numscalar(pointcritname, pointcrit)
    csdid__agg_boot_profile_add(3, phase_t0, biters * k)
}

void csdid__rescale_v_to_se(real matrix V, real colvector se)
{
    real scalar j, l, sj, sl, dj, dl, tol

    tol = sqrt(epsilon(1)) * 10
    for (j = 1; j <= rows(V); j++) {
        if (se[j] >= .) {
            V[j, .] = J(1, cols(V), 0)
            V[., j] = J(rows(V), 1, 0)
            continue
        }
        if (V[j, j] < . & V[j, j] > tol) {
            sj = se[j] / sqrt(V[j, j])
            V[j, .] = V[j, .] :* sj
            V[., j] = V[., j] :* sj
        }
        else {
            V[j, .] = J(1, cols(V), 0)
            V[., j] = J(rows(V), 1, 0)
            V[j, j] = se[j]^2
        }
    }
    for (j = 1; j <= rows(V); j++) {
        for (l = 1; l <= cols(V); l++) {
            if (V[j, l] >= .) V[j, l] = 0
        }
    }
}

void csdid_post_attgt_v(
    string scalar attname,
    string scalar ifname,
    string scalar clustervecname,
    string scalar drawsname,
    real scalar use_boot,
    string scalar vname)
{
    external real matrix CSDID_LAST_INFFUNC, CSDID_LAST_CLUSTER_VEC
    real matrix att, inf, sc, V, draws, centered
    real rowvector keep
    real colvector cluster_vec, se
    real scalar n, nc, scale

    att = st_matrix(attname)
    keep = selectindex((att[., 4] :< .) :& (abs(att[., 3] :+ 1) :>= 1e-8))'
    if (cols(keep) == 0) {
        st_matrix(vname, J(0, 0, .))
        return
    }

    if (ifname != "") {
        inf = st_matrix(ifname)
    }
    else {
        inf = CSDID_LAST_INFFUNC
    }
    if (rows(inf) == 0 | cols(inf) != rows(att)) {
        st_matrix(vname, diag((att[keep, 5]:^2)'))
        return
    }
    n = rows(inf)

    cluster_vec = J(0, 1, .)
    if (clustervecname != "") {
        cluster_vec = st_matrix(clustervecname)
    }
    else if (rows(CSDID_LAST_CLUSTER_VEC) == n & sum(CSDID_LAST_CLUSTER_VEC :>= .) == 0) {
        cluster_vec = CSDID_LAST_CLUSTER_VEC
    }

    V = J(cols(keep), cols(keep), .)
    if (use_boot != 0 & drawsname != "") {
        draws = st_matrix(drawsname)
        if (rows(draws) > 1 & cols(draws) == rows(att)) {
            centered = draws[., keep]
            centered = centered :- J(rows(centered), 1, 1) * (colsum(centered) / rows(centered))
            V = quadcross(centered, centered) / (rows(centered) - 1)
            if (rows(cluster_vec) == n & sum(cluster_vec :>= .) == 0) {
                nc = rows(uniqrows(cluster_vec))
                scale = nc / (n^2)
            }
            else {
                scale = 1 / n
            }
            V = V * scale
        }
    }

    if (sum(V :< .) == 0) {
        if (rows(cluster_vec) == n & sum(cluster_vec :>= .) == 0) {
            sc = csdid__cluster_sums(cluster_vec, inf)
            V = quadcross(sc[., keep], sc[., keep]) / (n^2)
        }
        else {
            V = quadcross(inf[., keep], inf[., keep]) / (n^2)
        }
    }

    se = att[keep, 5]
    csdid__rescale_v_to_se(V, se)
    st_matrix(vname, V)
}

void csdid_post_mapped_v(
    string scalar ifname,
    string scalar clustervecname,
    string scalar drawsname,
    real scalar use_boot,
    string scalar mapname,
    string scalar vname)
{
    external real matrix CSDID_LAST_CLUSTER_VEC, CSDID_LAST_AGG_INFFUNC
    real matrix inf, sc, V, Vvalid, oldV, draws, centered
    real rowvector map, valid_pos, cols_keep
    real colvector cluster_vec, se
    real scalar n, nc, scale, j

    if (ifname == "") {
        // Lean aggregation posts no e(agg_inffunc): an n_units-row matrix
        // never crosses into Stata's classic-matrix layer, whose cost is
        // quadratic in the longest dimension (see csdid_aggte). The caller
        // has already token-validated the cache against the active results,
        // so the posted covariances are computed from the cached copy.
        inf = CSDID_LAST_AGG_INFFUNC
    }
    else {
        inf = st_matrix(ifname)
    }
    oldV = st_matrix(vname)
    map = st_matrix(mapname)
    if (rows(map) > 1) map = map'
    V = J(cols(map), cols(map), 0)
    if (cols(map) == 0 | rows(inf) == 0 | cols(inf) == 0) {
        st_matrix(vname, V)
        return
    }
    valid_pos = selectindex((map :>= 1) :& (map :<= cols(inf)))
    if (cols(valid_pos) == 0) {
        st_matrix(vname, V)
        return
    }
    cols_keep = map[valid_pos]
    n = rows(inf)

    cluster_vec = J(0, 1, .)
    if (clustervecname != "") {
        cluster_vec = st_matrix(clustervecname)
    }
    else if (rows(CSDID_LAST_CLUSTER_VEC) == n & sum(CSDID_LAST_CLUSTER_VEC :>= .) == 0) {
        cluster_vec = CSDID_LAST_CLUSTER_VEC
    }

    Vvalid = J(cols(valid_pos), cols(valid_pos), .)
    if (use_boot != 0 & drawsname != "") {
        draws = st_matrix(drawsname)
        if (rows(draws) > 1 & cols(draws) == cols(inf)) {
            centered = draws[., cols_keep]
            centered = centered :- J(rows(centered), 1, 1) * (colsum(centered) / rows(centered))
            Vvalid = quadcross(centered, centered) / (rows(centered) - 1)
            if (rows(cluster_vec) == n & sum(cluster_vec :>= .) == 0) {
                nc = rows(uniqrows(cluster_vec))
                scale = nc / (n^2)
            }
            else {
                scale = 1 / n
            }
            Vvalid = Vvalid * scale
        }
    }

    if (sum(Vvalid :< .) == 0) {
        if (rows(cluster_vec) == n & sum(cluster_vec :>= .) == 0) {
            sc = csdid__cluster_sums(cluster_vec, inf)
            Vvalid = quadcross(sc[., cols_keep], sc[., cols_keep]) / (n^2)
        }
        else {
            Vvalid = quadcross(inf[., cols_keep], inf[., cols_keep]) / (n^2)
        }
    }

    for (j = 1; j <= cols(valid_pos); j++) {
        V[valid_pos[j], valid_pos] = Vvalid[j, .]
    }

    se = sqrt(diagonal(oldV))
    csdid__rescale_v_to_se(V, se)
    st_matrix(vname, V)
}

// ---------------------------------------------------------------------------
// RIF artifact export.
//
// Fills the CURRENT (empty, preset-obs) dataset with the saved-RIF columns
// directly from the Mata cache: id/group/weight from the unit map and one
// rif# column per ATT(g,t) cell. The old path routed the same numbers
// through `matrix IF = e(inffunc)' plus svmat - three crossings of Stata's
// classic-matrix layer, each quadratic in n_units (see csdid_aggte).
// st_store of the cached matrix is one linear copy. The caller has already
// token-validated the cache against the active e() results and set the
// observation count to rows(CSDID_LAST_INFFUNC).
// ---------------------------------------------------------------------------
void csdid_rif_export()
{
    external real matrix CSDID_LAST_INFFUNC, CSDID_LAST_UNIT_GROUP
    real matrix inf, ug
    real scalar n, k, j
    string rowvector rifnames
    real rowvector idx

    // Reading a Stata matrix INTO Mata is linear (measured: 0.00s at 50k
    // rows); only writes and Stata-side copies pay the quadratic cost. So
    // the export reads whichever source holds the influence functions -
    // e(inffunc) under full storage, the cache under lean - and never
    // creates another Stata matrix.
    inf = st_matrix("e(inffunc)")
    if (rows(inf) > 0) {
        ug = st_matrix("e(unit_group)")
    }
    else {
        inf = CSDID_LAST_INFFUNC
        ug = CSDID_LAST_UNIT_GROUP
    }
    n = rows(inf)
    k = cols(inf)
    if (k != rows(st_matrix("e(attgt)"))) {
        errprintf("stored influence functions do not match ATT(g,t) results\n")
        _error(498)
    }
    if (st_nobs() != n) {
        errprintf("csdid_rif_export: observation count does not match the influence functions\n")
        _error(498)
    }
    // schema: id group weight, exactly as the svmat path produced. The unit
    // map may carry a 4th (bootstrap draw-order) column; it is internal and
    // stays out of the artifact (F-001/F-022).
    idx = st_addvar("double", ("id", "group", "weight"))
    st_store(., idx, ug[., 1..3])
    rifnames = J(1, k, "")
    for (j = 1; j <= k; j++) rifnames[j] = "rif" + strofreal(j)
    idx = st_addvar("double", rifnames)
    st_store(., idx, inf)
}

// ---------------------------------------------------------------------------
// Global initialisation.
//
// These globals used to be assigned by bare top-level statements here, which
// only run when this file is compiled with `do'. `mata mlib add *()' stores
// FUNCTIONS ONLY, so a build that loads the engine from the precompiled
// lcsdid.mlib never executed them: every global stayed undeclared, and the
// first `external' declaration created it with a MISSING value. Missing is
// truthy in Mata, so csdid__rng_tables_init()'s `if (CSDID_RNG_TABLES_READY)
// return' guard returned immediately without building the lookup tables, and
// the first indexed read of the still-0x0 CSDID_XOR8F aborted with
// r(3301) "subscript invalid" (witness: tests/stata/test-f049.do run against
// build/, which puts the library on the adopath).
//
// Holding the assignments in a function makes them reachable from both load
// paths with one source of truth. The guard is on an explicit sentinel rather
// than on any of the payload globals, and compares to 1 so that the
// auto-created missing value falls through to initialisation.
// ---------------------------------------------------------------------------
// Panel-shape flags for the ado-side structural checks (EUX-001).
// Answers all four questions from ONE sort instead of three or four separate
// uniqrows() calls. uniqrows() sorts, so the previous formulation paid 3-4
// full sorts of an n-row matrix on EVERY estimation purely to be able to
// phrase a nice refusal on malformed data; on a 50,000-row panel that
// dominated the command's non-computational cost. Returns a 1x4 row vector:
//   [1] number of distinct ivar() values
//   [2] 1 if gvar() varies within a unit
//   [3] 1 if cluster() varies within a unit (0 when no cluster)
//   [4] 1 if some unit repeats a period
// Reads the data and mutates nothing, so the caller's sort order - which the
// fast-path detector keys off - is untouched.
void csdid__panel_shape_flags(string scalar idname, string scalar timename,
                              string scalar gname,  string scalar clname,
                              string scalar tousename, string scalar outname)
{
    real matrix X
    real colvector same
    real scalar n, hascl
    real rowvector out

    hascl = (clname != "")
    if (hascl) X = st_data(., (idname, timename, gname, clname), tousename)
    else       X = st_data(., (idname, timename, gname), tousename)

    n = rows(X)
    out = J(1, 4, 0)
    if (n == 0) {
        st_matrix(outname, out)
        return
    }
    if (n == 1) {
        out[1] = 1
        st_matrix(outname, out)
        return
    }

    X = X[order(X, (1, 2)), .]
    same = (X[2::n, 1] :== X[1::n - 1, 1])
    out[1] = 1 + sum(!same)
    out[2] = any(same :& (X[2::n, 3] :!= X[1::n - 1, 3]))
    if (hascl) out[3] = any(same :& (X[2::n, 4] :!= X[1::n - 1, 4]))
    out[4] = any(same :& (X[2::n, 2] :== X[1::n - 1, 2]))
    st_matrix(outname, out)
}

// Rows per distinct value of a variable, in one pass (F-014 group sizing).
// Replaces `levelsof' plus one `count if' per level - i.e. a sort plus one
// full data pass per group - with a single sorted scan. Returns a k x 2
// matrix of (value, rows). Reads only; the caller's sort order is untouched.
void csdid__value_counts(string scalar varname, string scalar tousename,
                         string scalar outname)
{
    real colvector v, same
    real matrix out
    real scalar n, k, i, j

    v = st_data(., varname, tousename)
    n = rows(v)
    if (n == 0) {
        st_matrix(outname, J(0, 2, .))
        return
    }
    v = sort(v, 1)
    same = J(0, 1, .)
    if (n > 1) same = (v[2::n] :== v[1::n - 1])
    k = 1 + (n > 1 ? sum(!same) : 0)
    out = J(k, 2, 0)
    j = 1
    out[1, 1] = v[1]
    out[1, 2] = 1
    for (i = 2; i <= n; i++) {
        if (v[i] != v[i - 1]) {
            j++
            out[j, 1] = v[i]
            out[j, 2] = 1
        }
        else out[j, 2] = out[j, 2] + 1
    }
    st_matrix(outname, out)
}

void csdid__globals_init()
{
    external real matrix CSDID_LAST_ATTGT, CSDID_LAST_INFFUNC, CSDID_LAST_GROUP_PROB
    external real matrix CSDID_LAST_UNIT_GROUP, CSDID_LAST_UNIT_ROW, CSDID_LAST_ROW_UNIT
    external real matrix CSDID_LAST_CLUSTER_VEC, CSDID_LAST_AGG_INFFUNC
    external real scalar CSDID_LAST_TOKEN, CSDID_TOKEN_COUNTER, CSDID_LAST_AGG_TOKEN
    external real matrix CSDID_PROFILE, CSDID_BOOT_PROFILE, CSDID_BOOT_KERNEL_PROFILE
    external real matrix CSDID_AGG_BOOT_PROFILE
    external real scalar CSDID_BOOT_PLUGIN_PROFILE_START
    external real matrix CSDID_OVL_X
    external real colvector CSDID_OVL_D
    external real scalar CSDID_OVL_STATUS
    external real matrix CSDID_AND8, CSDID_XOR8, CSDID_RBITS8, CSDID_MT_XOR_MAG
    external real colvector CSDID_AND8F, CSDID_XOR8F, CSDID_MT_TEMPER_LO, CSDID_MT_TEMPER_HI
    external real scalar CSDID_RNG_TABLES_READY
    external real scalar CSDID_GLOBALS_READY

    if (CSDID_GLOBALS_READY == 1) return

    CSDID_LAST_ATTGT = J(0, 0, .)
    CSDID_LAST_INFFUNC = J(0, 0, .)
    CSDID_LAST_GROUP_PROB = J(0, 0, .)
    CSDID_LAST_UNIT_GROUP = J(0, 0, .)
    CSDID_LAST_UNIT_ROW = J(0, 0, .)
    CSDID_LAST_ROW_UNIT = J(0, 0, .)
    CSDID_LAST_CLUSTER_VEC = J(0, 0, .)
    CSDID_LAST_AGG_INFFUNC = J(0, 0, .)
    CSDID_LAST_TOKEN = 0
    CSDID_TOKEN_COUNTER = 0
    CSDID_LAST_AGG_TOKEN = 0
    CSDID_PROFILE = J(8, 3, 0)
    CSDID_BOOT_PROFILE = J(6, 3, 0)
    CSDID_BOOT_KERNEL_PROFILE = J(5, 3, 0)
    CSDID_AGG_BOOT_PROFILE = J(3, 3, 0)
    CSDID_BOOT_PLUGIN_PROFILE_START = 0
    CSDID_AND8 = J(0, 0, .)
    CSDID_XOR8 = J(0, 0, .)
    CSDID_AND8F = J(0, 1, .)
    CSDID_XOR8F = J(0, 1, .)
    CSDID_RBITS8 = J(0, 0, .)
    CSDID_MT_TEMPER_LO = J(0, 1, .)
    CSDID_MT_TEMPER_HI = J(0, 1, .)
    CSDID_MT_XOR_MAG = J(0, 0, .)
    CSDID_RNG_TABLES_READY = 0
    CSDID_OVL_X = J(0, 0, .)
    CSDID_OVL_D = J(0, 1, .)
    CSDID_OVL_STATUS = .
    CSDID_GLOBALS_READY = 1
}

csdid__globals_init()

end
