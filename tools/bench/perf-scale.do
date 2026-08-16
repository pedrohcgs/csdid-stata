* ---------------------------------------------------------------------------
* perf-scale.do -- wall clock at increasing n for the paths the deep
* performance items live on, so a change to them can be shown to pay.
*
*   stata-mp -b do tools/bench/perf-scale.do <tag> [nunits list]
*
* Writes tools/bench/perfscale/<tag>.csv with one row per (cell, n).
*
* The small differential grid in perf-differential.do exists to prove a change
* moves no NUMBER; it is deliberately tiny and its timings are noise. This one
* exists to prove a change moves the CLOCK, so it runs the same handful of
* configurations at sizes where an O(N) pass or a cache-hostile stride is
* visible, and it reports the median of three timed calls after a discarded
* warmup, per the protocol the published benchmark uses.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

* -args- splits on whitespace, so a quoted list would lose everything after
* the first size; take the tag off the front and keep the rest verbatim.
gettoken tag nlist : 0
local tag = strtrim(`"`tag'"')
local nlist = strtrim(`"`nlist'"')
if "`tag'" == "" {
    display as error "usage: do perf-scale.do <tag> [nunits list]"
    exit 198
}
if `"`nlist'"' == "" local nlist "5000 20000 80000"

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
capture mkdir "`root'/tools/bench/perfscale"

program define ps_data
    version 15
    syntax , NUNITS(integer) NPERIODS(integer)

    clear
    quietly set obs `nunits'
    quietly generate long id = _n
    quietly generate byte arm = mod(_n, 5)
    quietly generate double g = cond(arm == 0, 0, 2 + arm)
    quietly generate double cl = mod(id, 50) + 1
    quietly generate double w = 0.5 + mod(id * 7, 13) / 13
    quietly generate double ui = mod(id * 11, 23) / 23 - 0.5
    quietly expand `nperiods'
    quietly bysort id: generate double time = _n
    quietly generate double x1 = mod(id * 13 + time * 5, 29) / 29
    quietly generate double y = ui + 0.2 * time + 0.7 * x1 ///
        + mod(id * 5 + time * 3, 31) / 31 ///
        + cond(g > 0 & time >= g, 1.1 + 0.3 * (time - g), 0)
end

* median of three timed calls after one discarded warmup, on a freshly
* reloaded copy of the same data
program define ps_time, rclass
    version 15
    syntax , CMD(string) DATA(string)

    quietly use "`data'", clear
    capture quietly `cmd'
    local t1 = .
    local t2 = .
    local t3 = .
    forvalues k = 1/3 {
        quietly use "`data'", clear
        timer clear 9
        timer on 9
        capture quietly `cmd'
        timer off 9
        quietly timer list 9
        local t`k' = r(t9)
    }
    local lo = min(`t1', `t2', `t3')
    local hi = max(`t1', `t2', `t3')
    local md = `t1' + `t2' + `t3' - `lo' - `hi'
    return scalar median = `md'
    return scalar min = `lo'
    return scalar max = `hi'
end

* ---------------------------------------------------------------------------
* The same protocol for an AGGREGATION, which is a different shape of
* measurement: the estimation that has to run first is not what is being
* timed, so it sits outside the timer and inside the replicate.
*
* Every other cell in this file, and every cell of the other two timing
* instruments the refactor gates on, is an estimation. The stage that rewrote
* the aggregation path therefore had no cell that could see a regression in
* it; this is that cell.
*
* reps() consecutive aggregations sit under one timer and the result is
* divided by reps(), because Stata's timer resolves to 1ms and one aggregation
* on a design this size is a few milliseconds. Repeating it is also what a
* user does: estat event, then estat group, then estat calendar, each reading
* the same stored results back.
*
* Aggregating reads the influence functions back, and where they were left is
* the whole difference between the two routes. Under lean storage they stay in
* Mata and the aggregation reads the cache; under storeall they were posted to
* a Stata matrix and are read back across the classic-matrix layer, which is
* quadratic in the number of units (measured in csdid__Agg::store: 4s at
* 25,000, 148s at 100,000). So the storeall cell is capped by its caller at a
* size where that crossing is a fraction of a second and the aggregation is
* still what dominates.
* ---------------------------------------------------------------------------
program define ps_time_agg, rclass
    version 15
    syntax , EST(string) AGG(string) DATA(string) [REPS(integer 10)]

    quietly use "`data'", clear
    capture quietly `est'
    capture quietly `agg'
    local t1 = .
    local t2 = .
    local t3 = .
    forvalues k = 1/3 {
        quietly use "`data'", clear
        capture quietly `est'
        timer clear 9
        timer on 9
        forvalues r = 1/`reps' {
            capture quietly `agg'
        }
        timer off 9
        quietly timer list 9
        local t`k' = r(t9) / `reps'
    }
    local lo = min(`t1', `t2', `t3')
    local hi = max(`t1', `t2', `t3')
    local md = `t1' + `t2' + `t3' - `lo' - `hi'
    return scalar median = `md'
    return scalar min = `lo'
    return scalar max = `hi'
end

tempname fh
file open `fh' using "`root'/tools/bench/perfscale/`tag'.csv", write replace
file write `fh' "tag,cell,nunits,nobs,seconds,min,max" _n

tempfile d
foreach n of local nlist {
    ps_data, nunits(`n') nperiods(10)
    quietly save "`d'", replace
    quietly count
    local nobs = r(N)

    ps_time, data("`d'") cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical")
    file write `fh' "`tag',panel_reg_analytic,`n',`nobs',`=r(median)',`=r(min)',`=r(max)'" _n

    ps_time, data("`d'") cmd("csdid y x1, ivar(id) time(time) gvar(g) method(dr) notyet analytical")
    file write `fh' "`tag',panel_dr_cov,`n',`nobs',`=r(median)',`=r(min)',`=r(max)'" _n

    ps_time, data("`d'") cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical cluster(cl)")
    file write `fh' "`tag',panel_reg_cluster,`n',`nobs',`=r(median)',`=r(min)',`=r(max)'" _n

    ps_time, data("`d'") cmd("csdid y, time(time) gvar(g) method(reg) notyet analytical")
    file write `fh' "`tag',rcs_reg,`n',`nobs',`=r(median)',`=r(min)',`=r(max)'" _n

    ps_time, data("`d'") cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical bal(none)")
    file write `fh' "`tag',unbal_reg_none,`n',`nobs',`=r(median)',`=r(min)',`=r(max)'" _n

    ps_time, data("`d'") cmd("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet wboot(reps(199) rseed(20260806))")
    file write `fh' "`tag',panel_reg_wboot,`n',`nobs',`=r(median)',`=r(min)',`=r(max)'" _n

    local est_lean "csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical"
    ps_time_agg, data("`d'") est("`est_lean'") agg("estat event")
    file write `fh' "`tag',agg_dynamic,`n',`nobs',`=r(median)',`=r(min)',`=r(max)'" _n

    ps_time_agg, data("`d'") est("`est_lean'") agg("estat group")
    file write `fh' "`tag',agg_group,`n',`nobs',`=r(median)',`=r(min)',`=r(max)'" _n

    * The storeall route reads the influence functions back out of a Stata
    * matrix, and that crossing is quadratic in the unit count, so above this
    * size the cell would measure the crossing rather than the aggregation.
    if `n' <= 5000 {
        ps_time_agg, data("`d'") reps(5) ///
            est("csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical storeall") ///
            agg("estat event")
        file write `fh' "`tag',agg_storeall,`n',`nobs',`=r(median)',`=r(min)',`=r(max)'" _n
    }
}
file close `fh'

display as text "perf-scale: `tag' written"
