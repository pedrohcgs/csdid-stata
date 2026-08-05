---
title: Code appendix
---

# Code appendix

Every number in [How csdid compares](articles/csdid-against-the-field.html)
comes from one of the scripts on this page. They are reproduced in full.
Five things were changed for publication: the file paths were shortened so
that everything runs from a single folder, a two-line run header was added
at the top of each script, a handful of copy-pasted or superseded header
comments were corrected to describe what that script actually runs, one
inert block of dead code was removed from `simdgp.do`, and
`scalebench_f.sh` lost the loop that made it wait for our other benchmark
tiers to finish before starting. That loop decided *when* the script began,
never what it measured. Nothing else moved &mdash; every seed, parameter,
regime, package option and line of executed logic is what produced the
published tables.

The Version 1.82 comparison needs one thing this folder cannot carry: a
checkout of Version 1.82 itself, which `scalebench_f_cell.do` expects at
`../csdid-182` (the released commit `fdbae255`), and which requires `drdid`
1.91 or later on the adopath. That script checks for both and stops rather
than installing anything.

The protocol is the same in every arm:

- **One population.** `simdgp.do` builds it. Cohorts are assigned
  deterministically, a quarter of units each, so the target does not re-roll
  from replication to replication.
- **Targets computed by hand from the data-generating process**, never
  re-derived from a draw: ATT(g, g+h) = (g&minus;2) + 0.5h, so the
  event-study truths are exactly 2.0, 2.5 and 3.0.
- **Fixed seeds.** Replication *r* uses seed 90000 + *r* everywhere, so the
  same draw is handed to every package and the arms line up replication by
  replication. The bootstrap arm uses 70000 + *r*.
- **500 draws** per setting, 1,000 units and seven periods per draw.
- **Rival packages at their current SSC releases**, each invoked as its own
  documentation prescribes. Where a package does not claim to support a
  setting, the attempt is still made and whatever it returns is recorded,
  including nothing.
- **csdid from source**, `src/ado` and `src/mata` pushed onto the adopath,
  never an installed copy.

To run them, put the files in one folder with the csdid source tree in
`../src`, and give each driver a unit count, a replication count and an
output file.

<p class="fold-controls">
<button type="button" onclick="foldAll(true)">Expand all</button>
<button type="button" onclick="foldAll(false)">Collapse all</button>
</p>

<script>
function foldAll(open) {
  var d = document.querySelectorAll('details.code-fold');
  for (var i = 0; i < d.length; i++) { d[i].open = open; }
}
</script>

## The population and the harness

Every arm below draws from the same population and is scored against the same targets. These three files are what the drivers load.

<details class="code-fold">
<summary><code>simdgp.do</code> &mdash; the population: one DGP, one set of targets, every sampling regime and misspecification design</summary>
<pre><code>* Run from the bench/ folder of the replication package. Not run on its
* own: the drivers load it with -do-.  It defines sim_dgp.
* ---------------------------------------------------------------------------
* ONE population, ONE set of target parameters, three ways the sample arrives.
*
* Y_it = mu_i + 0.3 t + tau(G_i, t) 1{t &gt;= G_i} + eps_it
*   mu_i ~ N(0,1) iid, eps_it ~ N(0,1) iid
*   cohorts G in {0, 3, 4, 5} with EQUAL population shares 0.25 each
*   tau(g, t) = (g - 2) + 0.5 (t - g)
*
* Targets, fixed by construction and identical in every regime:
*   ATT(g, g+h) = (g-2) + 0.5 h
*   event study  theta(h) = mean over cohorts with g+h &lt;= 7 of ATT(g, g+h)
*     h=0 -&gt; (1+2+3)/3 = 2.0     h=1 -&gt; (1.5+2.5+3.5)/3 = 2.5
*     h=2 -&gt; (2+3+4)/3   = 3.0
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
        quietly replace time = 2 if up &gt;= .18627
        quietly replace time = 3 if up &gt;= .35294
        quietly replace time = 4 if up &gt;= .50000
        quietly replace time = 5 if up &gt;= .60784
        quietly replace time = 6 if up &gt;= .69608
        quietly replace time = 7 if up &gt;= .82353
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
        quietly generate byte x1 = runiform() &lt; cond(gvar == 0, .35, .15 + .10 * gvar)
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
            quietly generate byte lowc = runiform() &lt; pmix
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
    quietly replace y = y + (gvar - 2) + 0.5 * (time - gvar) if gvar &gt; 0 &amp; time &gt;= gvar
    if "`regime'" == "unbalanced" {
        quietly generate double keepu = runiform()
        quietly drop if keepu &lt; `delta'
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
        quietly drop if keepu &lt; dropr
        drop keepu dropr
    }
    quietly generate byte treated = (gvar &gt; 0 &amp; time &gt;= gvar)
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar == 0
    quietly generate int cl = mod(id, 50) + 1
    quietly drop mu
    quietly compress
    * guard: no observation may leave sim_dgp with a missing outcome
    quietly count if missing(y)
    if r(N) &gt; 0 {
        display as error "sim_dgp: `=r(N)' missing outcomes"
        exit 459
    }
    if !inlist("`regime'", "rcs", "rcsvar") {
        quietly bysort id: generate long nobs_ = _N
        quietly summarize nobs_, meanonly
        local mx = r(max)
        drop nobs_
        if `mx' &lt;= 1 {
            display as error "sim_dgp: panel regime produced singleton units only"
            exit 459
        }
    }
end</code></pre>
</details>

<details class="code-fold">
<summary><code>simrun3.do</code> &mdash; the estimator harness: one program per package, each invoked at its own documented covariate specification, all harvested into the same 3x2 matrix</summary>
<pre><code>* Run from the bench/ folder of the replication package. Not run on its
* own: the drivers load it with -do-.  It defines sim_est3.
* One estimator, one regime -&gt; matrix R (3x2): h=0,1,2 estimate and SE.
*
* Every package is invoked as ITS OWN documentation prescribes, and where a
* package does not claim support the attempt is still made and whatever it
* returns is recorded -- including "nothing". did_multiplegt_dyn never mentions
* repeated cross sections, so its RCS row is the extreme-unbalanced path (each
* unit observed once), not a fabricated group structure.

capture program drop _fxes_parse
program define _fxes_parse
    * parse "e | est se ..." rows for exposures 0..2 and the Overall row from
    * a captured flexdid display log; returns fx_b0..fx_se2, fx_ov, fx_ovse
    * via c_local. flexdid's r() results are destroyed by two non-rclass
    * wrapper hops, so the displayed table is the only harvestable surface.
    args logfile
    foreach k in b0 se0 b1 se1 b2 se2 ov ovse {
        local `k' "."
    }
    tempname fh
    file open `fh' using "`logfile'", read text
    file read `fh' line
    while r(eof) == 0 {
        local bar = strpos(`"`line'"', "|")
        if `bar' &gt; 0 {
            local lhs = strtrim(substr(`"`line'"', 1, `bar' - 1))
            local rest = substr(`"`line'"', `bar' + 1, .)
            if inlist(`"`lhs'"', "0", "1", "2") {
                local b`lhs' : word 1 of `rest'
                local se`lhs' : word 2 of `rest'
            }
            else if `"`lhs'"' == "Overall" {
                local ov : word 1 of `rest'
                local ovse : word 2 of `rest'
            }
        }
        file read `fh' line
    }
    file close `fh'
    foreach k in b0 se0 b1 se1 b2 se2 ov ovse {
        c_local fx_`k' "``k''"
    }
end

capture program drop sim_est3

program define sim_est3, rclass
    syntax , PKG(string) REGIME(string) [BAL(string) COV METHod(string)]
    tempname R
    matrix `R' = J(3, 2, .)
    local ok = 1
    local note ""

    if "`pkg'" == "csdid" {
        local mth = cond("`method'" == "", "", "method(`method')")
        local xv = cond("`cov'" != "", "x1 x2", "")
        if inlist("`regime'", "rcs", "rcsvar") {
            capture csdid y `xv', time(time) gvar(gvar) notyet analytical base_period(varying) rcs `mth'
        }
        else {
            local bm = cond("`regime'" == "unbalanced", "`bal'", "none")
            capture csdid y `xv', ivar(id) time(time) gvar(gvar) notyet analytical ///
                base_period(varying) bal(`bm') `mth'
        }
        if _rc local ok = 0
        else {
            capture quietly estat event, window(0 2)
            if _rc local ok = 0
            else {
                matrix A = e(aggte)
                forvalues r = 1/`=rowsof(A)' {
                    forvalues h = 0/2 {
                        if A[`r',1] == `h' {
                            matrix `R'[`h'+1,1] = A[`r',2]
                            matrix `R'[`h'+1,2] = A[`r',3]
                        }
                    }
                }
                * the windowed overall (equal-weight average of the post
                * event-time effects) and its se, identical in every row
                matrix OVR = (A[1,4], A[1,5])
                * post-treatment ATT(g,t) cells against their known truths
                matrix AT = e(attgt)
                matrix CELLS = J(rowsof(AT), 4, .)
                local nc = 0
                forvalues r = 1/`=rowsof(AT)' {
                    if AT[`r',2] &gt;= AT[`r',1] {
                        local ++nc
                        matrix CELLS[`nc',1] = AT[`r',1]
                        matrix CELLS[`nc',2] = AT[`r',2]
                        matrix CELLS[`nc',3] = AT[`r',4]
                        matrix CELLS[`nc',4] = AT[`r',5]
                    }
                }
                return scalar n_cells = `nc'
                return matrix CELLS = CELLS
                return matrix OVR = OVR
            }
        }
    }
    else if "`pkg'" == "jwdid" {
        if inlist("`regime'", "rcs", "rcsvar") {
            local xv = cond("`cov'" != "", "x1 x2", "")
            capture jwdid y `xv', tvar(time) gvar(gvar)
        }
        else {
            local xv = cond("`cov'" != "", "x1 x2", "")
            capture jwdid y `xv', ivar(id) tvar(time) gvar(gvar)
        }
        if _rc local ok = 0
        else {
            capture quietly estat event
            if _rc local ok = 0
            else {
                matrix B = r(table)
                local cn : colnames B
                local base = .
                foreach c of local cn {
                    if strpos("`c'","bn.__event__") local base = real(subinstr("`c'","bn.__event__","",.))
                }
                if missing(`base') local ok = 0
                else {
                    forvalues h = 0/2 {
                        local lev = `base' + `h'
                        local pos : list posof "`lev'.__event__" in cn
                        if `pos' == 0 local pos : list posof "`lev'bn.__event__" in cn
                        if `pos' &gt; 0 {
                            matrix `R'[`h'+1,1] = B[1,`pos']
                            matrix `R'[`h'+1,2] = B[2,`pos']
                        }
                    }
                }
            }
        }
    }
    else if "`pkg'" == "jwdid_uc" {
        if inlist("`regime'", "rcs", "rcsvar") {
            local xv = cond("`cov'" != "", "x1 x2", "")
            capture jwdid y `xv', tvar(time) gvar(gvar) method(regress) corr
        }
        else {
            local xv = cond("`cov'" != "", "x1 x2", "")
            capture jwdid y `xv', ivar(id) tvar(time) gvar(gvar) method(regress) corr
        }
        if _rc local ok = 0
        else {
            capture quietly estat event, vce(unconditional)
            if _rc local ok = 0
            else {
                matrix B = r(table)
                local cn : colnames B
                local base = .
                foreach c of local cn {
                    if strpos("`c'","bn.__event__") local base = real(subinstr("`c'","bn.__event__","",.))
                }
                if missing(`base') local ok = 0
                else {
                    forvalues h = 0/2 {
                        local lev = `base' + `h'
                        local pos : list posof "`lev'.__event__" in cn
                        if `pos' == 0 local pos : list posof "`lev'bn.__event__" in cn
                        if `pos' &gt; 0 {
                            matrix `R'[`h'+1,1] = B[1,`pos']
                            matrix `R'[`h'+1,2] = B[2,`pos']
                        }
                    }
                }
            }
        }
    }
    else if "`pkg'" == "bjs" {
        if inlist("`regime'", "rcs", "rcsvar") {
            if "`cov'" != "" {
                * covariates exactly as the did_imputation help prescribes:
                * binary (gender-like) via fe() interacted with period
                * dummies; continuous time-invariant via timecontrols(),
                * which enters i.t#c.x2 with an unrestricted coefficient
                * per period
                capture did_imputation y id time gvar_miss, horizons(0/2) ///
                    fe(gvar time x1#time) timecontrols(x2)
            }
            else {
                capture did_imputation y id time gvar_miss, horizons(0/2) fe(gvar time)
            }
        }
        else {
            if "`cov'" != "" {
                * same help-prescribed path as the repeated-cross-section
                * branch: fe() for the binary covariate's period
                * interactions, timecontrols() for the continuous one
                capture did_imputation y id time gvar_miss, horizons(0/2) autosample ///
                    fe(id time x1#time) timecontrols(x2)
            }
            else capture did_imputation y id time gvar_miss, horizons(0/2) autosample
        }
        if _rc local ok = 0
        else {
            matrix B = r(table)
            local cn : colnames B
            forvalues h = 0/2 {
                local pos : list posof "tau`h'" in cn
                if `pos' &gt; 0 {
                    matrix `R'[`h'+1,1] = B[1,`pos']
                    matrix `R'[`h'+1,2] = B[2,`pos']
                }
            }
        }
    }
    else if "`pkg'" == "dcdh" {
        local ctl = cond("`cov'" != "", "controls(x1 x2)", "")
        capture did_multiplegt_dyn y id time treated, effects(3) `ctl' graphoptions(nodraw)
        if _rc local ok = 0
        else {
            forvalues h = 0/2 {
                local j = `h' + 1
                capture matrix `R'[`h'+1,1] = e(Effect_`j')
                capture matrix `R'[`h'+1,2] = e(se_effect_`j')
            }
        }
    }
    else if "`pkg'" == "flexdid" {
        if (0) local ok = 0
        else {
            tempfile fxlog
            capture log close fxparse
            quietly log using "`fxlog'", text replace name(fxparse)
            local xv = cond("`cov'" != "", "x1 x2", "")
            capture noisily flexdid y `xv', tx(treated) group(gvar) time(time) ///
                specification(lagsandleads) vce(robust)
            local fxrc = _rc
            capture noisily estat atet, byexposure nograph
            if `fxrc' == 0 local fxrc = _rc
            quietly log close fxparse
            if `fxrc' local ok = 0
            else {
                _fxes_parse "`fxlog'"
                matrix `R'[1,1] = real("`fx_b0'")
                matrix `R'[1,2] = real("`fx_se0'")
                matrix `R'[2,1] = real("`fx_b1'")
                matrix `R'[2,2] = real("`fx_se1'")
                matrix `R'[3,1] = real("`fx_b2'")
                matrix `R'[3,2] = real("`fx_se2'")
                matrix OVR = (real("`fx_ov'"), real("`fx_ovse'"))
                return scalar n_cells = 0
                matrix CELLS = J(1, 4, .)
                return matrix CELLS = CELLS
                return matrix OVR = OVR
            }
        }
    }
    else if "`pkg'" == "sa" {
        * Sun &amp; Abraham interaction-weighted estimator (eventstudyinteract).
        * Full relative-time dummy set, reference -1, never-treated control.
        capture drop ry_XX nevertr_XX g_XX*
        quietly gen int ry_XX = time - gvar if gvar &gt; 0
        quietly gen byte nevertr_XX = (gvar == 0)
        local dums ""
        foreach k in -4 -3 -2 0 1 2 3 4 {
            local nm = cond(`k' &lt; 0, "g_XXm`=abs(`k')'", "g_XXp`k'")
            quietly gen byte `nm' = (ry_XX == `k')
            quietly replace `nm' = 0 if missing(`nm')
            local dums "`dums' `nm'"
        }
        local sacov = cond("`cov'" != "", "covariates(x1 x2)", "")
        capture eventstudyinteract y `dums', cohort(gvar_miss) ///
            control_cohort(nevertr_XX) `sacov' absorb(id time) vce(cluster id)
        if _rc local ok = 0
        else {
            capture matrix BSA = e(b_iw)
            capture matrix VSA = e(V_iw)
            if _rc local ok = 0
            else {
                local cnsa : colnames BSA
                forvalues h = 0/2 {
                    local jj : list posof "g_XXp`h'" in cnsa
                    if `jj' &gt; 0 {
                        matrix `R'[`h'+1,1] = BSA[1,`jj']
                        matrix `R'[`h'+1,2] = sqrt(VSA[`jj',`jj'])
                    }
                }
            }
        }
    }
    else if inlist("`pkg'", "csdid_dr", "csdid_ipw", "csdid_reg") | ///
        inlist("`pkg'", "csdid_dr_nt", "csdid_ipw_nt", "csdid_reg_nt") {
        * field-design csdid arms: package defaults (multiplier-bootstrap
        * inference), method and comparison group parsed from the arm name,
        * harvested from estat event's r(table)
        local mth : word 2 of `=subinstr("`pkg'", "_", " ", .)'
        local nt = cond(strpos("`pkg'", "_nt"), "nevertreated", "")
        local xv = cond("`cov'" != "", "x1 x2", "")
        capture csdid y `xv', ivar(id) time(time) gvar(gvar) method(`mth') `nt'
        if _rc local ok = 0
        else {
            capture estat event, window(0 2)
            if _rc local ok = 0
            else {
                matrix E = r(table)
                local ce : colnames E
                forvalues h = 0/2 {
                    local j : list posof "Tp`h'" in ce
                    if `j' &gt; 0 {
                        matrix `R'[`h'+1,1] = E[1,`j']
                        matrix `R'[`h'+1,2] = E[2,`j']
                    }
                }
            }
        }
    }
    else if inlist("`pkg'", "lpdid_ctl", "lpdid_rw_ctl") {
        local rwo = cond(strpos("`pkg'", "_rw"), "rw", "")
        capture lpdid y, unit(id) time(time) treat(treated) post_window(2) ///
            pre_window(3) `rwo' controls(x1 x2)
        if _rc local ok = 0
        else {
            capture matrix B = e(results)
            if _rc local ok = 0
            else {
                local rn : rownames B
                forvalues h = 0/2 {
                    local pos : list posof "tau`h'" in rn
                    if `pos' &gt; 0 {
                        matrix `R'[`h'+1,1] = B[`pos',1]
                        matrix `R'[`h'+1,2] = B[`pos',2]
                    }
                }
            }
        }
    }
    else if "`pkg'" == "dcdh_tnp" {
        capture did_multiplegt_dyn y id time treated, effects(3) ///
            trends_nonparam(x1) graphoptions(nodraw) graph_off
        forvalues h = 0/2 {
            local j = `h' + 1
            local b = .
            local se = .
            capture local b = e(Effect_`j')
            capture local se = e(se_effect_`j')
            if `b' &lt; . {
                matrix `R'[`h'+1,1] = `b'
                matrix `R'[`h'+1,2] = `se'
            }
        }
    }
    else if "`pkg'" == "sa_xt" {
        * Sun &amp; Abraham with covariate-by-period-dummy interactions
        quietly {
            capture drop ry_XX nevertr_XX g_XX* xa_XX* xb_XX*
            gen int ry_XX = time - gvar if gvar &gt; 0
            gen byte nevertr_XX = (gvar == 0)
            local dums ""
            foreach k in -4 -3 -2 0 1 2 3 4 {
                local nm = cond(`k' &lt; 0, "g_XXm`=abs(`k')'", "g_XXp`k'")
                gen byte `nm' = (ry_XX == `k')
                replace `nm' = 0 if missing(`nm')
                local dums "`dums' `nm'"
            }
            local xl ""
            if "`cov'" != "" {
                forvalues t = 2/7 {
                    gen double xa_XX`t' = x1*(time==`t')
                    gen double xb_XX`t' = x2*(time==`t')
                    local xl "`xl' xa_XX`t' xb_XX`t'"
                }
            }
        }
        capture eventstudyinteract y `dums', cohort(gvar_miss) ///
            control_cohort(nevertr_XX) covariates(`xl') absorb(id time) vce(cluster id)
        if _rc local ok = 0
        else {
            capture matrix BSA = e(b_iw)
            capture matrix VSA = e(V_iw)
            if _rc local ok = 0
            else {
                local cnsa : colnames BSA
                forvalues h = 0/2 {
                    local jj : list posof "g_XXp`h'" in cnsa
                    if `jj' &gt; 0 {
                        matrix `R'[`h'+1,1] = BSA[1,`jj']
                        matrix `R'[`h'+1,2] = sqrt(VSA[`jj',`jj'])
                    }
                }
            }
        }
    }
    else if "`pkg'" == "bjs_wtr" {
        * did_imputation with population-share wtr() weights
        mkwtr
        local sopt = cond("`cov'" != "", "fe(id time x1#time) timecontrols(x2)", "")
        capture did_imputation y id time gvar_miss, wtr(w0 w1 w2) autosample `sopt'
        if _rc local ok = 0
        else {
            matrix W = r(table)
            local cw : colnames W
            forvalues h = 0/2 {
                local p : list posof "tau_w`h'" in cw
                if `p' &gt; 0 {
                    matrix `R'[`h'+1,1] = W[1,`p']
                    matrix `R'[`h'+1,2] = W[2,`p']
                }
            }
        }
    }
    else if "`pkg'" == "lpdid" {
        local ctl = cond("`cov'" != "", "controls(x1 x2)", "")
        capture lpdid y, unit(id) time(time) treat(treated) post_window(2) pre_window(3) `ctl'
        if _rc local ok = 0
        else {
            capture matrix B = e(results)
            if _rc local ok = 0
            else {
                local rn : rownames B
                forvalues h = 0/2 {
                    local pos : list posof "tau`h'" in rn
                    if `pos' &gt; 0 {
                        matrix `R'[`h'+1,1] = B[`pos',1]
                        matrix `R'[`h'+1,2] = B[`pos',2]
                    }
                }
            }
        }
    }
    else if "`pkg'" == "lpdid_rw" {
        local ctl = cond("`cov'" != "", "controls(x1 x2)", "")
        capture lpdid y, unit(id) time(time) treat(treated) post_window(2) pre_window(3) rw `ctl'
        if _rc local ok = 0
        else {
            capture matrix B = e(results)
            if _rc local ok = 0
            else {
                local rn : rownames B
                forvalues h = 0/2 {
                    local pos : list posof "tau`h'" in rn
                    if `pos' &gt; 0 {
                        matrix `R'[`h'+1,1] = B[`pos',1]
                        matrix `R'[`h'+1,2] = B[`pos',2]
                    }
                }
            }
        }
    }
    return scalar ok = `ok'
    return matrix R = `R'
end</code></pre>
</details>

<details class="code-fold">
<summary><code>simtruth.do</code> &mdash; population-target verification: cohort shares and realised truth, printed for each regime</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do simtruth.do
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
set linesize 160
foreach reg in balanced unbalanced rcs {
    sim_dgp, n(40000) seed(11) regime(`reg')
    quietly count
    local rows = r(N)
    preserve
    quietly bysort id: keep if _n == 1
    quietly count
    local nu = r(N)
    local sh ""
    foreach g in 0 3 4 5 {
        quietly count if gvar == `g'
        local one : display %5.3f r(N)/`nu'
        local sh "`sh' `one'"
    }
    restore
    quietly generate double te_ = (gvar - 2) + 0.5 * (time - gvar) if treated
    local tr ""
    forvalues h = 0/2 {
        quietly summarize te_ if treated &amp; time == gvar + `h', meanonly
        local one : display %5.3f r(mean)
        local tr "`tr' `one'"
    }
    drop te_
    di "TRUTH `reg' rows=`rows' units=`nu' shares:`sh' | sample-truth h0/h1/h2:`tr'"
}</code></pre>
</details>


## The command map

These are the controlled experiments behind the claims about what each command computes. Each one is built so that two candidate answers give visibly different numbers, and the command's output picks between them.

<details class="code-fold">
<summary><code>wts.do</code> &mdash; which weights each command puts on a cohort: one lopsided design where equal, size and effective-sample-size weighting give visibly different answers</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do wts.do
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/runners.do"

* Deliberately lopsided: cohort 3 is SMALL with a BIG effect, cohort 4 is LARGE
* with a SMALL effect. Any two weighting schemes then give visibly different
* event-study numbers, so the pooled estimate identifies the weights.
clear
set seed 99
quietly set obs 1100
generate long id = _n
generate int gvar = cond(id &lt;= 100, 3, cond(id &lt;= 1000, 4, 0))
quietly expand 7
quietly bysort id: generate int time = _n
quietly generate double eff = cond(gvar==3, 2.0, 0.5)
quietly generate double y = id*0.0005 + time*0.3 + rnormal()*0.10
quietly replace y = y + eff if gvar&gt;0 &amp; time&gt;=gvar
quietly generate byte treated = (gvar&gt;0 &amp; time&gt;=gvar)
quietly generate int gvar_miss = gvar
quietly replace gvar_miss = . if gvar==0
quietly generate int cl = mod(id,20)+1
tempfile d
quietly save "`d'", replace

quietly count if gvar==3 &amp; time==1
local n3 = r(N)
quietly count if gvar==4 &amp; time==1
local n4 = r(N)
di "SETUP cohort3 units=`n3' effect=2.0   cohort4 units=`n4' effect=0.5"
di "SETUP equal-weight h0   = " %7.4f (2.0+0.5)/2
di "SETUP size-weight h0    = " %7.4f (`n3'*2.0 + `n4'*0.5)/(`n3'+`n4')

* csdid ATT(g,t) then its own event aggregation
use "`d'", clear
quietly csdid y, ivar(id) time(time) gvar(gvar) analytical base_period(varying) bal(none)
matrix A = e(attgt)
forvalues r = 1/`=rowsof(A)' {
    if A[`r',1] == A[`r',2] di "  csdid ATT(g=" A[`r',1] ",e=0) = " %7.4f A[`r',4]
}
quietly estat event, window(0 0)
matrix E = e(aggte)
di "AGG csdid  event h0 = " %7.4f E[1,2]

use "`d'", clear
quietly bench_jwdid, horizons(0) cluster(cl)
matrix E = r(ES)
di "AGG jwdid  event h0 = " %7.4f E[1,2]

use "`d'", clear
quietly bench_dcdh, horizons(0) cluster(cl)
matrix E = r(ES)
di "AGG dcdh   event h0 = " %7.4f E[1,2]

use "`d'", clear
capture bench_bjs, horizons(0) cluster(cl)
if !_rc {
    matrix E = r(ES)
    di "AGG bjs    event h0 = " %7.4f E[1,2]
}
use "`d'", clear
capture bench_lpdid, horizons(0) cluster(cl)
if !_rc {
    matrix E = r(ES)
    di "AGG lpdid  event h0 = " %7.4f E[1,2]
}</code></pre>
</details>

<details class="code-fold">
<summary><code>wts2.do</code> &mdash; the same identification repeated at three cohort-size splits, so the weight is read off the movement and not off one number</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do wts2.do
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/runners.do"
capture program drop wtest
program define wtest
    args n3 n4
    clear
    set seed 99
    local tot = `n3' + `n4' + 100
    quietly set obs `tot'
    generate long id = _n
    generate int gvar = cond(id &lt;= `n3', 3, cond(id &lt;= `n3'+`n4', 4, 0))
    quietly expand 7
    quietly bysort id: generate int time = _n
    quietly generate double eff = cond(gvar==3, 2.0, 0.5)
    quietly generate double y = id*0.0005 + time*0.3 + rnormal()*0.10
    quietly replace y = y + eff if gvar&gt;0 &amp; time&gt;=gvar
    quietly generate byte treated = (gvar&gt;0 &amp; time&gt;=gvar)
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar==0
    quietly generate int cl = mod(id,20)+1
    tempfile d
    quietly save "`d'", replace
    local eqw = (2.0+0.5)/2
    local szw = (`n3'*2.0 + `n4'*0.5)/(`n3'+`n4')
    di "W n3=`n3' n4=`n4'  equal=" %6.4f `eqw' "  size=" %6.4f `szw'
    foreach pkg in csdid jwdid bjs dcdh lpdid {
        use "`d'", clear
        if "`pkg'" == "csdid" {
            quietly csdid y, ivar(id) time(time) gvar(gvar) analytical base_period(varying) bal(none)
            quietly estat event, window(0 0)
            matrix E = e(aggte)
            di "W    csdid = " %6.4f E[1,2]
        }
        else {
            capture bench_`pkg', horizons(0) cluster(cl)
            if !_rc {
                matrix E = r(ES)
                di "W    `pkg' = " %6.4f E[1,2]
            }
        }
    }
end
wtest 100 900
wtest 500 500
wtest 900 100</code></pre>
</details>

<details class="code-fold">
<summary><code>mech.do</code> &mdash; what makes the pooling estimators differ from base-period differencing: a one-pre-period design where they cannot differ, and a balanced/unbalanced pair at two seeds</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do mech.do
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/dgp.do"
quietly do "`B'/runners.do"

* TEST A. One pre-period only (T=2, g=2). A fitted-FE imputation has exactly one
* untreated period to learn from, so it CANNOT differ from single-base
* differencing. If jwdid/bjs then equal csdid, the balanced-panel gap is the
* pre-period pooling and nothing else.
capture program drop mechA
program define mechA
    quietly bench_dgp, design(dynamic) n(3000) t(2) seed(77) cohorts(1)
    quietly keep if gvar == 2 | gvar == 0
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar == 0
    tempfile d
    quietly save "`d'", replace
    use "`d'", clear
    quietly csdid y, ivar(id) time(time) gvar(gvar) analytical base_period(varying) notyet bal(none)
    matrix A = e(attgt)
    di "MECH A  csdid  = " %10.6f A[1,4]
    foreach pkg in jwdid bjs {
        use "`d'", clear
        capture bench_`pkg', horizons(0) cluster(cl)
        if _rc == 0 &amp; r(ok) == 1 {
            matrix E = r(ES)
            di "MECH A  `pkg'  = " %10.6f E[1,2]
        }
        else di "MECH A  `pkg'  FAILED"
    }
end
mechA

* TEST B. Does jwdid == bjs exactly on a BALANCED panel at a second seed, and
* do they come apart under unbalancedness at that seed too?
capture program drop mechB
program define mechB
    args struct seed
    quietly bench_dgp, design(dynamic) n(3000) t(7) seed(`seed') cohorts(2)
    quietly keep if gvar == 3 | gvar == 0
    if "`struct'" == "unbalanced" {
        set seed `=`seed'+5'
        quietly generate double du = runiform()
        quietly drop if du &lt; 0.15
        drop du
    }
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar == 0
    tempfile d
    quietly save "`d'", replace
    local out ""
    foreach pkg in jwdid bjs {
        use "`d'", clear
        capture bench_`pkg', horizons(1) cluster(cl)
        matrix E = r(ES)
        local out "`out'  `pkg'=" + string(E[1,2],"%9.6f")
    }
    di "MECH B  `struct' seed=`seed' `out'"
end
mechB balanced 101
mechB unbalanced 101
mechB balanced 202
mechB unbalanced 202</code></pre>
</details>


## Reliability arms

One population, one set of targets, and only the way the sample arrives changes. Each driver writes one row per (regime, package, replication, horizon), so nothing is aggregated before it can be inspected.

<details class="code-fold">
<summary><code>simmc.do</code> &mdash; Reliability I: the four sampling regimes (balanced, period-varying missingness, unbalanced, repeated cross sections), full package roster</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do simmc.do 1000 500 mc.csv
* Monte Carlo: one DGP, one fixed target (2.0 / 2.5 / 3.0), four sampling
* regimes -- balanced, period-varying missingness, unbalanced, and repeated
* cross sections.
* Writes one row per (regime, package, rep, horizon) so nothing is aggregated
* before it is inspected.
args nunits reps outfile
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {
    foreach reg in balanced varmiss unbalanced rcs {
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(`reg')
        tempfile d
        quietly save "`d'", replace
        local plist "csdid jwdid bjs dcdh lpdid"
        if inlist("`reg'", "unbalanced", "varmiss") local plist "csdid csdidpair jwdid bjs dcdh lpdid"
        foreach pkg of local plist {
            local realpkg = cond("`pkg'" == "csdidpair", "csdid", "`pkg'")
            local bopt = cond("`pkg'" == "csdidpair", "pair", "none")
            use "`d'", clear
            capture sim_est3, pkg(`realpkg') regime(`reg') bal(`bopt')
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                * every numeric goes through string(): file write's (exp)
                * writer chokes on a missing value, and a degenerate cell's
                * se (or estimate) is legitimately missing
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',`h',`v1',`v2'" _n
                }
                * r(OVR) undefined does NOT error a matrix assignment - Stata
                * reads it as scalar missing and builds a 1x1 - so the guard
                * is the scalar count only csdid returns
                local ncell = r(n_cells)
                if `ncell' &lt; . {
                    matrix OV = r(OVR)
                    local v1 = string(OV[1,1], "%18.0g")
                    local v2 = string(OV[1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',99,`v1',`v2'" _n
                    matrix CE = r(CELLS)
                    forvalues c = 1/`ncell' {
                        local code = 1000 * CE[`c',1] + CE[`c',2]
                        local v1 = string(CE[`c',3], "%18.0g")
                        local v2 = string(CE[`c',4], "%18.0g")
                        file write out "`reg',`pkg',`r',`code',`v1',`v2'" _n
                    }
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "`reg',`pkg',`r',`h',.,." _n
                }
            }
        }
    }
    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"</code></pre>
</details>

<details class="code-fold">
<summary><code>simmc_cov.do</code> &mdash; the covariate arm: repeated cross sections with x1 and x2, conditional parallel trends</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do simmc_cov.do 1000 500 mc_cov.csv
* Monte Carlo: one DGP, one fixed target (2.0 / 2.5 / 3.0), covariates on.
* Two repeated-cross-section regimes -- equal period sizes (rcs) and unequal
* period sizes (rcsvar).
* Writes one row per (regime, package, rep, horizon) so nothing is aggregated
* before it is inspected.
args nunits reps outfile
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {
    foreach reg in rcs rcsvar {
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(`reg') cov
        tempfile d
        quietly save "`d'", replace
        local plist "csdid jwdid bjs flexdid"
        foreach pkg of local plist {
            local realpkg = cond("`pkg'" == "csdidpair", "csdid", "`pkg'")
            local bopt = cond("`pkg'" == "csdidpair", "pair", "none")
            use "`d'", clear
            capture noisily sim_est3, pkg(`realpkg') regime(`reg') bal(`bopt') cov
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                * every numeric goes through string(): file write's (exp)
                * writer chokes on a missing value, and a degenerate cell's
                * se (or estimate) is legitimately missing
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',`h',`v1',`v2'" _n
                }
                * r(OVR) undefined does NOT error a matrix assignment - Stata
                * reads it as scalar missing and builds a 1x1 - so the guard
                * is the scalar count only csdid returns
                local ncell = r(n_cells)
                if `ncell' &lt; . {
                    matrix OV = r(OVR)
                    local v1 = string(OV[1,1], "%18.0g")
                    local v2 = string(OV[1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',99,`v1',`v2'" _n
                    matrix CE = r(CELLS)
                    forvalues c = 1/`ncell' {
                        local code = 1000 * CE[`c',1] + CE[`c',2]
                        local v1 = string(CE[`c',3], "%18.0g")
                        local v2 = string(CE[`c',4], "%18.0g")
                        file write out "`reg',`pkg',`r',`code',`v1',`v2'" _n
                    }
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "`reg',`pkg',`r',`h',.,." _n
                }
            }
        }
    }
    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"</code></pre>
</details>

<details class="code-fold">
<summary><code>simmc_rv.do</code> &mdash; the unequal-period repeated-cross-section regime on its own</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do simmc_rv.do 1000 500 mc_rv.csv
* Monte Carlo: one DGP, one fixed target (2.0 / 2.5 / 3.0), the unequal-period
* repeated-cross-section regime (rcsvar) on its own.
* Writes one row per (regime, package, rep, horizon) so nothing is aggregated
* before it is inspected.
args nunits reps outfile
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {
    foreach reg in rcsvar {
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(`reg')
        tempfile d
        quietly save "`d'", replace
        local plist "csdid jwdid bjs"
        if inlist("`reg'", "unbalanced", "varmiss") local plist "csdid csdidpair jwdid bjs dcdh lpdid"
        foreach pkg of local plist {
            local realpkg = cond("`pkg'" == "csdidpair", "csdid", "`pkg'")
            local bopt = cond("`pkg'" == "csdidpair", "pair", "none")
            use "`d'", clear
            capture sim_est3, pkg(`realpkg') regime(`reg') bal(`bopt')
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                * every numeric goes through string(): file write's (exp)
                * writer chokes on a missing value, and a degenerate cell's
                * se (or estimate) is legitimately missing
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',`h',`v1',`v2'" _n
                }
                * r(OVR) undefined does NOT error a matrix assignment - Stata
                * reads it as scalar missing and builds a 1x1 - so the guard
                * is the scalar count only csdid returns
                local ncell = r(n_cells)
                if `ncell' &lt; . {
                    matrix OV = r(OVR)
                    local v1 = string(OV[1,1], "%18.0g")
                    local v2 = string(OV[1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',99,`v1',`v2'" _n
                    matrix CE = r(CELLS)
                    forvalues c = 1/`ncell' {
                        local code = 1000 * CE[`c',1] + CE[`c',2]
                        local v1 = string(CE[`c',3], "%18.0g")
                        local v2 = string(CE[`c',4], "%18.0g")
                        file write out "`reg',`pkg',`r',`code',`v1',`v2'" _n
                    }
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "`reg',`pkg',`r',`h',.,." _n
                }
            }
        }
    }
    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"</code></pre>
</details>

<details class="code-fold">
<summary><code>simmc_fx.do</code> &mdash; the flexdid arm on repeated cross sections</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do simmc_fx.do 1000 500 mc_fx.csv
* Monte Carlo: one DGP, one fixed target (2.0 / 2.5 / 3.0), flexdid only, on
* the two repeated-cross-section regimes (rcs and rcsvar).
* Writes one row per (regime, package, rep, horizon) so nothing is aggregated
* before it is inspected.
args nunits reps outfile
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {
    foreach reg in rcs rcsvar {
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(`reg')
        tempfile d
        quietly save "`d'", replace
        local plist "flexdid"
        foreach pkg of local plist {
            local realpkg = cond("`pkg'" == "csdidpair", "csdid", "`pkg'")
            local bopt = cond("`pkg'" == "csdidpair", "pair", "none")
            use "`d'", clear
            capture noisily sim_est3, pkg(`realpkg') regime(`reg') bal(`bopt')
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                * every numeric goes through string(): file write's (exp)
                * writer chokes on a missing value, and a degenerate cell's
                * se (or estimate) is legitimately missing
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',`h',`v1',`v2'" _n
                }
                * r(OVR) undefined does NOT error a matrix assignment - Stata
                * reads it as scalar missing and builds a 1x1 - so the guard
                * is the scalar count only csdid returns
                local ncell = r(n_cells)
                if `ncell' &lt; . {
                    matrix OV = r(OVR)
                    local v1 = string(OV[1,1], "%18.0g")
                    local v2 = string(OV[1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',99,`v1',`v2'" _n
                    matrix CE = r(CELLS)
                    forvalues c = 1/`ncell' {
                        local code = 1000 * CE[`c',1] + CE[`c',2]
                        local v1 = string(CE[`c',3], "%18.0g")
                        local v2 = string(CE[`c',4], "%18.0g")
                        file write out "`reg',`pkg',`r',`code',`v1',`v2'" _n
                    }
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "`reg',`pkg',`r',`h',.,." _n
                }
            }
        }
    }
    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"</code></pre>
</details>

<details class="code-fold">
<summary><code>simmc_fxpanel.do</code> &mdash; the flexdid arm on the three panel regimes</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do simmc_fxpanel.do 1000 500 mc_fxpanel.csv
* Monte Carlo: one DGP, one fixed target (2.0 / 2.5 / 3.0), flexdid only, on
* the three panel regimes (balanced, varmiss, unbalanced).
* Writes one row per (regime, package, rep, horizon) so nothing is aggregated
* before it is inspected.
args nunits reps outfile
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {
    foreach reg in balanced varmiss unbalanced {
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(`reg')
        tempfile d
        quietly save "`d'", replace
        local plist "flexdid"
        foreach pkg of local plist {
            local realpkg = cond("`pkg'" == "csdidpair", "csdid", "`pkg'")
            local bopt = cond("`pkg'" == "csdidpair", "pair", "none")
            use "`d'", clear
            capture noisily sim_est3, pkg(`realpkg') regime(`reg') bal(`bopt')
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                * every numeric goes through string(): file write's (exp)
                * writer chokes on a missing value, and a degenerate cell's
                * se (or estimate) is legitimately missing
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',`h',`v1',`v2'" _n
                }
                * r(OVR) undefined does NOT error a matrix assignment - Stata
                * reads it as scalar missing and builds a 1x1 - so the guard
                * is the scalar count only csdid returns
                local ncell = r(n_cells)
                if `ncell' &lt; . {
                    matrix OV = r(OVR)
                    local v1 = string(OV[1,1], "%18.0g")
                    local v2 = string(OV[1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',99,`v1',`v2'" _n
                    matrix CE = r(CELLS)
                    forvalues c = 1/`ncell' {
                        local code = 1000 * CE[`c',1] + CE[`c',2]
                        local v1 = string(CE[`c',3], "%18.0g")
                        local v2 = string(CE[`c',4], "%18.0g")
                        file write out "`reg',`pkg',`r',`code',`v1',`v2'" _n
                    }
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "`reg',`pkg',`r',`h',.,." _n
                }
            }
        }
    }
    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"</code></pre>
</details>


## Misspecification

The covariates are real and parallel trends is conditional. These arms break the outcome model, then the propensity score, and record what each estimator does about it.

<details class="code-fold">
<summary><code>simmc_dr.do</code> &mdash; the three misspecification cells: both models right, outcome model wrong, propensity score wrong</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do simmc_dr.do 1000 500 mc_dr.csv
* Monte Carlo: one DGP, one fixed target (2.0 / 2.5 / 3.0), balanced panel
* with covariates. Three misspecification cells -- both models right, the
* outcome model wrong, the propensity score wrong.
* Writes one row per (regime, package, rep, horizon) so nothing is aggregated
* before it is inspected.
args nunits reps outfile
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {
    foreach cell in ok owrong pwrong {
        * msp MUST be resolved BEFORE the sim_dgp call that consumes it.
        * A -local- placed after the call hands every cell the PREVIOUS
        * iteration's misspecification and rotates all three labels.
        local msp = cond("`cell'" == "ok", "", cond("`cell'" == "owrong", "misspec(outcome)", "misspec(pscore)"))
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(balanced) cov `msp'
        tempfile d
        quietly save "`d'", replace
        local reg "bal_`cell'"
        local plist "csdid_dr csdid_ipw csdid_reg jwdid bjs dcdh lpdid flexdid"
        foreach pkg of local plist {
            local realpkg "`pkg'"
            local mopt ""
            if strpos("`pkg'", "csdid_") {
                local realpkg "csdid"
                local mopt "method(`=substr("`pkg'", 7, .)')"
            }
            local bopt "none"
            use "`d'", clear
            capture noisily sim_est3, pkg(`realpkg') regime(balanced) bal(none) cov `mopt'
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                * every numeric goes through string(): file write's (exp)
                * writer chokes on a missing value, and a degenerate cell's
                * se (or estimate) is legitimately missing
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',`h',`v1',`v2'" _n
                }
                * r(OVR) undefined does NOT error a matrix assignment - Stata
                * reads it as scalar missing and builds a 1x1 - so the guard
                * is the scalar count only csdid returns
                local ncell = r(n_cells)
                if `ncell' &lt; . {
                    matrix OV = r(OVR)
                    local v1 = string(OV[1,1], "%18.0g")
                    local v2 = string(OV[1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',99,`v1',`v2'" _n
                    matrix CE = r(CELLS)
                    forvalues c = 1/`ncell' {
                        local code = 1000 * CE[`c',1] + CE[`c',2]
                        local v1 = string(CE[`c',3], "%18.0g")
                        local v2 = string(CE[`c',4], "%18.0g")
                        file write out "`reg',`pkg',`r',`code',`v1',`v2'" _n
                    }
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "`reg',`pkg',`r',`h',.,." _n
                }
            }
        }
    }
    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"</code></pre>
</details>

<details class="code-fold">
<summary><code>simmc_ps2.do</code> &mdash; the propensity-score cell whose specification error loads on the linear trend</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do simmc_ps2.do 1000 500 mc_ps2.csv
* Monte Carlo: the pscore-misspec cell (latent-index selection,
* observed x2 = standardized exp(0.8 w), shifts at half scale). One cell,
* full roster. Same seeds as the DR arm.
args nunits reps outfile
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {
    quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(balanced) cov misspec(pscore2)
    tempfile d
    quietly save "`d'", replace
    local reg "bal_ps2"
    local plist "csdid_dr csdid_ipw csdid_reg jwdid bjs dcdh lpdid flexdid"
    foreach pkg of local plist {
        local realpkg "`pkg'"
        local mopt ""
        if strpos("`pkg'", "csdid_") {
            local realpkg "csdid"
            local mopt "method(`=substr("`pkg'", 7, .)')"
        }
        use "`d'", clear
        capture noisily sim_est3, pkg(`realpkg') regime(balanced) bal(none) cov `mopt'
        if _rc == 0 &amp; r(ok) == 1 {
            matrix RR = r(R)
            forvalues h = 0/2 {
                local v1 = string(RR[`h'+1,1], "%18.0g")
                local v2 = string(RR[`h'+1,2], "%18.0g")
                file write out "`reg',`pkg',`r',`h',`v1',`v2'" _n
            }
            local ncell = r(n_cells)
            if `ncell' &lt; . {
                matrix OV = r(OVR)
                local v1 = string(OV[1,1], "%18.0g")
                local v2 = string(OV[1,2], "%18.0g")
                file write out "`reg',`pkg',`r',99,`v1',`v2'" _n
                matrix CE = r(CELLS)
                forvalues c = 1/`ncell' {
                    local code = 1000 * CE[`c',1] + CE[`c',2]
                    local v1 = string(CE[`c',3], "%18.0g")
                    local v2 = string(CE[`c',4], "%18.0g")
                    file write out "`reg',`pkg',`r',`code',`v1',`v2'" _n
                }
            }
        }
        else {
            forvalues h = 0/2 {
                file write out "`reg',`pkg',`r',`h',.,." _n
            }
        }
    }
    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"</code></pre>
</details>

<details class="code-fold">
<summary><code>tnptest.do</code> &mdash; how much of did_multiplegt_dyn's covariate drift trends_nonparam() removes, over 100 replications</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do tnptest.do
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
capture file close out
file open out using "`B'/tnptest.csv", write replace text
file write out "variant,rep,h,est" _n
forvalues r = 1/100 {
    quietly sim_dgp, n(1000) seed(`=90000+`r'') regime(balanced) cov
    foreach v in tnp_x1 tnp_both {
        local opt = cond("`v'"=="tnp_x1", "trends_nonparam(x1)", "trends_nonparam(x1 x2)")
        capture quietly did_multiplegt_dyn y id time treated, effects(3) `opt' graphoptions(nodraw)
        if _rc == 0 {
            forvalues h = 0/2 {
                local e = string(e(Effect_`=`h'+1'), "%18.0g")
                file write out "`v',`r',`h',`e'" _n
            }
        }
        else file write out "`v',`r',0,FAILRC`=_rc'" _n
    }
}
file close out
display "TNP done"</code></pre>
</details>


## Inference comparisons

Two designs where commands agree on the point estimate and disagree on the standard error, so the difference that remains is the inference convention and nothing else. Both are single draws at a stated seed, not replication studies.

<details class="code-fold">
<summary><code>hetx.do</code> &mdash; jwdid and did_imputation on one draw with covariate-varying effects: identical point estimates, standard errors that are not (seed 4242, n = 50,000)</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do hetx.do
adopath ++ "../src/ado"
adopath ++ "../src/mata"
clear
set seed 4242
set obs 50000
gen id = _n
gen gvar = cond(mod(_n,4)==0, 0, cond(mod(_n,4)==1, 3, cond(mod(_n,4)==2, 4, 5)))
gen byte x1 = runiform() &lt; cond(gvar==0, .35, .15+.10*gvar)
gen double x2 = rnormal() + cond(gvar==0, -0.5, 0.4*(gvar-4))
gen double mu = rnormal()
expand 7
bysort id: gen time = _n
gen double y = mu + 0.3*time + 0.4*x1 + 0.6*x2 + (0.35*x1 + 0.45*x2)*time + rnormal()
* effects vary with cohort, event time, AND x2
gen double h = time - gvar
replace y = y + (gvar-2) + 0.5*h + 0.8*x2*(h+1) if gvar&gt;0 &amp; time&gt;=gvar
* analytic treated-average truths at ES(h): cohorts 3,4,5 equal shares,
* E[x2|g] = -0.4, 0, +0.4  =&gt;  X-term averages 0.8*mean(E[x2|g])*(h+1) = 0
* per-cohort truths differ, the equal-weight cohort average is:
forvalues hh = 0/2 {
    local tr`hh' = ((1+2+3)/3) + 0.5*`hh'
    di "HX truth ES(`hh') = " %6.4f `tr`hh'' "   (cohort truths differ by ±0.32*(h+1) through x2)"
}
csdid y x1 x2, ivar(id) time(time) gvar(gvar) analytical
estat event, window(0 2)
matrix E = e(aggte)
di "HX csdid dr : ES0=" %6.4f E[1,2] " ES1=" %6.4f E[2,2] " ES2=" %6.4f E[3,2]
capture drop gvar_miss
gen gvar_miss = gvar
replace gvar_miss = . if gvar==0
did_imputation y id time gvar_miss, horizons(0/2) autosample fe(id time x1#time) timecontrols(x2)
matrix B = r(table)
di "HX bjs      : ES0=" %6.4f B[1,1] " ES1=" %6.4f B[1,2] " ES2=" %6.4f B[1,3]
* cell-level check for one cohort with nonzero E[x2|g]: cohort 5, h=0: truth 3 + 0.8*0.4*1 = 3.32
matrix A = e(Nt)
matrix C = e(b)
jwdid y x1 x2, ivar(id) tvar(time) gvar(gvar)
estat event
matrix J = r(table)
local cn : colnames J
di "HX jwdid cols: `cn'"
di "HX jwdid    : ES0=" %8.6f J[1,1] " ES1=" %8.6f J[1,2] " ES2=" %8.6f J[1,3]
di "HX bjs again: ES0=" %8.6f B[1,1] " ES1=" %8.6f B[1,2] " ES2=" %8.6f B[1,3]
did_imputation y id time gvar_miss, horizons(0/2) autosample fe(id time x1#time) timecontrols(x2) cluster(id)
matrix B2 = r(table)
di "HXSE bjs   cluster(id): se0=" %8.6f B2[2,1] " se1=" %8.6f B2[2,2] " se2=" %8.6f B2[2,3]
jwdid y x1 x2, ivar(id) tvar(time) gvar(gvar) cluster(id)
estat event
matrix J2 = r(table)
di "HXSE jwdid cluster(id): se0=" %8.6f J2[2,1] " se1=" %8.6f J2[2,2] " se2=" %8.6f J2[2,3]</code></pre>
</details>

<details class="code-fold">
<summary><code>dcdhse.do</code> &mdash; csdid and did_multiplegt_dyn on a design where their point estimates coincide, so only the inference convention separates them (seed 31415)</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do dcdhse.do
adopath ++ "../src/ado"
adopath ++ "../src/mata"
clear
set seed 31415
set obs 20000
gen id = _n
gen gvar = cond(mod(_n,4)==0, 0, cond(mod(_n,4)==1, 3, cond(mod(_n,4)==2, 4, 5)))
gen double mu = rnormal()
expand 7
bysort id: gen time = _n
gen double y = mu + 0.3*time + rnormal()
replace y = y + (gvar-2) + 0.5*(time-gvar) if gvar&gt;0 &amp; time&gt;=gvar
gen byte D = (gvar&gt;0 &amp; time&gt;=gvar)
csdid y, ivar(id) time(time) gvar(gvar) analytical
estat event, window(0 2)
matrix E = e(aggte)
di "DC csdid : e0=" %7.4f E[1,2] " (se " %6.4f E[1,3] ")  e1=" %7.4f E[2,2] " (se " %6.4f E[2,3] ")  e2=" %7.4f E[3,2] " (se " %6.4f E[3,3] ")"
did_multiplegt_dyn y id time D, effects(3) graph_off
matrix M = e(estimates)
matrix V = e(variances)
di "DC dcdh  : e0=" %7.4f M[1,1] " (se " %6.4f sqrt(V[1,1]) ")  e1=" %7.4f M[2,1] " (se " %6.4f sqrt(V[2,1]) ")  e2=" %7.4f M[3,1] " (se " %6.4f sqrt(V[3,1]) ")"</code></pre>
</details>


## Precision and bands

What changes when the error process is not iid, and whether an interval read across the whole event-study path covers at its nominal level.

<details class="code-fold">
<summary><code>simmc_ur.do</code> &mdash; the error-process arm: within-unit random-walk errors, where base-period differencing is the efficient construction</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do simmc_ur.do 1000 500 mc_ur.csv
* Monte Carlo: one DGP, one fixed target (2.0 / 2.5 / 3.0), balanced panel
* with within-unit random-walk errors.
* Writes one row per (regime, package, rep, horizon) so nothing is aggregated
* before it is inspected.
args nunits reps outfile
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {
    foreach reg in unitroot {
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(balanced) errors(unitroot)
        tempfile d
        quietly save "`d'", replace
        local plist "csdid jwdid bjs dcdh lpdid flexdid"
        foreach pkg of local plist {
            local realpkg = cond("`pkg'" == "csdidpair", "csdid", "`pkg'")
            local bopt = cond("`pkg'" == "csdidpair", "pair", "none")
            use "`d'", clear
            capture noisily sim_est3, pkg(`realpkg') regime(balanced) bal(`bopt')
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                * every numeric goes through string(): file write's (exp)
                * writer chokes on a missing value, and a degenerate cell's
                * se (or estimate) is legitimately missing
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',`h',`v1',`v2'" _n
                }
                * r(OVR) undefined does NOT error a matrix assignment - Stata
                * reads it as scalar missing and builds a 1x1 - so the guard
                * is the scalar count only csdid returns
                local ncell = r(n_cells)
                if `ncell' &lt; . {
                    matrix OV = r(OVR)
                    local v1 = string(OV[1,1], "%18.0g")
                    local v2 = string(OV[1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',99,`v1',`v2'" _n
                    matrix CE = r(CELLS)
                    forvalues c = 1/`ncell' {
                        local code = 1000 * CE[`c',1] + CE[`c',2]
                        local v1 = string(CE[`c',3], "%18.0g")
                        local v2 = string(CE[`c',4], "%18.0g")
                        file write out "`reg',`pkg',`r',`code',`v1',`v2'" _n
                    }
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "`reg',`pkg',`r',`h',.,." _n
                }
            }
        }
    }
    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"</code></pre>
</details>

<details class="code-fold">
<summary><code>simmc_bands.do</code> &mdash; joint coverage: multiplier-bootstrap uniform bands over the whole event-study path</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do simmc_bands.do 1000 500 mc_bands.csv
* Whole-path inference: csdid multiplier-bootstrap uniform bands, balanced
* panel, no covariates, same seeds as the core study. Rows: h=0..2 carry
* (att, se_boot); rows h=40x carry the BAND (ci_low, ci_high) for h=x.
* Rivals' per-rep pointwise results already exist in the core CSV (same
* seeds), so joint pointwise coverage is computed from there.
args nunits reps outfile
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n
forvalues r = 1/`reps' {
    quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(balanced)
    capture csdid y, ivar(id) time(time) gvar(gvar) notyet base_period(varying) ///
        bal(none) wboot(reps(999) rseed(`=70000 + `r''))
    if _rc == 0 {
        capture quietly estat event, window(0 2)
        if _rc == 0 {
            matrix BG = e(boot_aggte)
            matrix A = e(aggte)
            forvalues i = 1/`=rowsof(A)' {
                local h = A[`i',1]
                if inlist(`h', 0, 1, 2) {
                    local v1 = string(BG[`i',2], "%18.0g")
                    local v2 = string(BG[`i',3], "%18.0g")
                    file write out "bands,csdid_band,`r',`h',`v1',`v2'" _n
                    local lo = string(BG[`i',5], "%18.0g")
                    local hi = string(BG[`i',6], "%18.0g")
                    file write out "bands,csdid_band,`r',`=400+`h'',`lo',`hi'" _n
                }
            }
        }
    }
    if mod(`r', 25) == 0 display "MCPROG rep `r' of `reps'"
}
file close out
display "MCDONE"</code></pre>
</details>

## Option arms and the designs that separate the estimators

The scripts below add the option arms discussed in the guide (lpdid <code>rw</code>, jwdid unconditional inference, did_imputation <code>wtr()</code>, eventstudyinteract) and the designs in which the commands genuinely part ways. The DGPs live in one definitions file (<code>fielddgp.do</code>); every design driver is a thin loop that writes one CSV row per (regime, pkg, rep, horizon), summarized by <code>mcsum.py</code>; and <code>eqgate.do</code> verifies, at the seed level, that every estimator arm reproduces the literal command it stands for. All run from the bench/ folder and seed replication r at 90000&nbsp;+&nbsp;r.

<details class="code-fold">
<summary><code>fielddgp.do</code> &mdash; every field-design DGP in one definitions file, the simdgp.do pattern</summary>
<pre><code>*-----------------------------------------------------------------------------
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
    quietly generate byte   x1 = runiform() &lt; cond(gvar==0, .35, .15 + .10*gvar)
    quietly generate double x2 = rnormal() + cond(gvar==0, -0.5, 0.4*(gvar-4))
    quietly expand 7
    quietly bysort id: generate int time = _n
    quietly generate double y = mu + 0.30*time + rnormal()
    quietly replace y = y + 0.4*x1 + 0.6*x2
    quietly replace y = y + x1*(2.0*sin(1.6*time)) + x2*(2.2*cos(1.3*time))
    quietly generate double tau = (gvar-2) + 0.5*(time-gvar) if gvar&gt;0 &amp; time&gt;=gvar
    quietly replace y = y + tau if gvar&gt;0 &amp; time&gt;=gvar
    quietly generate byte treated = (gvar&gt;0 &amp; time&gt;=gvar)
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
    quietly generate byte   x1 = runiform() &lt; cond(gvar==0, .35, .15 + .10*gvar)
    quietly generate double x2 = rnormal() + cond(gvar==0, -0.5, 0.4*(gvar-4))
    quietly expand 7
    quietly bysort id: generate int time = _n
    quietly generate double y = mu + 0.30*time + rnormal()
    quietly replace y = y + 0.4*x1 + 0.6*x2 + (0.35*x1 + 0.45*x2)*time
    quietly generate double ag = cond(gvar==3,0.3,cond(gvar==4,0.8,cond(gvar==5,1.5,0)))
    quietly generate double bg = cond(gvar==3,0.2,cond(gvar==4,0.6,cond(gvar==5,1.2,0)))
    quietly generate double tau = 0
    quietly replace tau = (gvar-2) + 0.5*(time-gvar) + ag*x1 + bg*x2*(time-gvar) ///
        if gvar&gt;0 &amp; time&gt;=gvar
    quietly replace y = y + tau if gvar&gt;0 &amp; time&gt;=gvar
    quietly generate byte treated = (gvar&gt;0 &amp; time&gt;=gvar)
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
    quietly generate byte   x1 = runiform() &lt; cond(gvar==0, .35, .15 + .10*gvar)
    quietly generate double x2 = rnormal() + cond(gvar==0, -0.5, 0.4*(gvar-4))
    quietly expand 7
    quietly bysort id: generate int time = _n
    quietly generate double y = mu + 0.30*time + rnormal()
    quietly replace y = y + 0.4*x1 + 0.6*x2
    quietly replace y = y + x1*(2.0*sin(1.6*time)) + x2*(2.2*cos(1.3*time))
    quietly generate double ag = cond(gvar==3,0.3,cond(gvar==4,0.8,cond(gvar==5,1.5,0)))
    quietly generate double bg = cond(gvar==3,0.2,cond(gvar==4,0.6,cond(gvar==5,1.2,0)))
    quietly generate double tau = (gvar-2) + 0.5*(time-gvar) + ag*x1 + bg*x2*(time-gvar) ///
        if gvar&gt;0 &amp; time&gt;=gvar
    quietly replace y = y + tau if gvar&gt;0 &amp; time&gt;=gvar
    quietly generate byte treated = (gvar&gt;0 &amp; time&gt;=gvar)
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
    quietly replace gvar = 3 + mod(_n,3) if u &gt;= `ntshare'
    quietly drop u
    quietly generate double mu = rnormal()
    quietly expand 7
    quietly bysort id: generate int time = _n
    quietly generate double y = mu + 0.30*time + rnormal()
    quietly replace y = y + (gvar-2) + 0.5*(time-gvar) if gvar&gt;0 &amp; time&gt;=gvar
    quietly generate byte treated = (gvar&gt;0 &amp; time&gt;=gvar)
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
    quietly replace y = y + (gvar-2) + 0.5*(time-gvar) if gvar&gt;0 &amp; time&gt;=gvar
    quietly generate byte treated = (gvar&gt;0 &amp; time&gt;=gvar)
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
    if "`mode'"=="drop"  quietly drop if ku&lt;dr
    if "`mode'"=="ymiss" quietly replace y = . if ku&lt;dr
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
        * ASYMMETRIC cohort means, common variance -&gt; logit-linear pscore
        quietly generate double x2 = rnormal() + cond(gvar==0, -0.5, ///
            cond(gvar==3, -0.8, cond(gvar==4, 0.0, 0.2)))
    }
    else {
        * UNEQUAL cohort sizes: 50/30/20 among treated, 25% never-treated
        quietly generate double u = runiform()
        quietly generate int gvar = 0
        quietly replace gvar = 3 if u&gt;=.25 &amp; u&lt;.625
        quietly replace gvar = 4 if u&gt;=.625 &amp; u&lt;.85
        quietly replace gvar = 5 if u&gt;=.85
        quietly drop u
        quietly generate double x2 = rnormal() + cond(gvar==0, -0.5, 0.4*(gvar-4))
    }
    quietly generate byte x1 = runiform() &lt; cond(gvar==0, .35, .15 + .10*gvar)
    quietly generate double mu = rnormal()
    quietly expand 7
    quietly bysort id: generate int time = _n
    quietly generate double y = mu + 0.30*time + rnormal()
    quietly replace y = y + 0.4*x1 + 0.6*x2
    if "`design'"=="B" {
        * NONLINEAR covariate trend, common across cohorts -&gt; conditional PT holds
        quietly replace y = y + (0.35*x1 + 0.45*x2 + 0.50*(x2^2-1))*time
        quietly generate double tau = (gvar-2) + 0.5*(time-gvar) if gvar&gt;0 &amp; time&gt;=gvar
    }
    else {
        quietly replace y = y + (0.35*x1 + 0.45*x2)*time
        quietly generate double ag = cond(gvar==3,0.3,cond(gvar==4,0.8,cond(gvar==5,1.5,0)))
        quietly generate double bg = cond(gvar==3,0.2,cond(gvar==4,0.6,cond(gvar==5,1.2,0)))
        quietly generate double tau = (gvar-2) + 0.5*(time-gvar) + ag*x1 + bg*x2*(time-gvar) ///
            if gvar&gt;0 &amp; time&gt;=gvar
        quietly drop ag bg
    }
    quietly replace y = y + tau if gvar&gt;0 &amp; time&gt;=gvar
    quietly generate byte treated = (gvar&gt;0 &amp; time&gt;=gvar)
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
    quietly replace y = y + (gvar-2) + 0.5*(time-gvar) if gvar&gt;0 &amp; time&gt;=gvar
    quietly generate byte treated = (gvar&gt;0 &amp; time&gt;=gvar)
    quietly drop mu
end

capture program drop mkwtr
program define mkwtr
    quietly capture drop K w0 w1 w2 ncell
    quietly gen int K = time - gvar if gvar &gt; 0 &amp; time &gt;= gvar
    forvalues h = 0/2 {
        quietly capture drop ncell
        quietly bysort gvar time: egen double ncell = total(K == `h') if K == `h'
        quietly gen double w`h' = cond(K == `h' &amp; ncell &gt; 0, 1/(3*ncell), 0)
        quietly replace w`h' = 0 if missing(w`h')
    }
end
</code></pre>
</details>
<details class="code-fold">
<summary><code>eqgate.do</code> &mdash; the seed-level equivalence gate: every arm moved into simrun3.do must reproduce its inline command exactly</summary>
<pre><code>*-----------------------------------------------------------------------------
*      eqgate.do -- seed-level equivalence gate for the refactored arms
*-----------------------------------------------------------------------------
* Every arm moved from inline driver code into sim_est3 must reproduce the
* inline command exactly, estimate and standard error, at the same seed.
* csdid arms use multiplier-bootstrap inference, so the RNG is reset to the
* same state immediately before the branch call and the inline call; the
* other arms consume no randomness at estimation.
* Output: eqgate.csv, one row per (seed, arm, horizon) with both values.
* Run from the bench/ folder. Pass = max |difference| is exactly zero.
*-----------------------------------------------------------------------------
clear all
set more off
* replication-package layout puts src/ beside bench/; in the repo checkout it
* sits three levels up -- probe for it
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"
quietly do "simrun3.do"

capture file close out
file open out using "eqgate.csv", write replace text
file write out "seed,arm,h,b_branch,b_inline,se_branch,se_inline" _n

foreach sd in 90001 90002 90003 {
    dgp_master, n(2000) seed(`sd')
    tempfile d
    quietly save "`d'", replace

    foreach arm in csdid_reg csdid_dr csdid_reg_nt lpdid lpdid_rw lpdid_ctl lpdid_rw_ctl dcdh_tnp sa_xt {

        * ---- branch path ----
        use "`d'", clear
        set seed 7654321
        local covopt = cond(inlist("`arm'", "lpdid", "lpdid_rw"), "", "cov")
        capture sim_est3, pkg(`arm') regime(balanced) bal(none) `covopt'
        matrix RB = r(R)

        * ---- inline path: the literal command the old drivers ran ----
        use "`d'", clear
        set seed 7654321
        matrix RI = J(3, 2, .)
        if inlist("`arm'", "csdid_reg", "csdid_dr", "csdid_reg_nt") {
            local mth = cond(strpos("`arm'", "_dr"), "dr", "reg")
            local nt  = cond(strpos("`arm'", "_nt"), "nevertreated", "")
            capture csdid y x1 x2, ivar(id) time(time) gvar(gvar) method(`mth') `nt'
            if _rc == 0 {
                capture estat event, window(0 2)
                if _rc == 0 {
                    matrix E = r(table)
                    local ce : colnames E
                    forvalues h = 0/2 {
                        local j : list posof "Tp`h'" in ce
                        if `j' &gt; 0 {
                            matrix RI[`h'+1,1] = E[1,`j']
                            matrix RI[`h'+1,2] = E[2,`j']
                        }
                    }
                }
            }
        }
        else if inlist("`arm'", "lpdid", "lpdid_rw", "lpdid_ctl", "lpdid_rw_ctl") {
            local rwo = cond(strpos("`arm'", "rw"), "rw", "")
            local cto = cond(strpos("`arm'", "ctl"), "controls(x1 x2)", "")
            capture lpdid y, unit(id) time(time) treat(treated) post_window(2) ///
                pre_window(3) `rwo' `cto'
            if _rc == 0 {
                capture matrix B = e(results)
                if _rc == 0 {
                    local rn : rownames B
                    forvalues h = 0/2 {
                        local pos : list posof "tau`h'" in rn
                        if `pos' &gt; 0 {
                            matrix RI[`h'+1,1] = B[`pos',1]
                            matrix RI[`h'+1,2] = B[`pos',2]
                        }
                    }
                }
            }
        }
        else if "`arm'" == "dcdh_tnp" {
            capture did_multiplegt_dyn y id time treated, effects(3) ///
                trends_nonparam(x1) graphoptions(nodraw) graph_off
            forvalues h = 0/2 {
                local j = `h' + 1
                local b = .
                local se = .
                capture local b = e(Effect_`j')
                capture local se = e(se_effect_`j')
                if `b' &lt; . {
                    matrix RI[`h'+1,1] = `b'
                    matrix RI[`h'+1,2] = `se'
                }
            }
        }
        else if "`arm'" == "sa_xt" {
            quietly {
                gen int ry = time - gvar if gvar &gt; 0
                gen byte nevertr = (gvar == 0)
                local dums ""
                foreach k in -4 -3 -2 0 1 2 3 4 {
                    local nm = cond(`k' &lt; 0, "g_m`=abs(`k')'", "g_p`k'")
                    gen byte `nm' = (ry == `k')
                    replace `nm' = 0 if missing(`nm')
                    local dums "`dums' `nm'"
                }
                local xl ""
                forvalues t = 2/7 {
                    gen double xa_`t' = x1*(time==`t')
                    gen double xb_`t' = x2*(time==`t')
                    local xl "`xl' xa_`t' xb_`t'"
                }
            }
            capture eventstudyinteract y `dums', cohort(gvar_miss) ///
                control_cohort(nevertr) covariates(`xl') absorb(id time) vce(cluster id)
            if _rc == 0 {
                matrix BS = e(b_iw)
                matrix VS = e(V_iw)
                local cn : colnames BS
                forvalues h = 0/2 {
                    local j : list posof "g_p`h'" in cn
                    if `j' &gt; 0 {
                        matrix RI[`h'+1,1] = BS[1,`j']
                        matrix RI[`h'+1,2] = sqrt(VS[`j',`j'])
                    }
                }
            }
        }

        forvalues h = 0/2 {
            local bb = string(RB[`h'+1,1], "%21.0g")
            local bi = string(RI[`h'+1,1], "%21.0g")
            local sb = string(RB[`h'+1,2], "%21.0g")
            local si = string(RI[`h'+1,2], "%21.0g")
            file write out "`sd',`arm',`h',`bb',`bi',`sb',`si'" _n
        }
    }
}
file close out
</code></pre>
</details>
<details class="code-fold">
<summary><code>lpdidrw.do</code> &mdash; the lpdid <code>rw</code> arm on every design where lpdid appears, same seeds as simmc.do</summary>
<pre><code>* Adds the lpdid `rw' arm to every design in which lpdid already appears.
* Same DGP, same seeds (90000 + rep) as simmc.do / simmc_dr.do / simmc_ps2.do,
* so the default-lpdid rows reproduce the published numbers and the rw rows
* drop straight into the same tables.
*   Usage: stata-mp -b do lpdidrw.do &lt;nunits&gt; &lt;reps&gt; &lt;outfile&gt;
args nunits reps outfile
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {

    * ---- Reliability I sampling regimes (no covariates) ----
    foreach reg in balanced varmiss unbalanced {
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(`reg')
        tempfile d
        quietly save "`d'", replace
        foreach pkg in lpdid lpdid_rw {
            use "`d'", clear
            capture sim_est3, pkg(`pkg') regime(`reg') bal(none)
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',`h',`v1',`v2'" _n
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "`reg',`pkg',`r',`h',.,." _n
                }
            }
        }
    }

    * ---- covariate cells: both models right, outcome wrong, pscore wrong ----
    foreach cell in ok owrong pwrong2 {
        local msp = cond("`cell'" == "ok", "", ///
            cond("`cell'" == "owrong", "misspec(outcome)", "misspec(pscore2)"))
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(balanced) cov `msp'
        tempfile dc
        quietly save "`dc'", replace
        foreach pkg in lpdid lpdid_rw {
            use "`dc'", clear
            capture sim_est3, pkg(`pkg') regime(balanced) bal(none) cov
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "bal_`cell',`pkg',`r',`h',`v1',`v2'" _n
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "bal_`cell',`pkg',`r',`h',.,." _n
                }
            }
        }
    }

    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
</code></pre>
</details>

<details class="code-fold">
<summary><code>jwuncond.do</code> &mdash; jwdid with <code>method(regress) corr</code> and <code>vce(unconditional)</code>, paired with the default on the same seeds</summary>
<pre><code>* Adds the jwdid unconditional-SE arm to every design in which lpdid already appears.
* Same DGP, same seeds (90000 + rep) as simmc.do / simmc_dr.do / simmc_ps2.do,
* so the default-lpdid rows reproduce the published numbers and the rw rows
* drop straight into the same tables.
*   Usage: stata-mp -b do lpdidrw.do &lt;nunits&gt; &lt;reps&gt; &lt;outfile&gt;
args nunits reps outfile
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {

    * ---- Reliability I sampling regimes (no covariates) ----
    foreach reg in balanced varmiss unbalanced {
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(`reg')
        tempfile d
        quietly save "`d'", replace
        foreach pkg in jwdid jwdid_uc {
            use "`d'", clear
            capture sim_est3, pkg(`pkg') regime(`reg') bal(none)
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',`h',`v1',`v2'" _n
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "`reg',`pkg',`r',`h',.,." _n
                }
            }
        }
    }

    * ---- covariate cells: both models right, outcome wrong, pscore wrong ----
    foreach cell in ok owrong pwrong2 {
        local msp = cond("`cell'" == "ok", "", ///
            cond("`cell'" == "owrong", "misspec(outcome)", "misspec(pscore2)"))
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(balanced) cov `msp'
        tempfile dc
        quietly save "`dc'", replace
        foreach pkg in jwdid jwdid_uc {
            use "`dc'", clear
            capture sim_est3, pkg(`pkg') regime(balanced) bal(none) cov
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "bal_`cell',`pkg',`r',`h',`v1',`v2'" _n
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "bal_`cell',`pkg',`r',`h',.,." _n
                }
            }
        }
    }

    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
</code></pre>
</details>

<details class="code-fold">
<summary><code>bjswtr.do</code> &mdash; did_imputation default vs <code>wtr()</code> population-share weights across the sampling regimes</summary>
<pre><code>* did_imputation: default vs wtr(population-share), all designs where it appears.
args nunits reps outfile
quietly do "simdgp.do"
capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

capture program drop mkwtr
program define mkwtr
    quietly capture drop K w0 w1 w2 ncell
    quietly gen int K = time - gvar if gvar &gt; 0 &amp; time &gt;= gvar
    forvalues h = 0/2 {
        quietly capture drop ncell
        quietly bysort gvar time: egen double ncell = total(K == `h') if K == `h'
        quietly gen double w`h' = cond(K == `h' &amp; ncell &gt; 0, 1/(3*ncell), 0)
        quietly replace w`h' = 0 if missing(w`h')
    }
end

forvalues r = 1/`reps' {
    foreach reg in balanced varmiss unbalanced {
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(`reg')
        tempfile d
        quietly save "`d'", replace

        use "`d'", clear
        capture did_imputation y id time gvar_miss, horizons(0/2) autosample
        local ok = (_rc == 0)
        forvalues h = 0/2 {
            local e = .
            local s = .
            if `ok' {
                matrix B = r(table)
                local cn : colnames B
                local p : list posof "tau`h'" in cn
                if `p' &gt; 0 {
                    local e = B[1,`p']
                    local s = B[2,`p']
                }
            }
            file write out "`reg',bjs,`r',`h'," (string(`e',"%18.0g")) "," (string(`s',"%18.0g")) _n
        }

        use "`d'", clear
        mkwtr
        capture did_imputation y id time gvar_miss, wtr(w0 w1 w2) autosample
        local ok2 = (_rc == 0)
        forvalues h = 0/2 {
            local e2 = .
            local s2 = .
            if `ok2' {
                matrix W = r(table)
                local cw : colnames W
                local p2 : list posof "tau_w`h'" in cw
                if `p2' &gt; 0 {
                    local e2 = W[1,`p2']
                    local s2 = W[2,`p2']
                }
            }
            file write out "`reg',bjs_wtr,`r',`h'," (string(`e2',"%18.0g")) "," (string(`s2',"%18.0g")) _n
        }
    }
    if mod(`r',25)==0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
</code></pre>
</details>

<details class="code-fold">
<summary><code>sarun.do</code> &mdash; the Sun and Abraham interaction-weighted estimator (eventstudyinteract) on the main designs</summary>
<pre><code>* Runs the Sun and Abraham arm (eventstudyinteract) via simrun3.do on the main designs.
* Same DGP, same seeds (90000 + rep) as simmc.do / simmc_dr.do / simmc_ps2.do,
* so the default-lpdid rows reproduce the published numbers and the rw rows
* drop straight into the same tables.
*   Usage: stata-mp -b do lpdidrw.do &lt;nunits&gt; &lt;reps&gt; &lt;outfile&gt;
args nunits reps outfile
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {

    * ---- Reliability I sampling regimes (no covariates) ----
    foreach reg in balanced varmiss unbalanced {
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(`reg')
        tempfile d
        quietly save "`d'", replace
        foreach pkg in sa {
            use "`d'", clear
            capture sim_est3, pkg(`pkg') regime(`reg') bal(none)
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "`reg',`pkg',`r',`h',`v1',`v2'" _n
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "`reg',`pkg',`r',`h',.,." _n
                }
            }
        }
    }

    * ---- covariate cells: both models right, outcome wrong, pscore wrong ----
    foreach cell in ok owrong pwrong2 {
        local msp = cond("`cell'" == "ok", "", ///
            cond("`cell'" == "owrong", "misspec(outcome)", "misspec(pscore2)"))
        quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(balanced) cov `msp'
        tempfile dc
        quietly save "`dc'", replace
        foreach pkg in sa {
            use "`dc'", clear
            capture sim_est3, pkg(`pkg') regime(balanced) bal(none) cov
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "bal_`cell',`pkg',`r',`h',`v1',`v2'" _n
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "bal_`cell',`pkg',`r',`h',.,." _n
                }
            }
        }
    }

    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
</code></pre>
</details>

<details class="code-fold">
<summary><code>optcost.do</code> &mdash; what the <code>rw</code> and unconditional options cost in run time, at the guide's timing protocol</summary>
<pre><code>*-----------------------------------------------------------------------------
*      optcost.do -- what the option arms cost in run time
*-----------------------------------------------------------------------------
* The guide's timing protocol: one discarded warmup per (arm, dataset), then
* the median of the requested trials.
*   jwdid default vs method(regress) corr + estat, vce(unconditional)
*   lpdid default vs rw
* Output: optcost.csv, one row per (n, arm). Run from the bench/ folder.
*   Usage: stata-mp -b do optcost.do &lt;trials&gt;
*-----------------------------------------------------------------------------
clear all
set more off
* replication-package layout puts src/ beside bench/; in the repo checkout it
* sits three levels up -- probe for it
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
args trials
if "`trials'" == "" local trials 5
quietly do "fielddgp.do"

capture program drop run_jw_default
program define run_jw_default
    quietly jwdid y, ivar(id) tvar(time) gvar(gvar)
    quietly estat event
end
capture program drop run_jw_uncond
program define run_jw_uncond
    quietly jwdid y, ivar(id) tvar(time) gvar(gvar) method(regress) corr
    quietly estat event, vce(unconditional)
end
capture program drop run_lp_default
program define run_lp_default
    quietly lpdid y, unit(id) time(time) treat(treated) post_window(2) pre_window(3)
end
capture program drop run_lp_rw
program define run_lp_rw
    quietly lpdid y, unit(id) time(time) treat(treated) post_window(2) pre_window(3) rw
end

capture program drop timeit
program define timeit, rclass
    syntax , WHAT(string) TRIALS(integer)
    capture noisily run_`what'
    tempname T
    matrix `T' = J(`trials', 1, .)
    forvalues k = 1/`trials' {
        timer clear 9
        timer on 9
        capture run_`what'
        timer off 9
        quietly timer list 9
        matrix `T'[`k',1] = r(t9)
    }
    tempname V
    mata: st_matrix("`V'", sort(st_matrix("`T'"), 1))
    local mid = ceil(`trials'/2)
    return scalar med = `V'[`mid',1]
end

capture file close out
file open out using "optcost.csv", write replace text
file write out "n,rows,arm,median_seconds" _n

foreach n in 1000 10000 {
    mkpanel, n(`n')
    local rows = _N
    tempfile d
    quietly save "`d'", replace
    foreach arm in jw_default jw_uncond lp_default lp_rw {
        use "`d'", clear
        capture timeit, what(`arm') trials(`trials')
        local m = cond(_rc, ., r(med))
        local v = string(`m', "%12.0g")
        file write out "`n',`rows',`arm',`v'" _n
    }
}
file close out
display "MCDONE optcost.csv"
</code></pre>
</details>

<details class="code-fold">
<summary><code>sa_equiv.do</code> &mdash; csdid <code>nevertreated</code> and eventstudyinteract on one draw per regime: the balanced-panel equivalence and where it stops</summary>
<pre><code>*-----------------------------------------------------------------------------
*      sa_equiv.do -- the csdid / eventstudyinteract equivalence, one draw
*-----------------------------------------------------------------------------
* One draw per sampling regime, no covariates: csdid with nevertreated and
* the interaction-weighted estimator coincide to machine precision on the
* balanced panel and part ways once the panel is unbalanced or period sizes
* vary. Output: sa_equiv.csv. Run from the bench/ folder.
*   Usage: stata-mp -b do sa_equiv.do
*-----------------------------------------------------------------------------
clear all
set more off
* replication-package layout puts src/ beside bench/; in the repo checkout it
* sits three levels up -- probe for it
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "simdgp.do"

capture file close out
file open out using "sa_equiv.csv", write replace text
file write out "regime,h,sa,csdid_nyt,diff" _n

foreach reg in balanced unbalanced varmiss {
    quietly sim_dgp, n(2000) seed(90007) regime(`reg')
    quietly {
        gen int ry = time - gvar if gvar &gt; 0
        gen byte nevertr = (gvar == 0)
        local dums ""
        foreach k in -4 -3 -2 0 1 2 3 4 {
            local nm = cond(`k' &lt; 0, "g_m`=abs(`k')'", "g_p`k'")
            gen byte `nm' = (ry == `k')
            replace `nm' = 0 if missing(`nm')
            local dums "`dums' `nm'"
        }
    }
    capture eventstudyinteract y `dums', cohort(gvar_miss) ///
        control_cohort(nevertr) absorb(id time) vce(cluster id)
    matrix BS = e(b_iw)
    local cn : colnames BS
    capture csdid y, ivar(id) time(time) gvar(gvar) nevertreated
    capture estat event, window(0 2)
    matrix E = r(table)
    local ce : colnames E
    forvalues h = 0/2 {
        local j : list posof "g_p`h'" in cn
        local sa = cond(`j' &gt; 0, BS[1,`j'], .)
        local jc : list posof "Tp`h'" in ce
        local cs = cond(`jc' &gt; 0, E[1,`jc'], .)
        local v1 = string(`sa', "%18.0g")
        local v2 = string(`cs', "%18.0g")
        local v3 = string(`sa' - `cs', "%18.0g")
        file write out "`reg',`h',`v1',`v2',`v3'" _n
    }
}
file close out
display "MCDONE sa_equiv.csv"
</code></pre>
</details>



<details class="code-fold">
<summary><code>sa_se.do</code> &mdash; standard errors of csdid and eventstudyinteract compared over 200 draws</summary>
<pre><code>*-----------------------------------------------------------------------------
*      sa_se.do -- standard errors of csdid and eventstudyinteract compared
*-----------------------------------------------------------------------------
* Balanced panel, no covariates, 200 draws: mean standard errors of the two
* commands and the largest point-estimate gap. Output: sa_se.csv.
* Run from the bench/ folder.
*   Usage: stata-mp -b do sa_se.do &lt;reps&gt;
*-----------------------------------------------------------------------------
clear all
set more off
* replication-package layout puts src/ beside bench/; in the repo checkout it
* sits three levels up -- probe for it
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
args reps
if "`reps'" == "" local reps 200
quietly do "simdgp.do"

matrix S = J(3, 5, 0)
forvalues r = 1/`reps' {
    quietly sim_dgp, n(1000) seed(`=90000 + `r'') regime(balanced)
    quietly {
        capture drop ry nevertr g_m* g_p*
        gen int ry = time - gvar if gvar &gt; 0
        gen byte nevertr = (gvar == 0)
        local dums ""
        foreach k in -4 -3 -2 0 1 2 3 4 {
            local nm = cond(`k' &lt; 0, "g_m`=abs(`k')'", "g_p`k'")
            gen byte `nm' = (ry == `k')
            replace `nm' = 0 if missing(`nm')
            local dums "`dums' `nm'"
        }
    }
    capture eventstudyinteract y `dums', cohort(gvar_miss) ///
        control_cohort(nevertr) absorb(id time) vce(cluster id)
    local sa_ok = (_rc == 0)
    if `sa_ok' {
        matrix BS = e(b_iw)
        matrix VS = e(V_iw)
        local cns : colnames BS
    }
    capture csdid y, ivar(id) time(time) gvar(gvar) nevertreated
    local cs_ok = (_rc == 0)
    if `cs_ok' {
        capture estat event, window(0 2)
        matrix EC = r(table)
        local cnc : colnames EC
    }
    if `sa_ok' &amp; `cs_ok' {
        forvalues h = 0/2 {
            local js : list posof "g_p`h'" in cns
            local jc : list posof "Tp`h'" in cnc
            if `js' &gt; 0 &amp; `jc' &gt; 0 {
                local i = `h' + 1
                matrix S[`i',1] = S[`i',1] + sqrt(VS[`js',`js'])
                matrix S[`i',2] = S[`i',2] + EC[2,`jc']
                matrix S[`i',3] = S[`i',3] + 1
                local db = abs(BS[1,`js'] - EC[1,`jc'])
                matrix S[`i',4] = S[`i',4] + `db'
                if `db' &gt; S[`i',5] matrix S[`i',5] = `db'
            }
        }
    }
}
capture file close out
file open out using "sa_se.csv", write replace text
file write out "h,mean_se_sa,mean_se_csdid,reps,mean_absdiff_b,max_absdiff_b" _n
forvalues h = 0/2 {
    local i = `h' + 1
    local n = S[`i',3]
    local v1 = string(S[`i',1]/`n', "%18.0g")
    local v2 = string(S[`i',2]/`n', "%18.0g")
    local v3 = string(S[`i',4]/`n', "%18.0g")
    local v4 = string(S[`i',5], "%18.0g")
    file write out "`h',`v1',`v2',`n',`v3',`v4'" _n
}
file close out
display "MCDONE sa_se.csv"
</code></pre>
</details>

<details class="code-fold">
<summary><code>sa_scale.do</code> &mdash; the csdid-reg/eventstudyinteract difference at n = 500 to 32,000: the root-n convergence check</summary>
<pre><code>*-----------------------------------------------------------------------------
*      sa_scale.do -- does the csdid-reg / eventstudyinteract gap shrink?
*-----------------------------------------------------------------------------
* With covariates the two are different estimators of the same estimand; the
* mean absolute difference should fall at the root-n rate. n = 500 to
* 32,000, 20 draws each. Output: sa_scale.csv. Run from the bench/ folder.
*   Usage: stata-mp -b do sa_scale.do &lt;reps&gt;
*-----------------------------------------------------------------------------
clear all
set more off
* replication-package layout puts src/ beside bench/; in the repo checkout it
* sits three levels up -- probe for it
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
args reps
if "`reps'" == "" local reps 20
quietly do "simdgp.do"

capture file close out
file open out using "sa_scale.csv", write replace text
file write out "n,mean_absdiff,mean_diff,reps" _n

foreach n in 500 2000 8000 32000 {
    local sumabs = 0
    local sumdif = 0
    local k = 0
    forvalues r = 1/`reps' {
        quietly sim_dgp, n(`n') seed(`=90000 + `r'') regime(balanced) cov
        tempfile d
        quietly save "`d'", replace
        local c0 = .
        capture csdid y x1 x2, ivar(id) time(time) gvar(gvar) method(reg) nevertreated
        if _rc == 0 {
            capture estat event, window(0 2)
            if _rc == 0 {
                matrix E = r(table)
                local ce : colnames E
                local j : list posof "Tp0" in ce
                if `j' &gt; 0 local c0 = E[1,`j']
            }
        }
        use "`d'", clear
        quietly {
            gen int ry = time - gvar if gvar &gt; 0
            gen byte nevertr = (gvar == 0)
            local dums ""
            foreach k2 in -4 -3 -2 0 1 2 3 4 {
                local nm = cond(`k2' &lt; 0, "g_m`=abs(`k2')'", "g_p`k2'")
                gen byte `nm' = (ry == `k2')
                replace `nm' = 0 if missing(`nm')
                local dums "`dums' `nm'"
            }
            local xl ""
            forvalues t = 2/7 {
                gen double xa_`t' = x1*(time==`t')
                gen double xb_`t' = x2*(time==`t')
                local xl "`xl' xa_`t' xb_`t'"
            }
        }
        local s0 = .
        capture eventstudyinteract y `dums', cohort(gvar_miss) ///
            control_cohort(nevertr) covariates(`xl') absorb(id time) vce(cluster id)
        if _rc == 0 {
            matrix BS = e(b_iw)
            local cn : colnames BS
            local j : list posof "g_p0" in cn
            if `j' &gt; 0 local s0 = BS[1,`j']
        }
        if `c0' &lt; . &amp; `s0' &lt; . {
            local sumabs = `sumabs' + abs(`c0' - `s0')
            local sumdif = `sumdif' + (`c0' - `s0')
            local k = `k' + 1
        }
    }
    local v1 = string(`sumabs'/`k', "%18.0g")
    local v2 = string(`sumdif'/`k', "%18.0g")
    file write out "`n',`v1',`v2',`k'" _n
}
file close out
display "MCDONE sa_scale.csv"
</code></pre>
</details>

<details class="code-fold">
<summary><code>cell_compare.do</code> &mdash; ATT(g,t) cells of csdid reg nevertreated against <code>e(b_interact)</code>, one draw</summary>
<pre><code>*-----------------------------------------------------------------------------
*      cell_compare.do -- ATT(g,t) cells against e(b_interact), one draw
*-----------------------------------------------------------------------------
* With covariates the disagreement between csdid reg (nevertreated) and the
* interaction-weighted estimator is already present at the cell level, not
* only after aggregation. Output: cell_compare.csv. Run from the bench/
* folder.
*   Usage: stata-mp -b do cell_compare.do
*-----------------------------------------------------------------------------
clear all
set more off
* replication-package layout puts src/ beside bench/; in the repo checkout it
* sits three levels up -- probe for it
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "simdgp.do"
quietly sim_dgp, n(4000) seed(90001) regime(balanced) cov
tempfile d
quietly save "`d'", replace

capture file close out
file open out using "cell_compare.csv", write replace text
file write out "source,cell,value" _n

quietly csdid y x1 x2, ivar(id) time(time) gvar(gvar) method(reg) nevertreated
matrix CB = e(b)
local cn : colnames CB
forvalues j = 1/`=colsof(CB)' {
    local nm : word `j' of `cn'
    local v = string(CB[1,`j'], "%18.0g")
    file write out "csdid,`nm',`v'" _n
}

use "`d'", clear
quietly {
    gen int ry = time - gvar if gvar &gt; 0
    gen byte nevertr = (gvar == 0)
    local dums ""
    foreach k in -4 -3 -2 0 1 2 3 4 {
        local nm = cond(`k' &lt; 0, "g_m`=abs(`k')'", "g_p`k'")
        gen byte `nm' = (ry == `k')
        replace `nm' = 0 if missing(`nm')
        local dums "`dums' `nm'"
    }
    local xl ""
    forvalues t = 2/7 {
        gen double xa_`t' = x1*(time==`t')
        gen double xb_`t' = x2*(time==`t')
        local xl "`xl' xa_`t' xb_`t'"
    }
}
quietly eventstudyinteract y `dums', cohort(gvar_miss) ///
    control_cohort(nevertr) covariates(`xl') absorb(id time) vce(cluster id)
matrix BI = e(b_interact)
local rn : rownames BI
local cnn : colnames BI
forvalues i = 1/`=rowsof(BI)' {
    local g : word `i' of `rn'
    forvalues j = 1/`=colsof(BI)' {
        local e : word `j' of `cnn'
        local v = string(BI[`i',`j'], "%18.0g")
        file write out "sa_b_interact,g`g'_`e',`v'" _n
    }
}
matrix W = e(ff_w)
forvalues i = 1/`=rowsof(W)' {
    local g : word `i' of `rn'
    forvalues j = 1/`=colsof(W)' {
        local e : word `j' of `cnn'
        local v = string(W[`i',`j'], "%18.0g")
        file write out "sa_ff_w,g`g'_`e',`v'" _n
    }
}
file close out
display "MCDONE cell_compare.csv"
</code></pre>
</details>

<details class="code-fold">
<summary><code>wtr_cells.do</code> &mdash; isolating single ATT(g,t) cells with did_imputation's <code>wtr()</code></summary>
<pre><code>* Can wtr() isolate individual ATT(g,t) cells from did_imputation?
* Truth for cell (g,t) is (g-2) + 0.5*(t-g).
clear all
set more off
quietly do "simdgp.do"
quietly sim_dgp, n(4000) seed(90001) regime(balanced)

quietly {
    gen double c33 = 0
    gen double c45 = 0
    gen double c57 = 0
    * one indicator per (g,t) cell, normalised to average within the cell
    foreach spec in 3_3 4_5 5_7 {
        local g = substr("`spec'",1,1)
        local t = substr("`spec'",3,1)
        count if gvar==`g' &amp; time==`t'
        local n = r(N)
        replace c`g'`t' = 1/`n' if gvar==`g' &amp; time==`t'
    }
}
di "--- cell sizes and weight totals ---"
foreach v in c33 c45 c57 {
    quietly summarize `v', meanonly
    di "   `v' sums to " %6.4f r(sum)
}
di ""
di "--- did_imputation with cell-isolating wtr() ---"
capture noisily did_imputation y id time gvar_miss, wtr(c33 c45 c57) autosample
matrix W = r(table)
local cw : colnames W
foreach pair in tau_c33:1.0 tau_c45:2.5 tau_c57:4.0 {
    local nm = substr("`pair'",1,strpos("`pair'",":")-1)
    local tr = substr("`pair'",strpos("`pair'",":")+1,.)
    local p : list posof "`nm'" in cw
    if `p' &gt; 0 di "   `nm'  est=" %9.5f W[1,`p'] "   truth=`tr'   diff=" %9.5f W[1,`p']-`tr'
}
</code></pre>
</details>

<details class="code-fold">
<summary><code>ctvar_all.do</code> &mdash; the calendar-time design: covariate trend effects vary with calendar time; every estimator and option</summary>
<pre><code>*-----------------------------------------------------------------------------
*      ctvar_all.do -- the calendar-time design, every command at every option
*-----------------------------------------------------------------------------
* Covariate trend effects vary with calendar time, identically across
* cohorts: conditional parallel trends holds and every outcome model is
* correctly specified cell by cell. Target ES(e) = 2.0 + 0.5 e.
* Writes one CSV row per (regime, pkg, rep, horizon); summarize with
* mcsum.py. Seeds replication r at 90000 + r. Run from the bench/ folder.
*   Usage: stata-mp -b do ctvar_all.do &lt;nunits&gt; &lt;reps&gt; &lt;outfile&gt;
*-----------------------------------------------------------------------------
clear all
set more off
args nunits reps outfile
* replication-package layout puts src/ beside bench/; in the repo checkout it
* sits three levels up -- probe for it
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"
quietly do "simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {
    dgp_ct, n(`nunits') seed(`=90000 + `r'')
    tempfile d
    quietly save "`d'", replace
    foreach pkg in csdid_dr csdid_ipw csdid_reg csdid_dr_nt csdid_ipw_nt csdid_reg_nt jwdid jwdid_uc bjs bjs_wtr dcdh dcdh_tnp lpdid lpdid_rw lpdid_ctl lpdid_rw_ctl sa sa_xt {
        use "`d'", clear
        * the plain lpdid arms run WITHOUT controls: the legacy lpdid branch
        * adds controls(x1 x2) whenever cov is passed, which is the separate
        * lpdid_ctl arm here
        local covopt = cond(inlist("`pkg'", "lpdid", "lpdid_rw"), "", "cov")
        capture sim_est3, pkg(`pkg') regime(balanced) bal(none) `covopt'
        if _rc == 0 &amp; r(ok) == 1 {
            matrix RR = r(R)
            forvalues h = 0/2 {
                local v1 = string(RR[`h'+1,1], "%18.0g")
                local v2 = string(RR[`h'+1,2], "%18.0g")
                file write out "ctvar,`pkg',`r',`h',`v1',`v2'" _n
            }
        }
        else {
            forvalues h = 0/2 {
                file write out "ctvar,`pkg',`r',`h',.,." _n
            }
        }
    }
    if mod(`r', 25) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
</code></pre>
</details>


<details class="code-fold">
<summary><code>cohorthet.do</code> &mdash; cohort-specific treatment-effect heterogeneity in X, all estimators</summary>
<pre><code>*-----------------------------------------------------------------------------
*      cohorthet.do -- cohort-specific treatment-effect heterogeneity in X
*-----------------------------------------------------------------------------
* tau(g,t,X) has cohort-specific coefficients on X and X-by-event-time;
* conditional parallel trends holds. Target ES(e) = 2.516667 + 0.633333 e.
* The appended _nt and sa arms are the pooled-gamma contamination test.
* Writes one CSV row per (regime, pkg, rep, horizon); summarize with
* mcsum.py. Seeds replication r at 90000 + r. Run from the bench/ folder.
*   Usage: stata-mp -b do cohorthet.do &lt;nunits&gt; &lt;reps&gt; &lt;outfile&gt;
*-----------------------------------------------------------------------------
clear all
set more off
args nunits reps outfile
* replication-package layout puts src/ beside bench/; in the repo checkout it
* sits three levels up -- probe for it
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"
quietly do "simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {
    dgp_ch, n(`nunits') seed(`=90000 + `r'')
    tempfile d
    quietly save "`d'", replace
    foreach pkg in csdid_dr csdid_reg jwdid bjs lpdid_rw_ctl dcdh sa csdid_reg_nt csdid_dr_nt sa_xt {
        use "`d'", clear
        capture sim_est3, pkg(`pkg') regime(balanced) bal(none) cov
        if _rc == 0 &amp; r(ok) == 1 {
            matrix RR = r(R)
            forvalues h = 0/2 {
                local v1 = string(RR[`h'+1,1], "%18.0g")
                local v2 = string(RR[`h'+1,2], "%18.0g")
                file write out "cohorthet,`pkg',`r',`h',`v1',`v2'" _n
            }
        }
        else {
            forvalues h = 0/2 {
                file write out "cohorthet,`pkg',`r',`h',.,." _n
            }
        }
    }
    if mod(`r', 25) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
</code></pre>
</details>


<details class="code-fold">
<summary><code>breakhunt.do</code> &mdash; two designs probing lpdid's covariate adjustment: nonlinear-in-X trends, unequal cohort sizes</summary>
<pre><code>*-----------------------------------------------------------------------------
*      breakhunt.do -- designs probing lpdid's covariate adjustment
*-----------------------------------------------------------------------------
* Design B: untreated trend nonlinear in x2 with asymmetric cohort means --
* every linear-outcome model is misspecified while the propensity score
* stays logit-linear, so csdid ipw/dr survive. Target ES(e) = 2.0 + 0.5 e.
* Design C: unequal cohort sizes (50/30/20) with cohort-specific tau(X)
* profiles. Target ES(e) = 2.0945 + 0.556 e (closed form in mcsum.py).
* Writes one CSV row per (regime, pkg, rep, horizon); summarize with
* mcsum.py. Seeds replication r at 90000 + r. Run from the bench/ folder.
*   Usage: stata-mp -b do breakhunt.do &lt;nunits&gt; &lt;reps&gt; &lt;outfile&gt;
*-----------------------------------------------------------------------------
clear all
set more off
args nunits reps outfile
* replication-package layout puts src/ beside bench/; in the repo checkout it
* sits three levels up -- probe for it
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"
quietly do "simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

foreach design in B C {
    forvalues r = 1/`reps' {
        dgp_break, n(`nunits') seed(`=90000 + `r'') design(`design')
        tempfile d
        quietly save "`d'", replace
        foreach pkg in csdid_dr csdid_ipw csdid_reg sa_xt lpdid_rw_ctl jwdid bjs {
            use "`d'", clear
            capture sim_est3, pkg(`pkg') regime(balanced) bal(none) cov
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "break`design',`pkg',`r',`h',`v1',`v2'" _n
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "break`design',`pkg',`r',`h',.,." _n
                }
            }
        }
        if mod(`r', 25) == 0 display "MCPROG design `design' rep `r' of `reps' done"
    }
}
file close out
display "MCDONE `outfile'"
</code></pre>
</details>


<details class="code-fold">
<summary><code>master.do</code> &mdash; the master design: both mechanisms at once, twelve estimator arms, closed-form target</summary>
<pre><code>*-----------------------------------------------------------------------------
*      master.do -- the master design, every command at every option
*-----------------------------------------------------------------------------
* Both mechanisms at once: covariate trend effects nonlinear in calendar
* time (common across cohorts, so conditional parallel trends holds exactly)
* plus cohort-specific treatment-effect heterogeneity in X.
* Closed-form target ES(e) = 2.516667 + 0.633333 e, verified in fielddgp.do.
* Writes one CSV row per (regime, pkg, rep, horizon); summarize with
* mcsum.py. Seeds replication r at 90000 + r. Run from the bench/ folder.
*   Usage: stata-mp -b do master.do &lt;nunits&gt; &lt;reps&gt; &lt;outfile&gt;
*-----------------------------------------------------------------------------
clear all
set more off
args nunits reps outfile
* replication-package layout puts src/ beside bench/; in the repo checkout it
* sits three levels up -- probe for it
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"
quietly do "simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {
    dgp_master, n(`nunits') seed(`=90000 + `r'')
    tempfile d
    quietly save "`d'", replace
    foreach pkg in csdid_reg csdid_dr jwdid jwdid_uc bjs lpdid lpdid_rw lpdid_ctl lpdid_rw_ctl dcdh dcdh_tnp sa sa_xt {
        use "`d'", clear
        * the plain lpdid arms run WITHOUT controls: the legacy lpdid branch
        * adds controls(x1 x2) whenever cov is passed, which is the separate
        * lpdid_ctl arm here
        local covopt = cond(inlist("`pkg'", "lpdid", "lpdid_rw"), "", "cov")
        capture sim_est3, pkg(`pkg') regime(balanced) bal(none) `covopt'
        if _rc == 0 &amp; r(ok) == 1 {
            matrix RR = r(R)
            forvalues h = 0/2 {
                local v1 = string(RR[`h'+1,1], "%18.0g")
                local v2 = string(RR[`h'+1,2], "%18.0g")
                file write out "master,`pkg',`r',`h',`v1',`v2'" _n
            }
        }
        else {
            forvalues h = 0/2 {
                file write out "master,`pkg',`r',`h',.,." _n
            }
        }
    }
    if mod(`r', 25) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
</code></pre>
</details>


<details class="code-fold">
<summary><code>smallnt.do</code> &mdash; comparison groups when the never-treated share is five percent</summary>
<pre><code>*-----------------------------------------------------------------------------
*      smallnt.do -- comparison groups with a five percent never-treated share
*-----------------------------------------------------------------------------
* Never-treated share ~5 percent; three equal treated cohorts, so the
* target stays ES(e) = 2.0 + 0.5 e.
* Writes one CSV row per (regime, pkg, rep, horizon); summarize with
* mcsum.py. Seeds replication r at 90000 + r. Run from the bench/ folder.
*   Usage: stata-mp -b do smallnt.do &lt;nunits&gt; &lt;reps&gt; &lt;outfile&gt;
*-----------------------------------------------------------------------------
clear all
set more off
args nunits reps outfile
* replication-package layout puts src/ beside bench/; in the repo checkout it
* sits three levels up -- probe for it
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"
quietly do "simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {
    dgp_snt, n(`nunits') seed(`=90000 + `r'')
    tempfile d
    quietly save "`d'", replace
    foreach pkg in csdid_dr csdid_dr_nt sa {
        use "`d'", clear
        capture sim_est3, pkg(`pkg') regime(balanced) bal(none) 
        if _rc == 0 &amp; r(ok) == 1 {
            matrix RR = r(R)
            forvalues h = 0/2 {
                local v1 = string(RR[`h'+1,1], "%18.0g")
                local v2 = string(RR[`h'+1,2], "%18.0g")
                file write out "smallnt,`pkg',`r',`h',`v1',`v2'" _n
            }
        }
        else {
            forvalues h = 0/2 {
                file write out "smallnt,`pkg',`r',`h',.,." _n
            }
        }
    }
    if mod(`r', 25) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"
</code></pre>
</details>

<details class="code-fold">
<summary><code>ymiss.do</code> &mdash; row-deletion versus outcome-missing representations of an unbalanced panel</summary>
<pre><code>*-----------------------------------------------------------------------------
*      ymiss.do -- two representations of an unbalanced panel
*-----------------------------------------------------------------------------
* Period-varying missingness applied the same way at the same seeds, either
* by deleting rows or by setting only the outcome to missing (cohort and X
* stay on the roster). Target ES(e) = 2.0 + 0.5 e. All three commands drop
* missing-Y rows internally, so the two representations coincide.
* Writes one CSV row per (regime, pkg, rep, horizon); summarize with
* mcsum.py. Seeds replication r at 90000 + r. Run from the bench/ folder.
*   Usage: stata-mp -b do ymiss.do &lt;nunits&gt; &lt;reps&gt; &lt;outfile&gt;
*-----------------------------------------------------------------------------
clear all
set more off
args nunits reps outfile
* replication-package layout puts src/ beside bench/; in the repo checkout it
* sits three levels up -- probe for it
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"
quietly do "simrun3.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

foreach mode in drop ymiss {
    forvalues r = 1/`reps' {
        dgp_ym, n(`nunits') seed(`=90000 + `r'') mode(`mode')
        tempfile d
        quietly save "`d'", replace
        foreach pkg in csdid_dr jwdid bjs {
            use "`d'", clear
            capture sim_est3, pkg(`pkg') regime(unbalanced) bal(none)
            if _rc == 0 &amp; r(ok) == 1 {
                matrix RR = r(R)
                forvalues h = 0/2 {
                    local v1 = string(RR[`h'+1,1], "%18.0g")
                    local v2 = string(RR[`h'+1,2], "%18.0g")
                    file write out "ymiss_`mode',`pkg',`r',`h',`v1',`v2'" _n
                }
            }
            else {
                forvalues h = 0/2 {
                    file write out "ymiss_`mode',`pkg',`r',`h',.,." _n
                }
            }
        }
        if mod(`r', 25) == 0 display "MCPROG mode `mode' rep `r' of `reps' done"
    }
}
file close out
display "MCDONE `outfile'"
</code></pre>
</details>



## Speed

Timing, with the warmup discarded. The runners hold the data, the clustering and the inference request fixed across packages, and record anything a package refuses rather than substituting something cheaper.

<details class="code-fold">
<summary><code>dgp.do</code> &mdash; the benchmark DGP and the three panel structures used by the timing grid</summary>
<pre><code>* Run from the bench/ folder of the replication package. Not run on its
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
        if `g' &lt;= `t' {
            quietly replace gvar = `g' if u &gt; (`k' - 1) / (`cohorts' + 1) &amp; u &lt;= `k' / (`cohorts' + 1)
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
    quietly generate byte treated = (gvar &gt; 0 &amp; time &gt;= gvar)

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
        quietly summarize gvar if gvar &gt; 0, meanonly
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
    if r(N) &gt; 0 {
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
        quietly drop if drop_u &lt; 0.15
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
end</code></pre>
</details>

<details class="code-fold">
<summary><code>validate.do</code> &mdash; pre-flight checks: every property the benchmark design claims, verified before an estimator sees the data</summary>
<pre><code>* Run from the bench/ folder of the replication package. Not run on its
* own: the drivers load it with -do-.  It defines bench_validate.
* ---------------------------------------------------------------------------
* Validate a generated dataset BEFORE any estimator touches it.
*
* Everything here is a property the design CLAIMS. If a claim fails the run
* aborts, because a silently wrong dataset costs more than a loud failure.
* ---------------------------------------------------------------------------
capture program drop bench_validate
program define bench_validate
    syntax , [QUIET MINCohorts(integer 2)]
    local fail 0

    * 1. no missing values anywhere that matters
    foreach v in id time gvar y {
        quietly count if missing(`v')
        if r(N) &gt; 0 {
            display as error "VALIDATE: `v' has `=r(N)' missing values"
            local fail 1
        }
    }

    * 2. never-treated units must EXIST and have outcomes
    quietly count if gvar == 0
    local nev = r(N)
    if `nev' == 0 {
        display as error "VALIDATE: no never-treated observations"
        local fail 1
    }
    quietly count if gvar == 0 &amp; !missing(y)
    if r(N) != `nev' {
        display as error "VALIDATE: never-treated have missing outcomes (`=`nev'-r(N)' of `nev')"
        local fail 1
    }

    * 3. treated units must exist, in more than one cohort
    quietly levelsof gvar if gvar &gt; 0, local(gs)
    local ng : word count `gs'
    if `ng' &lt; `mincohorts' {
        display as error "VALIDATE: fewer than `mincohorts' treated cohorts"
        local fail 1
    }

    * 4. gvar constant within unit
    tempvar gmin gmax
    quietly bysort id: egen double `gmin' = min(gvar)
    quietly bysort id: egen double `gmax' = max(gvar)
    quietly count if `gmin' != `gmax'
    if r(N) &gt; 0 {
        display as error "VALIDATE: gvar varies within unit for `=r(N)' rows"
        local fail 1
    }

    * 5. every cohort needs a pre-period, or its ATT is not identified
    quietly summarize time, meanonly
    local tmin = r(min)
    foreach g of local gs {
        if `g' &lt;= `tmin' {
            display as error "VALIDATE: cohort `g' has no pre-period (min time `tmin')"
            local fail 1
        }
    }

    * 6. the outcome must actually vary
    quietly summarize y
    if r(sd) == 0 {
        display as error "VALIDATE: outcome is constant"
        local fail 1
    }

    if `fail' {
        display as error "VALIDATE: dataset rejected"
        exit 459
    }
    if "`quiet'" == "" {
        quietly count
        display "VALIDATE ok: `=r(N)' rows, `ng' cohorts, `nev' never-treated rows, no missing"
    }
end</code></pre>
</details>

<details class="code-fold">
<summary><code>runners.do</code> &mdash; one timing runner per package, each given the same data, the same clustering, and the same inference request</summary>
<pre><code>* Run from the bench/ folder of the replication package. Not run on its
* own: the drivers load it with -do-.  It defines bench_csdid, bench_jwdid, bench_bjs, bench_dcdh, bench_lpdid and bench_flexdid.
* ---------------------------------------------------------------------------
* One runner per package. Each takes the SAME dataset and the SAME inference
* request, and returns the event-study coefficients in one shape:
*
*   bench_&lt;pkg&gt;, horizons(#) cluster(varname) [covariates(varlist) mode(string)]
*     -&gt; r(secs)     wall time for the estimation call alone
*     -&gt; r(ok)       1 if it produced coefficients
*     -&gt; r(note)     anything the package refused, dropped, or omitted
*     -&gt; matrix ES   horizon | estimate | se   (rows = horizons 0..H)
*
* mode is one of:
*   pointwise   analytical / asymptotic SEs, pointwise intervals
*   bootstrap   the package's own bootstrap, matched reps where available
*   bands       simultaneous / uniform confidence bands over the event study
*
* Every runner clusters on the same variable. Where a package cannot honour a
* request, the runner records WHY rather than silently substituting something
* else -- a benchmark that quietly downgrades one package's inference and then
* reports it as slower would be worthless.
* ---------------------------------------------------------------------------

capture program drop bench_reset
program define bench_reset, rclass
    capture matrix drop ES
end

* ------------------------------------------------------------------ csdid
capture program drop bench_csdid
program define bench_csdid, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string) STRUCTure(string) METHod(string)]
    if "`mode'" == "" local mode "pointwise"
    if "`structure'" == "" local structure "balanced"

    local inf "analytical"
    if "`mode'" == "bootstrap" local inf "wboot(reps(999) rseed(20260729)) pointwise"
    if "`mode'" == "bands"     local inf "wboot(reps(999) rseed(20260729))"

    * Match what every other package does with an incomplete panel: use all of
    * it. csdid's DEFAULT is bal(full), which drops units not observed in every
    * period -- on a 20-period panel with 15% of rows missing that is 96% of
    * units, and timing the 4% that remain would be a fabricated speed win, not
    * a measurement. rcs declares repeated cross sections, where no unit is
    * followed at all.
    local struct_opt "bal(none)"
    if "`structure'" == "rcs" local struct_opt "rcs"

    timer clear 99
    timer on 99
    local meth_opt = cond("`method'" == "", "", "method(`method')")
    capture noisily csdid y `covariates', ivar(id) time(time) gvar(gvar) ///
        notyet cluster(`cluster') `inf' `struct_opt' `meth_opt'
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    return local note ""
    if `rc' exit

    quietly estat event, window(0 `horizons')
    * e(aggte) is egt | att | se | overall_att | overall_se
    matrix A = e(aggte)
    matrix ES = J(`horizons' + 1, 3, .)
    forvalues k = 1/`horizons' {
        if `k' &gt; rowsof(A) continue
        matrix ES[`k', 1] = A[`k', 1]
        matrix ES[`k', 2] = A[`k', 2]
        matrix ES[`k', 3] = A[`k', 3]
    }
    return scalar overall = A[1, 4]
    return scalar overall_se = A[1, 5]
    return matrix ES = ES
end

* ------------------------------------------------------------------ jwdid
capture program drop bench_jwdid
program define bench_jwdid, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string) STRUCTure(string)]
    if "`mode'" == "" local mode "pointwise"

    * jwdid has no bootstrap and no band option: it reports analytical
    * cluster-robust SEs only. Recorded, not silently substituted.
    local note ""
    if "`mode'" != "pointwise" local note "no bootstrap or band option; analytical SEs only"

    timer clear 99
    timer on 99
    * repeated cross sections: jwdid's documented route is to omit ivar()
    local iv = cond("`structure'" == "rcs", "", "ivar(id)")
    capture noisily jwdid y `covariates', `iv' tvar(time) gvar(gvar) cluster(`cluster')
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    return local note "`note'"
    if `rc' exit

    capture quietly estat event
    if _rc {
        return scalar ok = 0
        return local note "`note'; estat event unavailable"
        exit
    }
    * estat event names columns &lt;level&gt;.__event__, where &lt;level&gt; is an internal
    * recoding of event time and the base (marked "bn") is the e = -1 reference.
    * The offset between level and event time depends on how many pre-periods
    * the panel has, so it MUST be derived from the base column rather than
    * assumed: a hardcoded offset leaves missing coefficients on a panel of a
    * different shape, which would be misread as jwdid failing to estimate
    * them.
    matrix B = r(table)
    matrix ES = J(`horizons' + 1, 3, .)
    local cn : colnames B
    local base = .
    foreach c of local cn {
        if strpos("`c'", "bn.__event__") {
            local base = real(subinstr("`c'", "bn.__event__", "", .))
        }
    }
    if missing(`base') {
        return scalar ok = 0
        return local note "`note'; could not locate the event-time base column"
        exit
    }
    forvalues h = 0/`horizons' {
        local k = `h' + 1
        matrix ES[`k', 1] = `h'
        * The column marked "bn" is Stata's factor-variable base for the
        * DISPLAY, not the event-study reference period: estat event reports
        * post-treatment coefficients only, and that first column IS h = 0.
        * Verified against a known DGP: reading bn as e = -1 shifts every
        * horizon by one and makes jwdid look badly biased when it is not.
        local lev = `base' + `h'
        * h = 0 is the column carrying the "bn" display marker, so its name is
        * &lt;lev&gt;bn.__event__ rather than &lt;lev&gt;.__event__
        local pos : list posof "`lev'.__event__" in cn
        if `pos' == 0 {
            local pos : list posof "`lev'bn.__event__" in cn
        }
        if `pos' &gt; 0 {
            matrix ES[`k', 2] = B[1, `pos']
            matrix ES[`k', 3] = B[2, `pos']
        }
    }
    return matrix ES = ES
end

* --------------------------------------------------------- did_imputation
capture program drop bench_bjs
program define bench_bjs, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string)]
    if "`mode'" == "" local mode "pointwise"

    local note ""
    if "`mode'" != "pointwise" local note "no bootstrap or band option; analytical SEs only"

    local ctrl ""
    if "`covariates'" != "" local ctrl "controls(`covariates')"

    * autosample is BJS's own remedy for observations whose fixed effects it
    * cannot impute. Without it the command refuses outright, so the comparison
    * would have no BJS column at all -- but it means BJS estimates on a
    * SMALLER sample than the others, which the guide must state.
    timer clear 99
    timer on 99
    capture noisily did_imputation y id time gvar_miss, ///
        horizons(0/`horizons') cluster(`cluster') autosample `ctrl'
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    return local note "`note'; autosample drops non-imputable observations"
    if `rc' exit

    matrix B = r(table)
    matrix ES = J(`horizons' + 1, 3, .)
    local k = 0
    forvalues h = 0/`horizons' {
        local k = `k' + 1
        matrix ES[`k', 1] = `h'
        capture matrix ES[`k', 2] = B[1, "tau`h'"]
        capture matrix ES[`k', 3] = B[2, "tau`h'"]
    }
    return matrix ES = ES
end

* ---------------------------------------------------- did_multiplegt_dyn
capture program drop bench_dcdh
program define bench_dcdh, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string)]
    if "`mode'" == "" local mode "pointwise"

    local boot ""
    local note ""
    if "`mode'" == "bootstrap" local boot "bootstrap(999)"
    if "`mode'" == "bands" {
        local boot "bootstrap(999)"
        local note "no simultaneous band option; bootstrap pointwise only"
    }
    local ctrl ""
    if "`covariates'" != "" local ctrl "controls(`covariates')"

    local eff = `horizons' + 1
    timer clear 99
    timer on 99
    capture noisily did_multiplegt_dyn y id time treated, ///
        effects(`eff') cluster(`cluster') `boot' `ctrl' graphoptions(nodraw)
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    return local note "`note'"
    if `rc' exit

    matrix ES = J(`horizons' + 1, 3, .)
    local k = 0
    forvalues h = 0/`horizons' {
        local k = `k' + 1
        local j = `h' + 1
        matrix ES[`k', 1] = `h'
        capture matrix ES[`k', 2] = e(Effect_`j')
        capture matrix ES[`k', 3] = e(se_effect_`j')
    }
    return matrix ES = ES
end

* ------------------------------------------------------------------ lpdid
capture program drop bench_lpdid
program define bench_lpdid, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string)]
    if "`mode'" == "" local mode "pointwise"

    local boot ""
    local note ""
    if "`mode'" == "bootstrap" local boot "bootstrap(999)"
    if "`mode'" == "bands" {
        local boot "bootstrap(999)"
        local note "no simultaneous band option; bootstrap pointwise only"
    }
    local ctrl ""
    if "`covariates'" != "" local ctrl "controls(`covariates')"

    timer clear 99
    timer on 99
    capture noisily lpdid y, unit(id) time(time) treat(treated) ///
        post_window(`horizons') pre_window(3) cluster(`cluster') `boot' `ctrl'
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    return local note "`note'"
    if `rc' exit

    * e(results): rows pre3..pre1, tau0..tauH; cols coefficient se t p ci_low ci_high obs
    capture matrix B = e(results)
    matrix ES = J(`horizons' + 1, 3, .)
    local rn : rownames B
    forvalues h = 0/`horizons' {
        local k = `h' + 1
        matrix ES[`k', 1] = `h'
        local pos : list posof "tau`h'" in rn
        if `pos' &gt; 0 {
            matrix ES[`k', 2] = B[`pos', 1]
            matrix ES[`k', 3] = B[`pos', 2]
        }
    }
    return matrix ES = ES
end

* ------------------------------------------------------------------ flexdid
* Timing-only runner: wall time for the estimation call. flexdid displays its
* overall at estimation time and its r() results are unreachable, so the
* timing needs no extraction machinery.
capture program drop bench_flexdid
program define bench_flexdid, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string) STRUCTure(string)]
    timer clear 99
    timer on 99
    capture quietly flexdid y `covariates', tx(treated) group(gvar) time(time) ///
        specification(lagsandleads) vce(robust)
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    return local note "overall displayed at estimation; no band or bootstrap option"
end</code></pre>
</details>

<details class="code-fold">
<summary><code>time.do</code> &mdash; the timing wrapper: one discarded warmup per package per dataset, then N trials, reported as the median</summary>
<pre><code>* Run from the bench/ folder of the replication package. Not run on its
* own: the drivers load it with -do-.  It defines bench_time.
* ---------------------------------------------------------------------------
* Timing protocol: one warmup per package per dataset, DISCARDED, then N
* trials, reported as the median.
*
* The warmup matters more than it sounds. Measured on 3,200 observations, the
* first csdid call in a session takes 0.709s and every call after it takes
* 0.013s -- a 55x difference that is entirely one-time Mata library loading.
* Timing the first call ranks the packages by how much of their machinery
* happens to be preloaded, which is a fact about the session, not the software.
* On that measurement csdid reads 18x SLOWER than jwdid; warmed, it is 2.5x
* faster.
* ---------------------------------------------------------------------------
capture program drop bench_time
program define bench_time, rclass
    syntax , PKG(string) DATA(string) HORizons(integer) CLuster(varname) ///
        [COVariates(varlist) MODE(string) STRUCTure(string) TRIALS(integer 5)]

    if "`mode'" == "" local mode "pointwise"
    local sopt ""
    if "`pkg'" == "csdid" &amp; "`structure'" != "" local sopt "structure(`structure')"

    * warmup, discarded
    use "`data'", clear
    capture bench_`pkg', horizons(`horizons') cluster(`cluster') ///
        covariates(`covariates') mode(`mode') `sopt'
    if _rc {
        return scalar ok = 0
        return scalar med = .
        return local note "runner error rc=`=_rc'"
        exit
    }
    local ok = r(ok)
    local note "`r(note)'"

    tempname T
    matrix `T' = J(`trials', 1, .)
    forvalues i = 1/`trials' {
        use "`data'", clear
        quietly bench_`pkg', horizons(`horizons') cluster(`cluster') ///
            covariates(`covariates') mode(`mode') `sopt'
        matrix `T'[`i', 1] = r(secs)
    }

    * median of the trials: robust to a single stray scheduling hiccup in a
    * way the mean is not.
    preserve
    clear
    quietly svmat double `T', names(t)
    quietly summarize t1, detail
    local med = r(p50)
    local lo = r(min)
    local hi = r(max)
    restore

    return scalar ok = `ok'
    return scalar med = `med'
    return scalar lo = `lo'
    return scalar hi = `hi'
    return local note "`note'"
end</code></pre>
</details>

<details class="code-fold">
<summary><code>scalebench.do</code> &mdash; the five-tier scaling grid: unbalanced ladder, repeated-cross-section ladder, periods scan, cohorts scan, and the cost of the default inference</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do scalebench.do A
* ---------------------------------------------------------------------------
* scalebench.do -- extended speed-benchmark grid for the comparison article.
*
*   stata-mp -b do scalebench.do &lt;A|B|C|D|E&gt; [smoke]
*
* Five scans, each runnable on its own so the tiers can be sequenced:
*
*   A  UNBALANCED LADDER   n_units in {1e3, 1e4, 1e5}, T=10, G=4, 15% MCAR
*                          csdid bal(full) and bal(none), jwdid,
*                          did_imputation, lpdid
*   B  RCS LADDER          n_per_period in {1e3, 1e4, 1e5}, T=10, G=4
*                          csdid rcs, flexdid, jwdid, did_imputation,
*                          each WITHOUT and WITH the covariate (pkg suffix
*                          _cov).
*   C  PERIODS SCAN        n_units=1e4, T in {5,10,20,40}, G=4, balanced
*   D  COHORTS SCAN        n_units=1e4, T=20, G in {3,6,12,18}, balanced
*   E  DEFAULT'S TRUE COST balanced ladder at the published sizes
*                          n_units in {1e2, 1e3, 1e4, 1e5}, T=10, G=4, timing
*                          csdid as published (analytical) against csdid at its
*                          SHIPPED DEFAULT inference: the multiplier bootstrap
*                          with simultaneous bands. The article's claim that
*                          the full default stays in the same league is a
*                          measurement, not an assertion.
*
* PROTOCOL (the one behind the published tables)
* ----------------------------------------------
* Same dgp.do (bench_dgp / bench_structure), same runners.do, same
* validate.do, same seed 20260729, same design(dynamic), same cluster
* variable cl (= mod(id,50)+1, 50 clusters), same horizons(5) event study,
* same csdid under test (repo src/ado + src/mata, never an installed copy).
* Timing goes through bench_time from time.do: ONE DISCARDED WARMUP per
* package per dataset, then TRIALS timed calls on a freshly reloaded copy of
* the same dataset.
*
* What each published cell is:
*
*   statistic   the MEDIAN of 10 timed trials, after one discarded warmup
*               per package per dataset. min and max go into the note column
*               of every row, so the spread behind each median is visible
*               without re-running anything. At these sizes the spread never
*               exceeded a few hundredths of a second.
*
*   process     one Stata process per TIER, not per cell. The warmup is
*               still discarded per package per dataset, so no package
*               inherits a warm cache from another; what a per-cell process
*               would add is crash isolation. Every call is therefore
*               capture-guarded and a failure is written as a row rather
*               than raised. If a tier dies, re-run the survivors with the
*               optional 3rd/4th args (see ONLYN/ONLYPKG below).
*
* CELL LABELLING
* --------------
* Cells are labelled by the design primitives -- n_units, T, cohorts -- and
* the row count is DERIVED and reported alongside. For repeated cross
* sections n_units means OBSERVATIONS PER PERIOD (bench_structure gives every
* observation its own id), so rows = n_per_period x T. For the unbalanced
* ladder rows ~ 0.85 x n_units x T after the 15% MCAR deletion.
*
* COVARIATES
* ----------
* A package label ending in _cov is the same package on the same dataset with
* covariates(x) added -- x is the single unit-level covariate bench_dgp already
* carries, and each runner handles it the way the published with-covariates
* cells did:
* csdid and jwdid and flexdid take it as a regressor list, did_imputation as
* controls().
*
* CSV: scan, n_units, T, cohorts, rows, pkg, median_seconds, trials, ok, note
* appended to scalebench-results.csv (smoke runs go to scalebench-smoke.csv).
*
* dcdh (did_multiplegt_dyn) is excluded by design: runtime.
* ---------------------------------------------------------------------------
args tier smoke onlyn onlypkg

if !inlist("`tier'", "A", "B", "C", "D", "E") {
    display as error "usage: do scalebench.do &lt;A|B|C|D|E&gt; [smoke] [only_n] [only_pkg]"
    exit 198
}
local issmoke = ("`smoke'" != "" &amp; "`smoke'" != "0" &amp; "`smoke'" != ".")

local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."

quietly do "`B'/dgp.do"
quietly do "`B'/runners.do"
quietly do "`B'/validate.do"
quietly do "`B'/time.do"

global SB_CSV "`B'/scalebench-results.csv"
if `issmoke' global SB_CSV "`B'/scalebench-smoke.csv"
global SB_ONLYN  "`onlyn'"
global SB_ONLYPKG "`onlypkg'"

* Bootstrap draws for the tier-E shipped-default column. 999 matches the reps
* every other bootstrap in this harness uses; csdid's own default is 1000, a
* 0.1% difference in cost. The smoke drops to 99 purely to exercise mechanics,
* and the count is written into every row's note so no timing can be mistaken
* for a 999-draw number.
global SB_BOOTREPS 999
if `issmoke' global SB_BOOTREPS 99

set more off
set rmsg off

* ---------------------------------------------------------------------------
* Extra runners. Both are thin wrappers so runners.do -- the file the
* published numbers came from -- is not touched.
*
* bench_csdidbf   csdid at its SHIPPED DEFAULT, bal(full). Identical to
*                 bench_csdid in every other respect. bench_csdid overrides
*                 the default to bal(none) so that csdid uses the same rows
*                 as the rivals; scan A times both, because the difference
*                 between them IS the thing scan A is measuring.
* bench_jwdidrcs  bench_jwdid with structure(rcs) forced. bench_time only
*                 forwards structure() when pkg is csdid, and jwdid's
*                 documented repeated-cross-section route is to omit ivar();
*                 without this wrapper jwdid would be recorded UNSUPPORTED on
*                 RCS data.
* ---------------------------------------------------------------------------
capture program drop bench_csdidbf
program define bench_csdidbf, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string) STRUCTure(string) METHod(string)]
    if "`mode'" == "" local mode "pointwise"

    local inf "analytical"
    if "`mode'" == "bootstrap" local inf "wboot(reps(999) rseed(20260729)) pointwise"
    if "`mode'" == "bands"     local inf "wboot(reps(999) rseed(20260729))"

    * NO bal() option: whatever csdid ships as its default is what is timed.
    local meth_opt = cond("`method'" == "", "", "method(`method')")
    timer clear 99
    timer on 99
    capture noisily csdid y `covariates', ivar(id) time(time) gvar(gvar) ///
        notyet cluster(`cluster') `inf' `meth_opt'
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    return local note "csdid shipped default bal(full)"
    if `rc' exit

    * extraction only; the timer is already off, so nothing here can move a
    * reported number
    capture quietly estat event, window(0 `horizons')
    if _rc {
        return local note "csdid shipped default bal(full); estat event rc=`=_rc'"
        exit
    }
    matrix A = e(aggte)
    matrix ES = J(`horizons' + 1, 3, .)
    forvalues k = 1/`horizons' {
        if `k' &gt; rowsof(A) continue
        matrix ES[`k', 1] = A[`k', 1]
        matrix ES[`k', 2] = A[`k', 2]
        matrix ES[`k', 3] = A[`k', 3]
    }
    return matrix ES = ES
end

capture program drop bench_csdidpair
program define bench_csdidpair, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string) STRUCTure(string) METHod(string)]
    if "`mode'" == "" local mode "pointwise"

    local inf "analytical"
    if "`mode'" == "bootstrap" local inf "wboot(reps(999) rseed(20260729)) pointwise"
    if "`mode'" == "bands"     local inf "wboot(reps(999) rseed(20260729))"

    * bal(pair): balance each 2x2 separately, Version 1.82's estimand.
    local meth_opt = cond("`method'" == "", "", "method(`method')")
    timer clear 99
    timer on 99
    capture noisily csdid y `covariates', ivar(id) time(time) gvar(gvar) ///
        notyet cluster(`cluster') bal(pair) `inf' `meth_opt'
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    return local note "csdid bal(pair), per-comparison balancing"
    if `rc' exit

    * extraction only; the timer is already off, so nothing here can move a
    * reported number
    capture quietly estat event, window(0 `horizons')
    if _rc {
        return local note "csdid bal(pair), per-comparison balancing; estat event rc=`=_rc'"
        exit
    }
    matrix A = e(aggte)
    matrix ES = J(`horizons' + 1, 3, .)
    forvalues k = 1/`horizons' {
        if `k' &gt; rowsof(A) continue
        matrix ES[`k', 1] = A[`k', 1]
        matrix ES[`k', 2] = A[`k', 2]
        matrix ES[`k', 3] = A[`k', 3]
    }
    return matrix ES = ES
end

* bench_csdidboot  csdid at its SHIPPED DEFAULT INFERENCE: the multiplier
*                  bootstrap with SIMULTANEOUS bands. csdid's own message is
*                  explicit that "omitting both uses the bootstrap, the
*                  default", at biters 1000; reps are pinned at $SB_BOOTREPS
*                  (999) so the draw count matches every other bootstrap in
*                  this harness and the seed is fixed. wboot() WITHOUT
*                  pointwise is the uniform-band path, which is the same thing
*                  bench_csdid calls mode(bands). bal() is left at its default
*                  too -- tier E is balanced, so that selects the same rows as
*                  the published bal(none) column. On this machine the macOS
*                  bootstrap accelerator plugin ships with the package and is
*                  active; e(bootstrap_accelerator) is read back after the
*                  timed call and written into the note, so the configuration
*                  is recorded rather than assumed.
capture program drop bench_csdidboot
program define bench_csdidboot, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string) STRUCTure(string) METHod(string)]
    local reps = 999
    if "$SB_BOOTREPS" != "" local reps = $SB_BOOTREPS
    local meth_opt = cond("`method'" == "", "", "method(`method')")

    timer clear 99
    timer on 99
    capture noisily csdid y `covariates', ivar(id) time(time) gvar(gvar) ///
        notyet cluster(`cluster') wboot(reps(`reps') rseed(20260729)) `meth_opt'
    local rc = _rc
    timer off 99
    quietly timer list 99
    local secs = r(t99)

    local acc "`e(bootstrap_accelerator)'"
    local accst "`e(bootstrap_accelerator_status)'"
    local accsec = .
    capture local accsec = e(bootstrap_accelerator_seconds)
    local accstr = trim(string(`accsec', "%12.4f"))

    return scalar secs = `secs'
    return scalar ok = (`rc' == 0)
    return local note "shipped-default inference: wboot reps(`reps') rseed(20260729) simultaneous bands; accelerator=`acc'/`accst' accel_secs=`accstr'"
    if `rc' exit

    capture quietly estat event, window(0 `horizons')
    if _rc {
        return local note "shipped-default inference: wboot reps(`reps') simultaneous bands; accelerator=`acc'/`accst'; estat event rc=`=_rc'"
        exit
    }
    matrix A = e(aggte)
    matrix ES = J(`horizons' + 1, 3, .)
    forvalues k = 1/`horizons' {
        if `k' &gt; rowsof(A) continue
        matrix ES[`k', 1] = A[`k', 1]
        matrix ES[`k', 2] = A[`k', 2]
        matrix ES[`k', 3] = A[`k', 3]
    }
    return matrix ES = ES
end

capture program drop bench_jwdidrcs
program define bench_jwdidrcs, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string) STRUCTure(string)]
    local copt = cond("`covariates'" == "", "", "covariates(`covariates')")
    local mopt = cond("`mode'" == "", "", "mode(`mode')")
    bench_jwdid, horizons(`horizons') cluster(`cluster') `copt' `mopt' structure(rcs)
    return scalar secs = r(secs)
    return scalar ok = r(ok)
    return local note "`r(note)'"
end

* ---------------------------------------------------------------------------
* One CSV row. Opened and closed per row so a killed run still leaves every
* completed cell on disk.
* ---------------------------------------------------------------------------
capture program drop sb_write
program define sb_write
    syntax , SCAN(string) N(integer) T(integer) G(integer) ROWS(real) ///
        PKG(string) MED(string) TRIALS(integer) OK(integer) [NOTE(string)]

    local note = subinstr("`note'", ",", ";", .)
    local note = subinstr("`note'", `"""', "", .)

    tempname fh
    capture confirm file "$SB_CSV"
    if _rc {
        file open `fh' using "$SB_CSV", write text replace
        file write `fh' "scan,n_units,T,cohorts,rows,pkg,median_seconds,trials,ok,note" _n
        file close `fh'
    }
    file open `fh' using "$SB_CSV", write text append
    file write `fh' "`scan',`n',`t',`g',`=`rows'',`pkg',`med',`trials',`ok',`note'" _n
    file close `fh'
end

* ---------------------------------------------------------------------------
* One cell: one (scan, n_units, T, cohorts, structure) dataset, every package
* timed on THAT dataset, one row written per package.
* ---------------------------------------------------------------------------
capture program drop sb_cell
program define sb_cell
    syntax , SCAN(string) N(integer) T(integer) G(integer) STRUCTure(string) ///
        PKGS(string) TRIALS(integer)

    if "$SB_ONLYN" != "" &amp; "$SB_ONLYN" != "`n'" exit

    * ---- data: the published DGP, the published seed, nothing else
    quietly bench_dgp, design(dynamic) n(`n') t(`t') seed(20260729) cohorts(`g')
    quietly bench_structure, structure(`structure') seed(20260729)
    quietly generate int gvar_miss = gvar
    quietly replace gvar_miss = . if gvar == 0
    local rows = _N

    * realized cohort structure. bench_dgp places cohorts at consecutive dates
    * starting at floor(T/3)+1 and silently skips any adoption date past T, so
    * a REQUESTED cohort count larger than the treatable span becomes a smaller
    * realized count plus a larger never-treated share. Recorded, not assumed.
    quietly levelsof gvar if gvar &gt; 0, local(gs)
    local greal : word count `gs'
    quietly count if gvar == 0
    local nev = r(N)
    local nevpct = round(100 * `nev' / `rows', 0.1)

    * horizons: the published tables use 5. A 5-period panel cannot support
    * five post-periods, so the horizon is capped at what the panel has and the
    * cap is written into the note (it enters the timed call for
    * did_imputation and lpdid, so it must be visible).
    local first_g = floor(`t' / 3) + 1
    local hmax = `t' - `first_g'
    local h = min(5, `hmax')
    if `h' &lt; 1 local h = 1

    * the input is checked before any estimator sees it
    capture bench_validate, quiet
    if _rc {
        foreach pkg of local pkgs {
            sb_write, scan(`scan') n(`n') t(`t') g(`g') rows(`rows') pkg(`pkg') ///
                med(.) trials(`trials') ok(0) note(dataset rejected by bench_validate rc=`=_rc')
        }
        clear
        exit
    }

    tempfile d
    quietly save "`d'", replace
    display as text "SB CELL `scan' n=`n' T=`t' G=`g' (realized `greal') rows=`rows' H=`h'"

    foreach pkg of local pkgs {
        if "$SB_ONLYPKG" != "" &amp; "$SB_ONLYPKG" != "`pkg'" continue

        * a _cov suffix is the same package with the DGP's covariate added
        local base "`pkg'"
        local copt ""
        local covnote "cov=none"
        if substr("`pkg'", -4, 4) == "_cov" {
            local base = substr("`pkg'", 1, length("`pkg'") - 4)
            local copt "covariates(x)"
            local covnote "cov=x"
        }

        * package label -&gt; runner program, plus the structure the runner needs
        local runner "`base'"
        local sopt ""
        local extra ""
        if "`base'" == "csdid_balfull" {
            local runner "csdidbf"
            local extra "bal(full) is the shipped default; drops units not observed in every period"
        }
        if "`base'" == "csdid_balpair" {
            local runner "csdidpair"
            local extra "bal(pair): per-comparison balancing, Version 1.82's estimand"
        }
        if "`base'" == "csdid_balnone" {
            local runner "csdid"
            local extra "bal(none); same rows as the rivals"
        }
        if "`base'" == "csdid_analytical" {
            local runner "csdid"
            local extra "as published in the speed tables: analytical clustered SEs"
        }
        if "`base'" == "csdid_boot999" local runner "csdidboot"
        if "`base'" == "did_imputation" local runner "bjs"
        if "`base'" == "jwdid" &amp; "`structure'" == "rcs" local runner "jwdidrcs"
        if "`runner'" == "csdid" &amp; "`structure'" == "rcs" local sopt "structure(rcs)"

        local med = .
        local lo = .
        local hi = .
        local ok = 0
        local rnote ""

        capture noisily bench_time, pkg(`runner') data("`d'") horizons(`h') ///
            cluster(cl) trials(`trials') `copt' `sopt'
        local rc = _rc
        if `rc' {
            local rnote "harness error rc=`rc'"
        }
        else {
            capture local ok = r(ok)
            capture local med = r(med)
            capture local lo = r(lo)
            capture local hi = r(hi)
            local rnote "`r(note)'"
        }

        local medstr = trim(string(`med', "%14.4f"))
        local lostr  = trim(string(`lo',  "%14.4f"))
        local histr  = trim(string(`hi',  "%14.4f"))
        local note "H=`h'; G_real=`greal'; nevertreated=`nevpct'%; `covnote'; min=`lostr'; max=`histr'"
        if "`extra'" != "" local note "`note'; `extra'"
        if "`rnote'" != "" local note "`note'; `rnote'"

        sb_write, scan(`scan') n(`n') t(`t') g(`g') rows(`rows') pkg(`pkg') ///
            med(`medstr') trials(`trials') ok(`ok') note(`note')
        display as text "SB ROW  `scan' n=`n' T=`t' G=`g' rows=`rows' `pkg' med=`medstr' ok=`ok'"
    }
    clear
    capture matrix drop ES A B
end

* ---------------------------------------------------------------------------
* The grids.
* ---------------------------------------------------------------------------
local trials = 10
if `issmoke' local trials = 1

display as text "SB START tier=`tier' smoke=`issmoke' trials=`trials' csv=$SB_CSV"

* ---- A. unbalanced ladder: T=10, G=4, 15% MCAR row deletion (bench_structure
*         unbalanced, seed 20260729 -&gt; runiform() &lt; 0.15 dropped). Rows land at
*         ~0.85 x n x T: 8.5k / 85k / 850k.
if "`tier'" == "A" {
    local ns "1000 10000 100000"
    if `issmoke' local ns "200"
    foreach n of local ns {
        sb_cell, scan(A_unbal) n(`n') t(10) g(4) structure(unbalanced) trials(`trials') ///
            pkgs(csdid_balfull csdid_balpair csdid_balnone jwdid did_imputation lpdid)
    }
}

* ---- B. repeated cross sections: n_units = observations per period, T=10,
*         G=4 -- the structure behind the published RCS table.
*         Rows = n x T: 10k / 100k / 1M.
*
*         Every package runs twice per size: without and with the covariate.
*         The published RCS table prints a dash for jwdid-with-covariates; a
*         live functional check has since confirmed jwdid runs on RCS data
*         with covariates and returns estat event cleanly, so the dash was a
*         missing measurement, not a package limitation. It is measured here.
if "`tier'" == "B" {
    local ns "1000 10000 100000"
    if `issmoke' local ns "200"
    foreach n of local ns {
        sb_cell, scan(B_rcs) n(`n') t(10) g(4) structure(rcs) trials(`trials') ///
            pkgs(csdid flexdid jwdid did_imputation ///
                 csdid_cov flexdid_cov jwdid_cov did_imputation_cov)
    }
}

* ---- C. periods scan: n_units fixed, T varies. On a balanced panel bal(none)
*         and bal(full) select the same rows, so one csdid column suffices and
*         it is the same runner the published tables used.
if "`tier'" == "C" {
    local n = 10000
    local ts "5 10 20 40"
    if `issmoke' {
        local n = 200
        local ts "5 10"
    }
    foreach t of local ts {
        sb_cell, scan(C_periods) n(`n') t(`t') g(4) structure(balanced) trials(`trials') ///
            pkgs(csdid jwdid did_imputation lpdid)
    }
}

* ---- D. cohorts scan: T=20 fixed, requested cohort count varies. Adoption
*         dates are consecutive from period 7; requests past period 20 fall
*         outside the panel and become never-treated, so G_real and the
*         never-treated share are written into every row.
if "`tier'" == "D" {
    local n = 10000
    local gs "3 6 12 18"
    if `issmoke' {
        local n = 200
        local gs "3 6"
    }
    foreach g of local gs {
        sb_cell, scan(D_cohorts) n(`n') t(20) g(`g') structure(balanced) trials(`trials') ///
            pkgs(csdid jwdid did_imputation lpdid)
    }
}

* ---- E. the default's true cost: the published balanced ladder (rows 1k /
*         10k / 100k / 1M), two configurations of the same command on the same
*         data -- csdid as the speed tables report it (analytical, clustered)
*         and csdid at its shipped default inference (999 multiplier bootstrap
*         draws, simultaneous bands, clustered), each followed by the same
*         estat event window. The gap between the two columns IS the price of
*         the default, measured rather than asserted.
if "`tier'" == "E" {
    local ns "100 1000 10000 100000"
    if `issmoke' local ns "200"
    foreach n of local ns {
        sb_cell, scan(E_default) n(`n') t(10) g(4) structure(balanced) trials(`trials') ///
            pkgs(csdid_analytical csdid_boot999)
    }
}

display as text "SB DONE tier=`tier' smoke=`issmoke'"</code></pre>
</details>

<details class="code-fold">
<summary><code>scalebench_f_cell.do</code> &mdash; one Version 1.82 vs 2.0.0 cell in its own Stata process, because the two versions share a command name and cannot share an adopath</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do scalebench_f_cell.do csdid_182 F_n 1000 10 4 balanced 7 out.csv
* ---------------------------------------------------------------------------
* Tier F, ONE cell, ONE implementation, ONE Stata process.
*
*   stata-mp -b do scalebench_f_cell.do &lt;impl&gt; &lt;scan&gt; &lt;n&gt; &lt;t&gt; &lt;g&gt; &lt;structure&gt; &lt;trials&gt; &lt;csv&gt;
*     impl = csdid_182 | csdid_200
*
* Why this is a separate file rather than a tier inside scalebench.do:
* 1.82 and 2.0 are both called `csdid`. They cannot coexist on one adopath,
* and a program already loaded in a session does not reload when the path
* changes, so each implementation must be timed in a fresh process.
*
* WORKLOAD (same in both versions, each written in its own syntax):
*
*   1.82  csdid y x, ivar(id) time(time) gvar(gvar) method(dripw)
*                    cluster(cl) agg(event)
*   2.0   csdid y x, ivar(id) time(time) gvar(gvar) method(dr) analytical
*                    cluster(cl) agg(event) nevertreated base_period(varying)
*
* The pinning matters: 1.82's defaults are never-treated controls and a
* varying base period, 2.0's are not-yet-treated and universal, so 2.0 must be
* pinned to 1.82's defaults or the two stop computing the same thing and the
* ratio stops meaning anything. 1.82 has no
* `analytical` option because analytical IS its default, and its doubly robust
* estimator is spelled `dripw` where 2.0 spells it `dr`.
*
* Scheme handling:
*   unbalanced  2.0 gets bal(pair). 1.82 balances each 2x2 separately and has
*               no bal() option at all; bal(pair) is that mode, so this is a
*               true like-for-like rather than an approximation.
*   rcs         1.82 has no rcs option; its repeated-cross-section route is to
*               OMIT ivar(). 2.0 has an explicit rcs option. Whether 1.82
*               actually completes is determined by running it, not assumed.
*
* NOTE: tier F's csdid_200 column is NOT comparable to tier E's csdid_analytical
* column. Tier E times the shipped defaults (notyet, universal base period);
* tier F pins 2.0 to 1.82's defaults so the A/B is like-for-like. Different
* estimand, different work, different number.
* ---------------------------------------------------------------------------
* REQUIREMENTS: a checkout of csdid Version 1.82 at ../csdid-182, pinned to
* its released commit fdbae255, and drdid 1.91 or later on the adopath. Both
* are checked below and neither is installed by this script.
args impl scan n t g structure trials csv

if !inlist("`impl'", "csdid_182", "csdid_200") {
    display as error "impl must be csdid_182 or csdid_200"
    exit 198
}

local root ".."
local legacy "../csdid-182"
local B "."

* ---- adopath: exactly one implementation is reachable, and it is asserted
if "`impl'" == "csdid_200" {
    adopath ++ "`root'/src/ado"
    adopath ++ "`root'/src/mata"
}
else {
    adopath ++ "`legacy'/codes"
    * 1.82 refuses to run without drdid &gt;= 1.91. This checks for it and errors
    * rather than installing.
    capture which drdid
    if _rc {
        display as error "legacy baseline requires drdid on the Stata adopath"
        exit 499
    }
}
findfile csdid.ado
local resolved = subinstr("`r(fn)'", "\\", "/", .)
if "`impl'" == "csdid_200" {
    assert strpos("`resolved'", "`root'/src/ado/csdid.ado") &gt; 0
}
else {
    assert strpos("`resolved'", "`legacy'/codes/csdid.ado") &gt; 0
}
display as text "F RESOLVED `impl' -&gt; `resolved'"

quietly do "`B'/dgp.do"
quietly do "`B'/validate.do"
quietly do "`B'/time.do"

* ---- the two runners. Same shape as runners.do so bench_time drives them.
* The scheme travels in a GLOBAL, not in the structure() option: bench_time
* forwards structure() only when pkg is literally "csdid", so a runner under
* any other name never sees it. Without the global, 2.0 would run the RCS cell
* at its default bal(full) and the unbalanced cell without bal(pair), which
* would report a speed win taken on a smaller sample.
capture program drop bench_c182
program define bench_c182, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string) STRUCTure(string)]
    if "$F_STRUCT" != "" local structure "$F_STRUCT"
    local iv "ivar(id)"
    if "`structure'" == "rcs" local iv ""
    timer clear 99
    timer on 99
    capture noisily csdid y `covariates', `iv' time(time) gvar(gvar) ///
        method(dripw) cluster(`cluster') agg(event)
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    return local note "1.82 method(dripw) agg(event) clustered; analytical is its default"
    if `rc' return local note "1.82 method(dripw) agg(event) clustered; FAILED rc=`rc'"
end

capture program drop bench_c200
program define bench_c200, rclass
    syntax , HORizons(integer) CLuster(varname) [COVariates(varlist) MODE(string) STRUCTure(string)]
    if "$F_STRUCT" != "" local structure "$F_STRUCT"
    * pinned to 1.82's defaults so the comparison is like-for-like
    local cpin "nevertreated base_period(varying)"
    if "`structure'" == "unbalanced" local cpin "`cpin' bal(pair)"
    if "`structure'" == "rcs"        local cpin "`cpin' rcs"
    timer clear 99
    timer on 99
    capture noisily csdid y `covariates', ivar(id) time(time) gvar(gvar) ///
        method(dr) analytical cluster(`cluster') agg(event) `cpin'
    local rc = _rc
    timer off 99
    quietly timer list 99
    return scalar secs = r(t99)
    return scalar ok = (`rc' == 0)
    return local note "2.0 method(dr) analytical agg(event) clustered; pinned `cpin'"
    if `rc' return local note "2.0 method(dr) analytical agg(event) clustered; pinned `cpin'; FAILED rc=`rc'"
end

* ---- one CSV row, same schema as scalebench.do
capture program drop f_write
program define f_write
    syntax , SCAN(string) N(integer) T(integer) G(integer) ROWS(real) ///
        PKG(string) MED(string) TRIALS(integer) OK(integer) [NOTE(string)]
    local note = subinstr("`note'", ",", ";", .)
    local note = subinstr("`note'", `"""', "", .)
    tempname fh
    capture confirm file "$F_CSV"
    if _rc {
        file open `fh' using "$F_CSV", write text replace
        file write `fh' "scan,n_units,T,cohorts,rows,pkg,median_seconds,trials,ok,note" _n
        file close `fh'
    }
    file open `fh' using "$F_CSV", write text append
    file write `fh' "`scan',`n',`t',`g',`=`rows'',`pkg',`med',`trials',`ok',`note'" _n
    file close `fh'
end

global F_CSV "`csv'"
global F_STRUCT "`structure'"

* ---- data: the scalebench primitives, the published DGP, the published seed
quietly bench_dgp, design(dynamic) n(`n') t(`t') seed(20260729) cohorts(`g')
quietly bench_structure, structure(`structure') seed(20260729)
local rows = _N
quietly levelsof gvar if gvar &gt; 0, local(gs)
local greal : word count `gs'
quietly count if gvar == 0
local nevpct = round(100 * r(N) / `rows', 0.1)
local first_g = floor(`t' / 3) + 1
local hmax = `t' - `first_g'
local h = min(5, `hmax')
if `h' &lt; 1 local h = 1

capture bench_validate, quiet
if _rc {
    f_write, scan(`scan') n(`n') t(`t') g(`g') rows(`rows') pkg(`impl') ///
        med(.) trials(`trials') ok(0) note(dataset rejected by bench_validate)
    exit
}

tempfile d
quietly save "`d'", replace

local runner = cond("`impl'" == "csdid_182", "c182", "c200")
local med = .
local lo = .
local hi = .
local ok = 0
local rnote ""
capture noisily bench_time, pkg(`runner') data("`d'") horizons(`h') ///
    cluster(cl) covariates(x) trials(`trials') structure(`structure')
local rc = _rc
if `rc' {
    local rnote "harness error rc=`rc'"
}
else {
    capture local ok = r(ok)
    capture local med = r(med)
    capture local lo = r(lo)
    capture local hi = r(hi)
    local rnote "`r(note)'"
}

local medstr = trim(string(`med', "%14.4f"))
local lostr  = trim(string(`lo',  "%14.4f"))
local histr  = trim(string(`hi',  "%14.4f"))
local note "H=`h'; G_real=`greal'; nevertreated=`nevpct'%; scheme=`structure'; cov=x; min=`lostr'; max=`histr'; `rnote'"

f_write, scan(`scan') n(`n') t(`t') g(`g') rows(`rows') pkg(`impl') ///
    med(`medstr') trials(`trials') ok(`ok') note(`note')
display as text "F ROW `scan' `impl' n=`n' T=`t' G=`g' rows=`rows' med=`medstr' ok=`ok' trials=`trials'"</code></pre>
</details>

<details class="code-fold">
<summary><code>scalebench_f.sh</code> &mdash; the Version 1.82 comparison launcher: the trial-count policy and the 120-second skip rule that decide how many times each legacy cell is timed</summary>
<pre><code>#!/usr/bin/env bash
# Run from the bench/ folder of the replication package.
# Usage:  bash scalebench_f.sh
# ---------------------------------------------------------------------------
# Tier F: csdid 1.82 against csdid 2.0, one fresh Stata process per (cell,
# implementation) because the two versions are both called `csdid` and cannot
# share an adopath.
#
# Appends a progress line per sub-scan.
#
# TRIALS POLICY (stated per row in the CSV's trials column):
#   csdid_200  7 trials everywhere, never reduced.
#   csdid_182  7 / 5 / 3 / 2 as its projected per-call cost crosses 3s / 10s /
#              30s / 120s, and SKIPPED above 120s with a recorded row.
# The projection is L200(T,G) x (0.7 + 0.00126 n) / 0.952 / 1.21, fitted to the
# smoke: legacy is linear in n over 2k-100k rows (1.19s / 2.01s / 3.31s /
# 13.27s at n = 200 / 1000 / 2000 / 10000, T=10, G=4), and the 1.21 calibrates
# the fit's 21% over-prediction at n=10000. Each launch also carries a hard
# timeout so a projection that is wrong cannot run away with the wall clock.
# ---------------------------------------------------------------------------
set -u
B="."
STATA=/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp
CSV="$B/scalebench-results.csv"
PROG="$B/scalebench-progress.txt"
cd "$B"

echo "TIER F start $(date +%H:%M)" &gt;&gt; "$PROG"

skip_row () { # scan n t g rows pkg note
  printf '%s,%s,%s,%s,%s,%s,.,0,0,%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" &gt;&gt; "$CSV"
}

run_cell () { # impl scan n t g structure trials cap
  local impl=$1 scan=$2 n=$3 t=$4 g=$5 st=$6 tr=$7 cap=$8
  timeout "$cap" "$STATA" -b do scalebench_f_cell.do "$impl" "$scan" "$n" "$t" "$g" "$st" "$tr" "$CSV" &gt;/dev/null 2&gt;&amp;1
  local rc=$?
  if [ $rc -ne 0 ]; then
    local rows=$((n * t))
    skip_row "$scan" "$n" "$t" "$g" "$rows" "$impl" "launch failed or exceeded the ${cap}s cap; rc=$rc"
  fi
}

# csdid_200 first in every cell, so a legacy overrun never costs us the 2.0 row.
pair () { # scan n t g structure legacy_trials legacy_cap
  run_cell csdid_200 "$1" "$2" "$3" "$4" "$5" 7 900
  run_cell csdid_182 "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

# ---- F_n: the n ladder, T=10, G=4, balanced
pair F_n   1000  10 4 balanced 7 300
pair F_n   5000  10 4 balanced 5 400
pair F_n  20000  10 4 balanced 3 600
pair F_n  50000  10 4 balanced 2 900
# 2.0 always runs the 1M-row rung; legacy only if the MEASURED 500k rung
# projects under the 120s cap (rows double, so the projection is ~2.05x).
run_cell csdid_200 F_n 100000 10 4 balanced 7 1200
L50=$(awk -F, '$1=="F_n" &amp;&amp; $2=="50000" &amp;&amp; $6=="csdid_182" {print $7}' "$CSV" | tail -1)
if [ -n "${L50:-}" ] &amp;&amp; awk "BEGIN{exit !($L50 &gt; 0 &amp;&amp; $L50 * 2.05 &lt;= 120)}"; then
  run_cell csdid_182 F_n 100000 10 4 balanced 2 1200
else
  skip_row F_n 100000 10 4 1000000 csdid_182 \
    "skipped by the 120s cap; projection basis: measured 500k legacy call ${L50:-NA}s x 2.05 rows"
fi
echo "F_n done $(date +%H:%M)" &gt;&gt; "$PROG"

# ---- F_T: periods scan, n=5000, G=4, balanced
pair F_T 5000  5 4 balanced 7 300
pair F_T 5000 10 4 balanced 5 400
pair F_T 5000 20 4 balanced 3 600
pair F_T 5000 40 4 balanced 2 900
echo "F_T done $(date +%H:%M)" &gt;&gt; "$PROG"

# ---- F_G: cohorts scan, n=5000, T=20, balanced
pair F_G 5000 20  3 balanced 3 600
pair F_G 5000 20  6 balanced 3 700
pair F_G 5000 20 12 balanced 2 900
echo "F_G done $(date +%H:%M)" &gt;&gt; "$PROG"

# ---- F_scheme: n=10000, T=10, G=4, three sampling schemes
pair F_scheme 10000 10 4 balanced   3 600
pair F_scheme 10000 10 4 unbalanced 3 600
pair F_scheme 10000 10 4 rcs        3 600
echo "F_scheme done $(date +%H:%M)" &gt;&gt; "$PROG"

echo "TIER F DONE $(date +%H:%M) rows=$(wc -l &lt; "$CSV")" &gt;&gt; "$PROG"</code></pre>
</details>

<details class="code-fold">
<summary><code>rcstime.do</code> &mdash; the repeated-cross-section timing probe, best of three trials at two sizes</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do rcstime.do
local root ".."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
do "`B'/dgp.do"
do "`B'/runners.do"

foreach n in 5000 20000 {
    bench_dgp, design(dynamic) n(`n') t(20) seed(20260729) cohorts(12)
    bench_structure, structure(rcs) seed(20260729)
    generate int gvar_miss = gvar
    replace gvar_miss = . if gvar == 0
    local rows = _N
    tempfile d
    save "`d'", replace
    di "SCALE rcs rows=`rows'"
    foreach pkg in csdid bjs dcdh jwdid lpdid {
        local sopt ""
        if "`pkg'" == "csdid" local sopt "structure(rcs)"
        * warmup, discarded
        use "`d'", clear
        capture bench_`pkg', horizons(5) cluster(cl) `sopt'
        local wok = _rc
        if `wok' != 0 | r(ok) == 0 {
            di "TIMED rcs `rows' `pkg' UNSUPPORTED"
        }
        else {
            local best = .
            forvalues i = 1/3 {
                use "`d'", clear
                quietly bench_`pkg', horizons(5) cluster(cl) `sopt'
                local s = r(secs)
                if `s' &lt; `best' local best = `s'
            }
            di "TIMED rcs `rows' `pkg' best=" %8.4f `best'
        }
    }
}</code></pre>
</details>

<details class="code-fold">
<summary><code>mbench.do</code> &mdash; cost of pushing an n-row matrix across the Mata/Stata boundary, and of Stata-side copies of it</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do mbench.do
* Cost of an n-row matrix crossing the Mata &lt;-&gt; Stata matrix boundary,
* and of Stata-side copies of it. No csdid code involved.
foreach n in 25000 50000 100000 {
    timer clear 1
    timer on 1
    mata: st_matrix("X", J(`n', 10, 1))
    timer off 1
    timer clear 2
    timer on 2
    matrix Y = X
    timer off 2
    timer clear 3
    timer on 3
    matrix colnames X = a b c d e f g h i j
    timer off 3
    quietly timer list
    di "MB n=`n'  st_matrix_write=" %8.2f r(t1) "  stata_copy=" %8.2f r(t2) "  colnames=" %8.2f r(t3)
    matrix drop X Y
}</code></pre>
</details>

<details class="code-fold">
<summary><code>mbench2.do</code> &mdash; cost of reading a Stata matrix back into Mata</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do mbench2.do
foreach n in 12500 25000 50000 {
    mata: st_matrix("X", J(`n', 4, 1))
    timer clear 1
    timer on 1
    mata: __r = st_matrix("X")
    timer off 1
    mata: mata drop __r
    quietly timer list
    di "MB2 n=`n'  read_into_mata=" %8.2f r(t1)
    matrix drop X
}</code></pre>
</details>


## Analysis

These scripts turn the raw per-replication and per-cell CSVs into the tables in the guide. Nothing here estimates anything; each one only summarises a file the arms above wrote.

<details class="code-fold">
<summary><code>mcsum.py</code> &mdash; the analyzer: bias, SD, RMSE, mean standard error and 95% coverage against the fixed population targets, per event time, per ATT(g,t) cell, with the count of replications each command could and could not estimate</summary>
<pre><code>#!/usr/bin/env python3
# Run from the bench/ folder of the replication package.
# Usage:  python3 mcsum.py &lt;results.csv&gt;
"""Monte Carlo summary: bias/SD/RMSE/coverage against FIXED population
targets. Truth is never re-derived from the draws.

Reads one row per (regime, package, rep, horizon) from a simulation CSV and
prints, for each event-study horizon and for the post-treatment average,
the bias against the population target, the spread across draws, the mean
reported standard error, and the coverage of nominal 95% intervals.

Horizon codes: 0/1/2 are event times, 99 is the post-treatment average, and
any code &gt;= 1000 is a group-time cell packed as 1000*g + t.

Usage:  mcsum.py FILE.csv
"""
import csv, math, sys, collections

ES_TRUTH = {0: 2.0, 1: 2.5, 2: 3.0}
# field designs with their own closed-form targets (base, slope in event time)
REGIME_TRUTH = {"master": (2.516667, 0.633333), "cohorthet": (2.516667, 0.633333),
                "breakC": (2.0945, 0.556)}
def es_truth(regime, h):
    base, slope = REGIME_TRUTH.get(regime, (2.0, 0.5))
    return base + slope * h
POST_AVG_TRUTH = (2.0 + 2.5 + 3.0) / 3.0          # equal-weight window(0 2) overall
def cell_truth(code):                              # code = 1000*g + t
    g, t = divmod(code, 1000)
    return (g - 2) + 0.5 * (t - g)

PKG = {"csdid": "csdid bal(none)", "csdidpair": "csdid bal(pair)",
       "csdid_dr": "csdid dr", "csdid_ipw": "csdid ipw", "csdid_reg": "csdid reg",
       "jwdid": "jwdid", "jwdid_uc": "jwdid uncond", "bjs": "did_imputation", "bjs_wtr": "did_imputation wtr", "dcdh": "did_multiplegt_dyn",
       "lpdid": "lpdid", "sa": "eventstudyinteract", "lpdid_rw": "lpdid rw", "flexdid": "flexdid", "csdid_band": "csdid uniform band"}
ORDER = ["csdid", "csdidpair", "csdid_dr", "csdid_ipw", "csdid_reg",
         "jwdid", "jwdid_uc", "bjs", "bjs_wtr", "sa", "dcdh", "lpdid", "lpdid_rw", "flexdid", "csdid_band"]
REGIMES = ["balanced", "varmiss", "unbalanced", "rcs", "rcsvar",
           "bal_ok", "bal_owrong", "bal_pwrong", "bal_pwrong2", "bal_ps2", "unitroot", "bands"]

def num(x):
    try:
        v = float(x)
        return None if math.isnan(v) else v
    except Exception:
        return None

def order_key(pkg):
    return (ORDER.index(pkg), pkg) if pkg in ORDER else (len(ORDER), pkg)

def label(pkg):
    return PKG.get(pkg, pkg)

def regimes_in(rows):
    seen = {r["regime"] for r in rows}
    out = [g for g in REGIMES if g in seen]
    out += sorted(seen - set(out))
    return out

def pkgs_in(rows):
    return sorted({r["pkg"] for r in rows}, key=order_key)

def table(rows, hsel, truth, lab, regs, pkgs):
    print(f"\n== {lab}   default truth = {truth:.4f} (field designs use their own) ==")
    print(f"  {'regime':&lt;11}{'estimator':&lt;20}{'reps':&gt;5}{'bias':&gt;9}{'sd':&gt;8}"
          f"{'rmse':&gt;8}{'meanSE':&gt;8}{'cover95':&gt;8}")
    for regime in regs:
        for pkg in pkgs:
            v = [(num(r["est"]), num(r["se"])) for r in rows
                 if r["regime"] == regime and r["pkg"] == pkg and int(r["h"]) == hsel]
            ok = [(e, s) for e, s in v if e is not None]
            if not v:
                continue
            if not ok:
                print(f"  {regime:&lt;11}{label(pkg):&lt;20}    - unsupported/empty")
                continue
            n = len(ok)
            rtruth = es_truth(regime, hsel) if hsel in (0, 1, 2) else truth
            est = [e for e, _ in ok]
            m = sum(est) / n
            sd = math.sqrt(sum((e - m) ** 2 for e in est) / (n - 1)) if n &gt; 1 else float("nan")
            rmse = math.sqrt(sum((e - rtruth) ** 2 for e in est) / n)
            ses = [s for _, s in ok if s is not None]
            mse = sum(ses) / len(ses) if ses else float("nan")
            cov = [1 if abs(e - rtruth) &lt;= 1.959964 * s else 0
                   for e, s in ok if s is not None and s &gt; 0]
            cvr = sum(cov) / len(cov) if cov else float("nan")
            print(f"  {regime:&lt;11}{label(pkg):&lt;20}{n:&gt;5}{m-rtruth:&gt;+9.4f}{sd:&gt;8.4f}"
                  f"{rmse:&gt;8.4f}{mse:&gt;8.4f}{cvr:&gt;8.3f}")

def usable(rows, regs, pkgs):
    """Replications that produced a usable estimate, per regime and package.

    A replication is attempted if any row exists for it and usable if the
    event-study estimate is non-missing. The difference is the count of
    draws the command declined to estimate (for csdid under a broken
    propensity score, the overlap check that refuses the cell)."""
    print("\n== usable replications (attempted / usable / declined) ==")
    print(f"  {'regime':&lt;11}{'estimator':&lt;20}{'attempt':&gt;8}{'usable':&gt;8}{'declined':&gt;9}")
    att = collections.defaultdict(set)
    use = collections.defaultdict(set)
    for r in rows:
        if int(r["h"]) not in (0, 1, 2):
            continue
        key = (r["regime"], r["pkg"])
        att[key].add(int(r["rep"]))
        if num(r["est"]) is not None:
            use[key].add(int(r["rep"]))
    for regime in regs:
        for pkg in pkgs:
            key = (regime, pkg)
            if key not in att:
                continue
            a, u = len(att[key]), len(use[key])
            print(f"  {regime:&lt;11}{label(pkg):&lt;20}{a:&gt;8}{u:&gt;8}{a-u:&gt;9}")

def cells(rows, regs, pkgs):
    """Cell-level block: every ATT(g,t) cell with its mean reported SE.

    The mean SE column is what makes two estimators on the same cell
    comparable in spread, not only in location."""
    print("\n== ATT(g,t) cells: bias and mean reported SE ==")
    print(f"  {'regime':&lt;11}{'estimator':&lt;20}{'cell':&gt;12}{'reps':&gt;6}"
          f"{'truth':&gt;8}{'bias':&gt;9}{'sd':&gt;8}{'meanSE':&gt;8}{'cover95':&gt;8}")
    acc = collections.defaultdict(list)
    for r in rows:
        h = int(r["h"])
        if h &gt;= 1000:
            e, s = num(r["est"]), num(r["se"])
            if e is not None:
                acc[(r["regime"], r["pkg"], h)].append((e, s))
    for regime in regs:
        for pkg in pkgs:
            codes = sorted(c for (g, p, c) in acc if g == regime and p == pkg)
            for code in codes:
                v = acc[(regime, pkg, code)]
                g, t = divmod(code, 1000)
                truth = cell_truth(code)
                n = len(v)
                est = [e for e, _ in v]
                m = sum(est) / n
                sd = math.sqrt(sum((e - m) ** 2 for e in est) / (n - 1)) if n &gt; 1 else float("nan")
                ses = [s for _, s in v if s is not None]
                mse = sum(ses) / len(ses) if ses else float("nan")
                cov = [1 if abs(e - rtruth) &lt;= 1.959964 * s else 0
                       for e, s in v if s is not None and s &gt; 0]
                cvr = sum(cov) / len(cov) if cov else float("nan")
                print(f"  {regime:&lt;11}{label(pkg):&lt;20}{f'ATT({g},{t})':&gt;12}{n:&gt;6}"
                      f"{truth:&gt;8.3f}{m-rtruth:&gt;+9.4f}{sd:&gt;8.4f}{mse:&gt;8.4f}{cvr:&gt;8.3f}")

def worst_cells(rows, regs, pkgs):
    print("\n== ATT(g,t) cells: worst |bias| over the post grid ==")
    acc = collections.defaultdict(list)
    for r in rows:
        h = int(r["h"])
        if h &gt;= 1000 and num(r["est"]) is not None:
            acc[(r["regime"], r["pkg"], h)].append(float(r["est"]))
    worst = collections.defaultdict(lambda: (0.0, None))
    for (regime, pkg, code), v in acc.items():
        b = abs(sum(v) / len(v) - cell_truth(code))
        if b &gt; worst[(regime, pkg)][0]:
            worst[(regime, pkg)] = (b, code)
    for regime in regs:
        for pkg in pkgs:
            if (regime, pkg) in worst:
                b, code = worst[(regime, pkg)]
                g, t = divmod(code, 1000)
                print(f"  {regime:&lt;11}{label(pkg):&lt;20}max|bias|={b:.4f} at ATT({g},{t})")

def main(path):
    rows = list(csv.DictReader(open(path)))
    print(f"rows: {len(rows)}   reps: {max(int(r['rep']) for r in rows)}")
    regs, pkgs = regimes_in(rows), pkgs_in(rows)
    for h in (0, 1, 2):
        table(rows, h, ES_TRUTH[h], f"event study ES({h})", regs, pkgs)
    table(rows, 99, POST_AVG_TRUTH, "post-treatment average (window 0-2)", regs, pkgs)
    usable(rows, regs, pkgs)
    cells(rows, regs, pkgs)
    worst_cells(rows, regs, pkgs)

if __name__ == "__main__":
    main(sys.argv[1])</code></pre>
</details>

<details class="code-fold">
<summary><code>bandsum.py</code> &mdash; joint coverage: how often a uniform band, and how often three pointwise intervals, cover the whole event-study path at once</summary>
<pre><code>#!/usr/bin/env python3
# Run from the bench/ folder of the replication package.
# Usage:  python3 bandsum.py &lt;bands.csv&gt; &lt;ladder.csv&gt;
"""Joint (simultaneous) coverage of the three post-treatment event times.

An event study is a family of estimates, so the question is how often the
whole path is covered at once, not how often one horizon is. This reads two
simulation CSVs and reports, for each interval construction, the fraction of
replications in which ES(0), ES(1) and ES(2) are ALL covered.

  * csdid uniform band: the multiplier-bootstrap band, stored as one row per
    horizon with h = 400 + horizon, the lower endpoint in the est column and
    the upper endpoint in the se column.
  * csdid three pointwise CIs: the same draws, est +/- 1.96*se at each of the
    three horizons, counted jointly.
  * every rival: est +/- 1.96*se at each of the three horizons on the
    balanced-panel rows of the ladder run, counted jointly.

A replication is counted only if all three horizons are present and usable;
the count that entered each rate is printed so a thinned cell cannot pass
itself off as a full one.

Usage:  bandsum.py BANDS.csv LADDER.csv
"""
import csv, math, sys, collections

ES_TRUTH = {0: 2.0, 1: 2.5, 2: 3.0}
BAND_OFFSET = 400                                  # h = 400 + horizon
Z = 1.959964

PKG = {"csdid": "csdid bal(none)", "jwdid": "jwdid", "bjs": "did_imputation",
       "dcdh": "did_multiplegt_dyn", "lpdid": "lpdid", "flexdid": "flexdid",
       "csdidpair": "csdid bal(pair)"}
ORDER = ["csdid", "csdidpair", "jwdid", "bjs", "dcdh", "lpdid", "flexdid"]

def num(x):
    try:
        v = float(x)
        return None if math.isnan(v) else v
    except Exception:
        return None

def load(path):
    return list(csv.DictReader(open(path)))

def joint_band(rows, regime="bands", pkg="csdid_band"):
    """Fraction of reps whose uniform band contains all three truths."""
    got = collections.defaultdict(dict)
    for r in rows:
        if r["regime"] != regime or r["pkg"] != pkg:
            continue
        h = int(r["h"])
        if BAND_OFFSET &lt;= h &lt;= BAND_OFFSET + 2:
            lo, hi = num(r["est"]), num(r["se"])
            if lo is not None and hi is not None:
                got[int(r["rep"])][h - BAND_OFFSET] = (lo, hi)
    full = [v for v in got.values() if len(v) == 3]
    hit = sum(1 for v in full
              if all(v[h][0] &lt;= ES_TRUTH[h] &lt;= v[h][1] for h in (0, 1, 2)))
    return hit, len(full)

def joint_pointwise(rows, regime, pkg):
    """Fraction of reps whose three pointwise 95% CIs all contain the truth."""
    got = collections.defaultdict(dict)
    for r in rows:
        if r["regime"] != regime or r["pkg"] != pkg:
            continue
        h = int(r["h"])
        if h in (0, 1, 2):
            e, s = num(r["est"]), num(r["se"])
            if e is not None and s is not None and s &gt; 0:
                got[int(r["rep"])][h] = (e, s)
    full = [v for v in got.values() if len(v) == 3]
    hit = sum(1 for v in full
              if all(abs(v[h][0] - ES_TRUTH[h]) &lt;= Z * v[h][1] for h in (0, 1, 2)))
    return hit, len(full)

def line(lab, hit, n):
    rate = hit / n if n else float("nan")
    print(f"  {lab:&lt;34}{rate:&gt;8.3f}   ({hit} of {n} reps)")

def main(bands_path, ladder_path):
    bands, ladder = load(bands_path), load(ladder_path)

    print("== joint coverage of ES(0), ES(1), ES(2) ==")
    print(f"  truths: {ES_TRUTH[0]}, {ES_TRUTH[1]}, {ES_TRUTH[2]}\n")

    line("csdid uniform band", *joint_band(bands))
    line("csdid three pointwise CIs", *joint_pointwise(bands, "bands", "csdid_band"))

    seen = {r["pkg"] for r in ladder if r["regime"] == "balanced"}
    for pkg in [p for p in ORDER if p in seen]:
        hit, n = joint_pointwise(ladder, "balanced", pkg)
        if n:
            line(f"{PKG.get(pkg, pkg)} pointwise", hit, n)

    print("\n== per-horizon pointwise coverage, same reps (diagnostic) ==")
    for lab, rows, regime, pkg in (
            [("csdid (bands run)", bands, "bands", "csdid_band")] +
            [(PKG.get(p, p), ladder, "balanced", p) for p in ORDER if p in seen]):
        got = collections.defaultdict(dict)
        for r in rows:
            if r["regime"] != regime or r["pkg"] != pkg:
                continue
            h = int(r["h"])
            if h in (0, 1, 2):
                e, s = num(r["est"]), num(r["se"])
                if e is not None and s is not None and s &gt; 0:
                    got[int(r["rep"])][h] = (e, s)
        full = [v for v in got.values() if len(v) == 3]
        rates = []
        for h in (0, 1, 2):
            c = sum(1 for v in full if abs(v[h][0] - ES_TRUTH[h]) &lt;= Z * v[h][1])
            rates.append(c / len(full) if full else float("nan"))
        print(f"  {lab:&lt;34}" + "".join(f"{x:&gt;8.3f}" for x in rates) +
              f"   (n={len(full)})")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])</code></pre>
</details>

<details class="code-fold">
<summary><code>mk_speed_tables.py</code> &mdash; the speed tables: every timed cell printed from the benchmark CSV, deduplicated keep-last, with its trial count and note</summary>
<pre><code># Run from the bench/ folder of the replication package.
# Usage:  python3 mk_speed_tables.py
import csv, sys
B="."
rows=list(csv.DictReader(open(B+"/scalebench-results.csv")))
def get(scan,**kw):
    out=[]
    for r in rows:
        if r["scan"]!=scan: continue
        if all(r[k]==v for k,v in kw.items()): out.append(r)
    return out
def t(r):
    try: return float(r["median_seconds"])
    except: return None
def fmt(x,dp=2):
    if x is None: return "—"
    return f"{x:.{dp}f}"
# dedupe keep-last on (scan,n,T,G,pkg)
seen={}
for r in rows: seen[(r["scan"],r["n_units"],r["T"],r["cohorts"],r["pkg"])]=r
rows=list(seen.values())
for scan in ["E_default","A_unbal","B_rcs","C_periods","D_cohorts","F_n","F_T","F_G","F_scheme"]:
    print("=== "+scan)
    for r in rows:
        if r["scan"]==scan:
            print(f'{r["n_units"]},{r["T"]},{r["cohorts"]},{r["rows"]},{r["pkg"]},{fmt(t(r),3)},{r["trials"]},{r["note"][:60]}')</code></pre>
</details>

<details class="code-fold">
<summary><code>figdata.do</code> &mdash; per-replication estimates behind the opening figure: all nine command arms on the unequal-period-sampling design, same seeds as the Reliability I tables</summary>
<pre><code>* Per-replication estimates behind the hero figure: every command on the
* unequal-period-sampling design (varmiss), event times 0-2.
* Same DGP and seeds (90000 + rep) as the Reliability I tables, so the
* bias and coverage computed from this file reproduce the published rows.
*   Usage: stata-mp -b do figdata.do &lt;nunits&gt; &lt;reps&gt; &lt;outfile&gt;
args nunits reps outfile
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
local B "."
quietly do "`B'/simdgp.do"
quietly do "`B'/simrun3.do"

* population-share wtr() weights for did_imputation (as in bjswtr.do)
capture program drop mkwtr
program define mkwtr
    quietly capture drop K w0 w1 w2 ncell
    quietly gen int K = time - gvar if gvar &gt; 0 &amp; time &gt;= gvar
    forvalues h = 0/2 {
        quietly capture drop ncell
        quietly bysort gvar time: egen double ncell = total(K == `h') if K == `h'
        quietly gen double w`h' = cond(K == `h' &amp; ncell &gt; 0, 1/(3*ncell), 0)
        quietly replace w`h' = 0 if missing(w`h')
    }
end

capture file close out
file open out using "`outfile'", write replace text
file write out "regime,pkg,rep,h,est,se" _n

forvalues r = 1/`reps' {

    quietly sim_dgp, n(`nunits') seed(`=90000 + `r'') regime(varmiss)
    tempfile d
    quietly save "`d'", replace

    foreach pkg in csdid jwdid jwdid_uc bjs bjs_wtr dcdh lpdid lpdid_rw sa {
        use "`d'", clear
        capture sim_est3, pkg(`pkg') regime(varmiss) bal(none)
        if _rc == 0 &amp; r(ok) == 1 {
            matrix RR = r(R)
            forvalues h = 0/2 {
                local v1 = string(RR[`h'+1,1], "%18.0g")
                local v2 = string(RR[`h'+1,2], "%18.0g")
                file write out "varmiss,`pkg',`r',`h',`v1',`v2'" _n
            }
        }
        else {
            forvalues h = 0/2 {
                file write out "varmiss,`pkg',`r',`h',.,." _n
            }
        }
    }

    if mod(`r', 10) == 0 display "MCPROG rep `r' of `reps' done"
}
file close out
display "MCDONE `outfile'"</code></pre>
</details>

<details class="code-fold">
<summary><code>fig_hero.R</code> &mdash; draws the opening figure from figdata.csv: ridge densities of the estimates and zipper plots of the confidence intervals</summary>
<pre><code>#------------------------------------------------------------------------------
# Hero figure for the csdid-against-the-field guide
#
# Reads the per-replication estimates written by figdata.do (unequal period
# sampling design, event time 0) and draws a two-panel figure in the style of
# the DR-with-weak-overlap / DDD papers: ridge densities of the estimates on
# the left, zipper plots of the confidence intervals on the right.
#
# Inputs : figdata.csv           (regime,pkg,rep,h,est,se)
# Outputs: &lt;outdir&gt;/field-hero-varmiss.png
#          figcheck.csv          (bias and coverage per command, for the gate)
#
# Usage  : Rscript fig_hero.R [infile] [outdir]
#------------------------------------------------------------------------------
rm(list = ls())

library(ggplot2)
library(ggridges)
library(ggtext)
library(cowplot)
library(ggplotify)
library(dplyr)
library(tibble)
library(grid)

#------------------------------------------------------------------------------
# Set parameters
#------------------------------------------------------------------------------
args    &lt;- commandArgs(trailingOnly = TRUE)
infile  &lt;- ifelse(length(args) &gt;= 1, args[1], "figdata.csv")
outdir  &lt;- ifelse(length(args) &gt;= 2, args[2], ".")
h_sel   &lt;- 0          # event time shown in the figure
truth   &lt;- 2.0        # population ES(0) in the Reliability I designs
z95     &lt;- qnorm(0.975)

navy &lt;- "#012169"
gray &lt;- "#525252"

# display labels and colors, in the order of the published table (top first)
pkg_meta &lt;- tribble(
  ~pkg,       ~label,                  ~color,
  "csdid",    "csdid",                 "#1e40af",
  "jwdid",    "jwdid",                 "#d97706",
  "jwdid_uc", "jwdid uncond*",         "#b45309",
  "bjs",      "did_imputation",        "#b91c1c",
  "bjs_wtr",  "did_imputation wtr*",   "#15803d",
  "dcdh",     "did_multiplegt_dyn",    "#7c3aed",
  "lpdid",    "lpdid",                 "#6b7280",
  "lpdid_rw", "lpdid rw*",             "#334155",
  "sa",       "eventstudyinteract",    "#be185d"
)
pkg_meta &lt;- pkg_meta %&gt;%
  filter(!pkg %in% c("jwdid_uc", "bjs_wtr", "lpdid_rw"))
est_colors &lt;- setNames(pkg_meta$color, pkg_meta$label)

#------------------------------------------------------------------------------
# Theme (theme_dr_paper, trimmed)
#------------------------------------------------------------------------------
theme_fig &lt;- function(base_size = 13) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title       = element_text(color = navy, face = "bold", size = 15),
      plot.subtitle    = element_text(color = gray, size = 11,
                                      margin = margin(b = 8)),
      axis.title       = element_text(color = navy),
      axis.text        = element_text(color = gray),
      legend.position  = "none",
      panel.grid.major = element_line(color = "gray90", linewidth = 0.3),
      panel.grid.minor = element_blank(),
      plot.background  = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "white", color = NA),
      plot.margin      = margin(10, 10, 10, 10)
    )
}

#------------------------------------------------------------------------------
# Load, restrict to the plotted horizon, compute the summary used by the gate
#------------------------------------------------------------------------------
raw &lt;- read.csv(infile, stringsAsFactors = FALSE)

dat &lt;- raw %&gt;%
  filter(h == h_sel, !is.na(est), !is.na(se)) %&gt;%
  inner_join(pkg_meta, by = "pkg") %&gt;%
  mutate(
    label = factor(label, levels = rev(pkg_meta$label)),  # csdid on top
    lower = est - z95 * se,
    upper = est + z95 * se,
    cover = lower &lt;= truth &amp; truth &lt;= upper
  )

summ &lt;- dat %&gt;%
  group_by(label) %&gt;%
  summarise(reps = n(), bias = mean(est) - truth,
            coverage = mean(cover), .groups = "drop") %&gt;%
  arrange(desc(label))

write.csv(summ, "figcheck.csv", row.names = FALSE)

# shared horizontal scale so the two panels can be read against each other
xlims &lt;- range(c(dat$lower, dat$upper, dat$est))

#------------------------------------------------------------------------------
# Left panel: ridge densities of the estimates
#------------------------------------------------------------------------------
ridge_p &lt;- ggplot(dat, aes(x = est, y = label, fill = label)) +
  geom_density_ridges(alpha = 0.85, rel_min_height = 0.01, scale = 1.35) +
  geom_vline(xintercept = truth, colour = navy, linewidth = 1,
             linetype = "dashed") +
  scale_fill_manual(values = est_colors) +
  scale_y_discrete(expand = c(0, 0.2)) +
  coord_cartesian(xlim = xlims, clip = "off") +
  labs(title = "Where the estimates land",
       subtitle = "Density of the 500 estimates at e=0",
       x = NULL, y = NULL) +
  theme_fig() +
  theme(axis.text.y = element_text(color = navy, face = "bold", size = 11),
        plot.margin = margin(15, 12, 10, 10))

#------------------------------------------------------------------------------
# Right panel: zipper plot of the confidence intervals
#------------------------------------------------------------------------------
html_lab &lt;- setNames(
  paste0("&lt;span style='color:", pkg_meta$color, "'&gt;**", pkg_meta$label,
         "**&lt;/span&gt;"),
  pkg_meta$label)

zdat &lt;- dat %&gt;%
  mutate(
    flabel     = factor(html_lab[as.character(label)],
                        levels = html_lab),               # csdid strip on top
    draw_col   = ifelse(cover, est_colors[as.character(label)], "#000000"),
    draw_alpha = ifelse(cover, 0.45, 0.65)
  )

cov_anno &lt;- summ %&gt;%
  mutate(flabel = factor(html_lab[as.character(label)], levels = html_lab),
         run = -Inf, y_pos = Inf,
         lab = paste0("bias ", sprintf("%+.2f", bias), " &amp;middot; coverage ",
                      formatC(100 * coverage, format = "f", digits = 0), "%"))

zip_base &lt;- ggplot(zdat, aes(x = rep)) +
  geom_linerange(aes(ymin = lower, ymax = upper,
                     colour = draw_col, alpha = draw_alpha),
                 linewidth = 0.35, show.legend = FALSE) +
  geom_hline(yintercept = truth, colour = navy, linetype = "dashed",
             linewidth = 0.8) +
  facet_grid(flabel ~ ., switch = "y") +
  scale_colour_identity() +
  scale_alpha_identity() +
  coord_flip() +
  scale_y_continuous(limits = xlims) +
  labs(title = "Whether the intervals cover the truth",
       subtitle = "One 95% confidence interval per sample; black = does not cover the truth",
       x = NULL, y = NULL) +
  theme_fig() +
  ggtext::geom_richtext(
    data = cov_anno, aes(x = run, y = y_pos, label = lab),
    inherit.aes = FALSE, hjust = 1, vjust = 0,
    fill = alpha("white", 0.85), label.color = NA,
    label.padding = unit(c(1, 3, 1, 3), "pt"),
    color = navy, size = 3.0) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.spacing.y    = unit(2, "pt"),
    strip.text.y.left  = ggtext::element_markdown(angle = 0, vjust = 0.5,
                                                  hjust = 0, size = 9),
    strip.placement    = "outside",
    axis.text.y        = element_blank(),
    axis.ticks.y       = element_blank(),
    plot.margin        = margin(15, 10, 10, 6)
  )

zip_p &lt;- zip_base

#------------------------------------------------------------------------------
# Assemble: title block on top, panels, source note at the bottom
#------------------------------------------------------------------------------
panels &lt;- cowplot::plot_grid(ridge_p, zip_p, ncol = 2, rel_widths = c(1, 1.15))

title_grob &lt;- cowplot::ggdraw() +
  cowplot::draw_label(
    "Event-study estimates under unequal sampling across periods",
    x = 0.012, y = 0.80, hjust = 0, vjust = 0.5, color = navy,
    fontface = "bold", size = 19) +
  cowplot::draw_label(
    paste0("Staggered DiD with no covariates: 1,000 units, 7 periods, three treated cohorts plus a never-treated group; 500 simulated samples.\n",
           "Each period keeps a different share of its units (45% to 95%), independent of everything else. Truth at e=0 is 2. Every command at its default."),
    x = 0.012, y = 0.30, hjust = 0, vjust = 0.5, color = gray, size = 12,
    lineheight = 1.15)

foot_grob &lt;- cowplot::ggdraw() +
  cowplot::draw_label(
    paste0("Same data-generating process and seeds as the Reliability I tables. Biases flip sign with the horizon (the imputation commands move from\n",
           "-0.16 at e=0 to +0.23 at e=2), so averaging across horizons would cancel misses rather than reveal them. Non-default options are discussed in the text."),
    x = 0.012, y = 0.55, hjust = 0, vjust = 0.5, color = gray, size = 10.5,
    lineheight = 1.2)

combo &lt;- cowplot::plot_grid(title_grob, panels, foot_grob, ncol = 1,
                            rel_heights = c(0.155, 1, 0.085))

ggsave(file.path(outdir, "field-hero-varmiss.png"), combo,
       width = 13, height = 7.6, dpi = 200, bg = "white")</code></pre>
</details>

<details class="code-fold">
<summary><code>fig_speed.R</code> &mdash; draws the opening speed figure from the numbers in the Speed-section tables</summary>
<pre><code>#------------------------------------------------------------------------------
# Speed figure for the csdid-against-the-field guide
#
# Two log-log panels drawn from the published Speed-section tables:
#   A. seconds vs rows       (unbalanced-panel table: n x {1k,10k,100k}, T=10)
#   B. seconds vs periods T  (T-scaling table: T x {5,10,20,40}, n=10,000)
# The numbers below are exactly the numbers printed in those tables; the
# timing protocol (median of 10 runs, event study plus clustered standard
# errors) is described in the Speed section.
#
# Output : &lt;outdir&gt;/field-speed.png
# Usage  : Rscript fig_speed.R [outdir]
#------------------------------------------------------------------------------
rm(list = ls())

library(ggplot2)
library(ggtext)
library(cowplot)
library(dplyr)
library(tibble)

#------------------------------------------------------------------------------
# Set parameters
#------------------------------------------------------------------------------
args   &lt;- commandArgs(trailingOnly = TRUE)
outdir &lt;- ifelse(length(args) &gt;= 1, args[1], ".")

navy &lt;- "#012169"
gray &lt;- "#525252"
cols &lt;- c("csdid"          = "#1e40af",
          "jwdid"          = "#d97706",
          "did_imputation" = "#b91c1c",
          "lpdid"          = "#6b7280")

# Speed section, "Unbalanced panels" table (csdid at bal(none), T=10, G=4)
size_tab &lt;- tribble(
  ~rows,   ~csdid, ~jwdid, ~lpdid, ~did_imputation,
  8500,     0.10,   0.20,   0.32,   0.57,
  85000,    0.69,   0.70,   0.85,   3.85,
  850000,   3.79,   6.28,   5.83,   38.0
)

# Speed section, T-scaling table (balanced panel, n=10,000, G=4)
T_tab &lt;- tribble(
  ~T,  ~csdid, ~jwdid, ~lpdid, ~did_imputation,
  5,    0.13,   0.26,   0.55,   1.44,
  10,   0.26,   0.67,   1.05,   3.44,
  20,   0.52,   2.76,   1.92,   8.99,
  40,   1.07,  12.1,    3.66,  20.0
)

#------------------------------------------------------------------------------
# Theme
#------------------------------------------------------------------------------
theme_fig &lt;- function(base_size = 13) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title       = element_text(color = navy, face = "bold", size = 15),
      plot.subtitle    = element_text(color = gray, size = 11,
                                      margin = margin(b = 8)),
      axis.title       = element_text(color = navy),
      axis.text        = element_text(color = gray),
      legend.position  = "none",
      panel.grid.major = element_line(color = "gray90", linewidth = 0.3),
      panel.grid.minor = element_blank(),
      plot.background  = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "white", color = NA),
      plot.margin      = margin(10, 10, 10, 10)
    )
}

#------------------------------------------------------------------------------
# One workhorse for both panels: log-log lines with end labels
#------------------------------------------------------------------------------
speed_panel &lt;- function(tab, xvar, title, subtitle, xlab, xbreaks, xlabels,
                        vj = NULL) {
  long &lt;- tab %&gt;%
    tidyr::pivot_longer(-dplyr::all_of(xvar), names_to = "cmd",
                        values_to = "sec") %&gt;%
    mutate(cmd = factor(cmd, levels = names(cols)))
  ends &lt;- long %&gt;%
    group_by(cmd) %&gt;% slice_max(.data[[xvar]], n = 1) %&gt;% ungroup() %&gt;%
    mutate(lab = paste0("**", cmd, "** ", sec, "s"),
           vjust = if (is.null(vj)) 0.5
                   else dplyr::coalesce(vj[as.character(cmd)], 0.5))

  ggplot(long, aes(x = .data[[xvar]], y = sec, colour = cmd)) +
    geom_line(linewidth = 1.1) +
    geom_point(size = 2.4) +
    ggtext::geom_richtext(
      data = ends, aes(label = lab, vjust = vjust), hjust = 0,
      nudge_x = 0.045, fill = NA, label.color = NA, size = 3.6,
      show.legend = FALSE) +
    scale_colour_manual(values = cols) +
    scale_x_log10(breaks = xbreaks, labels = xlabels,
                  expand = expansion(mult = c(0.04, 0.42))) +
    scale_y_log10(breaks = c(0.1, 0.3, 1, 3, 10, 30),
                  labels = c("0.1", "0.3", "1", "3", "10", "30")) +
    labs(title = title, subtitle = subtitle, x = xlab, y = "seconds") +
    theme_fig()
}

pA &lt;- speed_panel(size_tab, "rows",
  "More data",
  "Unbalanced panel (15% of rows deleted), T=10, four cohorts",
  "rows in the panel",
  c(8500, 85000, 850000), c("8,500", "85,000", "850,000"),
  vj = c(jwdid = -0.3, lpdid = 0.5, csdid = 1.3))

pB &lt;- speed_panel(T_tab, "T",
  "More periods",
  "Balanced panel, 10,000 units, four cohorts",
  "number of time periods",
  c(5, 10, 20, 40), c("5", "10", "20", "40"))

#------------------------------------------------------------------------------
# Assemble: title block, panels, source note
#------------------------------------------------------------------------------
panels &lt;- cowplot::plot_grid(pA, pB, ncol = 2)

title_grob &lt;- cowplot::ggdraw() +
  cowplot::draw_label(
    "Computation time by sample size and number of periods",
    x = 0.012, y = 0.76, hjust = 0, vjust = 0.5, color = navy,
    fontface = "bold", size = 19) +
  cowplot::draw_label(
    "Run time of one event-study estimation with clustered standard errors; median of 10 runs. Both axes on log scale.",
    x = 0.012, y = 0.22, hjust = 0, vjust = 0.5, color = gray, size = 12)

foot_grob &lt;- cowplot::ggdraw() +
  cowplot::draw_label(
    paste0("Numbers from the Speed section tables. csdid timed at bal(none), the common-sample choice, with analytical inference;\n",
           "its default (999 bootstrap draws plus uniform bands) adds about a third of a second at one million rows."),
    x = 0.012, y = 0.5, hjust = 0, vjust = 0.5, color = gray, size = 10.5,
    lineheight = 1.2)

combo &lt;- cowplot::plot_grid(title_grob, panels, foot_grob, ncol = 1,
                            rel_heights = c(0.16, 1, 0.11))

ggsave(file.path(outdir, "field-speed.png"), combo,
       width = 13, height = 5.6, dpi = 200, bg = "white")</code></pre>
</details>
