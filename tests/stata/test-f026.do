version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

confirm file "`root'/tests/fixtures/parity/f026/expected/new-stata/ereturn.json"

global F026_ATTGT_COLS "group time event_time att se n_treat_t n_treat_pre n_control_t n_control_pre base_time"
global F026_GP_COLS "group prob n_units"
global F026_UG_COLS "id group weight"
global F026_UG_COLS4 "id group weight first_period"
global F026_AGGTE_COLS "egt att se overall_att overall_se"
global F026_IF_COLS "c1 c2 c3 c4 c5 c6"
global F026_CLUSTER_COLS "cluster"
global F026_ATTGT_ROWS "r1 r2 r3 r4 r5 r6"

program define f026_assert_attgt_matrices
    version 15
    syntax , IFRows(integer) UNITRows(integer) [UGCols(integer 3)]

    matrix A = e(attgt)
    assert rowsof(A) == 6
    assert colsof(A) == 10
    local cn : colnames A
    assert "`cn'" == "$F026_ATTGT_COLS"
    local rn : rownames A
    assert "`rn'" == "$F026_ATTGT_ROWS"

    matrix IF = e(inffunc)
    assert rowsof(IF) == `ifrows'
    assert colsof(IF) == 6
    local cn : colnames IF
    assert "`cn'" == "$F026_IF_COLS"

    matrix GP = e(group_prob)
    assert rowsof(GP) == 2
    assert colsof(GP) == 3
    local cn : colnames GP
    assert "`cn'" == "$F026_GP_COLS"
    assert GP[1,1] == 3
    assert GP[2,1] == 4
    assert abs(GP[1,2] - 1/3) < 1e-12
    assert abs(GP[2,2] - 1/3) < 1e-12
    assert GP[1,3] == `unitrows'
    assert GP[2,3] == `unitrows'

    * The unit map is id/group/weight, plus the internal draw-order period on
    * the two sample shapes whose bootstrap unit order is period-major: the
    * repeated cross section and the unbalanced panel. A balanced panel draws
    * cohort-major and carries no fourth column.
    matrix UG = e(unit_group)
    assert rowsof(UG) == `unitrows'
    assert colsof(UG) == `ugcols'
    local cn : colnames UG
    if `ugcols' == 4 {
        assert "`cn'" == "$F026_UG_COLS4"
    }
    else {
        assert "`cn'" == "$F026_UG_COLS"
    }
    forvalues i = 1/`=rowsof(UG)' {
        assert UG[`i', 3] == 1
    }
end

program define f026_assert_cluster_matrix
    version 15

    matrix CV = e(cluster_vec)
    assert rowsof(CV) == 48
    assert colsof(CV) == 1
    local cn : colnames CV
    assert "`cn'" == "$F026_CLUSTER_COLS"
    forvalues i = 1/`=rowsof(CV)' {
        local expected = mod(`i' - 1, 8) + 1
        assert CV[`i', 1] == `expected'
    }
end

program define f026_assert_common_macros
    version 15
    syntax , PANELMODE(string) [IDVAR(string) CLUSTERVAR(string)]

    assert "`e(cmd)'" == "csdid"
    assert "`e(version)'" == "2.0.0"
    assert "`e(yname)'" == "y"
    assert "`e(timevar)'" == "time"
    assert "`e(gvar)'" == "g"
    assert "`e(idvar)'" == "`idvar'"
    assert "`e(clustervar)'" == "`clustervar'"
    assert "`e(panel_mode)'" == "`panelmode'"
    assert "`e(control_group)'" == "nevertreated"
    assert "`e(method)'" == "reg"
    assert "`e(method_requested)'" == "reg"
    assert "`e(weightvar)'" == ""
    assert "`e(base_period)'" == "varying"
    assert "`e(fix_weights)'" == ""
end

program define f026_assert_common_scalars
    version 15
    syntax , N(integer) NUnits(integer)

    assert e(N) == `n'
    assert e(N_units) == `nunits'
    assert e(N_attgt) == 6
    assert e(N_groups) == 2
    assert e(N_time) == 4
    assert e(anticipation) == 0
    assert e(level) == 95
end

import delimited using "`root'/tests/fixtures/parity/f026/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none) storeall
assert `"`e(cmdline)'"' == `"csdid y, ivar(id) time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none) storeall"'
f026_assert_common_macros, panelmode("panel") idvar("id")
f026_assert_common_scalars, n(192) nunits(48)
f026_assert_attgt_matrices, ifrows(48) unitrows(48)

capture noisily csdid_estat attgt
assert _rc == 0
assert "`e(cmd)'" == "csdid"

csdid_stats simple
assert "`e(agg_type)'" == "simple"
assert e(agg_level) == 95
assert e(N_aggte) == 1
matrix AG = e(aggte)
assert rowsof(AG) == 1
assert colsof(AG) == 5
local cn : colnames AG
assert "`cn'" == "$F026_AGGTE_COLS"
local rn : rownames AG
assert "`rn'" == "r1"
f026_assert_attgt_matrices, ifrows(48) unitrows(48)

import delimited using "`root'/tests/fixtures/parity/f026/inputs/input.csv", clear asdouble
csdid y, time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none) storeall
assert `"`e(cmdline)'"' == `"csdid y, time(time) gvar(g) method(reg) analytical nevertreated base_period(varying) bal(none) storeall"'
f026_assert_common_macros, panelmode("repeated-cross-section")
f026_assert_common_scalars, n(192) nunits(192)
f026_assert_attgt_matrices, ifrows(192) unitrows(192) ugcols(4)

* In a repeated cross section the map's id column is the observation number the
* estimation read, and its fourth column is that observation's period, cached
* so the bootstrap draw order does not depend on how the data are sorted
* afterwards. Check the pairing against the data itself.
matrix UGRC = e(unit_group)
forvalues i = 1/`=rowsof(UGRC)' {
    local obs = UGRC[`i', 1]
    assert UGRC[`i', 4] == time[`obs']
}

import delimited using "`root'/tests/fixtures/parity/f026/inputs/input.csv", clear asdouble
csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) analytical nevertreated base_period(varying) bal(none) storeall
assert `"`e(cmdline)'"' == `"csdid y, ivar(id) time(time) gvar(g) method(reg) cluster(cl) analytical nevertreated base_period(varying) bal(none) storeall"'
f026_assert_common_macros, panelmode("panel") idvar("id") clustervar("cl")
f026_assert_common_scalars, n(192) nunits(48)
assert e(N_clusters) == 8
f026_assert_attgt_matrices, ifrows(48) unitrows(48)
f026_assert_cluster_matrix

macro drop F026_ATTGT_COLS F026_GP_COLS F026_UG_COLS F026_UG_COLS4 F026_AGGTE_COLS F026_IF_COLS F026_CLUSTER_COLS F026_ATTGT_ROWS
