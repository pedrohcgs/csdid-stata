* Missing-row mechanisms, with the original DGPs and seeds made explicit.
* Run: do missing_rows_diagnostic.do <engine snapshot> <dgp.do> <output dir>
* Main panel: n=2000, T=10, seed=20260729, four treatment cohorts,
* and 15% MCAR row deletion. Surgical panel: n=500, T=7, the same
* seed and cohort design, with one cohort-4 unit's observations removed.
version 18
clear all
set more off
set linesize 255
set processors 1
args engine dgp outdir
assert "`engine'" != ""
assert "`dgp'" != ""
assert "`outdir'" != ""
adopath ++ "`engine'/pkg"
adopath ++ "`engine'/src/mata"
adopath ++ "`engine'/src/ado"
quietly _csdid_engine_load
mata: st_local("engine_stamp", csdid_mlib_version())
assert "`engine_stamp'" == "2.0.1|17"
file open ident using "`outdir'/identity.txt", write replace text
file write ident "stata_version=`c(stata_version)'" _n
file write ident "stata_edition=`c(edition_real)'" _n
file write ident "stata_processors=`c(processors)'" _n
file write ident "stata_born=`c(born_date)'" _n
file write ident "engine_stamp=`engine_stamp'" _n
foreach cmd in csdid csdid_stats _csdid_engine_load jwdid did_imputation xthdidregress gencohort did_multiplegt_dyn lpdid eventstudyinteract flexdid reghdfe ftools drdid {
    quietly findfile `cmd'.ado
    file write ident "package:`cmd'=`r(fn)'" _n
}
capture findfile lmoremata.mlib
if _rc file write ident "package:lmoremata=MISSING" _n
else file write ident "package:lmoremata=`r(fn)'" _n
file close ident
quietly do "`dgp'"

file open metrics using "`outdir'/missing-row-metrics.csv", write replace text
file write metrics "metric,value" _n
file open indicators using "`outdir'/indicator-history.csv", write replace text
file write indicators "command,dataset,h,estimate,abs_difference_from_removed_unit" _n
file open cells using "`outdir'/paired-cells.csv", write replace text
file write cells "labels,group,time,xthdid,hand_pair,csdid_pair,abs_xthdid_hand,abs_xthdid_csdid,status" _n
file open dynamic using "`outdir'/dynamic-labels.csv", write replace text
file write dynamic "h,derived_labels,true_labels,difference" _n

program define mr_metric
    syntax , NAME(string) VALUE(real)
    assert !missing(`value')
    file write metrics "`name'," (string(`value', "%24.17g")) _n
end

program define mr_indicator, rclass
    syntax , CMD(string) DATA(string)
    use "`data'", clear
    quietly xtset id time
    tempname E
    matrix `E' = J(3,1,.)
    if "`cmd'" == "xthdid" {
        quietly xthdidregress ra (y) (treated), group(id) vce(cluster cl)
        quietly estat aggregation, dynamic
        matrix EV = r(table)
        local names : colnames EV
        forvalues h=0/2 {
            local p : list posof "`h'" in names
            assert `p' > 0
            matrix `E'[`h'+1,1] = EV[1,`p']
        }
    }
    else if "`cmd'" == "dcdh" {
        quietly did_multiplegt_dyn y id time treated, effects(3) cluster(cl) graph_off
        forvalues h=0/2 {
            matrix `E'[`h'+1,1] = e(Effect_`=`h'+1')
        }
    }
    else if "`cmd'" == "lpdid" {
        quietly lpdid y, unit(id) time(time) treat(treated) post_window(2) pre_window(2) cluster(cl) nograph
        matrix EV = e(results)
        local names : rownames EV
        forvalues h=0/2 {
            local p : list posof "tau`h'" in names
            assert `p' > 0
            matrix `E'[`h'+1,1] = EV[`p',1]
        }
    }
    forvalues h=0/2 {
        assert !missing(`E'[`h'+1,1])
    }
    return matrix E = `E'
end

program define mr_pair, rclass
    syntax , DATA(string) COHORT(name) G(integer) T(integer)
    preserve
    use "`data'", clear
    local b = `g' - 1
    quietly keep if inlist(time, `b', `t') & inlist(`cohort', 0, `g')
    quietly bysort id: generate int nper = _N
    quietly keep if nper == 2
    quietly summarize y if `cohort' == `g' & time == `t', meanonly
    assert r(N) > 0
    local ty = r(mean)
    quietly summarize y if `cohort' == `g' & time == `b', meanonly
    assert r(N) > 0
    local tb = r(mean)
    quietly summarize y if `cohort' == 0 & time == `t', meanonly
    assert r(N) > 0
    local cy = r(mean)
    quietly summarize y if `cohort' == 0 & time == `b', meanonly
    assert r(N) > 0
    local cb = r(mean)
    restore
    return scalar att = (`ty' - `tb') - (`cy' - `cb')
end

program define mr_cells
    syntax , DATA(string) COHORT(name) LABEL(string) XMATRIX(name) [NCELLS(integer 0)]
    local xnames : colfullnames `xmatrix'
    use "`data'", clear
    quietly csdid y, ivar(id) time(time) gvar(`cohort') method(reg) nevertreated cluster(cl) analytical pointwise bal(pair)
    matrix CS = e(attgt)
    local n 0
    local unavailable 0
    local wh 0
    local wc 0
    forvalues i=1/`=rowsof(CS)' {
        local g = CS[`i',colnumb(CS,"group")]
        local t = CS[`i',colnumb(CS,"time")]
        if `t' < `g' continue
        local cs = CS[`i',colnumb(CS,"att")]
        local hit ""
        foreach nm of local xnames {
            if strpos("`nm'", ":") == 0 continue
            local eq = real(substr("`nm'",1,strpos("`nm'",":")-1))
            local rest = substr("`nm'",strpos("`nm'",":")+1,.)
            local lev = real(subinstr(subinstr("`rest'","bn.time","",.),".time","",.))
            if `eq' == `g' & `lev' == `t' & strpos("`rest'","bn") == 0 local hit "`nm'"
        }
        if missing(`cs') {
            * Later derived cohorts have no observed immediately preceding
            * base. Record the finite xthdid value rather than asserting an
            * unsupported universal paired-cell equivalence.
            assert CS[`i',colnumb(CS,"n_treat_pre")] == 0
            assert "`hit'" != ""
            local p : list posof "`hit'" in xnames
            local xv = `xmatrix'[1,`p']
            assert !missing(`xv')
            local ++unavailable
            file write cells "`label',`g',`t'," (string(`xv',"%24.17g")) ",,,,,no_paired_base" _n
            continue
        }
        assert "`hit'" != ""
        local p : list posof "`hit'" in xnames
        local xv = `xmatrix'[1,`p']
        mr_pair, data("`data'") cohort(`cohort') g(`g') t(`t')
        local hv = r(att)
        local dh = abs(`xv'-`hv')
        local dc = abs(`xv'-`cs')
        assert reldif(`xv',`hv') < 1e-12
        assert reldif(`xv',`cs') < 1e-12
        local wh = max(`wh',`dh')
        local wc = max(`wc',`dc')
        local ++n
        file write cells "`label',`g',`t'," (string(`xv',"%24.17g")) "," (string(`hv',"%24.17g")) "," (string(`cs',"%24.17g")) "," (string(`dh',"%24.17g")) "," (string(`dc',"%24.17g")) ",paired" _n
    }
    assert `n' > 0
    if `ncells' > 0 assert `n' == `ncells'
    mr_metric, name("missing_`label'_post_cells") value(`n')
    mr_metric, name("missing_`label'_unavailable_post_cells") value(`unavailable')
    mr_metric, name("missing_`label'_total_post_cells") value(`=`n'+`unavailable'')
    mr_metric, name("missing_`label'_xthdid_finite_without_pair") value(`unavailable')
    mr_metric, name("missing_`label'_pair_max_abs") value(`wh')
    mr_metric, name("missing_`label'_csdid_max_abs") value(`wc')
end

* One deleted first-treated row; record every dynamic horizon, without
* presuming that the unit's earlier control contributions also disappear.
quietly bench_dgp, design(dynamic) n(500) t(7) seed(20260729) cohorts(4)
quietly bench_structure, structure(balanced) seed(20260729)
quietly levelsof id if gvar == 4, local(g4)
local u : word 1 of `g4'
mr_metric, name("missing_surgical_probe_id") value(`u')
tempfile FULL P1 P2 NOU
quietly save "`FULL'"
quietly drop if id == `u' & time == 4
quietly save "`P1'"
use "`FULL'", clear
quietly drop if id == `u' & inlist(time,3,4)
quietly save "`P2'"
use "`FULL'", clear
quietly drop if id == `u'
quietly save "`NOU'"
foreach cmd in xthdid dcdh lpdid {
    mr_indicator, cmd(`cmd') data("`NOU'")
    matrix NO = r(E)
    foreach variant in FULL P1 P2 {
        mr_indicator, cmd(`cmd') data("``variant''")
        matrix EV = r(E)
        local worst 0
        forvalues h=0/2 {
            local e = EV[`h'+1,1]
            local delta = abs(`e'-NO[`h'+1,1])
            local worst = max(`worst',`delta')
            mr_metric, name("missing_`cmd'_`variant'_h`h'_abs_gap") value(`delta')
            file write indicators "`cmd',`variant',`h'," (string(`e',"%24.17g")) "," (string(`delta',"%24.17g")) _n
        }
        mr_metric, name("missing_`cmd'_`variant'_max_abs_dynamic_gap") value(`worst')
        if inlist("`variant'","P1","P2") {
            local same_h1 = reldif(EV[2,1],NO[2,1]) < 1e-12
            mr_metric, name("missing_`cmd'_`variant'_h1_equal_1e12") value(`same_h1')
            if "`cmd'" == "xthdid" | ("`cmd'" == "lpdid" & "`variant'" == "P2") {
                forvalues h=0/2 {
                    assert reldif(EV[`h'+1,1],NO[`h'+1,1]) < 1e-12
                }
            }
            if "`cmd'" == "lpdid" {
                assert `same_h1'
                assert reldif(EV[3,1],NO[3,1]) < 1e-12
            }
        }
    }
}

* Original 15%-MCAR experiment, including every usercohort post cell.
quietly bench_dgp, design(dynamic) n(2000) t(10) seed(20260729) cohorts(4)
quietly bench_structure, structure(unbalanced) seed(20260729)
quietly xtset id time
quietly bysort id: egen double dercoh = min(cond(treated==1,time,.))
quietly replace dercoh = 0 if missing(dercoh)
quietly bysort id: generate byte unit_tag = (_n==1)
quietly count if unit_tag & gvar>0
mr_metric, name("missing_xthdid_treated_units") value(`=r(N)')
quietly count if unit_tag & gvar>0 & dercoh!=gvar
mr_metric, name("missing_xthdid_relabelled_units") value(`=r(N)')
drop unit_tag
tempfile UNBAL
quietly save "`UNBAL'"
quietly xthdidregress ra (y) (treated), group(id) vce(cluster cl)
matrix XD = e(b)
quietly estat aggregation, dynamic
matrix ED = r(table)
local nd : colnames ED
use "`UNBAL'", clear
quietly xthdidregress ra (y) (treated), group(id) usercohort(gvar) vce(cluster cl)
matrix XU = e(b)
quietly estat aggregation, dynamic
matrix EU = r(table)
local nu : colnames EU
local maxshift 0
local minshift 0
local maxsignedshift 0
forvalues h=0/5 {
    local pd : list posof "`h'" in nd
    local pu : list posof "`h'" in nu
    assert `pd' > 0 & `pu' > 0
    local diff = ED[1,`pd'] - EU[1,`pu']
    local maxshift = max(`maxshift',abs(`diff'))
    local minshift = min(`minshift',`diff')
    local maxsignedshift = max(`maxsignedshift',`diff')
    file write dynamic "`h'," (string(ED[1,`pd'],"%24.17g")) "," (string(EU[1,`pu'],"%24.17g")) "," (string(`diff',"%24.17g")) _n
}
mr_metric, name("missing_xthdid_max_abs_dynamic_shift") value(`maxshift')
mr_metric, name("missing_xthdid_min_signed_dynamic_shift") value(`minshift')
mr_metric, name("missing_xthdid_max_signed_dynamic_shift") value(`maxsignedshift')
mr_cells, data("`UNBAL'") cohort(dercoh) label(derived) xmatrix(XD)
mr_cells, data("`UNBAL'") cohort(gvar) label(usercohort) xmatrix(XU) ncells(22)

* Count the exact rows the documented jwdid unit screen removes.
use "`UNBAL'", clear
local before = _N
quietly bysort id: egen int first_retained = min(time)
quietly generate byte predicted_drop = gvar>0 & first_retained>=gvar
quietly count if predicted_drop
local predicted_rows = r(N)
quietly bysort id: generate byte unit_tag = (_n==1)
quietly count if predicted_drop & unit_tag
local predicted_units = r(N)
drop first_retained unit_tag
log using "`outdir'/jwdid-call.log", text replace name(mr_jw)
noisily jwdid y, ivar(id) tvar(time) gvar(gvar) cluster(cl)
log close mr_jw
local after = _N
quietly count if !e(sample)
local excluded_rows = r(N)
assert e(sample) == !predicted_drop
mr_metric, name("missing_jwdid_predicted_removed_units") value(`predicted_units')
mr_metric, name("missing_jwdid_removed_rows") value(`excluded_rows')
mr_metric, name("missing_jwdid_predicted_removed_rows") value(`predicted_rows')
mr_metric, name("missing_jwdid_data_rows_removed") value(`=`before'-`after'')
assert `excluded_rows' == `predicted_rows'
assert `before' == `after'

* Never-treated coding: the same documented usercohort probe records the
* refusal explicitly rather than treating an expected caught error as a pass.
use "`UNBAL'", clear
quietly generate double gm = cond(gvar==0,.,gvar)
capture noisily xthdidregress ra (y) (treated), group(id) usercohort(gm) vce(cluster cl)
local missing_never_rc = _rc
mr_metric, name("missing_usercohort_never_missing_rc") value(`missing_never_rc')
assert `missing_never_rc' != 0

file close metrics
file close indicators
file close cells
file close dynamic
display as result "MISSING-ROW-DIAGNOSTIC-COMPLETE"
