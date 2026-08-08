* Run from the bench/ folder of the replication package. Not run on its
* own: the drivers load it with -do-.  It defines bench_dgp, bench_dgp_stress and bench_structure.
* ---------------------------------------------------------------------------
* Staggered-adoption DGP for the cross-package comparison.
*
* Staggered only, by design: absorbing binary treatment, no anticipation, one
* adoption date per unit. That is the setting where Callaway-Sant'Anna,
* Wooldridge ETWFE, Borusyak-Jaravel-Spiess imputation and LP-DiD all target
* comparable objects, so an agreement check between them is meaningful rather
* than a category error.
*
* Four designs, switched by `design':
*   homogeneous     constant effect, no covariates. Every estimator should agree
*                   on post-treatment event-study coefficients. This is the
*                   validation cell -- if packages disagree here, something is
*                   configured wrong, not estimated differently.
*   dynamic         effects grow with exposure, no covariates. Still common
*                   ground: all four target the same dynamic path.
*   condpt          conditional parallel trends. Trends depend on a covariate,
*                   so UNCONDITIONAL estimators are biased by construction and
*                   the covariate handling is what is being tested.
*   hetero          treatment effects vary with a covariate AND trends depend on
*                   it. This separates estimators that model heterogeneity from
*                   those that assume it away.
*
* Deterministic given seed(). Nothing here favours any package: the covariate
* enters trends and effects through plain linear terms every estimator can in
* principle capture.
* ---------------------------------------------------------------------------
capture program drop bench_dgp
program define bench_dgp
    syntax , DESIGN(string) N(integer) T(integer) SEED(integer) [COHORTS(integer 4)]

    clear
    set seed `seed'
    quietly set obs `n'
    generate long id = _n

    * staggered adoption: cohorts spread over the middle of the panel, plus a
    * never-treated group. gvar = 0 is never treated.
    quietly generate double u = runiform()
    quietly generate int gvar = 0
    local first_g = floor(`t' / 3) + 1
    forvalues k = 1/`cohorts' {
        local g = `first_g' + `k' - 1
        if `g' <= `t' {
            quietly replace gvar = `g' if u > (`k' - 1) / (`cohorts' + 1) & u <= `k' / (`cohorts' + 1)
        }
    }
    drop u

    * unit covariate; drives trends and/or effect size in the covariate designs
    quietly generate double x = rnormal()
    quietly generate double alpha = rnormal()

    quietly expand `t'
    quietly bysort id: generate int time = _n
    quietly bysort id: generate double eps = rnormal()

    * baseline outcome, then design-specific trend and effect
    quietly generate double y = alpha + 0.3 * time + eps

    if "`design'" == "condpt" | "`design'" == "hetero" {
        * trends depend on x: unconditional parallel trends FAILS by design
        quietly replace y = y + 0.25 * x * time
    }

    quietly generate int e = cond(gvar == 0, ., time - gvar)
    quietly generate byte treated = (gvar > 0 & time >= gvar)

    if "`design'" == "homogeneous" {
        quietly replace y = y + 1.0 if treated
    }
    else if "`design'" == "dynamic" {
        quietly replace y = y + (0.5 + 0.25 * e) if treated
    }
    else if "`design'" == "condpt" {
        quietly replace y = y + 1.0 if treated
    }
    else if "`design'" == "hetero" {
        * effect size varies with the same covariate that drives trends
        quietly replace y = y + (0.5 + 0.6 * x + 0.2 * e) if treated
    }
    else if "`design'" == "hard" {
        * The case the packages should actually diverge on: conditional parallel
        * trends AND effects that vary with the covariate, with exposure, and
        * ACROSS COHORTS. An estimator that averages cohorts under an implicit
        * homogeneity assumption targets a different number here, and that is
        * the point -- not a defect in it.
        quietly summarize gvar if gvar > 0, meanonly
        local gbar = r(mean)
        quietly generate double te = 0.30 + 0.60 * x + 0.15 * e + 0.25 * (gvar - `gbar')
        quietly replace y = y + te if treated
    }
    else {
        display as error "unknown design: `design'"
        exit 198
    }

    * Sample truth for this draw: the average true effect among treated units at
    * each horizon. Computed from the DGP rather than derived analytically, so
    * it stays correct whatever the realised cohort composition turns out to be
    * -- which matters precisely because later cohorts drop out at long
    * horizons and shift the mix.
    capture confirm variable te
    if _rc {
        quietly generate double te = .
        quietly replace te = y - (alpha + 0.3 * time + eps) if treated
        if "`design'" == "condpt" | "`design'" == "hetero" {
            quietly replace te = te - 0.25 * x * time if treated
        }
    }

    * cluster identifier, coarser than the unit: every package is given the
    * same clustering choice so inference is compared like for like.
    quietly generate int cl = mod(id, 50) + 1

    * Guard: in Stata . * 0 = . , so an effect built from `e' (missing for
    * never-treated units) can silently make their OUTCOME missing, leaving a
    * dataset with no usable never-treated controls that every package would
    * quietly estimate around. Checked on every draw, never assumed.
    quietly count if missing(y)
    if r(N) > 0 {
        display as error "bench_dgp: `=r(N)' observations have a missing outcome; the design is broken"
        exit 459
    }

    keep id time gvar y x e treated cl te
    order id time gvar y x e treated cl te
    quietly compress
end

* ---------------------------------------------------------------------------
* Stress configuration: many units, many periods, many cohorts. Everything the
* small config has, at a scale where implementation differences show up --
* the number of 2x2 cells grows with cohorts x periods, so this is where an
* estimator that scales badly stops being competitive.
* ---------------------------------------------------------------------------
capture program drop bench_dgp_stress
program define bench_dgp_stress
    syntax , DESIGN(string) SEED(integer) [N(integer 5000) T(integer 20) COHORTS(integer 12)]
    bench_dgp, design(`design') n(`n') t(`t') seed(`seed') cohorts(`cohorts')
end

* ---------------------------------------------------------------------------
* Panel structure. The DGP is identical in all three; only which rows survive,
* and whether a unit can be followed, differs.
*
*   balanced    every unit in every period
*   unbalanced  ~15% of unit-periods deleted, spread over units and periods
*   rcs         every observation is its own unit. Cohort membership is still
*               observed per row (it is a group-level attribute such as a
*               state's adoption year), which is what makes ATT(g,t)
*               identified without following anyone over time.
* ---------------------------------------------------------------------------
capture program drop bench_structure
program define bench_structure
    syntax , STRUCTURE(string) [SEED(integer 1)]

    if "`structure'" == "balanced" exit

    if "`structure'" == "unbalanced" {
        set seed `=`seed' + 77'
        quietly generate double drop_u = runiform()
        quietly drop if drop_u < 0.15
        drop drop_u
        exit
    }

    if "`structure'" == "rcs" {
        * one observation per unit: nobody is followed, so no within-unit
        * differencing is available to any estimator.
        quietly replace id = _n
        exit
    }

    display as error "unknown structure: `structure'"
    exit 198
end