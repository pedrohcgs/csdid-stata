version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define _py001_repost_csdid, eclass
    version 15
    ereturn matrix attgt = A
    ereturn matrix inffunc = IF
    ereturn matrix group_prob = GP
    ereturn matrix unit_group = UG
    ereturn local cmd "csdid"
    ereturn local clustervar ""
end

program define py001_fit
    version 15
    syntax, METHOD(string)

    import delimited using "`c(pwd)'/tests/fixtures/parity/py001/inputs/aggte-data.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') analytical
end

program define py001_assert_simple
    version 15

    quietly csdid_stats, type(simple)
    matrix G = e(aggte)
    assert rowsof(G) == 1
    assert missing(G[1, 1])
    assert !missing(G[1, 4])
    assert abs(G[1, 4] - 1) < .5
    assert !missing(G[1, 5])
    assert G[1, 5] > 0
end

program define py001_assert_dynamic
    version 15

    quietly csdid_stats, type(dynamic)
    matrix G = e(aggte)
    assert rowsof(G) > 0
    local has_pre 0
    local has_post 0
    forvalues i = 1/`=rowsof(G)' {
        if G[`i', 1] < 0 local has_pre 1
        if G[`i', 1] >= 0 local has_post 1
        if `i' > 1 assert G[`i', 1] >= G[`=`i'-1', 1]
        if !missing(G[`i', 2]) assert G[`i', 3] > 0
    }
    assert `has_pre' == 1
    assert `has_post' == 1
    assert !missing(G[1, 4])
    assert abs(G[1, 4] - 1) < .5
end

program define py001_assert_group
    version 15

    quietly csdid_stats, type(group)
    matrix G = e(aggte)
    assert rowsof(G) > 0
    forvalues i = 1/`=rowsof(G)' {
        assert G[`i', 1] > 0
        if !missing(G[`i', 2]) assert G[`i', 3] > 0
    }
    assert !missing(G[1, 4])
    assert abs(G[1, 4] - 1) < .5
end

program define py001_assert_calendar
    version 15

    matrix A = e(attgt)
    local min_group = A[1, 1]
    forvalues i = 1/`=rowsof(A)' {
        if A[`i', 1] < `min_group' local min_group = A[`i', 1]
    }

    quietly csdid_stats, type(calendar)
    matrix G = e(aggte)
    assert rowsof(G) > 0
    forvalues i = 1/`=rowsof(G)' {
        assert G[`i', 1] >= `min_group'
        if !missing(G[`i', 2]) assert G[`i', 3] > 0
    }
    assert !missing(G[1, 4])
    assert abs(G[1, 4] - 1) < .5
end

program define py001_assert_windows
    version 15

    quietly csdid_stats, type(dynamic)
    matrix Full = e(aggte)
    local n_full = rowsof(Full)

    quietly csdid_stats, type(dynamic) min_e(-1)
    matrix MinE = e(aggte)
    assert rowsof(MinE) <= `n_full'
    forvalues i = 1/`=rowsof(MinE)' {
        assert MinE[`i', 1] >= -1
    }

    quietly csdid_stats, type(dynamic) max_e(1)
    matrix MaxE = e(aggte)
    assert rowsof(MaxE) <= `n_full'
    forvalues i = 1/`=rowsof(MaxE)' {
        assert MaxE[`i', 1] <= 1
    }

    quietly csdid_stats, type(dynamic) min_e(-1) max_e(1)
    matrix Both = e(aggte)
    forvalues i = 1/`=rowsof(Both)' {
        assert Both[`i', 1] >= -1
        assert Both[`i', 1] <= 1
    }

    quietly csdid_stats, type(dynamic) balance_e(1)
    matrix Bal = e(aggte)
    assert rowsof(Bal) <= `n_full'
end

program define py001_assert_type_structure
    version 15
    syntax, TYPE(string)

    quietly csdid_stats, type(`type')
    confirm matrix e(aggte)
    matrix G = e(aggte)
    assert rowsof(G) > 0
    assert "`e(agg_type)'" == "`type'"
    assert e(N_aggte) == rowsof(G)
    assert e(agg_level) == 95
end

program define py001_assert_na_rm
    version 15

    matrix A = e(attgt)
    matrix IF = e(inffunc)
    matrix GP = e(group_prob)
    matrix UG = e(unit_group)
    matrix A[1, 4] = .
    forvalues r = 1/`=rowsof(IF)' {
        matrix IF[`r', 1] = .
    }
    _py001_repost_csdid
    quietly csdid_stats, type(dynamic) na_rm
    matrix G = e(aggte)
    assert rowsof(G) > 0
    assert !missing(G[1, 4])
end

confirm file "`root'/tests/fixtures/parity/py001/inputs/aggte-data.csv"
confirm file "`root'/tests/fixtures/parity/py001/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/py001/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/py001/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/py001/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/py001/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 46
quietly count if coverage_status == "mapped"
assert r(N) == 46
quietly count if divergence_id != ""
assert r(N) == 0

py001_fit, method(dr)
py001_assert_simple
py001_assert_dynamic
py001_assert_group
py001_assert_calendar
py001_assert_windows
py001_assert_type_structure, type(simple)
py001_assert_type_structure, type(dynamic)
py001_assert_type_structure, type(group)
py001_assert_type_structure, type(calendar)

quietly csdid_stats, type(dynamic) level(99)
assert e(agg_level) == 99
assert e(bstrap) == 0

py001_fit, method(dr)
py001_assert_na_rm

foreach method in dr reg ipw {
    py001_fit, method(`method')
    py001_assert_simple
    py001_fit, method(`method')
    py001_assert_dynamic
    py001_fit, method(`method')
    py001_assert_group
    py001_fit, method(`method')
    py001_assert_calendar
    py001_fit, method(`method')
    py001_assert_windows
    py001_fit, method(`method')
    py001_assert_na_rm
}

* ---------------------------------------------------------------------------
* PY001 R-oracle comparison (added 2026-07-27)
* The assertions above check aggregation structure and loose bounds; they never
* compared a value against R. This pins the ATT(g,t) cells for all three methods,
* and the aggregation block that follows pins every aggregation variant.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/py001/expected/r/attgt.csv"
tempfile py001_actual
quietly {
    clear
    set obs 0
    gen str32 scenario = ""
    gen double group = .
    gen double time = .
    gen double att_stata = .
    gen double se_stata = .
    save "`py001_actual'", replace emptyok
}
capture program drop py001_grab
program define py001_grab
    args tag store
    tempname A
    matrix `A' = e(attgt)
    local nr = rowsof(`A')
    preserve
    quietly {
        clear
        set obs `nr'
        gen str32 scenario = "`tag'"
        gen double group = .
        gen double time = .
        gen double att_stata = .
        gen double se_stata = .
        forvalues i = 1/`nr' {
            replace group     = `A'[`i',1] in `i'
            replace time      = `A'[`i',2] in `i'
            replace att_stata = `A'[`i',4] in `i'
            replace se_stata  = `A'[`i',5] in `i'
        }
        append using "`store'"
        save "`store'", replace
    }
    restore
end

foreach method in dr reg ipw {
    import delimited using "`root'/tests/fixtures/parity/py001/inputs/aggte-data.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(`method') analytical
    py001_grab "`method'" "`py001_actual'"
}

import delimited using "`root'/tests/fixtures/parity/py001/expected/r/attgt.csv", clear asdouble varnames(1)
quietly merge 1:1 scenario group time using "`py001_actual'", assert(match) nogen
quietly count
assert r(N) == 27
quietly generate double d_att = abs(att - att_stata)
quietly generate double d_se  = abs(se - se_stata)
quietly summarize d_att, meanonly
assert r(max) < 1e-9
quietly summarize d_se, meanonly
assert r(max) < 1e-9
display "PY001 OK: 27 cells (three methods) match R to <1e-9"

confirm file "`root'/tests/fixtures/parity/py001/expected/r/aggte-overall.csv"
tempfile py001_ov
quietly {
    clear
    set obs 0
    gen str24 spec = ""
    gen double ov_stata = .
    save "`py001_ov'", replace emptyok
}
capture program drop py001_ovgrab
program define py001_ovgrab
    args tag store
    tempname G
    matrix `G' = e(aggte)
    local ov = `G'[1, colnumb(`G', "overall_att")]
    preserve
    quietly {
        clear
        set obs 1
        gen str24 spec = "`tag'"
        gen double ov_stata = `ov'
        append using "`store'"
        save "`store'", replace
    }
    restore
end
import delimited using "`root'/tests/fixtures/parity/py001/inputs/aggte-data.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical
quietly csdid_stats, type(simple) na_rm
py001_ovgrab "simple" "`py001_ov'"
quietly csdid_stats, type(group) na_rm
py001_ovgrab "group" "`py001_ov'"
quietly csdid_stats, type(calendar) na_rm
py001_ovgrab "calendar" "`py001_ov'"
quietly csdid_stats, type(dynamic) na_rm
py001_ovgrab "dynamic" "`py001_ov'"
quietly csdid_stats, type(dynamic) na_rm min_e(-1)
py001_ovgrab "dynamic_min_e_m1" "`py001_ov'"
quietly csdid_stats, type(dynamic) na_rm max_e(1)
py001_ovgrab "dynamic_max_e_1" "`py001_ov'"
quietly csdid_stats, type(dynamic) na_rm min_e(-1) max_e(1)
py001_ovgrab "dynamic_min_m1_max_1" "`py001_ov'"
quietly csdid_stats, type(dynamic) na_rm balance_e(1)
py001_ovgrab "dynamic_balance_e_1" "`py001_ov'"

import delimited using "`root'/tests/fixtures/parity/py001/expected/r/aggte-overall.csv", clear asdouble varnames(1)
quietly merge 1:1 spec using "`py001_ov'", assert(match) nogen
quietly generate double d_ov = abs(overall_att - ov_stata)
quietly summarize d_ov, meanonly
assert r(max) < 1e-9
display "PY001 AGG OK: 8 aggregation overalls match R to <1e-9"
