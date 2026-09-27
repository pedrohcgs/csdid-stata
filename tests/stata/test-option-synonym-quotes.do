* ---------------------------------------------------------------------------
* A quoted value means the same under a synonym as under the primary spelling.
*
* baseperiod() and fixweights() arrive through csdid's catch-all, which kept
* the quotes that syntax strips from base_period() and fix_weights(). So
* baseperiod("varying") failed the empty-value test and silently ran the
* universal base -- different pre-treatment cells, no message -- and any quoted
* value, garbage included, was accepted. fixweights("base") skipped its
* validation, reached Mata as an invalid expression (r(3000)) and cleared the
* previous estimation on the way.
*
* The same holds for an empty value: rseed("`unset'") and reps("") were as
* empty as rseed() but ran unseeded, 1000-draw bootstraps at rc 0, and an
* empty wboot(cluster()) ran unclustered. And a seed past 2^31 - 1, which
* set seed refuses, was reduced modulo 2^32, so rseed(4294967297) repeated
* rseed(1)'s draws while recording a different seed.
* ---------------------------------------------------------------------------
version 15
clear all
set more off
set linesize 200

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

use "`root'/src/data/mpdta.dta", clear

* -- 1. baseperiod("varying") is base_period(varying) ----------------------
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical base_period(varying)
matrix primary = e(attgt)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical baseperiod("varying")
assert "`e(base_period)'" == "varying"
assert mreldif(e(attgt), primary) == 0

* -- 2. a quoted invalid value is refused, and prior results survive -------
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical baseperiod("bogus")
assert _rc == 198
assert "`e(cmd)'" == "csdid"
assert "`e(base_period)'" == "varying"

* -- 3. fixweights("base") is fix_weights(base) ----------------------------
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical fix_weights(base)
matrix primary = e(attgt)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical fixweights("base")
assert "`e(fix_weights)'" == "base_period"
assert mreldif(e(attgt), primary) == 0

* -- 4. a quoted invalid fixweights() is refused at entry --------------------
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical fixweights("bogus")
assert _rc == 198
assert "`e(cmd)'" == "csdid"

* -- 5. quoted or bare empty bootstrap values refuse --------------------
local unset
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) reps(200) rseed("`unset'")
assert _rc == 198
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) reps("") rseed(1)
assert _rc == 198
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) wboot(reps(200) rseed("`unset'"))
assert _rc == 198
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) wboot(reps(200) rseed(1) cluster(`unset'))
assert _rc == 198

* -- 5b. empties in every quoting form and position; quoted values run ---
foreach bad in `"wboot(rseed(`"`unset'"') reps(200))"' `"wboot(rseed(" ") reps(200))"' ///
    `"wboot(reps(`"`unset'"')) rseed(1)"' `"wboot(reps(200) rseed(1) cluster(`"`unset'"'))"' ///
    `"wboot(cluster(" ") reps(200) rseed(1))"' `"wboot(reps(200) rseed(1) wtype())"' ///
    `"reps(200) rseed(`"`unset'"')"' `"reps(200) rseed(" ")"' {
    capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) `bad'
    assert _rc == 198
}
local s1 1
local r25 25
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) wboot(reps(25) rseed("`s1'"))
assert "`e(rseed)'" == "1"
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) wboot(rseed(1) reps("`r25'"))
assert e(biters) == 25

* -- 6. seeds stop where set seed stops --------------------------------
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) reps(50) rseed(2147483648)
assert _rc == 198
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) reps(50) rseed(2147483647)
assert _rc == 0

* -- 6b. inner blanks mean nothing in the synonyms either -----------------
use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical base_period(varying)
matrix primary = e(attgt)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical baseperiod( varying )
assert "`e(base_period)'" == "varying"
assert mreldif(e(attgt), primary) == 0
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical fixweights( base )
assert "`e(fix_weights)'" == "base_period"

* -- 6c. a documented option given twice, or with a value its type refuses,
*        is named as such, not called unsupported ------------------------
program define osq_log_has, rclass
    version 15
    syntax using/, MESSAGE(string)
    tempname fh
    local body ""
    file open `fh' using `"`using'"', read text
    file read `fh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " local clean = strtrim(substr(`"`clean'"', 3, .))
        local body `"`body' `clean'"'
        file read `fh' line
    }
    file close `fh'
    return scalar has = strpos(`"`body'"', `"`message'"') > 0
end
tempfile olg
foreach bad in "anticipation(1.5)" "method(dr) method(reg)" {
    log using "`olg'", text replace name(osq)
    capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical `bad'
    local rc = _rc
    log close osq
    assert `rc' == 198
    osq_log_has using "`olg'", message("more than once or with a value it does not take")
    assert r(has) == 1
}
log using "`olg'", text replace name(osq)
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical frobnicate(1)
log close osq
osq_log_has using "`olg'", message("unsupported option(s): frobnicate(1)")
assert r(has) == 1

* -- 7. a cluster abbreviation names the same variable on every route, and
*       under set varabbrev off it is refused on every route ---------------
generate double statecl = floor(countyreal / 1000)
local abbrev_on = (c(varabbrev) == "on")
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) wboot(reps(50) rseed(1) cluster(statec))
if `abbrev_on' {
    assert _rc == 0
    assert "`e(clustervar)'" == "statecl"
    capture noisily csdid_stats, type(simple) cluster(statecl)
    assert _rc == 0
}
else assert _rc == 111
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) cluster(statecl) analytical
capture noisily csdid_stats, type(simple) cluster(statec)
assert _rc == cond(`abbrev_on', 0, 111)

* -- 7b. the using route takes the abbreviation too; an unresolvable name
*        on the direct route says so rather than advising a rerun --------
tempfile rif7
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) cluster(statecl) analytical saverif("`rif7'") replace
capture noisily csdid_stats using "`rif7'", type(simple) cluster(statec)
if `abbrev_on' assert _rc == 0
else assert _rc != 0
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) cluster(statecl) analytical
capture noisily csdid_stats, type(simple) cluster(nosuchcl)
assert _rc == 111

* -- 8. small parser defects -------------------------------------------
* a quoted filename that happens to contain "reps()" is a filename
tempfile stub8
local odd "`stub8' reps() .dta"
use "`root'/src/data/mpdta.dta", clear
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical saverif("`odd'") replace
assert _rc == 0
capture erase "`odd'"
* vce(cl ...) is Stata's usual abbreviation of vce(cluster ...)
generate double statecl2 = floor(countyreal / 1000)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical vce(cl statecl2)
assert "`e(clustervar)'" == "statecl2"
* a cluster variable that does not exist is not "non-numeric"
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical vce(cluster nosuchvar)
assert _rc == 111
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) wboot(reps(50) rseed(1) cluster(nosuchvar))
assert _rc == 111
* csdid reset forgets csdid's globals, not the user's
global CSDID_USER_OWN "keep me"
csdid reset
assert "$CSDID_USER_OWN" == "keep me"
macro drop CSDID_USER_OWN

* -- 9. csdid_plot names a repeated documented option -------------------
use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
tempfile plg
log using "`plg'", text replace name(osq)
capture noisily csdid_plot, group(2004) group(2006)
local rc = _rc
log close osq
assert `rc' == 198
osq_log_has using "`plg'", message("option group() is given more than once")
assert r(has) == 1

* -- 9b. a cohort requested twice is named once in the fallback note -------
use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
log using "`plg'", text replace name(osq)
csdid_plot, group(2005 2005) saving("`plg'.dta") replace
log close osq
osq_log_has using "`plg'", message("no cohort 2005 2005")
assert r(has) == 0
osq_log_has using "`plg'", message("no cohort 2005")
assert r(has) == 1

* -- 10. method(drimp) names what replaces it ----------------------------
log using "`plg'", text replace name(osq)
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical method(drimp)
local rc = _rc
log close osq
assert `rc' == 198
osq_log_has using "`plg'", message("method(dr), the default, is the locally efficient doubly robust estimator")
assert r(has) == 1

* -- 11. grammar after the fixes ---------------------------------------
use "`root'/src/data/mpdta.dta", clear
local cq `"`"varying"'"'
foreach case in "METHOD(dr)|unsupported option(s): METHOD(dr)" ///
                "pointwise pointwise|option pointwise is given more than once" ///
                "notyet(1)|option notyet is given more than once or with a value" ///
                "seed(3000000000)|the bootstrap seed must be at most" {
    gettoken c_opt c_msg : case, parse("|")
    local c_msg = substr(`"`c_msg'"', 2, .)
    log using "`plg'", text replace name(osq)
    capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) reps(50) `c_opt'
    local rc = _rc
    log close osq
    assert `rc' == 198
    osq_log_has using "`plg'", message(`"`c_msg'"')
    assert r(has) == 1
}
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical baseperiod(`cq')
assert "`e(base_period)'" == "varying"
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical baseperiod('varying')
assert _rc == 198
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical base_period(varying) baseperiod(" varying ")
assert "`e(base_period)'" == "varying"
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical fix_weights(base) fixweights(baseperiod)
assert "`e(fix_weights)'" == "base_period"
* a comma inside a quoted saverif() filename is part of the filename
tempfile stub11
local d11 "`stub11'-d"
mkdir "`d11'"
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical saverif("`d11'/keep.dta") replace
checksum "`d11'/keep.dta"
local keep_sum = r(checksum)
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical method(reg) saverif("`d11'/keep, replace")
checksum "`d11'/keep.dta"
assert r(checksum) == `keep_sum'
confirm file "`d11'/keep, replace.dta"
* and the standard idiom, a quoted name followed by the replace sub-option,
* still overwrites the named file
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical method(ipw) saverif("`d11'/keep.dta", replace)
checksum "`d11'/keep.dta"
assert r(checksum) != `keep_sum'
capture confirm file "`d11'/keep.dta , replace.dta"
assert _rc != 0
* a directory is not a destination
capture noisily csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical saverif("`d11'") replace
assert _rc == 603
erase "`d11'/keep.dta"
erase "`d11'/keep, replace.dta"
rmdir "`d11'"

display as text "test-option-synonym-quotes: a quoted synonym value means what the primary spelling means"
