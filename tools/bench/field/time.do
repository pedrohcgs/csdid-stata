* Run from the bench/ folder of the replication package. Not run on its
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
        [COVariates(varlist) MODE(string) STRUCTure(string) TRIALS(integer 5) CAP(real 0)]

    if "`mode'" == "" local mode "pointwise"
    local sopt ""
    if "`pkg'" == "csdid" & "`structure'" != "" local sopt "structure(`structure')"

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
    local warmsecs = r(secs)

    * a command that failed its warmup has nothing to time: running the
    * trials anyway would record the cost of failing, not of estimating
    if `ok' != 1 {
        return scalar ok = `ok'
        return scalar med = .
        return scalar medagg = .
        return local note "`note'; warmup failed, trials skipped"
        exit
    }

    * Per-call cap, mirroring the Version 1.82 tier's 120-second skip
    * rule: a cell whose single WARMUP call exceeds the cap is recorded,
    * not timed. The warmup seconds go into the note so the table can say
    * how far past the cap the call went. ok = -1 distinguishes "measured
    * once, too slow to trial" from a runner failure.
    if `cap' > 0 & `ok' == 1 & `warmsecs' > `cap' {
        return scalar ok = -1
        return scalar med = .
        return local note "`note'; not timed: single warmup call took `=string(`warmsecs', "%9.1f")'s, past the `cap's cap"
        exit
    }

    tempname T
    matrix `T' = J(`trials', 2, .)
    forvalues i = 1/`trials' {
        use "`data'", clear
        quietly bench_`pkg', horizons(`horizons') cluster(`cluster') ///
            covariates(`covariates') mode(`mode') `sopt'
        matrix `T'[`i', 1] = r(secs)
        * runners that deliver the event study in the estimation call return
        * no split; their aggregation cost is already inside column 1
        capture matrix `T'[`i', 2] = r(secs_agg)
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
    quietly count if !missing(t2)
    local hasagg = (r(N) > 0)
    local medagg = .
    if `hasagg' {
        quietly summarize t2, detail
        local medagg = r(p50)
    }
    restore

    return scalar ok = `ok'
    return scalar med = `med'
    return scalar lo = `lo'
    return scalar hi = `hi'
    return scalar medagg = `medagg'
    return local note "`note'"
end