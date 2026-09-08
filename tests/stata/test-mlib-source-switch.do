* Source-only installations must be identified by their actual source file.
* Both have library identity "none", so switching ado-paths or working
* directories once kept the departed engine at rc 0. reset also retained its
* functions and could not reload source replaced at the same path.
*
* Each arm is independently runnable for red qualification against the old
* loader: do tests/stata/test-mlib-source-switch.do adopath|cwd|reset.

version 15
clear all
set more off
args selected_arm
local root "`c(pwd)'"
local arms "adopath cwd reset"
if "`selected_arm'" != "" local arms "`selected_arm'"

tempfile stub
local scratch "`stub'-source-switch"
mkdir "`scratch'"
mkdir "`scratch'/a"
mkdir "`scratch'/b"
mkdir "`scratch'/unrelated"
sysdir set PLUS "`scratch'"
sysdir set PERSONAL "`scratch'"
sysdir set SITE "`scratch'"
sysdir set OLDPLACE "`scratch'"
quietly do "`root'/src/ado/_csdid_engine_load.ado"
quietly do "`root'/src/ado/csdid.ado"
mata: real scalar source_switch_user_function() return(41)

program define source_switch_write
    version 15
    args directory value
    tempname fh
    file open `fh' using "`directory'/csdid.ado", write replace text
    file write `fh' "* source-switch fixture" _n
    file close `fh'
    file open `fh' using "`directory'/csdid.mata", write replace text
    file write `fh' "version 14" _n "mata:" _n
    file write `fh' "real matrix csdid__mean(real matrix x) return(mean(x))" _n
    file write `fh' `"string scalar csdid_mlib_version() return("2.0.0|source")"' _n
    file write `fh' "real scalar csdid__source_switch_witness() return(`value')" _n
    file write `fh' "end" _n
    file close `fh'
end

program define source_switch_run
    version 15
    args scratch arm
    capture mata: mata drop CSDID_*
    capture mata: mata drop csdid_*
    capture mata: mata drop csdid_*()
    capture macro drop CSDID_*
    source_switch_write "`scratch'/a" 1
    source_switch_write "`scratch'/b" 2
    cd "`scratch'"
    capture findfile lcsdid_v2.mlib
    assert _rc == 601
    if "`arm'" == "cwd" cd "`scratch'/a"
    else adopath ++ "`scratch'/a"

    mata: source_switch_user_state = 37
    mata: csdidx_source_switch_lookalike = 43
    _csdid_engine_load
    mata: assert(csdid__source_switch_witness() == 1)
    assert "$CSDID_ENGINE_LIBRARY" == "none"

    * A settings change that still resolves the same file must leave the
    * engine state intact. A later ordinary call must stop at the marker too.
    mata: CSDID_SOURCE_SWITCH_STATE = 19
    adopath ++ "`scratch'/unrelated"
    _csdid_engine_load
    mata: assert(CSDID_SOURCE_SWITCH_STATE == 19)
    _csdid_engine_load
    mata: assert(CSDID_SOURCE_SWITCH_STATE == 19)
    adopath - "`scratch'/unrelated"

    if "`arm'" == "adopath" {
        adopath - "`scratch'/a"
        adopath ++ "`scratch'/b"
    }
    else if "`arm'" == "cwd" cd "`scratch'/b"
    else if "`arm'" == "reset" {
        * Only reset promises to reread a file replaced at an unchanged path.
        source_switch_write "`scratch'/a" 2
        csdid reset
    }
    else error 198

    _csdid_engine_load
    mata: assert(csdid__source_switch_witness() == 2)
    mata: assert(source_switch_user_state == 37)
    mata: assert(source_switch_user_function() == 41)
    mata: assert(csdidx_source_switch_lookalike == 43)
    local held_state 0
    capture mata: st_local("held_state", strofreal(CSDID_SOURCE_SWITCH_STATE))
    assert `held_state' == 0
    if "`arm'" == "adopath" adopath - "`scratch'/b"
    if "`arm'" == "reset" adopath - "`scratch'/a"
end

local test_rc 0
foreach arm of local arms {
    capture noisily source_switch_run "`scratch'" "`arm'"
    if _rc {
        local test_rc = _rc
        continue, break
    }
    display as text "test-mlib-source-switch: `arm' loads the arriving source and preserves unrelated Mata state"
}

cd "`root'"
foreach arm in a b {
    capture erase "`scratch'/`arm'/csdid.ado"
    capture erase "`scratch'/`arm'/csdid.mata"
    capture rmdir "`scratch'/`arm'"
}
capture rmdir "`scratch'/unrelated"
capture rmdir "`scratch'"
if `test_rc' exit `test_rc'
display as text "test-mlib-source-switch: COMPLETE"
