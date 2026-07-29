version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

mata:
real scalar f032__sd(real colvector v)
{
    real scalar n, m

    n = rows(v)
    if (n <= 1) return(.)
    m = mean(v)
    return(sqrt(quadcrossdev(v, m, v, m) / (n - 1)))
}

void f032__summarize_if(string scalar attname, string scalar ifname, string scalar outname)
{
    real matrix att, inf, out
    real colvector v
    real scalar k, sumsq

    att = st_matrix(attname)
    inf = st_matrix(ifname)
    out = J(cols(inf), 10, .)
    for (k = 1; k <= cols(inf); k++) {
        v = inf[., k]
        sumsq = quadcross(v, v)
        out[k, .] = (
            att[k, 1], att[k, 2], att[k, 3], k,
            mean(v), f032__sd(v), sum(v), sumsq,
            min(v), max(v)
        )
    }
    st_matrix(outname, out)
}

void f032__gram(string scalar ifname, string scalar outname)
{
    real matrix inf

    inf = st_matrix(ifname)
    st_matrix(outname, quadcross(inf, inf))
}

real scalar f032__matrix_maxabsdiff(string scalar aname, string scalar bname)
{
    real matrix a, b

    a = st_matrix(aname)
    b = st_matrix(bname)
    if (rows(a) != rows(b) | cols(a) != cols(b)) return(.)
    return(max(abs(vec(a :- b))))
}
end

program define f032_save_agg, eclass
    version 15
    syntax , TYPE(string) SAVING(string)

    csdid_stats, type(`type')
    matrix M = e(aggte)
    preserve
    clear
    svmat double M, names(col)
    gen str16 type = "`type'"
    gen seq = _n
    save "`saving'", replace
    restore
end

program define f032_collect_aggs
    version 15
    syntax , SAVING(string) DATA(string) [FAST NOFAST]

    tempfile part all
    local fastopt ""
    if "`fast'" != "" local fastopt "fast"
    if "`nofast'" != "" local fastopt "nofast"
    local first 1
    foreach type in simple group calendar dynamic {
        import delimited using "`data'", clear asdouble
        csdid y, ivar(id) time(time) gvar(g) method(reg) `fastopt' analytical nevertreated base_period(varying) bal(none)
        f032_save_agg, type(`type') saving("`part'")
        if `first' {
            use "`part'", clear
            save "`all'", replace
            local first 0
        }
        else {
            use "`all'", clear
            append using "`part'"
            save "`all'", replace
        }
    }
    use "`all'", clear
    save "`saving'", replace
end

tempfile base_att fast_att shuffle_att base_if fast_if shuffle_if
tempfile base_gram fast_gram shuffle_gram base_agg fast_agg shuffle_agg actual_agg

import delimited using "`root'/tests/fixtures/parity/f032/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) nofast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 0
assert e(fast_allowed) == 0
assert e(fast_used) == 0
assert "`e(fast_mode)'" == "off"
assert "`e(compute_path)'" == "baseline"
matrix A0 = e(attgt)
matrix IF0 = e(inffunc)
mata: f032__summarize_if("A0", "IF0", "S0")
matrix colnames S0 = group time event_time inffunc_col mean sd sum sumsq min max
mata: f032__gram("IF0", "G0")
preserve
clear
svmat double A0, names(col)
rename (att se) (att_base se_base)
save "`base_att'", replace
restore
preserve
clear
svmat double S0, names(col)
rename (mean sd sum sumsq min max) ///
       (mean_base sd_base sum_base sumsq_base min_base max_base)
save "`base_if'", replace
restore
preserve
clear
svmat double G0
gen row = _n
reshape long G0, i(row) j(col)
rename G0 gram_base
save "`base_gram'", replace
restore
f032_collect_aggs, saving("`base_agg'") data("`root'/tests/fixtures/parity/f032/inputs/input.csv") nofast

import delimited using "`root'/tests/fixtures/parity/f032/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) fast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 1
assert e(fast_allowed) == 1
assert e(fast_used) == 1
assert "`e(fast_mode)'" == "on"
assert "`e(compute_path)'" == "fast-balanced-panel"
matrix A1 = e(attgt)
matrix IF1 = e(inffunc)
mata: f032__summarize_if("A1", "IF1", "S1")
matrix colnames S1 = group time event_time inffunc_col mean sd sum sumsq min max
mata: f032__gram("IF1", "G1")
preserve
clear
svmat double A1, names(col)
rename (att se) (att_fast se_fast)
save "`fast_att'", replace
restore
preserve
clear
svmat double S1, names(col)
rename (mean sd sum sumsq min max) ///
       (mean_fast sd_fast sum_fast sumsq_fast min_fast max_fast)
save "`fast_if'", replace
restore
preserve
clear
svmat double G1
gen row = _n
reshape long G1, i(row) j(col)
rename G1 gram_fast
save "`fast_gram'", replace
restore
f032_collect_aggs, saving("`fast_agg'") data("`root'/tests/fixtures/parity/f032/inputs/input.csv") fast

import delimited using "`root'/tests/fixtures/parity/f032/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 0
assert e(fast_auto) == 1
assert e(fast_allowed) == 1
assert e(fast_used) == 1
assert "`e(fast_mode)'" == "auto"
assert "`e(compute_path)'" == "fast-balanced-panel"
matrix Aauto = e(attgt)
mata: st_numscalar("f032_auto_fast_diff", f032__matrix_maxabsdiff("A1", "Aauto"))
assert scalar(f032_auto_fast_diff) <= 1e-12

import delimited using "`root'/tests/fixtures/parity/f032/inputs/input-shuffled.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) fast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-balanced-panel"
matrix A2 = e(attgt)
matrix IF2 = e(inffunc)
mata: f032__summarize_if("A2", "IF2", "S2")
matrix colnames S2 = group time event_time inffunc_col mean sd sum sumsq min max
mata: f032__gram("IF2", "G2")
preserve
clear
svmat double A2, names(col)
rename (att se) (att_shuffle se_shuffle)
save "`shuffle_att'", replace
restore
preserve
clear
svmat double S2, names(col)
rename (mean sd sum sumsq min max) ///
       (mean_shuffle sd_shuffle sum_shuffle sumsq_shuffle min_shuffle max_shuffle)
save "`shuffle_if'", replace
restore
preserve
clear
svmat double G2
gen row = _n
reshape long G2, i(row) j(col)
rename G2 gram_shuffle
save "`shuffle_gram'", replace
restore
f032_collect_aggs, saving("`shuffle_agg'") data("`root'/tests/fixtures/parity/f032/inputs/input-shuffled.csv") fast

import delimited using "`root'/tests/fixtures/parity/f032/expected/r/attgt.csv", clear asdouble
merge 1:1 group time using "`base_att'", nogen assert(match)
merge 1:1 group time using "`fast_att'", nogen assert(match)
merge 1:1 group time using "`shuffle_att'", nogen assert(match)
assert abs(att - att_base) <= 1e-8 + 1e-8 * abs(att)
assert abs(se - se_base) <= 1e-8 + 1e-8 * abs(se)
assert abs(att - att_fast) <= 1e-8 + 1e-8 * abs(att)
assert abs(se - se_fast) <= 1e-8 + 1e-8 * abs(se)
assert abs(att - att_shuffle) <= 1e-8 + 1e-8 * abs(att)
assert abs(se - se_shuffle) <= 1e-8 + 1e-8 * abs(se)
assert abs(att_base - att_fast) <= 1e-12 + 1e-12 * abs(att_base)
assert abs(se_base - se_fast) <= 1e-12 + 1e-12 * abs(se_base)
assert abs(att_base - att_shuffle) <= 1e-12 + 1e-12 * abs(att_base)
assert abs(se_base - se_shuffle) <= 1e-12 + 1e-12 * abs(se_base)

use "`base_if'", clear
merge 1:1 group time event_time inffunc_col using "`fast_if'", nogen assert(match)
merge 1:1 group time event_time inffunc_col using "`shuffle_if'", nogen assert(match)
foreach v in mean sd sum sumsq min max {
    assert abs(`v'_base - `v'_fast) <= 1e-10 + 1e-10 * abs(`v'_base)
    assert abs(`v'_base - `v'_shuffle) <= 1e-10 + 1e-10 * abs(`v'_base)
}

use "`base_gram'", clear
merge 1:1 row col using "`fast_gram'", nogen assert(match)
merge 1:1 row col using "`shuffle_gram'", nogen assert(match)
assert abs(gram_base - gram_fast) <= 1e-10 + 1e-10 * abs(gram_base)
assert abs(gram_base - gram_shuffle) <= 1e-10 + 1e-10 * abs(gram_base)

tempfile fast_agg_named shuffle_agg_named
use "`fast_agg'", clear
rename (att se overall_att overall_se egt) ///
       (att_fast se_fast overall_att_fast overall_se_fast egt_fast)
save "`fast_agg_named'", replace

use "`shuffle_agg'", clear
rename (att se overall_att overall_se egt) ///
       (att_shuffle se_shuffle overall_att_shuffle overall_se_shuffle egt_shuffle)
save "`shuffle_agg_named'", replace

use "`base_agg'", clear
rename (att se overall_att overall_se egt) ///
       (att_base se_base overall_att_base overall_se_base egt_base)
merge 1:1 type seq using "`fast_agg_named'", nogen assert(match)
merge 1:1 type seq using "`shuffle_agg_named'", nogen assert(match)
save "`actual_agg'", replace

import delimited using "`root'/tests/fixtures/parity/f032/expected/r/aggte.csv", clear asdouble
sort type egt
by type: gen seq = _n
merge 1:1 type seq using "`actual_agg'", nogen assert(match)
assert missing(egt) == missing(egt_base) if missing(egt) | missing(egt_base)
assert missing(egt) == missing(egt_fast) if missing(egt) | missing(egt_fast)
assert missing(egt) == missing(egt_shuffle) if missing(egt) | missing(egt_shuffle)
assert abs(egt - egt_base) <= 1e-10 if !missing(egt)
assert abs(egt - egt_fast) <= 1e-10 if !missing(egt)
assert abs(egt - egt_shuffle) <= 1e-10 if !missing(egt)
foreach v in att se overall_att overall_se {
    assert abs(`v' - `v'_base) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v')
    assert abs(`v' - `v'_fast) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v')
    assert abs(`v' - `v'_shuffle) <= 1e-8 + 1e-8 * abs(`v') if !missing(`v')
    assert abs(`v'_base - `v'_fast) <= 1e-10 + 1e-10 * abs(`v'_base) if !missing(`v'_base)
    assert abs(`v'_base - `v'_shuffle) <= 1e-10 + 1e-10 * abs(`v'_base) if !missing(`v'_base)
}

tempfile option_actual option_base option_fast option_part
local first_option 1
foreach control_group in nevertreated notyettreated {
    * States the never-treated arm explicitly; the omitted-option default is now not-yet-treated.
    local cgopt "nevertreated"
    if "`control_group'" == "notyettreated" local cgopt "notyet"
    foreach base_period in varying universal {
        import delimited using "`root'/tests/fixtures/parity/f032/inputs/input.csv", clear asdouble
        csdid y, ivar(id) time(time) gvar(g) method(reg) `cgopt' base_period(`base_period') nofast analytical bal(none)
        assert e(fast_requested) == 0
        assert e(fast_allowed) == 0
        assert e(fast_used) == 0
        assert "`e(fast_mode)'" == "off"
        assert "`e(compute_path)'" == "baseline"
        matrix B = e(attgt)
        clear
        svmat double B, names(col)
        gen str16 control_group = "`control_group'"
        gen str12 base_period = "`base_period'"
        rename (event_time att se) (event_time_base att_base se_base)
        keep control_group base_period group time event_time_base att_base se_base
        save "`option_base'", replace

        import delimited using "`root'/tests/fixtures/parity/f032/inputs/input.csv", clear asdouble
        csdid y, ivar(id) time(time) gvar(g) method(reg) `cgopt' base_period(`base_period') fast analytical bal(none)
        assert e(fast_requested) == 1
        assert e(fast_used) == 1
        assert "`e(compute_path)'" == "fast-balanced-panel"
        matrix F = e(attgt)
        clear
        svmat double F, names(col)
        gen str16 control_group = "`control_group'"
        gen str12 base_period = "`base_period'"
        rename (event_time att se) (event_time_fast att_fast se_fast)
        keep control_group base_period group time event_time_fast att_fast se_fast
        merge 1:1 control_group base_period group time using "`option_base'", nogen assert(match)
        assert event_time_base == event_time_fast
        assert missing(att_base) == missing(att_fast)
        assert missing(se_base) == missing(se_fast)
        assert abs(att_base - att_fast) <= 1e-12 + 1e-12 * abs(att_base) if !missing(att_base)
        assert abs(se_base - se_fast) <= 1e-12 + 1e-12 * abs(se_base) if !missing(se_base)
        save "`option_part'", replace
        if `first_option' {
            save "`option_actual'", replace
            local first_option 0
        }
        else {
            append using "`option_actual'"
            save "`option_actual'", replace
        }
    }
}

import delimited using "`root'/tests/fixtures/parity/f032/expected/r/fast-option-grid.csv", clear asdouble
merge 1:1 control_group base_period group time using "`option_actual'", nogen assert(match)
assert event_time == event_time_base
assert event_time == event_time_fast
assert missing(att) == missing(att_base)
assert missing(att) == missing(att_fast)
assert missing(se) == missing(se_base)
assert missing(se) == missing(se_fast)
assert abs(att - att_base) <= 1e-8 + 1e-8 * abs(att) if !missing(att)
assert abs(att - att_fast) <= 1e-8 + 1e-8 * abs(att) if !missing(att)
assert abs(se - se_base) <= 1e-8 + 1e-8 * abs(se) if !missing(se)
assert abs(se - se_fast) <= 1e-8 + 1e-8 * abs(se) if !missing(se)

import delimited using "`root'/tests/fixtures/parity/f032/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) nofast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 0
assert e(fast_allowed) == 0
assert e(fast_used) == 0
assert "`e(fast_mode)'" == "off"
assert "`e(compute_path)'" == "baseline"
matrix B = e(attgt)
import delimited using "`root'/tests/fixtures/parity/f032/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) fast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-balanced-panel"
matrix F = e(attgt)
mata: st_numscalar("f032_maxdiff", f032__matrix_maxabsdiff("B", "F"))
assert scalar(f032_maxdiff) <= 1e-10

foreach method in dr ipw {
    import delimited using "`root'/tests/fixtures/parity/f032/inputs/input.csv", clear asdouble
    csdid y, ivar(id) time(time) gvar(g) method(`method') nofast analytical nevertreated base_period(varying) bal(none)
    assert e(fast_requested) == 0
    assert e(fast_allowed) == 0
    assert e(fast_used) == 0
    assert "`e(fast_mode)'" == "off"
    assert "`e(compute_path)'" == "baseline"
    matrix B = e(attgt)

    import delimited using "`root'/tests/fixtures/parity/f032/inputs/input.csv", clear asdouble
    csdid y, ivar(id) time(time) gvar(g) method(`method') fast analytical nevertreated base_period(varying) bal(none)
    assert e(fast_requested) == 1
    assert e(fast_used) == 1
    assert "`e(compute_path)'" == "fast-balanced-panel"
    matrix F = e(attgt)
    mata: st_numscalar("f032_maxdiff", f032__matrix_maxabsdiff("B", "F"))
    assert scalar(f032_maxdiff) <= 1e-10
}

import delimited using "`root'/tests/fixtures/parity/f032/inputs/input.csv", clear asdouble
csdid y x1 x2, ivar(id) time(time) gvar(g) method(reg) nofast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 0
assert e(fast_allowed) == 0
assert e(fast_used) == 0
assert "`e(fast_mode)'" == "off"
assert "`e(compute_path)'" == "baseline"
matrix B = e(attgt)
import delimited using "`root'/tests/fixtures/parity/f032/inputs/input.csv", clear asdouble
csdid y x1 x2, ivar(id) time(time) gvar(g) method(reg) fast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-balanced-panel"
matrix F = e(attgt)
mata: st_numscalar("f032_maxdiff", f032__matrix_maxabsdiff("B", "F"))
assert scalar(f032_maxdiff) <= 1e-10

import delimited using "`root'/tests/fixtures/parity/f032/inputs/input.csv", clear asdouble
csdid y [iw=w], ivar(id) time(time) gvar(g) method(reg) nofast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 0
assert e(fast_allowed) == 0
assert e(fast_used) == 0
assert "`e(fast_mode)'" == "off"
assert "`e(compute_path)'" == "baseline"
matrix B = e(attgt)
import delimited using "`root'/tests/fixtures/parity/f032/inputs/input.csv", clear asdouble
csdid y [iw=w], ivar(id) time(time) gvar(g) method(reg) fast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-balanced-panel"
matrix F = e(attgt)
mata: st_numscalar("f032_maxdiff", f032__matrix_maxabsdiff("B", "F"))
assert scalar(f032_maxdiff) <= 1e-10

import delimited using "`root'/tests/fixtures/parity/f032/inputs/input-unbalanced.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) nofast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 0
assert e(fast_allowed) == 0
assert e(fast_used) == 0
assert "`e(fast_mode)'" == "off"
assert "`e(compute_path)'" == "baseline"
matrix B = e(attgt)
import delimited using "`root'/tests/fixtures/parity/f032/inputs/input-unbalanced.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) fast analytical nevertreated base_period(varying) bal(none)
assert e(fast_requested) == 1
assert e(fast_used) == 1
assert "`e(compute_path)'" == "fast-allow-unbalanced"
matrix F = e(attgt)
mata: st_numscalar("f032_maxdiff", f032__matrix_maxabsdiff("B", "F"))
assert scalar(f032_maxdiff) <= 1e-10
