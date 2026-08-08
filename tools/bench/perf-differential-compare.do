* ---------------------------------------------------------------------------
* perf-differential-compare.do -- diff two snapshots written by
* perf-differential.do, channel by channel, and refuse to call them equal
* unless every channel is present in both.
*
*   stata-mp -b do tools/bench/perf-differential-compare.do <before> <after>
*
* Prints one PERFDIFF line per (cell, channel) that MOVED, one PERFDIFF-MISSING
* line per channel present in one snapshot and not the other, and a final
* PERFDIFF-VERDICT line. A snapshot that is missing files is not "equal": a
* change that makes a cell stop producing e(b) would otherwise read as no
* difference at all.
*
* Comparison is EXACT on the numbers (bitwise, via a difference of zero), not
* approximate. A performance change is expected to move nothing; anything that
* moves is either a defect or a deliberate parity change that has to be argued
* on its own terms.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

args before after
if "`after'" == "" {
    display as error "usage: do perf-differential-compare.do <before> <after>"
    exit 198
}

local root "`c(pwd)'"
local A "`root'/tools/bench/perfdiff/`before'"
local B "`root'/tools/bench/perfdiff/`after'"

local ndiff 0
local nmiss 0
local nsame 0

* Enumerate every file in the BEFORE snapshot, then check the reverse
* direction too so an added file is also reported.
local files : dir "`A'" files "*.dta"
foreach f of local files {
    capture confirm file "`B'/`f'"
    if _rc {
        display as text "PERFDIFF-MISSING `f' present in `before', absent in `after'"
        local ++nmiss
        continue
    }
    if substr("`f'", 1, 7) == "timing_" continue

    quietly use "`A'/`f'", clear
    quietly count
    local nA = r(N)
    tempfile aa
    quietly save "`aa'", replace
    quietly use "`B'/`f'", clear
    quietly count
    local nB = r(N)
    if `nA' != `nB' {
        display as text "PERFDIFF `f' ROWS `nA' -> `nB'"
        local ++ndiff
        continue
    }
    quietly describe, varlist
    local vB "`r(varlist)'"
    quietly use "`aa'", clear
    quietly describe, varlist
    local vA "`r(varlist)'"
    if "`vA'" != "`vB'" {
        display as text "PERFDIFF `f' VARLIST changed"
        local ++ndiff
        continue
    }

    * Classify the variables ONCE, against the BEFORE file, before the loop
    * starts loading other datasets. Doing the -confirm- inside the loop asks
    * about whatever happens to be in memory at the time, which after the
    * first iteration is the merged pair -- and then every variable looks like
    * a string.
    quietly use "`aa'", clear
    local numvars ""
    local strvars ""
    foreach v of local vA {
        capture confirm numeric variable `v'
        if !_rc {
            local numvars "`numvars' `v'"
        }
        else {
            local strvars "`strvars' `v'"
        }
    }

    local moved 0
    foreach v of local vA {
        local isnum : list v in numvars
        if `isnum' {
            quietly use "`aa'", clear
            quietly keep `v'
            quietly rename `v' __a
            quietly generate long __row = _n
            tempfile onecol
            quietly save "`onecol'", replace
            quietly use "`B'/`f'", clear
            quietly keep `v'
            quietly rename `v' __b
            quietly generate long __row = _n
            quietly merge 1:1 __row using "`onecol'", nogenerate
            * missing must match missing: a cell that starts or stops being
            * estimable is a change, and a plain difference would hide it
            quietly count if (__a >= .) != (__b >= .)
            local nm = r(N)
            quietly count if (__a < .) & (__b < .) & (__a != __b)
            local nd = r(N)
            if `nm' > 0 | `nd' > 0 {
                quietly generate double __d = abs(__a - __b) if (__a < .) & (__b < .)
                quietly summarize __d, meanonly
                local mx = r(max)
                display as text "PERFDIFF `f' `v' missing-pattern-diffs=`nm' value-diffs=`nd' maxabs=`mx'"
                local moved 1
            }
        }
        else {
            quietly use "`aa'", clear
            quietly keep `v'
            quietly rename `v' __a
            quietly generate long __row = _n
            tempfile onecol
            quietly save "`onecol'", replace
            quietly use "`B'/`f'", clear
            quietly keep `v'
            quietly rename `v' __b
            quietly generate long __row = _n
            quietly merge 1:1 __row using "`onecol'", nogenerate
            quietly count if __a != __b
            if r(N) > 0 {
                display as text "PERFDIFF `f' `v' STRING diffs=`r(N)'"
                local moved 1
            }
        }
    }
    if `moved' {
        local ++ndiff
    }
    else {
        local ++nsame
    }
}

local filesB : dir "`B'" files "*.dta"
foreach f of local filesB {
    capture confirm file "`A'/`f'"
    if _rc {
        display as text "PERFDIFF-MISSING `f' present in `after', absent in `before'"
        local ++nmiss
    }
}

* Timings, reported but never part of the verdict. One file per cell, so a
* per-process run cannot race on a shared append.
tempfile tA tB
local gotA 0
local filesTA : dir "`A'" files "timing_*.dta"
foreach f of local filesTA {
    quietly use "`A'/`f'", clear
    quietly rename seconds sec_before
    quietly drop rc
    if `gotA' quietly append using "`tA'"
    quietly save "`tA'", replace
    local gotA 1
}
local gotB 0
local filesTB : dir "`B'" files "timing_*.dta"
foreach f of local filesTB {
    quietly use "`B'/`f'", clear
    quietly rename seconds sec_after
    quietly drop rc
    if `gotB' quietly append using "`tB'"
    quietly save "`tB'", replace
    local gotB 1
}
if `gotA' & `gotB' {
    quietly use "`tB'", clear
    quietly merge 1:1 cell using "`tA'", keep(match) nogenerate
    quietly generate double ratio = sec_after / sec_before
    gsort -sec_before
    forvalues i = 1/`=_N' {
        local c = cell[`i']
        local sb : display %8.3f sec_before[`i']
        local sa : display %8.3f sec_after[`i']
        local rr : display %6.3f ratio[`i']
        display as text "PERFTIME `c' `sb' `sa' `rr'"
    }
    quietly summarize sec_before, meanonly
    local totb : display %8.3f r(sum)
    quietly summarize sec_after, meanonly
    local tota : display %8.3f r(sum)
    display as text "PERFTIME TOTAL `totb' -> `tota'"
}

display as text "PERFDIFF-VERDICT identical=`nsame' moved=`ndiff' missing=`nmiss'"
if `ndiff' > 0 | `nmiss' > 0 {
    display as error "PERFDIFF-VERDICT NOT IDENTICAL"
}
else {
    display as text "PERFDIFF-VERDICT ALL CHANNELS IDENTICAL"
}
