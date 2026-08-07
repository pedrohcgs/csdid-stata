* F059 -- the pre-test results survive posting.
*
* _csdid_post_replace_bv rebuilds e() from a hand-maintained enumeration after
* `ereturn clear'. e(wald_stat), e(wald_df) and e(wald_pvalue) were not in it,
* so both live posting paths -- `csdid ..., agg(event)' and
* `estat <type>, post' -- destroyed them.
*
* The failure was invisible in the output: csdid prints the pre-test line
* BEFORE the aggregation posts, so a run said
*     P-value for pre-test of parallel trends assumption:  0.16812
* and then `confirm scalar e(wald_pvalue)' failed -- against help csdid, which
* names exactly that confirm as the test for "a p-value was printed here", and
* against csdid_estat's help, which promises the estimation scalars survive
* posting.
*
* tests/meta/test-posting-scalar-coverage.sh gates the enumeration itself so
* the next scalar added to estimation cannot vanish the same way.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f059_make_panel
    version 15
    clear
    quietly set obs 120
    quietly generate long id = _n
    quietly generate double g = cond(mod(id, 4) == 0, 0, ///
        cond(mod(id, 4) == 1, 3, cond(mod(id, 4) == 2, 4, 0)))
    quietly expand 5
    quietly bysort id: generate double time = _n
    quietly generate double y = mod(id * 17 + time * 5, 29) / 29 ///
        + 0.2 * time + cond(g > 0 & time >= g, 1.1, 0)
end

* -----------------------------------------------------------------------
* Baseline: the pre-test is computable, so all three scalars are posted.
* -----------------------------------------------------------------------
f059_make_panel
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical
capture confirm scalar e(wald_pvalue)
assert _rc == 0
local w_stat = e(wald_stat)
local w_df = e(wald_df)
local w_p = e(wald_pvalue)
assert `w_stat' < . & `w_df' < . & `w_p' < .

* -----------------------------------------------------------------------
* 1. estat event, post keeps them.
* -----------------------------------------------------------------------
quietly estat event, post
foreach s in wald_stat wald_df wald_pvalue {
    capture confirm scalar e(`s')
    assert _rc == 0
}
assert reldif(e(wald_stat), `w_stat') < 1e-10
assert e(wald_df) == `w_df'
assert reldif(e(wald_pvalue), `w_p') < 1e-10

* -----------------------------------------------------------------------
* 2. csdid ..., agg(event) keeps them -- the run prints the pre-test line and
*    the scalar behind it has to still be there afterwards.
* -----------------------------------------------------------------------
f059_make_panel
quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical ///
    agg(event)
foreach s in wald_stat wald_df wald_pvalue {
    capture confirm scalar e(`s')
    assert _rc == 0
}
assert reldif(e(wald_stat), `w_stat') < 1e-10
assert e(wald_df) == `w_df'
assert reldif(e(wald_pvalue), `w_p') < 1e-10

* e(b) really is the aggregation, i.e. the post happened.
assert "`e(cmd)'" == "csdid"
matrix Bagg = e(b)
local bn : colnames Bagg
assert strpos("`bn'", "Post_avg") > 0

* -----------------------------------------------------------------------
* 3. Other estat aggregations that post keep them too.
* -----------------------------------------------------------------------
foreach agg in simple group calendar dynamic {
    f059_make_panel
    quietly csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical
    quietly estat `agg', post
    foreach s in wald_stat wald_df wald_pvalue {
        capture confirm scalar e(`s')
        assert _rc == 0
    }
}

display as text "test-f059: pre-test scalars survive posting OK"
