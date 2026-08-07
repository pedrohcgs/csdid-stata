*-----------------------------------------------------------------------------
*      optcost.do -- what the option arms cost in run time
*-----------------------------------------------------------------------------
* The guide's timing protocol: one discarded warmup per (arm, dataset), then
* the median of the requested trials.
*   jwdid default vs method(regress) corr + estat, vce(unconditional)
*   lpdid default vs rw
* Output: optcost.csv, one row per (n, arm). Run from the bench/ folder.
*   Usage: stata-mp -b do optcost.do <trials>
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
