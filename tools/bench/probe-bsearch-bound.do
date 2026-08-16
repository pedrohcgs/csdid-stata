* ---------------------------------------------------------------------------
* What it costs a binary search to ask for its own upper bound in the form
* that works for BOTH a row vector and a column vector.
*
* csdid__time_index (row vector, cols()) and csdid__sorted_col_index (column
* vector, rows()) are the same sixteen lines twice; a single routine declared
* `real vector' can serve both, and the only thing it has to do differently is
* take its upper bound with length() instead. Both helpers are called PER ROW
* of the estimation sample, which is a no-go zone for per-call overhead, so
* the difference is measured before the merge and not argued about.
*
* The bound is taken ONCE per call, outside the while loop, so what is being
* priced here is one builtin call per search and not one per iteration.
*
*   stata-mp -b do tools/bench/probe-bsearch-bound.do
*
* Writes tools/bench/perfscale/probe-bsearch-bound.csv (round, form, seconds).
* ---------------------------------------------------------------------------
clear all
set more off

* --- parameters ------------------------------------------------------------
local REPS    400000
local NLEVELS 40
local ROUNDS  3
local OUT     "tools/bench/perfscale/probe-bsearch-bound.csv"

mata:
mata set matastrict on

real scalar probe__cols(real rowvector tlist, real scalar tval)
{
    real scalar lo, hi, mid

    lo = 1
    hi = cols(tlist)
    while (lo <= hi) {
        mid = floor((lo + hi) / 2)
        if (tlist[mid] == tval) return(mid)
        if (tlist[mid] < tval) {
            lo = mid + 1
        }
        else {
            hi = mid - 1
        }
    }
    return(.)
}

real scalar probe__rows(real colvector values, real scalar target)
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

real scalar probe__length(real vector values, real scalar target)
{
    real scalar lo, hi, mid

    lo = 1
    hi = length(values)
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

void probe_bsearch(real scalar reps, real scalar nlevels, real scalar rounds,
                   string scalar outfile)
{
    real rowvector tlist
    real colvector values
    real scalar r, i, t0, acc, fh, target

    tlist  = 1..nlevels
    values = (1::nlevels)

    fh = fopen(outfile, "w")
    fput(fh, "round,form,seconds")

    for (r = 1; r <= rounds; r++) {
        // row vector, cols()
        t0 = timer_clear(9), timer_on(9)
        acc = 0
        for (i = 1; i <= reps; i++) {
            target = mod(i, nlevels) + 1
            acc = acc + probe__cols(tlist, target)
        }
        timer_off(9)
        fput(fh, sprintf("%f,rowvector_cols,%12.0g", r, timer_value(9)[1]))

        // column vector, rows()
        timer_clear(9), timer_on(9)
        acc = 0
        for (i = 1; i <= reps; i++) {
            target = mod(i, nlevels) + 1
            acc = acc + probe__rows(values, target)
        }
        timer_off(9)
        fput(fh, sprintf("%f,colvector_rows,%12.0g", r, timer_value(9)[1]))

        // row vector through the merged form, length()
        timer_clear(9), timer_on(9)
        acc = 0
        for (i = 1; i <= reps; i++) {
            target = mod(i, nlevels) + 1
            acc = acc + probe__length(tlist, target)
        }
        timer_off(9)
        fput(fh, sprintf("%f,rowvector_length,%12.0g", r, timer_value(9)[1]))

        // column vector through the merged form, length()
        timer_clear(9), timer_on(9)
        acc = 0
        for (i = 1; i <= reps; i++) {
            target = mod(i, nlevels) + 1
            acc = acc + probe__length(values, target)
        }
        timer_off(9)
        fput(fh, sprintf("%f,colvector_length,%12.0g", r, timer_value(9)[1]))

        if (acc < 0) printf("unreachable\n")
    }
    fclose(fh)
}
end

mata: probe_bsearch(`REPS', `NLEVELS', `ROUNDS', "`OUT'")

import delimited "`OUT'", clear varnames(1) asdouble
collapse (min) seconds, by(form)
generate double per_call_ns = seconds / `REPS' * 1e9
list form seconds per_call_ns, noobs
display as text "probe-bsearch-bound: `REPS' calls x `ROUNDS' rounds, minimum of rounds"
