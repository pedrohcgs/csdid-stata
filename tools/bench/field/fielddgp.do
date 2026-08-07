*-----------------------------------------------------------------------------
*      fielddgp.do -- data generating processes for the field comparisons
*-----------------------------------------------------------------------------
* One definitions file, the simdgp.do pattern: every DGP used by the option-
* arm and separating-design drivers below, defined once. Loaded by each
* driver with -do "fielddgp.do"-. Programs set their own seed, so results
* depend only on the seed argument, never on load order.
*   dgp_ct      covariate trend effects vary with CALENDAR time (ctvar)
*   dgp_ch      cohort-specific treatment-effect heterogeneity in X
*   dgp_master  both mechanisms at once; target ES(e) = 2.516667 + 0.633333e
*   dgp_snt     small (5 percent) never-treated share
*   dgp_ym      period-varying missingness as row deletion or missing Y
*   dgp_break   designs B (nonlinear-in-X trend) and C (unequal cohorts)
*   mkpanel     balanced timing panel for the option-cost benchmarks
*   mkwtr       population-share wtr() weights for did_imputation
* Run from the bench/ folder of the replication package.
*-----------------------------------------------------------------------------

capture program drop dgp_ct
program define dgp_ct
    syntax , N(integer) SEED(integer)
    clear
    set seed `seed'
    quietly set obs `n'
    generate long id = _n
    quietly generate int gvar = cond(mod(_n,4)==0, 0, cond(mod(_n,4)==1, 3, ///
        cond(mod(_n,4)==2, 4, 5)))
    quietly generate double mu = rnormal()
    quietly generate byte   x1 = runiform() < cond(gvar==0, .35, .15 + .10*gvar)
    quietly generate double x2 = rnormal() + cond(gvar==0, -0.5, 0.4*(gvar-4))
    quietly expand 7
    quietly bysort id: generate int time = _n
    quietly generate double y = mu + 0.30*time + rnormal()
    quietly replace y = y + 0.4*x1 + 0.6*x2
    quietly replace y = y + x1*(2.0*sin(1.6*time)) + x2*(2.2*cos(1.3*time))
    quietly generate double tau = (gvar-2) + 0.5*(time-gvar) if gvar>0 & time>=gvar
    quietly replace y = y + tau if gvar>0 & time>=gvar
    quietly generate byte treated = (gvar>0 & time>=gvar)
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar==0
    quietly drop mu
end

capture program drop dgp_ch
program define dgp_ch
    syntax , N(integer) SEED(integer)
    clear
    set seed `seed'
    quietly set obs `n'
    generate long id = _n
    quietly generate int gvar = cond(mod(_n,4)==0, 0, cond(mod(_n,4)==1, 3, ///
        cond(mod(_n,4)==2, 4, 5)))
    quietly generate double mu = rnormal()
    quietly generate byte   x1 = runiform() < cond(gvar==0, .35, .15 + .10*gvar)
    quietly generate double x2 = rnormal() + cond(gvar==0, -0.5, 0.4*(gvar-4))
    quietly expand 7
    quietly bysort id: generate int time = _n
    quietly generate double y = mu + 0.30*time + rnormal()
    quietly replace y = y + 0.4*x1 + 0.6*x2 + (0.35*x1 + 0.45*x2)*time
    quietly generate double ag = cond(gvar==3,0.3,cond(gvar==4,0.8,cond(gvar==5,1.5,0)))
    quietly generate double bg = cond(gvar==3,0.2,cond(gvar==4,0.6,cond(gvar==5,1.2,0)))
    quietly generate double tau = 0
    quietly replace tau = (gvar-2) + 0.5*(time-gvar) + ag*x1 + bg*x2*(time-gvar) ///
        if gvar>0 & time>=gvar
    quietly replace y = y + tau if gvar>0 & time>=gvar
    quietly generate byte treated = (gvar>0 & time>=gvar)
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar==0
    quietly drop mu ag bg
end

capture program drop dgp_master
program define dgp_master
    syntax , N(integer) SEED(integer)
    clear
    set seed `seed'
    quietly set obs `n'
    generate long id = _n
    quietly generate int gvar = cond(mod(_n,4)==0, 0, cond(mod(_n,4)==1, 3, ///
        cond(mod(_n,4)==2, 4, 5)))
    quietly generate double mu = rnormal()
    quietly generate byte   x1 = runiform() < cond(gvar==0, .35, .15 + .10*gvar)
    quietly generate double x2 = rnormal() + cond(gvar==0, -0.5, 0.4*(gvar-4))
    quietly expand 7
    quietly bysort id: generate int time = _n
    quietly generate double y = mu + 0.30*time + rnormal()
    quietly replace y = y + 0.4*x1 + 0.6*x2
    quietly replace y = y + x1*(2.0*sin(1.6*time)) + x2*(2.2*cos(1.3*time))
    quietly generate double ag = cond(gvar==3,0.3,cond(gvar==4,0.8,cond(gvar==5,1.5,0)))
    quietly generate double bg = cond(gvar==3,0.2,cond(gvar==4,0.6,cond(gvar==5,1.2,0)))
    quietly generate double tau = (gvar-2) + 0.5*(time-gvar) + ag*x1 + bg*x2*(time-gvar) ///
        if gvar>0 & time>=gvar
    quietly replace y = y + tau if gvar>0 & time>=gvar
    quietly generate byte treated = (gvar>0 & time>=gvar)
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar==0
    quietly drop mu ag bg
end

capture program drop dgp_snt
program define dgp_snt
    syntax , N(integer) SEED(integer) [NTSHARE(real 0.05)]
    clear
    set seed `seed'
    quietly set obs `n'
    generate long id = _n
    quietly generate double u = runiform()
    quietly generate int gvar = 0
    quietly replace gvar = 3 + mod(_n,3) if u >= `ntshare'
    quietly drop u
    quietly generate double mu = rnormal()
    quietly expand 7
    quietly bysort id: generate int time = _n
    quietly generate double y = mu + 0.30*time + rnormal()
    quietly replace y = y + (gvar-2) + 0.5*(time-gvar) if gvar>0 & time>=gvar
    quietly generate byte treated = (gvar>0 & time>=gvar)
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar==0
    quietly drop mu
end

capture program drop dgp_ym
program define dgp_ym
    syntax , N(integer) SEED(integer) MODE(string)
    clear
    set seed `seed'
    quietly set obs `n'
    generate long id = _n
    quietly generate int gvar = cond(mod(_n,4)==0, 0, cond(mod(_n,4)==1, 3, ///
        cond(mod(_n,4)==2, 4, 5)))
    quietly generate double mu = rnormal()
    quietly expand 7
    quietly bysort id: generate int time = _n
    quietly generate double y = mu + 0.30*time + rnormal()
    quietly replace y = y + (gvar-2) + 0.5*(time-gvar) if gvar>0 & time>=gvar
    quietly generate byte treated = (gvar>0 & time>=gvar)
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar==0
    quietly drop mu
    * period-varying missingness, identical draw either way
    quietly generate double ku = runiform()
    quietly generate double dr = .
    quietly replace dr=.05 if time==1
    quietly replace dr=.15 if time==2
    quietly replace dr=.25 if time==3
    quietly replace dr=.45 if time==4
    quietly replace dr=.55 if time==5
    quietly replace dr=.35 if time==6
    quietly replace dr=.10 if time==7
    if "`mode'"=="drop"  quietly drop if ku<dr
    if "`mode'"=="ymiss" quietly replace y = . if ku<dr
    quietly drop ku dr
end

capture program drop dgp_break
program define dgp_break
    syntax , N(integer) SEED(integer) DESIGN(string)
    clear
    set seed `seed'
    quietly set obs `n'
    generate long id = _n
    if "`design'"=="B" {
        quietly generate int gvar = cond(mod(_n,4)==0, 0, cond(mod(_n,4)==1, 3, ///
            cond(mod(_n,4)==2, 4, 5)))
        * ASYMMETRIC cohort means, common variance -> logit-linear pscore
        quietly generate double x2 = rnormal() + cond(gvar==0, -0.5, ///
            cond(gvar==3, -0.8, cond(gvar==4, 0.0, 0.2)))
    }
    else {
        * UNEQUAL cohort sizes: 50/30/20 among treated, 25% never-treated
        quietly generate double u = runiform()
        quietly generate int gvar = 0
        quietly replace gvar = 3 if u>=.25 & u<.625
        quietly replace gvar = 4 if u>=.625 & u<.85
        quietly replace gvar = 5 if u>=.85
        quietly drop u
        quietly generate double x2 = rnormal() + cond(gvar==0, -0.5, 0.4*(gvar-4))
    }
    quietly generate byte x1 = runiform() < cond(gvar==0, .35, .15 + .10*gvar)
    quietly generate double mu = rnormal()
    quietly expand 7
    quietly bysort id: generate int time = _n
    quietly generate double y = mu + 0.30*time + rnormal()
    quietly replace y = y + 0.4*x1 + 0.6*x2
    if "`design'"=="B" {
        * NONLINEAR covariate trend, common across cohorts -> conditional PT holds
        quietly replace y = y + (0.35*x1 + 0.45*x2 + 0.50*(x2^2-1))*time
        quietly generate double tau = (gvar-2) + 0.5*(time-gvar) if gvar>0 & time>=gvar
    }
    else {
        quietly replace y = y + (0.35*x1 + 0.45*x2)*time
        quietly generate double ag = cond(gvar==3,0.3,cond(gvar==4,0.8,cond(gvar==5,1.5,0)))
        quietly generate double bg = cond(gvar==3,0.2,cond(gvar==4,0.6,cond(gvar==5,1.2,0)))
        quietly generate double tau = (gvar-2) + 0.5*(time-gvar) + ag*x1 + bg*x2*(time-gvar) ///
            if gvar>0 & time>=gvar
        quietly drop ag bg
    }
    quietly replace y = y + tau if gvar>0 & time>=gvar
    quietly generate byte treated = (gvar>0 & time>=gvar)
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar==0
    quietly drop mu
end

capture program drop mkpanel
program define mkpanel
    syntax , N(integer) [T(integer 10)]
    clear
    set seed 20260731
    quietly set obs `n'
    generate long id = _n
    quietly generate int gvar = cond(mod(_n,4)==0, 0, cond(mod(_n,4)==1, 3, ///
        cond(mod(_n,4)==2, 4, 5)))
    quietly generate double mu = rnormal()
    quietly expand `t'
    quietly bysort id: generate int time = _n
    quietly generate double y = mu + 0.30*time + rnormal()
    quietly replace y = y + (gvar-2) + 0.5*(time-gvar) if gvar>0 & time>=gvar
    quietly generate byte treated = (gvar>0 & time>=gvar)
    quietly drop mu
end

capture program drop mkwtr
program define mkwtr
    quietly capture drop K w0 w1 w2 ncell
    quietly gen int K = time - gvar if gvar > 0 & time >= gvar
    forvalues h = 0/2 {
        quietly capture drop ncell
        quietly bysort gvar time: egen double ncell = total(K == `h') if K == `h'
        quietly gen double w`h' = cond(K == `h' & ncell > 0, 1/(3*ncell), 0)
        quietly replace w`h' = 0 if missing(w`h')
    }
end
