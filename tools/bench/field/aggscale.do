* Temporary: does estat event scale with n? -- not part of the suite.
clear all
set more off
args outfile
local root ".."
capture confirm file "`root'/src/ado/csdid.ado"
if _rc local root "../../.."
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
quietly do "fielddgp.do"

capture file close out
file open out using "`outfile'", write replace text
file write out "stata,n,rows,fit_seconds,estat_seconds" _n
local ver = c(stata_version)

foreach n in 1000 10000 100000 {
    mkpanel, n(`n')
    local rows = _N
    tempfile d
    quietly save "`d'", replace
    * warmup
    use "`d'", clear
    capture quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(999) rseed(20260729))
    capture quietly estat event
    * timed: median of 3
    tempname TF TE
    matrix `TF' = J(3,1,.)
    matrix `TE' = J(3,1,.)
    forvalues k = 1/3 {
        use "`d'", clear
        timer clear 8
        timer on 8
        quietly csdid y, ivar(id) time(time) gvar(gvar) wboot(reps(999) rseed(20260729))
        timer off 8
        timer clear 9
        timer on 9
        quietly estat event
        timer off 9
        quietly timer list 8
        matrix `TF'[`k',1] = r(t8)
        quietly timer list 9
        matrix `TE'[`k',1] = r(t9)
    }
    mata: st_matrix("`TF'", sort(st_matrix("`TF'"), 1))
    mata: st_matrix("`TE'", sort(st_matrix("`TE'"), 1))
    local vf = string(`TF'[2,1], "%12.0g")
    local ve = string(`TE'[2,1], "%12.0g")
    file write out "`ver',`n',`rows',`vf',`ve'" _n
}
file close out
display "MCDONE"
