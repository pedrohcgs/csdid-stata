* Run from the bench/ folder of the replication package, with the csdid
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
                if `s' < `best' local best = `s'
            }
            di "TIMED rcs `rows' `pkg' best=" %8.4f `best'
        }
    }
}
