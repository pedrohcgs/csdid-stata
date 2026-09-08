* Once estimation starts, every failure must clear the previous e() state.
* A captured Break in the plugin path once exited directly with the old fit
* still live; an uncaptured posting error had the same problem. Entry
* refusals still preserve the prior fit, and if e(sample) is resolved before
* clearing that fit. Faults are injected into scratch definitions only.

version 15
clear all
set more off
args selected_target selected_rc
local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
import delimited "`root'/tests/fixtures/parity/f034/inputs/input.csv", clear asdouble

program define lifecycle_bless, eclass
    version 15
    ereturn clear
    ereturn scalar sentinel = 123
    ereturn local cmd "lifecycle_bless"
end

* Read the current function signature, so these faults do not carry a second
* independently maintained copy of the Mata boundary. The injected body marks
* execution before raising the requested rc; every arm asserts that marker.
mata:
void lifecycle_write_stub(string scalar source, string scalar target,
                          string scalar destination, real scalar failure_rc)
{
    real scalar input, output, copying
    string matrix line
    input = fopen(source, "r")
    output = fopen(destination, "w")
    fput(output, "mata:")
    copying = 0
    line = fget(input)
    while (rows(line) > 0) {
        if (strpos(line, "void " + target + "(") == 1) copying = 1
        if (copying) {
            fput(output, line)
            if (strtrim(line) == "{") {
                fput(output, "    st_numscalar(" + char(34) +
                     "CSDID_LIFECYCLE_FAULT_HIT" + char(34) + ", 1)")
                fput(output, "    _error(" + strofreal(failure_rc) + ")")
                fput(output, "}")
                fput(output, "end")
                st_local("wrote", "1")
                break
            }
        }
        line = fget(input)
    }
    fclose(input)
    fclose(output)
}
end

program define lifecycle_inject
    version 15
    args root target failure_rc
    tempfile fault
    local wrote 0
    mata: lifecycle_write_stub("`root'/src/mata/csdid.mata", "`target'", "`fault'", `failure_rc')
    assert `wrote' == 1
    mata: mata drop `target'()
    quietly do "`fault'"
end

program define lifecycle_restore
    version 15
    args root
    capture mata: mata drop CSDID_*
    capture mata: mata drop csdid_*
    capture mata: mata drop csdid_*()
    capture macro drop CSDID_ENGINE_*
    quietly do "`root'/src/mata/csdid.mata"
end

local fit "y x1 x2, ivar(id) time(time) gvar(g) method(reg)"
quietly csdid `fit' analytical
matrix expected_att = e(attgt)
matrix expected_v = e(V)

* A prior fit's e(sample) is usable even though e() is cleared before the
* estimation kernel. Compare against the same qualifier materialized first.
quietly regress y x1 x2 if mod(id, 3) != 0
generate byte previous_sample = e(sample)
quietly csdid y x1 x2 if e(sample), ivar(id) time(time) gvar(g) method(reg) analytical
matrix from_esample = e(attgt)
generate byte used_esample = e(sample)
quietly csdid y x1 x2 if previous_sample, ivar(id) time(time) gvar(g) method(reg) analytical
assert mreldif(from_esample, e(attgt)) == 0
assert used_esample == e(sample)

* These are the same actual plugin stages users can interrupt. Platforms
* without the optional binary still exercise both posting-failure arms.
quietly csdid `fit' reps(99) rseed(1)
local has_plugin = ("`e(bootstrap_accelerator_status)'" == "plugin-active")
local targets "csdid_post_attgt_v csdid_post_attgt_v"
local codes "1 498"
if `has_plugin' {
    local targets "`targets' csdid_boot_plugin_prepare csdid_boot_plugin_record csdid_boot_plugin_finish"
    local codes "`codes' 1 1 1"
}
else display as text "test-estimation-error-lifecycle: plugin stages unavailable; testing both posting failures"
if "`selected_target'" != "" {
    if strpos("`selected_target'", "plugin") assert `has_plugin' == 1
    local targets "`selected_target'"
    local codes "`selected_rc'"
}

foreach prior in regress csdid bless {
    forvalues arm = 1/`: word count `targets'' {
        quietly lifecycle_restore "`root'"
        quietly csdid `fit' analytical
        if "`prior'" == "regress" quietly regress y x1 x2
        if "`prior'" == "bless" lifecycle_bless
        local oldcmd "`e(cmd)'"
        local hadb 0
        capture confirm matrix e(b)
        if !_rc {
            local hadb 1
            matrix oldb = e(b)
        }
        capture noisily csdid y, ivar(id) time(time) gvar(g) method(invalid)
        assert _rc == 198
        assert "`e(cmd)'" == "`oldcmd'"
        if `hadb' {
            matrix currentb = e(b)
            assert mreldif(oldb, currentb) == 0
        }
        if "`prior'" == "bless" assert e(sentinel) == 123

        local target : word `arm' of `targets'
        local failure_rc : word `arm' of `codes'
        lifecycle_inject "`root'" "`target'" `failure_rc'
        capture scalar drop CSDID_LIFECYCLE_FAULT_HIT
        local inference "analytical"
        if strpos("`target'", "plugin") local inference "reps(99) rseed(1)"
        capture noisily csdid `fit' `inference'
        assert _rc == `failure_rc'
        assert scalar(CSDID_LIFECYCLE_FAULT_HIT) == 1
        scalar drop CSDID_LIFECYCLE_FAULT_HIT
        local remaining : e(scalars)
        local remaining "`remaining' `: e(macros)' `: e(matrices)'"
        assert strtrim("`remaining'") == ""
        display as text "test-estimation-error-lifecycle: `prior', `target', rc `failure_rc' clears e()"
    }
}

* A clean successful run remains numerically identical after all failures.
quietly lifecycle_restore "`root'"
quietly csdid `fit' analytical
assert mreldif(expected_att, e(attgt)) == 0
matrix final_v = e(V)
assert mreldif(expected_v, final_v) == 0
display as text "test-estimation-error-lifecycle: COMPLETE"
