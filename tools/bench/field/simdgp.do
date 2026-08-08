* Run from the bench/ folder of the replication package. Not run on its
* own: the drivers load it with -do-.  It defines sim_dgp.
* ---------------------------------------------------------------------------
* ONE population, ONE set of target parameters, three ways the sample arrives.
*
* Y_it = mu_i + 0.3 t + tau(G_i, t) 1{t >= G_i} + eps_it
*   mu_i ~ N(0,1) iid, eps_it ~ N(0,1) iid
*   cohorts G in {0, 3, 4, 5} with EQUAL population shares 0.25 each
*   tau(g, t) = (g - 2) + 0.5 (t - g)
*
* Targets, fixed by construction and identical in every regime:
*   ATT(g, g+h) = (g-2) + 0.5 h
*   event study  theta(h) = mean over cohorts with g+h <= 7 of ATT(g, g+h)
*     h=0 -> (1+2+3)/3 = 2.0     h=1 -> (1.5+2.5+3.5)/3 = 2.5
*     h=2 -> (2+3+4)/3   = 3.0
*
* Regimes, all satisfying the stationarity condition that (G, X) does not
* depend on T -- missingness and period assignment are independent of G:
*   balanced    every unit in every period
*   unbalanced  each (i,t) kept with prob 1-delta, MCAR
*   rcs         n*T individuals, each observed in exactly ONE period, period
*               drawn independently of G. Same rows and same per-period sample
*               size as the balanced panel, so precision is comparable.
* ---------------------------------------------------------------------------
capture program drop sim_dgp
program define sim_dgp
    syntax , N(integer) SEED(integer) [T(integer 7) REGIME(string) DELTA(real 0.30) COV MISSPEC(string) ERRORS(string)]
    if "`regime'" == "" local regime "balanced"

    clear
    set seed `seed'
    if "`regime'" == "rcs" {
        * one row per individual; nobody is followed
        quietly set obs `=`n' * `t''
        generate long id = _n
        quietly generate int time = 1 + mod(_n - 1, `t')
    }
    else if "`regime'" == "rcsvar" {
        * repeated cross sections with UNEQUAL period sizes: the period each
        * individual is observed in is drawn with probabilities lambda_t that
        * vary over calendar time, independent of (G, X). Stationarity RC-1
        * holds; the equal-cross-section-size condition B.2 fails. This is
        * the repeated-cross-section counterpart of varmiss.
        quietly set obs `=`n' * `t''
        generate long id = _n
        quietly generate double up = runiform()
        * lambda proportional to (.95,.85,.75,.55,.45,.65,.90)/5.10
        quietly generate int time = 1
        quietly replace time = 2 if up >= .18627
        quietly replace time = 3 if up >= .35294
        quietly replace time = 4 if up >= .50000
        quietly replace time = 5 if up >= .60784
        quietly replace time = 6 if up >= .69608
        quietly replace time = 7 if up >= .82353
        drop up
    }
    else {
        quietly set obs `n'
        generate long id = _n
    }
    * Cohorts assigned deterministically, exactly a quarter of units each.
    * Drawing them at random re-rolls the TARGET every replication, which is
    * the one thing this study must hold fixed.
    quietly generate int gvar = cond(mod(_n, 4) == 0, 0, cond(mod(_n, 4) == 1, 3, ///
        cond(mod(_n, 4) == 2, 4, 5)))
    quietly generate double mu = rnormal()
    if "`cov'" != "" {
        * Time-INVARIANT unit covariates ("gender", "baseline earnings"),
        * drawn at the UNIT level - before any expand - and correlated with
        * the cohort: that correlation is what makes parallel trends
        * conditional rather than vacuous.
        quietly generate byte x1 = runiform() < cond(gvar == 0, .35, .15 + .10 * gvar)
        if "`misspec'" == "pscore" {
            * cohorts differ in the VARIANCE of x2: P(G|x2) depends on x2
            * squared, so a logit linear in (x1, x2) is misspecified while
            * the outcome stays linear in X - dr and reg survive, ipw not.
            * MEASURED NULL: the even-function pscore error is orthogonal to
            * the linear trend under symmetric x2, so nothing breaks here.
            * pscore2 is the design whose error loads on the trend.
            quietly generate double x2 = (0.55 + 0.22 * cond(gvar == 0, 0, gvar - 2)) * rnormal()
        }
        else if "`misspec'" == "pscore2" {
            * selection is logit-LINEAR in a latent index w (same cohort
            * mean-shifts as the clean cell, so overlap is bounded by
            * construction); the researcher observes x2 = standardized
            * exp(0.8 w). P(G|x2) is a logit in log, so a logit linear in
            * (x1, x2) is misspecified AND its error is skewed with x2 -
            * it loads on the linear trend. The outcome stays linear in the
            * OBSERVED x2, so reg/dr and every imputation rival keep a
            * correct outcome model: only ipw's one chance is the wrong one.
            * Standardized to mean 0, var 1 in population (closed form over
            * the four equal-share cohort shifts). Curvature tunable via
            * global PS2CURV; default 0.8.
            local cv = cond("$PS2CURV" == "", 0.8, real("$PS2CURV"))
            local sc = cond("$PS2SCALE" == "", 0.5, real("$PS2SCALE"))
            local m1 = 0
            local m2 = 0
            foreach mu in -0.5 -0.4 0 0.4 {
                local m1 = `m1' + exp(`cv' * `sc' * `mu' + `cv'^2 / 2) / 4
                local m2 = `m2' + exp(2 * `cv' * `sc' * `mu' + 2 * `cv'^2) / 4
            }
            local sd = sqrt(`m2' - `m1'^2)
            quietly generate double w = rnormal() + `sc' * cond(gvar == 0, -0.5, 0.4 * (gvar - 4))
            quietly generate double x2 = (exp(`cv' * w) - `m1') / `sd'
            quietly drop w
        }
        else if "`misspec'" == "pscore3" {
            * bounded-nonlinearity alternative: x2 | G is a two-normal
            * mixture whose weight varies by cohort. The cross-cohort log
            * density ratio is a smooth sigmoid in x2 - nonlinear (logit
            * linear in x2 misspecified) but FLAT in the tails, so overlap
            * is safe by construction. Monotone-in-x2 selection makes the
            * pscore error load on the linear trend. Outcome linear in x2.
            * pmix must be a VARIABLE: a local cond() on gvar evaluates the
            * first observation only and hands every cohort one mixture
            quietly generate double pmix = cond(gvar == 0, 0.75, 0.80 - 0.15 * (gvar - 3))
            quietly generate byte lowc = runiform() < pmix
            quietly generate double x2 = cond(lowc, -0.55 + 0.60 * rnormal(), 0.80 + 0.85 * rnormal())
            quietly drop lowc pmix
        }
        else {
            quietly generate double x2 = rnormal() + cond(gvar == 0, -0.5, 0.4 * (gvar - 4))
        }
    }
    if !inlist("`regime'", "rcs", "rcsvar") {
        quietly expand `t'
        quietly bysort id: generate int time = _n
    }
    if "`errors'" == "unitroot" {
        * within-unit random-walk errors: eps_t = eps_{t-1} + nu_t. This is
        * the covariance structure under which base-period differencing is
        * the efficient construction and pre-period pooling is not - the
        * mirror image of the iid case. Panel regimes only.
        quietly bysort id (time): generate double nu = rnormal()
        quietly bysort id (time): generate double epsrw = sum(nu)
        quietly generate double y = mu + 0.30 * time + epsrw
        quietly drop nu epsrw
    }
    else {
        quietly generate double y = mu + 0.30 * time + rnormal()
    }
    if "`cov'" != "" {
        * X is generated at the UNIT level, before expand, so it is
        * time-invariant within unit; this block only adds its effect on the
        * level and trend of Y(0). Treatment effects do NOT depend on X, so
        * the targets stay exactly 2.0 / 2.5 / 3.0.
        quietly replace y = y + 0.4 * x1 + 0.6 * x2 + (0.35 * x1 + 0.45 * x2) * time
        if "`misspec'" == "outcome" {
            quietly replace y = y + 0.45 * (x2^2 - 1) * time
        }
    }
    quietly replace y = y + (gvar - 2) + 0.5 * (time - gvar) if gvar > 0 & time >= gvar
    if "`regime'" == "unbalanced" {
        quietly generate double keepu = runiform()
        quietly drop if keepu < `delta'
        drop keepu
    }
    if "`regime'" == "varmiss" {
        * Period-VARYING missingness: the drop probability depends only on
        * calendar time, never on (G, X) or the potential outcomes, so the
        * stationarity condition RC-1 still holds exactly while the
        * equal-cross-section-size condition B.2 fails by construction.
        * lambda_t is what separates estimators that weight by realized
        * observation counts from estimators that weight by population
        * shares; under B.2 the two coincide and nothing can be learned.
        quietly generate double keepu = runiform()
        quietly generate double dropr = .
        quietly replace dropr = .05 if time == 1
        quietly replace dropr = .15 if time == 2
        quietly replace dropr = .25 if time == 3
        quietly replace dropr = .45 if time == 4
        quietly replace dropr = .55 if time == 5
        quietly replace dropr = .35 if time == 6
        quietly replace dropr = .10 if time == 7
        quietly drop if keepu < dropr
        drop keepu dropr
    }
    quietly generate byte treated = (gvar > 0 & time >= gvar)
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar == 0
    quietly generate int cl = mod(id, 50) + 1
    quietly drop mu
    quietly compress
    * guard: no observation may leave sim_dgp with a missing outcome
    quietly count if missing(y)
    if r(N) > 0 {
        display as error "sim_dgp: `=r(N)' missing outcomes"
        exit 459
    }
    if !inlist("`regime'", "rcs", "rcsvar") {
        quietly bysort id: generate long nobs_ = _N
        quietly summarize nobs_, meanonly
        local mx = r(max)
        drop nobs_
        if `mx' <= 1 {
            display as error "sim_dgp: panel regime produced singleton units only"
            exit 459
        }
    }
end