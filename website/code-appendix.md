---
title: Code appendix
---

# Code appendix

Every number in [How csdid compares](articles/csdid-against-the-field.html)
comes from one of the scripts on this page. They are reproduced in full.
Four things were changed for publication: the file paths were shortened so
that everything runs from a single folder, a two-line run header was added
at the top of each script, a handful of copy-pasted header comments were
corrected to describe what that script actually runs, and one inert block of
dead code was removed from `simdgp.do`. Nothing else moved &mdash; every
seed, parameter, regime, package option and line of executed logic is what
produced the published tables.

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
<summary><code>simrun3.do</code> &mdash; the estimator harness: one program per package, all six harvested into the same 3x2 matrix</summary>
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
    else if "`pkg'" == "bjs" {
        if inlist("`regime'", "rcs", "rcsvar") {
            if "`cov'" != "" {
                * time-invariant covariates enter the imputation model through
                * time interactions, as the did_imputation help prescribes:
                * dummies via fe() (gender-by-period FE), continuous via
                * controls() as explicit x*t variables
                capture drop __x2t
                quietly generate double __x2t = x2 * time
                capture did_imputation y id time gvar_miss, horizons(0/2) ///
                    fe(gvar time x1#time) controls(x2 __x2t)
            }
            else {
                capture did_imputation y id time gvar_miss, horizons(0/2) fe(gvar time)
            }
        }
        else {
            if "`cov'" != "" {
                capture drop __x2t
                quietly generate double __x2t = x2 * time
                capture did_imputation y id time gvar_miss, horizons(0/2) autosample ///
                    fe(id time x1#time) controls(__x2t)
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
<summary><code>scalebench.do</code> &mdash; the four-tier scaling grid: unbalanced ladder, repeated-cross-section ladder, periods scan, cohorts scan</summary>
<pre><code>* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do scalebench.do A
* ---------------------------------------------------------------------------
* scalebench.do -- extended speed-benchmark grid for the comparison article.
*
*   stata-mp -b do scalebench.do &lt;A|B|C|D&gt; [smoke]
*
* Four scans, each runnable on its own so the tiers can be sequenced:
*
*   A  UNBALANCED LADDER   n_units in {1e3, 1e4, 1e5}, T=10, G=4, 15% MCAR
*                          csdid bal(full) and bal(none), jwdid,
*                          did_imputation, lpdid
*   B  RCS LADDER          n_per_period in {1e3, 1e4, 1e5}, T=10, G=4
*                          csdid rcs, flexdid, jwdid, did_imputation
*   C  PERIODS SCAN        n_units=1e4, T in {5,10,20,40}, G=4, balanced
*   D  COHORTS SCAN        n_units=1e4, T=20, G in {3,6,12,18}, balanced
*
* PROTOCOL (the same one behind the published tables)
* ---------------------------------------------------
* Same dgp.do (bench_dgp / bench_structure), same runners.do, same
* validate.do, same seed 20260729, same design(dynamic), same cluster
* variable cl (= mod(id,50)+1, 50 clusters), same horizons(5) event study,
* same csdid under test (repo src/ado + src/mata, never an installed copy).
* Timing goes through bench_time from time.do: ONE DISCARDED WARMUP per
* package per dataset, then TRIALS timed calls on a freshly reloaded copy of
* the same dataset.
*
* Two documented differences from the published tables, both recorded
* rather than hidden:
*
*   statistic   The published tables report the MEAN of 10 reps. bench_time
*               returns the MEDIAN of its trials. Trials are set to 10 here
*               so the sample is the same size, and min/max go in the note
*               column so the spread is visible. At the published sizes the
*               sd never exceeded a few hundredths of a second, so median
*               and mean agree to well under 1%.
*
*   process     The published tables ran ONE Stata process per cell. This
*               driver runs one process per TIER. The warmup is still
*               discarded per package per dataset, so no package inherits a
*               warm cache from another; what is not reproduced is crash
*               isolation. Every call is therefore capture-guarded and a
*               failure is written as a row, not raised. If a tier dies,
*               re-run the survivors with the optional 3rd/4th args (see
*               ONLYN/ONLYPKG below).
*
* CELL LABELLING
* --------------
* Cells are labelled by the design primitives -- n_units, T, cohorts -- and
* the row count is DERIVED and reported alongside. For repeated cross
* sections n_units means OBSERVATIONS PER PERIOD (bench_structure gives every
* observation its own id), so rows = n_per_period x T. For the unbalanced
* ladder rows ~ 0.85 x n_units x T after the 15% MCAR deletion.
*
* CSV: scan, n_units, T, cohorts, rows, pkg, median_seconds, trials, ok, note
* appended to scalebench-results.csv (smoke runs go to scalebench-smoke.csv).
*
* dcdh (did_multiplegt_dyn) is excluded by design: runtime.
* ---------------------------------------------------------------------------
args tier smoke onlyn onlypkg

if !inlist("`tier'", "A", "B", "C", "D") {
    display as error "usage: do scalebench.do &lt;A|B|C|D&gt; [smoke] [only_n] [only_pkg]"
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

        * package label -&gt; runner program, plus the structure the runner needs
        local runner "`pkg'"
        local sopt ""
        local extra ""
        if "`pkg'" == "csdid_balfull" {
            local runner "csdidbf"
            local extra "bal(full) is the shipped default; drops units not observed in every period"
        }
        if "`pkg'" == "csdid_balnone" {
            local runner "csdid"
            local extra "bal(none); same rows as the rivals"
        }
        if "`pkg'" == "did_imputation" local runner "bjs"
        if "`pkg'" == "jwdid" &amp; "`structure'" == "rcs" local runner "jwdidrcs"
        if "`runner'" == "csdid" &amp; "`structure'" == "rcs" local sopt "structure(rcs)"

        local med = .
        local lo = .
        local hi = .
        local ok = 0
        local rnote ""

        capture noisily bench_time, pkg(`runner') data("`d'") horizons(`h') ///
            cluster(cl) trials(`trials') `sopt'
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
        local note "H=`h'; G_real=`greal'; nevertreated=`nevpct'%; min=`lostr'; max=`histr'"
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
            pkgs(csdid_balfull csdid_balnone jwdid did_imputation lpdid)
    }
}

* ---- B. repeated cross sections: n_units = observations per period, T=10,
*         G=4 -- the structure behind the published RCS table.
*         Rows = n x T: 10k / 100k / 1M.
if "`tier'" == "B" {
    local ns "1000 10000 100000"
    if `issmoke' local ns "200"
    foreach n of local ns {
        sb_cell, scan(B_rcs) n(`n') t(10) g(4) structure(rcs) trials(`trials') ///
            pkgs(csdid flexdid jwdid did_imputation)
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

display as text "SB DONE tier=`tier' smoke=`issmoke'"</code></pre>
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

One script turns the raw per-replication CSVs into the bias and coverage tables in the guide.

<details class="code-fold">
<summary><code>mcsum.py</code> &mdash; the analyzer: bias, SD, RMSE, mean standard error and 95% coverage against the fixed population targets</summary>
<pre><code>#!/usr/bin/env python3
# Run from the bench/ folder of the replication package.
# Usage:  python3 mcsum.py &lt;results.csv&gt;
"""Monte Carlo summary: bias/SD/RMSE/coverage against FIXED population
targets. Truth is never re-derived from the draws."""
import csv, math, sys, collections

ES_TRUTH = {0: 2.0, 1: 2.5, 2: 3.0}
POST_AVG_TRUTH = (2.0 + 2.5 + 3.0) / 3.0          # equal-weight window(0 2) overall
def cell_truth(code):                              # code = 1000*g + t
    g, t = divmod(code, 1000)
    return (g - 2) + 0.5 * (t - g)

PKG = {"csdid": "csdid bal(none)", "csdidpair": "csdid bal(pair)", "jwdid": "jwdid",
       "bjs": "did_imputation", "dcdh": "did_multiplegt_dyn", "lpdid": "lpdid"}
ORDER = ["csdid", "csdidpair", "jwdid", "bjs", "dcdh", "lpdid"]
REGIMES = ["balanced", "varmiss", "unbalanced", "rcs", "rcsvar", "bal_ok", "bal_owrong", "bal_pwrong", "unitroot", "bands"]

def num(x):
    try:
        v = float(x)
        return None if math.isnan(v) else v
    except Exception:
        return None

def table(rows, hsel, truth, label):
    print(f"\n== {label}   truth = {truth:.4f} ==")
    print(f"  {'regime':&lt;11}{'estimator':&lt;20}{'reps':&gt;5}{'bias':&gt;9}{'sd':&gt;8}"
          f"{'rmse':&gt;8}{'meanSE':&gt;8}{'cover95':&gt;8}")
    for regime in REGIMES:
        for pkg in ORDER:
            v = [(num(r["est"]), num(r["se"])) for r in rows
                 if r["regime"] == regime and r["pkg"] == pkg and int(r["h"]) == hsel]
            ok = [(e, s) for e, s in v if e is not None]
            if not v:
                continue
            if not ok:
                print(f"  {regime:&lt;11}{PKG[pkg]:&lt;20}    - unsupported/empty")
                continue
            n = len(ok)
            est = [e for e, _ in ok]
            m = sum(est) / n
            sd = math.sqrt(sum((e - m) ** 2 for e in est) / (n - 1)) if n &gt; 1 else float("nan")
            rmse = math.sqrt(sum((e - truth) ** 2 for e in est) / n)
            ses = [s for _, s in ok if s is not None]
            mse = sum(ses) / len(ses) if ses else float("nan")
            cov = [1 if abs(e - truth) &lt;= 1.959964 * s else 0
                   for e, s in ok if s is not None and s &gt; 0]
            cvr = sum(cov) / len(cov) if cov else float("nan")
            print(f"  {regime:&lt;11}{PKG[pkg]:&lt;20}{n:&gt;5}{m-truth:&gt;+9.4f}{sd:&gt;8.4f}"
                  f"{rmse:&gt;8.4f}{mse:&gt;8.4f}{cvr:&gt;8.3f}")

def main(path):
    rows = list(csv.DictReader(open(path)))
    print(f"rows: {len(rows)}   reps: {max(int(r['rep']) for r in rows)}")
    for h in (0, 1, 2):
        table(rows, h, ES_TRUTH[h], f"event study ES({h})")
    table(rows, 99, POST_AVG_TRUTH, "post-treatment average (window 0-2)")
    # csdid ATT(g,t) cells: max |bias| across the post grid, per regime/mode
    print("\n== csdid ATT(g,t) cells: worst |bias| over the post grid ==")
    cells = collections.defaultdict(list)
    for r in rows:
        h = int(r["h"])
        if h &gt;= 1000 and num(r["est"]) is not None:
            cells[(r["regime"], r["pkg"], h)].append(float(r["est"]))
    worst = collections.defaultdict(lambda: (0.0, None))
    for (regime, pkg, code), v in cells.items():
        b = abs(sum(v) / len(v) - cell_truth(code))
        if b &gt; worst[(regime, pkg)][0]:
            worst[(regime, pkg)] = (b, code)
    for regime in REGIMES:
        for pkg in ORDER:
            if (regime, pkg) in worst:
                b, code = worst[(regime, pkg)]
                g, t = divmod(code, 1000)
                print(f"  {regime:&lt;11}{PKG[pkg]:&lt;20}max|bias|={b:.4f} at ATT({g},{t})")

if __name__ == "__main__":
    main(sys.argv[1])</code></pre>
</details>

