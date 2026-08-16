* test-pscoretrim-binding.do
* ---------------------------------------------------------------------------
* Where the propensity-score trim cuts, on both estimation paths.
*
* DRDID keeps a control iff `ps.fit < trim.level'. With an intercept-only
* design the fitted score is the same constant for every unit, so the trim is
* all-or-nothing: below the treated share it empties the comparison group,
* mw.cont is exactly 0, drdid_panel returns 0/0 and did reports a missing ATT.
* Above it, nothing is trimmed at all.
*
* That leaves one case decided by the FIT rather than by the rule -- a treated
* share exactly equal to the trim level, which is what round designs give at a
* round pscoretrim() (995/1000 at the shipped default). R's score is fastglm's
* terminal IRLS iterate, whose float residue falls on DIFFERENT sides of the
* exact share at different shares and sample sizes (measured: 3.9e-15 under at
* 0.995, 1.5e-9 under at 0.90, exact at 0.50, up to 4.2e-15 over at 0.85), so
* no deterministic rule can match R-as-executed at every tie. csdid's
* convention is strict everywhere: a score exactly at the level empties the
* comparison group and the cell refuses loudly. Where that departs from R (a
* keep-side tie), the departure is a visible missing, never a silently
* reported number; see csdid__trim_keep and AGENTS.md.
*
* Qualification: the tie cells below fail against the tie-keeps variant
* (commit 0ff4184), where they return a finite ATT; the below-share refusal
* and method(reg) cells pass on both, which is what makes them the guard that
* pscoretrim() still binds.
*
* Designs are deterministic (no RNG): y = mod(id,13)/4 + (t==2)*mod(id,7)/8
* + 0.5*(g==2 & t==2), every term a dyadic rational, so the same doubles reach
* Stata and R. Reference values are did 2.5.1 / DRDID 1.3.0 with
* base_period = "varying", control_group = "nevertreated", bstrap = FALSE;
* did::att_gt does not forward trim.level, so a user-set trim is quoted from
* DRDID::drdid_panel / std_ipw_did_panel directly, which is what pscoretrim()
* documents. Tolerances are the ~1e-13 spread between the two summation
* orders, not a modelling allowance.
* ---------------------------------------------------------------------------
version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* att and se of the single estimated cell
program define _tb_cell, rclass
    tempname A
    matrix `A' = e(attgt)
    return scalar att = `A'[1, 4]
    return scalar se = `A'[1, 5]
end

*-----------------------------------------------------------------------------
* Design T: 1990 treated, 10 never-treated, treated share EXACTLY 0.995 -- the
* shipped pscoretrim() default.
*-----------------------------------------------------------------------------
clear
quietly set obs 2000
generate long id = _n
generate byte g = cond(id <= 1990, 2, 0)
quietly expand 2
quietly bysort id: generate byte t = _n
generate double y = mod(id, 13)/4 + (t == 2)*(mod(id, 7)/8) + 0.5*(g == 2 & t == 2)
tempfile dT
quietly save "`dT'"

*-----------------------------------------------------------------------------
* Part 1: at the tie the cell REFUSES, on both paths, in both kernels --
* csdid's documented strict convention. method(reg) fits no propensity score
* and reports the estimate (did 2.5.1 reg: 0.46231155778894462 panel,
* 0.46231155778895439 RCS).
*-----------------------------------------------------------------------------
foreach m in dr ipw {
    foreach fm in "" "nofast" {
        quietly csdid y, ivar(id) time(t) gvar(g) method(`m') ///
            base_period(varying) analytical `fm'
        _tb_cell
        assert missing(r(att)) & missing(r(se))
    }
    * repeated cross sections
    quietly csdid y, time(t) gvar(g) method(`m') base_period(varying) analytical
    _tb_cell
    assert missing(r(att))
}
foreach fm in "" "nofast" {
    quietly csdid y, ivar(id) time(t) gvar(g) method(reg) ///
        base_period(varying) analytical `fm'
    _tb_cell
    assert reldif(r(att), 0.46231155778894462) <= 1e-9
    assert reldif(r(se), 0.07104238298726416) <= 1e-9
}
quietly csdid y, time(t) gvar(g) method(reg) base_period(varying) analytical
_tb_cell
assert reldif(r(att), 0.46231155778895439) <= 1e-9
assert reldif(r(se), 0.32880647149335979) <= 1e-9

*-----------------------------------------------------------------------------
* Part 2: a trim BELOW the share still empties the comparison group. Keeping
* the tie must not turn pscoretrim() back into a no-op.
*
* DRDID at trim.level 0.99 and 0.50 on this design returns NaN, which did
* reports as NA. method(reg) never fits a propensity score and is unaffected.
*-----------------------------------------------------------------------------
foreach tl in .99 .5 {
    foreach m in dr ipw {
        foreach fm in "" "nofast" {
            quietly csdid y, ivar(id) time(t) gvar(g) method(`m') ///
                base_period(varying) analytical pscoretrim(`tl') `fm'
            _tb_cell
            assert missing(r(att)) & missing(r(se))
        }
        quietly csdid y, time(t) gvar(g) method(`m') base_period(varying) ///
            analytical pscoretrim(`tl')
        _tb_cell
        assert missing(r(att))
    }
    quietly csdid y, ivar(id) time(t) gvar(g) method(reg) ///
        base_period(varying) analytical pscoretrim(`tl')
    _tb_cell
    assert reldif(r(att), 0.46231155778894462) <= 1e-9
}

*-----------------------------------------------------------------------------
* Part 3: the same knife edge at a user-set trim. Design N is 900 treated and
* 100 never-treated, share exactly 0.9: the strict convention refuses at the
* tie (DRDID's undershooting iterate happens to keep here -- the documented
* knife-edge departure), and a trim below the share still refuses.
*-----------------------------------------------------------------------------
clear
quietly set obs 1000
generate long id = _n
generate byte g = cond(id <= 900, 2, 0)
quietly expand 2
quietly bysort id: generate byte t = _n
generate double y = mod(id, 13)/4 + (t == 2)*(mod(id, 7)/8) + 0.5*(g == 2 & t == 2)

foreach m in dr ipw {
    foreach fm in "" "nofast" {
        quietly csdid y, ivar(id) time(t) gvar(g) method(`m') ///
            base_period(varying) analytical pscoretrim(.90) `fm'
        _tb_cell
        assert missing(r(att)) & missing(r(se))

        quietly csdid y, ivar(id) time(t) gvar(g) method(`m') ///
            base_period(varying) analytical pscoretrim(.89) `fm'
        _tb_cell
        assert missing(r(att))
    }
}

*-----------------------------------------------------------------------------
* Part 4: method(ipw) with iweights refuses exactly the cells method(dr)
* refuses, on the two designs that pull the weighted and the unweighted share
* apart.
*
* Design A: 6000 treated (w = 1) and 5 never-treated (w = 6000). Unweighted
* share 0.99916736, weighted 0.16667. R's overlap_check_fail is UNWEIGHTED, so
* did 2.5.1 warns "overlap condition violated" and returns NA -- with and
* without the weights.
*-----------------------------------------------------------------------------
clear
quietly set obs 6005
generate long id = _n
generate byte g = cond(id <= 6000, 2, 0)
generate double wt = cond(id <= 6000, 1, 6000)
quietly expand 2
quietly bysort id: generate byte t = _n
generate double y = mod(id, 13)/4 + (t == 2)*(mod(id, 7)/8) + 0.5*(g == 2 & t == 2)

foreach m in ipw dr {
    quietly csdid y [iw=wt], ivar(id) time(t) gvar(g) method(`m') ///
        base_period(varying) analytical nofast
    _tb_cell
    assert missing(r(att))
    quietly csdid y, ivar(id) time(t) gvar(g) method(`m') ///
        base_period(varying) analytical
    _tb_cell
    assert missing(r(att))
}

*-----------------------------------------------------------------------------
* Design B: 500 treated (w = 1000) and 500 never-treated (w = 1). Unweighted
* share 0.5, weighted 0.99900099900099903 -- the share the ESTIMATOR trims on.
* DRDID with i.weights: trim.level 0.995 -> NaN for both estimators;
* trim.level 0.9999 -> dr ATT 0.49774999999999736 se 0.015801325102661499,
* std_ipw ATT 0.49775000000000419 se 0.015801325102661516.
*-----------------------------------------------------------------------------
clear
quietly set obs 1000
generate long id = _n
generate byte g = cond(id <= 500, 2, 0)
generate double wt = cond(id <= 500, 1000, 1)
quietly expand 2
quietly bysort id: generate byte t = _n
generate double y = mod(id, 13)/4 + (t == 2)*(mod(id, 7)/8) + 0.5*(g == 2 & t == 2)

foreach m in ipw dr {
    quietly csdid y [iw=wt], ivar(id) time(t) gvar(g) method(`m') ///
        base_period(varying) analytical nofast
    _tb_cell
    assert missing(r(att))
    quietly csdid y [iw=wt], ivar(id) time(t) gvar(g) method(`m') ///
        base_period(varying) analytical nofast pscoretrim(.9999)
    _tb_cell
    assert reldif(r(att), 0.49775000000000419) <= 1e-9
    assert reldif(r(se), 0.015801325102661516) <= 1e-9
}

*-----------------------------------------------------------------------------
* Part 5: the intercept-only ipw shortcut carries DRDID's own ceiling.
*
* It returns before csdid__cap_ps_rc() ever runs, so the pmin(ps.fit, 1 - 1e-06)
* that DRDID applies before forming ps/(1-ps) has to be applied there. It was
* 1 - 1e-08, two orders too permissive, which let a control weight reach ~1e8
* where DRDID's stops at ~1e6 and refused a cell DRDID estimates.
*
* 500 treated (w = 1e7) and 500 never-treated (w = 1): weighted share
* 0.99999990000001004, unweighted 0.5, so the unweighted overlap guard passes
* and the ceiling decides. At pscoretrim(.9999995) DRDID's clamped score
* 0.999999 is below the trim and std_ipw_did_panel returns ATT
* 0.49775000000000919, se 0.01580132510266152; the tolerance is loose because
* the shortcut forms the control mass as mean(w) - mean(w*d), which cancels to
* ~1e-10 at this weight ratio.
*-----------------------------------------------------------------------------
clear
quietly set obs 1000
generate long id = _n
generate byte g = cond(id <= 500, 2, 0)
generate double wt = cond(id <= 500, 1e7, 1)
quietly expand 2
quietly bysort id: generate byte t = _n
generate double y = mod(id, 13)/4 + (t == 2)*(mod(id, 7)/8) + 0.5*(g == 2 & t == 2)

quietly csdid y [iw=wt], ivar(id) time(t) gvar(g) method(ipw) ///
    base_period(varying) analytical nofast pscoretrim(.9999995)
_tb_cell
assert reldif(r(att), 0.49775000000000919) <= 1e-7
assert reldif(r(se), 0.01580132510266152) <= 1e-7

display as text "test-pscoretrim-binding passed"
