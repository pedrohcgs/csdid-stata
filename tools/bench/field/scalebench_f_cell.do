* Run from the bench/ folder of the replication package, with the csdid
* source tree in ../src.  Usage:  stata-mp -b do scalebench_f_cell.do csdid_182 F_n 1000 10 4 balanced 7 out.csv
* ---------------------------------------------------------------------------
* Tier F, ONE cell, ONE implementation, ONE Stata process.
*
*   stata-mp -b do scalebench_f_cell.do <impl> <scan> <n> <t> <g> <structure> <trials> <csv>
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
    * 1.82 refuses to run without drdid >= 1.91. This checks for it and errors
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
    assert strpos("`resolved'", "`root'/src/ado/csdid.ado") > 0
}
else {
    assert strpos("`resolved'", "`legacy'/codes/csdid.ado") > 0
}
display as text "F RESOLVED `impl' -> `resolved'"

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
quietly levelsof gvar if gvar > 0, local(gs)
local greal : word count `gs'
quietly count if gvar == 0
local nevpct = round(100 * r(N) / `rows', 0.1)
local first_g = floor(`t' / 3) + 1
local hmax = `t' - `first_g'
local h = min(5, `hmax')
if `h' < 1 local h = 1

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
display as text "F ROW `scan' `impl' n=`n' T=`t' G=`g' rows=`rows' med=`medstr' ok=`ok' trials=`trials'"
