* Run the missing-row and point/inference checks on one frozen engine.
* Arguments: engine snapshot, published-script directory, output directory.
* Copy missing_rows_diagnostic.do into the output directory before running.
version 18
clear all
set more off
set linesize 255
set processors 1
args engine scripts outdir
assert "`engine'" != "" & "`scripts'" != "" & "`outdir'" != ""
do "`outdir'/missing_rows_diagnostic.do" "`engine'" "`scripts'/dgp.do" "`outdir'"

* Preserve the unchanged diagnostic's version context from the campaign.
version 15: do "`scripts'/hetx.do"
version 18
file open metrics using "`outdir'/publication-metrics.csv", write replace text
file write metrics "metric,value" _n
file open points using "`outdir'/point-inference.csv", write replace text
file write points "design,result_matrix,h,result_name,event_label,estimate,se" _n
local worst 0
foreach mat in B J B2 J2 {
    local names : colnames `mat'
    assert colsof(`mat') >= 3
    forvalues h=0/2 {
        local p = `h' + 1
        local name : word `p' of `names'
        if inlist("`mat'","B","B2") {
            assert "`name'" == "tau`h'"
            local event = `h'
        }
        else {
            local lev = real(subinstr(subinstr("`name'","bn.__event__","",.),".__event__","",.))
            assert !missing(`lev')
            local lab : value label __event__
            assert "`lab'" != ""
            local event : label (`lab') `lev'
            assert real("`event'") == `h'
        }
        assert !missing(`mat'[1,`p']) & !missing(`mat'[2,`p'])
        assert `mat'[2,`p'] > 0
        file write points "hetx,`mat',`h',`name',`event'," (string(`mat'[1,`p'],"%24.17g")) "," (string(`mat'[2,`p'],"%24.17g")) _n
    }
}
forvalues h=0/2 {
    local p = `h' + 1
    local worst = max(`worst',abs(B[1,`p']-J[1,`p']),abs(B2[1,`p']-J2[1,`p']))
    mr_metric, name("publication_hetx_e`h'_se_gap_percent") value(`=100*(B2[2,`p']/J2[2,`p']-1)')
}
mr_metric, name("publication_hetx_max_abs_point_difference") value(`worst')
mr_metric, name("publication_hetx_verified_horizons") value(3)

version 15: do "`scripts'/dcdhse.do"
version 18
local rn : rownames M
local vn : rownames V
local worst 0
local mingap .
local maxgap .
forvalues h=0/2 {
    local p = `h' + 1
    assert E[`p',1] == `h'
    local name : word `p' of `rn'
    local vname : word `p' of `vn'
    assert "`name'" == "Effect_`p'" & "`vname'" == "`name'"
    assert !missing(E[`p',2]) & !missing(E[`p',3]) & !missing(M[`p',1]) & !missing(V[`p',1])
    assert E[`p',3] > 0 & V[`p',1] > 0
    file write points "dcdhse,E,`h',ES`h',`h'," (string(E[`p',2],"%24.17g")) "," (string(E[`p',3],"%24.17g")) _n
    file write points "dcdhse,M,`h',`name',`h'," (string(M[`p',1],"%24.17g")) "," (string(sqrt(V[`p',1]),"%24.17g")) _n
    local worst = max(`worst',abs(E[`p',2]-M[`p',1]))
    local gap = 100*(E[`p',3]/sqrt(V[`p',1])-1)
    if `h' == 0 local mingap = `gap'
    else local mingap = min(`mingap',`gap')
    if `h' == 0 local maxgap = `gap'
    else local maxgap = max(`maxgap',`gap')
    mr_metric, name("publication_dcdh_e`h'_se_gap_percent") value(`gap')
}
mr_metric, name("publication_dcdh_max_abs_point_difference") value(`worst')
mr_metric, name("publication_dcdh_min_se_gap_percent") value(`mingap')
mr_metric, name("publication_dcdh_max_se_gap_percent") value(`maxgap')
mr_metric, name("publication_dcdh_verified_horizons") value(3)
file close metrics
file close points
assert c(processors) == 1
display as result "PUBLICATION-DIAGNOSTIC-COMPLETE"
