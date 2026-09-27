* Lean results keep their influence functions outside e(), so three ordinary
* steps leave the results in e() and the influence functions gone: csdid
* reset, mata clear, and estimates use in a later session. Aggregating then
* has to refuse, and the refusal has to name that cause. The token check
* alone cannot tell it from a genuine mismatch -- results restored from an
* earlier estimation than the one the session holds -- and both used to be
* reported as "do not match the last csdid run", which after a reset blames
* a run nobody made.
*
* Three arms: reset (csdid_stats), mata clear (estat), and the genuine
* mismatch, which must keep its own message.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define chr_log_has, rclass
    version 15
    syntax using/, MESSAGE(string)

    tempname lh
    local body ""
    file open `lh' using `"`using'"', read text
    file read `lh' line
    while r(eof) == 0 {
        local clean = strtrim(`"`line'"')
        if substr(`"`clean'"', 1, 2) == "> " {
            local clean = strtrim(substr(`"`clean'"', 3, .))
        }
        local body `"`body'`clean' "'
        file read `lh' line
    }
    file close `lh'
    local hay = subinstr(`"`body'"', " ", "", .)
    local needle = subinstr(`"`message'"', " ", "", .)
    return scalar found = strpos(`"`hay'"', `"`needle'"') > 0
end

local held "the influence functions of these results are not held in this session"
local mismatch "the stored results do not match the last csdid run"

use "`root'/src/data/mpdta.dta", clear

* ARM 1 -- csdid reset, then csdid_stats.
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
csdid reset
tempfile log1
log using "`log1'", replace text name(chr1)
capture noisily csdid_stats simple
local rc1 = _rc
log close chr1
assert `rc1' == 498
chr_log_has using "`log1'", message("`held'")
assert r(found) == 1
chr_log_has using "`log1'", message("`mismatch'")
assert r(found) == 0

* ARM 2 -- mata clear, then estat.
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
mata: mata clear
tempfile log2
log using "`log2'", replace text name(chr2)
capture noisily estat event
local rc2 = _rc
log close chr2
assert `rc2' == 498
chr_log_has using "`log2'", message("`held'")
assert r(found) == 1

* ARM 3 -- a genuine mismatch: the session holds a later estimation.
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
estimates store chr_first
quietly csdid lemp lpop, ivar(countyreal) time(year) gvar(first_treat) analytical
estimates restore chr_first
tempfile log3
log using "`log3'", replace text name(chr3)
capture noisily csdid_stats simple
local rc3 = _rc
log close chr3
assert `rc3' == 498
chr_log_has using "`log3'", message("`mismatch'")
assert r(found) == 1
chr_log_has using "`log3'", message("`held'")
assert r(found) == 0

display as text "test-cache-held-refusal: PASS"
