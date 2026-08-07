* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do scalebench.do A
* ---------------------------------------------------------------------------
* scalebench.do -- extended speed-benchmark grid for the comparison article.
*
*   stata-mp -b do scalebench.do <A|B|C|D|E|G> [smoke]
*
* Six scans, each runnable on its own so the tiers can be sequenced:
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
*   G  BALANCED LADDER    n_units in {1e3, 1e4, 1e5}, T=10, G=4, fully
*                          balanced: the tier-A package set (csdid analytical,
*                          jwdid, did_imputation, lpdid) at the same sizes,
*                          without the missingness.
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
* dcdh (did_multiplegt_dyn) runs everywhere its design support allows
* (owner call, 05aug2026; it had been excluded for runtime). Cells whose
* single warmup call exceeds the 120-second cap are recorded as not
* timed, mirroring the Version 1.82 tier's skip rule.
* ---------------------------------------------------------------------------
args tier smoke onlyn onlypkg

if !inlist("`tier'", "A", "B", "C", "D", "E", "G") {
    display as error "usage: do scalebench.do <A|B|C|D|E|G> [smoke] [only_n] [only_pkg]"
    exit 198
}
local issmoke = ("`smoke'" != "" & "`smoke'" != "0" & "`smoke'" != ".")

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
* "." is the positional placeholder for "no filter", matching the smoke arg
if "$SB_ONLYN" == "." global SB_ONLYN ""
if "$SB_ONLYPKG" == "." global SB_ONLYPKG ""

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
    local fitsecs = r(t99)
    return scalar ok = (`rc' == 0)
    return scalar secs_fit = `fitsecs'
    if `rc' {
        return scalar secs = `fitsecs'
        return local note "csdid shipped default bal(full); used_N=`e(N)'"
        exit
    }

    * The event study is part of what a user asks for, so it is part of what
    * we time. csdid and jwdid deliver it in a SECOND call; every other command
    * in this comparison delivers it inside its single call. Timing only the
    * fit would hand these two a deliverable that the others pay for. The
    * split survives as secs_fit / secs_agg.
    timer clear 98
    timer on 98
    capture quietly estat event, window(0 `horizons')
    local arc = _rc
    timer off 98
    quietly timer list 98
    local aggsecs = r(t98)
    return scalar secs_agg = `aggsecs'
    return scalar secs = `fitsecs' + `aggsecs'
    if `arc' {
        return scalar ok = 0
        return local note "csdid shipped default bal(full); estat event rc=`arc'"
        exit
    }
    return local note "csdid shipped default bal(full); used_N=`e(N)'"
    matrix A = e(aggte)
    matrix ES = J(`horizons' + 1, 3, .)
    forvalues k = 1/`=`horizons'+1' {
        if `k' > rowsof(A) continue
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
    local fitsecs = r(t99)
    return scalar ok = (`rc' == 0)
    return scalar secs_fit = `fitsecs'
    if `rc' {
        return scalar secs = `fitsecs'
        return local note "csdid bal(pair), per-comparison balancing; used_N=`e(N)'"
        exit
    }

    * The event study is part of what a user asks for, so it is part of what
    * we time. csdid and jwdid deliver it in a SECOND call; every other command
    * in this comparison delivers it inside its single call. Timing only the
    * fit would hand these two a deliverable that the others pay for. The
    * split survives as secs_fit / secs_agg.
    timer clear 98
    timer on 98
    capture quietly estat event, window(0 `horizons')
    local arc = _rc
    timer off 98
    quietly timer list 98
    local aggsecs = r(t98)
    return scalar secs_agg = `aggsecs'
    return scalar secs = `fitsecs' + `aggsecs'
    if `arc' {
        return scalar ok = 0
        return local note "csdid bal(pair), per-comparison balancing; estat event rc=`arc'"
        exit
    }
    return local note "csdid bal(pair), per-comparison balancing; used_N=`e(N)'"
    matrix A = e(aggte)
    matrix ES = J(`horizons' + 1, 3, .)
    forvalues k = 1/`=`horizons'+1' {
        if `k' > rowsof(A) continue
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
    local fitsecs = r(t99)

    local acc "`e(bootstrap_accelerator)'"
    local accst "`e(bootstrap_accelerator_status)'"
    local accsec = .
    capture local accsec = e(bootstrap_accelerator_seconds)
    local accstr = trim(string(`accsec', "%12.4f"))

    return scalar ok = (`rc' == 0)
    return scalar secs_fit = `fitsecs'
    if `rc' {
        return scalar secs = `fitsecs'
        return local note "shipped-default inference: wboot reps(`reps') rseed(20260729) simultaneous bands; accelerator=`acc'/`accst' accel_secs=`accstr'"
        exit
    }

    * Under the shipped default the aggregation is NOT a cheap extraction:
    * csdid_estat recomputes the aggregate and, under wboot, re-draws the
    * multiplier bootstrap for the aggregate influence functions. Leaving it
    * outside the clock is what made the default look nearly free. Tier E
    * exists to price the default, so the price has to include this.
    timer clear 98
    timer on 98
    capture quietly estat event, window(0 `horizons')
    local arc = _rc
    timer off 98
    quietly timer list 98
    local aggsecs = r(t98)
    return scalar secs_agg = `aggsecs'
    return scalar secs = `fitsecs' + `aggsecs'
    if `arc' {
        return scalar ok = 0
        return local note "shipped-default inference: wboot reps(`reps') simultaneous bands; accelerator=`acc'/`accst'; estat event rc=`arc'"
        exit
    }
    return local note "shipped-default inference: wboot reps(`reps') rseed(20260729) simultaneous bands; accelerator=`acc'/`accst' accel_secs=`accstr'; fit=`=string(`fitsecs',"%9.3f")'s agg=`=string(`aggsecs',"%9.3f")'s"
    matrix A = e(aggte)
    matrix ES = J(`horizons' + 1, 3, .)
    forvalues k = 1/`=`horizons'+1' {
        if `k' > rowsof(A) continue
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
    capture return scalar secs_fit = r(secs_fit)
    capture return scalar secs_agg = r(secs_agg)
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

    if "$SB_ONLYN" != "" & "$SB_ONLYN" != "`n'" exit

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
    quietly levelsof gvar if gvar > 0, local(gs)
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
    if `h' < 1 local h = 1

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
        if "$SB_ONLYPKG" != "" & "$SB_ONLYPKG" != "`pkg'" continue

        * a _cov suffix is the same package with the DGP's covariate added
        local base "`pkg'"
        local copt ""
        local covnote "cov=none"
        if substr("`pkg'", -4, 4) == "_cov" {
            local base = substr("`pkg'", 1, length("`pkg'") - 4)
            local copt "covariates(x)"
            local covnote "cov=x"
        }

        * package label -> runner program, plus the structure the runner needs
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
        if "`base'" == "eventstudyinteract" local runner "esi"
        if "`base'" == "did_multiplegt_dyn" local runner "dcdh"
        if "`base'" == "jwdid" & "`structure'" == "rcs" local runner "jwdidrcs"
        if "`runner'" == "csdid" & "`structure'" == "rcs" local sopt "structure(rcs)"

        local med = .
        local lo = .
        local hi = .
        local ok = 0
        local rnote ""
        local medagg = .

        capture noisily bench_time, pkg(`runner') data("`d'") horizons(`h') ///
            cluster(cl) trials(`trials') `copt' `sopt' cap(120)
        local rc = _rc
        if `rc' {
            local rnote "harness error rc=`rc'"
        }
        else {
            capture local ok = r(ok)
            capture local med = r(med)
            capture local lo = r(lo)
            capture local hi = r(hi)
            capture local medagg = r(medagg)
            local rnote "`r(note)'"
        }

        local medstr = trim(string(`med', "%14.4f"))
        local lostr  = trim(string(`lo',  "%14.4f"))
        local histr  = trim(string(`hi',  "%14.4f"))
        local note "H=`h'; G_real=`greal'; nevertreated=`nevpct'%; `covnote'; min=`lostr'; max=`histr'"
        * commands that aggregate in a second call report the split, so the
        * share of the total spent aggregating stays visible in the record
        if !missing("`medagg'") & "`medagg'" != "." {
            local note "`note'; agg=`=trim(string(`medagg', "%14.4f"))'"
        }
        if "`extra'" != "" local note "`note'; `extra'"
        if "`rnote'" != "" local note "`note'; `rnote'"

        * a capped cell was measured once and never trialled: the record
        * must not claim otherwise, and the cap explanation leads the note
        local wtrials = cond(`ok' == -1, 0, `trials')
        if `ok' == -1 local note "`rnote'; `note'"
        sb_write, scan(`scan') n(`n') t(`t') g(`g') rows(`rows') pkg(`pkg') ///
            med(`medstr') trials(`wtrials') ok(`ok') note(`note')
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
*         unbalanced, seed 20260729 -> runiform() < 0.15 dropped). Rows land at
*         ~0.85 x n x T: 8.5k / 85k / 850k.
if "`tier'" == "A" {
    local ns "1000 10000 100000"
    if `issmoke' local ns "200"
    foreach n of local ns {
        sb_cell, scan(A_unbal) n(`n') t(10) g(4) structure(unbalanced) trials(`trials') ///
            pkgs(csdid_balfull csdid_balpair csdid_balnone jwdid did_imputation lpdid eventstudyinteract did_multiplegt_dyn xthdid)
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
            pkgs(csdid flexdid jwdid did_imputation hdid ///
                 csdid_cov flexdid_cov jwdid_cov did_imputation_cov hdid_cov)
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
            pkgs(csdid jwdid did_imputation lpdid eventstudyinteract did_multiplegt_dyn xthdid)
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
            pkgs(csdid jwdid did_imputation lpdid eventstudyinteract did_multiplegt_dyn xthdid)
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

* ---- G. balanced ladder, cross-package: same n ladder as tier A, T=10, G=4,
*         no missingness. csdid runs analytical clustered, as in every other
*         cross-package speed table.
if "`tier'" == "G" {
    local ns "1000 10000 100000"
    if `issmoke' local ns "200"
    foreach n of local ns {
        sb_cell, scan(G_bal) n(`n') t(10) g(4) structure(balanced) trials(`trials') ///
            pkgs(csdid_analytical jwdid did_imputation lpdid eventstudyinteract did_multiplegt_dyn xthdid)
    }
}

display as text "SB DONE tier=`tier' smoke=`issmoke'"