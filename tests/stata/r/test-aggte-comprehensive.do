version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define _rt002_repost_csdid, eclass
    version 15
    ereturn matrix attgt = A
    ereturn matrix inffunc = IF
    ereturn matrix group_prob = GP
    ereturn matrix unit_group = UG
    ereturn local cmd "csdid"
    ereturn local clustervar ""
end

program define rt002_fit
    version 15
    import delimited using "`c(pwd)'/tests/fixtures/parity/rt002/inputs/aggte-data.csv", clear asdouble
    quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical
end

program define rt002_assert_simple
    version 15
    quietly csdid_stats, type(simple)
    matrix G = e(aggte)
    assert rowsof(G) == 1
    assert missing(G[1, 1])
    assert !missing(G[1, 4])
    assert abs(G[1, 4] - 1) < .5
    assert !missing(G[1, 5])
    assert G[1, 5] > 0
    assert "`e(agg_type)'" == "simple"
    assert e(N_aggte) == rowsof(G)
end

program define rt002_assert_dynamic
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
    assert "`e(agg_type)'" == "dynamic"
end

program define rt002_assert_group
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
    assert "`e(agg_type)'" == "group"
end

program define rt002_assert_calendar
    version 15
    matrix A0 = e(attgt)
    local min_group = A0[1, 1]
    forvalues i = 1/`=rowsof(A0)' {
        if A0[`i', 1] < `min_group' local min_group = A0[`i', 1]
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
    assert "`e(agg_type)'" == "calendar"
end

program define rt002_assert_windows
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

program define rt002_assert_type_structure
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

program define rt002_assert_na_rm
    version 15
    matrix A = e(attgt)
    matrix IF = e(inffunc)
    matrix GP = e(group_prob)
    matrix UG = e(unit_group)
    matrix A[1, 4] = .
    forvalues r = 1/`=rowsof(IF)' {
        matrix IF[`r', 1] = .
    }
    _rt002_repost_csdid
    quietly csdid_stats, type(dynamic) na_rm
    matrix G = e(aggte)
    assert rowsof(G) > 0
    assert !missing(G[1, 4])
end

program define rt002_assert_gmaxe_excl
    version 15
    matrix A = e(attgt)
    matrix IF = e(inffunc)
    matrix GP = e(group_prob)
    matrix UG = e(unit_group)
    local g_first = A[1, 1]
    local last_pos .
    local last_e .
    forvalues i = 1/`=rowsof(A)' {
        if A[`i', 1] == `g_first' & A[`i', 2] >= `g_first' {
            local last_pos = `i'
            local last_e = A[`i', 3]
        }
    }
    assert `last_pos' < .
    assert `last_e' > 0
    forvalues i = 1/`=rowsof(A)' {
        if A[`i', 1] == `g_first' & A[`i', 2] >= `g_first' & `i' != `last_pos' {
            matrix A[`i', 4] = .
            forvalues r = 1/`=rowsof(IF)' {
                matrix IF[`r', `i'] = .
            }
        }
    }
    local max_e = max(0, `last_e' - 1)
    _rt002_repost_csdid
    quietly csdid_stats, type(group) na_rm max_e(`max_e')
    matrix G = e(aggte)
    assert rowsof(G) > 0
    forvalues i = 1/`=rowsof(G)' {
        assert G[`i', 1] != `g_first'
    }
end

confirm file "`root'/tests/fixtures/parity/rt002/inputs/aggte-data.csv"
confirm file "`root'/tests/fixtures/parity/rt002/expected/contract/upstream-test-map.csv"
confirm file "`root'/tests/fixtures/parity/rt002/expected/contract/upstream-test-map.json"
confirm file "`root'/tests/fixtures/parity/rt002/expected/contract/approved-divergence.csv"
confirm file "`root'/tests/fixtures/parity/rt002/expected/contract/approved-divergence.json"
confirm file "`root'/tests/fixtures/parity/rt002/expected/contract/scenarios.csv"
confirm file "`root'/tests/fixtures/parity/rt002/metadata/manifest.json"

import delimited using "`root'/tests/fixtures/parity/rt002/expected/contract/upstream-test-map.csv", clear varnames(1) stringcols(_all)
assert _N == 32
quietly count if coverage_status == "mapped"
assert r(N) == 30
quietly count if coverage_status == "approved-divergence"
assert r(N) == 2

rt002_fit
rt002_assert_simple
rt002_assert_dynamic
rt002_assert_group
rt002_assert_calendar
rt002_assert_windows
rt002_assert_type_structure, type(simple)
rt002_assert_type_structure, type(dynamic)
rt002_assert_type_structure, type(group)
rt002_assert_type_structure, type(calendar)

quietly csdid_stats, type(dynamic) level(99)
assert e(agg_level) == 99
assert e(bstrap) == 0

rt002_fit
rt002_assert_na_rm

rt002_fit
rt002_assert_gmaxe_excl

rt002_fit
rt002_assert_group

* ---------------------------------------------------------------------------
* RT002 R-oracle comparison (added 2026-07-27)
*
* Everything above asserts option plumbing and loose bounds such as
* abs(G[1,4] - 1) < .5, which never compared an aggregate against R. The block
* below pins every aggregation this test exercises -- simple, group, calendar,
* dynamic, and the windowed and balanced dynamic variants -- against R's own
* overall value and per-event-time cells.
* ---------------------------------------------------------------------------
confirm file "`root'/tests/fixtures/parity/rt002/expected/r/aggte-overall.csv"
confirm file "`root'/tests/fixtures/parity/rt002/expected/r/aggte-cells.csv"

tempfile rt002_ov rt002_cell
quietly {
    clear
    set obs 0
    gen str24 spec = ""
    gen double ov_stata = .
    save "`rt002_ov'", replace emptyok
    clear
    set obs 0
    gen str24 spec = ""
    gen double egt = .
    gen double att_stata = .
    save "`rt002_cell'", replace emptyok
}

capture program drop rt002_oracle
program define rt002_oracle
    args tag ovfile cellfile
    syntax [anything], [MINE(string) MAXE(string) BALE(string) TYPE(string)]
end

capture program drop rt002_grab
program define rt002_grab
    args tag ovfile cellfile
    tempname G
    matrix `G' = e(aggte)
    * overall_att is a COLUMN of e(aggte), not a stored scalar
    local ov = `G'[1, colnumb(`G', "overall_att")]
    preserve
    quietly {
        clear
        set obs 1
        gen str24 spec = "`tag'"
        gen double ov_stata = `ov'
        append using "`ovfile'"
        save "`ovfile'", replace
    }
    restore
    preserve
    quietly {
        clear
        svmat double `G', names(col)
        capture confirm variable egt
        if !_rc {
            quietly drop if missing(egt)
            if _N > 0 {
                gen str24 spec = "`tag'"
                rename att att_stata
                keep spec egt att_stata
                append using "`cellfile'"
                save "`cellfile'", replace
            }
        }
    }
    restore
end

import delimited using "`root'/tests/fixtures/parity/rt002/inputs/aggte-data.csv", clear asdouble
quietly csdid y x, ivar(id) time(period) gvar(g) method(dr) analytical
quietly csdid_stats, type(simple) na_rm
rt002_grab "simple" "`rt002_ov'" "`rt002_cell'"
quietly csdid_stats, type(group) na_rm
rt002_grab "group" "`rt002_ov'" "`rt002_cell'"
quietly csdid_stats, type(calendar) na_rm
rt002_grab "calendar" "`rt002_ov'" "`rt002_cell'"
quietly csdid_stats, type(dynamic) na_rm
rt002_grab "dynamic" "`rt002_ov'" "`rt002_cell'"
quietly csdid_stats, type(dynamic) na_rm min_e(-1)
rt002_grab "dynamic_min_e_m1" "`rt002_ov'" "`rt002_cell'"
quietly csdid_stats, type(dynamic) na_rm max_e(1)
rt002_grab "dynamic_max_e_1" "`rt002_ov'" "`rt002_cell'"
quietly csdid_stats, type(dynamic) na_rm min_e(-1) max_e(1)
rt002_grab "dynamic_min_m1_max_1" "`rt002_ov'" "`rt002_cell'"
quietly csdid_stats, type(dynamic) na_rm balance_e(1)
rt002_grab "dynamic_balance_e_1" "`rt002_ov'" "`rt002_cell'"

import delimited using "`root'/tests/fixtures/parity/rt002/expected/r/aggte-overall.csv", clear asdouble varnames(1)
quietly merge 1:1 spec using "`rt002_ov'", assert(match) nogen
quietly generate double d_ov = abs(overall_att - ov_stata)
quietly summarize d_ov, meanonly
assert r(max) < 1e-9

import delimited using "`root'/tests/fixtures/parity/rt002/expected/r/aggte-cells.csv", clear asdouble varnames(1)
quietly merge 1:1 spec egt using "`rt002_cell'", assert(match) nogen
quietly generate double d_cell = abs(att - att_stata)
quietly summarize d_cell, meanonly
assert r(max) < 1e-9

display "RT002 OK: 8 aggregation overalls and 25 event cells match R to <1e-9"
