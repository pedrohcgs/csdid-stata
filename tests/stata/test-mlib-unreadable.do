* An lcsdid_v2.mlib this Stata cannot read must be ANNOUNCED, not skipped in
* silence. This is the on-disk shape a shipped package has for every user
* whose Stata is older than the machine that built the library: findfile
* resolves the file, Mata refuses its object code before any stamp can be
* read, and the session falls back to compiling csdid.mata. csdid.sthlp
* promises that fall-back is said once; before the loader announced it on
* this branch, the user's only symptom was an unexplained first-call delay
* in every session, and the stamp-arm gate could not see it because its
* "newerstata" arm doctors the stamp STRING under the running Stata, which
* produces a library whose object code loads fine.
*
* The staged library here is deliberately unreadable bytes rather than a
* real newer-Stata build -- no older Stata exists on the test machine -- so
* the arm exercises exactly the loader condition (found, not loadable) and
* not dyld-level specifics.

version 15
clear all
set more off

local root "`c(pwd)'"
confirm file "`root'/src/ado/_csdid_engine_load.ado"
confirm file "`root'/src/mata/csdid.mata"

tempfile stub
local scratch "`stub'-unread"
mkdir "`scratch'"
mkdir "`scratch'/plus"
mkdir "`scratch'/personal"
mkdir "`scratch'/site"
mkdir "`scratch'/oldplace"

* The machine this runs on may hold a real csdid installation; the session's
* system directories are pointed at empty scratch so nothing readable can
* answer the probe from outside the staging.
sysdir set PLUS "`scratch'/plus"
sysdir set PERSONAL "`scratch'/personal"
sysdir set SITE "`scratch'/site"
sysdir set OLDPLACE "`scratch'/oldplace"

* Unreadable library: ado text under the library's name.
copy "`root'/src/ado/csdid.ado" "`scratch'/lcsdid_v2.mlib"

adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"
adopath ++ "`scratch'"

tempfile lg
log using "`lg'", replace text name(unreadarm)
capture noisily _csdid_engine_load
local load_rc = _rc
log close unreadarm

* The fall-back must succeed and the session must be running the source.
assert `load_rc' == 0
local marker `"$CSDID_ENGINE_RESOLVED"'
assert strpos(`"`marker'"', "2.0.0|source;") == 1

* The note: names the file it could not read, says the results are the same,
* and asks for nothing -- "re-install csdid" is the OTHER refusal's remedy
* and must not appear here (a loop that cannot end, for this user).
* The log wraps long lines with a "> " continuation prefix, so a phrase can
* straddle a physical line break; logical lines are reassembled before any
* phrase is looked for.
local said_found 0
local said_nothing 0
local said_reinstall 0
local logical ""
file open fh using "`lg'", read text
file read fh line
while r(eof) == 0 {
    if substr(`"`line'"', 1, 2) == "> " {
        local tail = substr(`"`line'"', 3, .)
        local logical `"`logical'`tail'"'
    }
    else {
        if strpos(`"`logical'"', "could not read it") local said_found 1
        if strpos(`"`logical'"', "Nothing needs to be done") local said_nothing 1
        if strpos(`"`logical'"', "re-install csdid") local said_reinstall 1
        local logical `"`line'"'
    }
    file read fh line
}
if strpos(`"`logical'"', "could not read it") local said_found 1
if strpos(`"`logical'"', "Nothing needs to be done") local said_nothing 1
if strpos(`"`logical'"', "re-install csdid") local said_reinstall 1
file close fh
assert `said_found' == 1
assert `said_nothing' == 1
assert `said_reinstall' == 0

* Announced once per decision, not once per call: a second load stops at the
* session marker and says nothing.
tempfile lg2
log using "`lg2'", replace text name(unreadarm2)
capture noisily _csdid_engine_load
local load_rc2 = _rc
log close unreadarm2
assert `load_rc2' == 0
local said_again 0
file open fh using "`lg2'", read text
file read fh line
while r(eof) == 0 {
    if strpos(`"`line'"', "could not read it") local said_again 1
    file read fh line
}
file close fh
assert `said_again' == 0

* Cleanup before the verdict, so a red run does not strand the staging.
capture erase "`scratch'/lcsdid_v2.mlib"

display as text "test-mlib-unreadable: an unreadable compiled library is announced once, the source path answers, and the user is asked for nothing"
