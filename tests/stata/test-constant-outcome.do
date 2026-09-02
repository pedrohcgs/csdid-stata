* ---------------------------------------------------------------------------
* An outcome that never changes is refused, and says why.
*
* Before this, csdid estimated it: every ATT(g,t) came back exactly 0 with a
* missing standard error and no band -- a table that reads like "a precisely
* estimated null" rather than "there is nothing here". Three warnings did fire,
* but all named the SYMPTOM (standard errors could not be computed) and their
* list of causes did not include this one.
*
* The test is EXACT equality of the extremes over the estimation sample, not a
* tolerance. An outcome that varies by one part in a million is
* degenerate-but-estimable and must keep running -- that is what
* tests/stata/test-boot-degenerate-screen.do pins -- so this test checks both
* sides of that line.
*
* Owner-approved divergence from did 2.5.1, which runs and returns a critical
* value of -Inf with a table of zeros.
* ---------------------------------------------------------------------------
version 15
clear all
set more off
set linesize 200

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define co_log_has, rclass
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
    local cb = subinstr(`"`body'"', " ", "", .)
    local cm = subinstr(`"`message'"', " ", "", .)
    return scalar found = strpos(`"`body'"', `"`message'"') > 0 | strpos(`"`cb'"', `"`cm'"') > 0
end

clear
set obs 100
generate long id = _n
generate int g = cond(mod(id,3) == 0, 0, 2 + mod(id,3))
expand 4
bysort id: generate int t = _n
generate double yconst = 7
generate double ynear = 7
quietly replace ynear = 7 + 1e-6 if id == 1 & t == 2
generate double ygood = 1 + 0.05*t + 0.4*(g > 0 & t >= g) + mod(id, 7)/9

* 1. a literally constant outcome is refused, by name
tempfile lg
log using "`lg'", text replace name(co1)
capture noisily csdid yconst, ivar(id) time(t) gvar(g) method(reg) nevertreated analytical
local rc_const = _rc
log close co1
assert `rc_const' == 459
co_log_has using "`lg'", message("takes the same value")
assert r(found)
* nothing was posted: a refusal must not leave results standing
assert "`e(cmd)'" == ""

* 2. an outcome that varies by one part in a million still runs
capture noisily csdid ynear, ivar(id) time(t) gvar(g) method(reg) nevertreated analytical
assert _rc == 0

* 3. an ordinary outcome is untouched
capture noisily csdid ygood, ivar(id) time(t) gvar(g) method(reg) nevertreated analytical
assert _rc == 0

* 4. the refusal describes the ESTIMATION sample, so an if() that flattens the
*    outcome is caught even when the full variable varies. The subsample keeps
*    every period and both treated and never-treated units, so a constant
*    outcome is the ONLY thing left to refuse -- and the message is checked,
*    because a generic "no observations" would be the wrong reason.
generate double ymix = ygood
quietly replace ymix = 5 if mod(id, 2) == 0
tempfile lg4
log using "`lg4'", text replace name(co4)
capture noisily csdid ymix if mod(id, 2) == 0, ivar(id) time(t) gvar(g) method(reg) nevertreated analytical
local rc_sub = _rc
log close co4
assert `rc_sub' == 459
co_log_has using "`lg4'", message("takes the same value")
assert r(found)
* and the same variable over the FULL sample still estimates
capture noisily csdid ymix, ivar(id) time(t) gvar(g) method(reg) nevertreated analytical
assert _rc == 0

display as text "test-constant-outcome: a constant outcome is refused and says why"
