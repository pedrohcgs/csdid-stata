* F069 -- the printed output says how the standard errors were produced.
*
* A reader of a csdid table cannot tell an analytical run from a multiplier
* bootstrap, cannot see the replication count, and -- the part that actually
* costs people time -- cannot see that an UNSEEDED bootstrap was run, whose
* numbers drift between two identical calls. csdid prints those facts under
* the estimation table. The aggregation printed nothing: its Display parsed
* level() and discarded it, so even the confidence level shown in the table
* was absent from the header.
*
* Neither header was covered by a test. Both are covered here, because a
* printed line that nothing asserts is a line that silently stops printing.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* Read a logged run back and confirm a line containing every fragment exists.
* Fragment-wise rather than whole-line, so that column widths, wrapping and
* the surrounding table cannot make this brittle.
program define f069_expect
    version 15
    syntax , LOGFILE(string) FRAGMENTS(string) [ABSENT(string)]

    * Stata's log wraps at the line width and marks the continuation with a
    * leading "> ". Those have to be rejoined with NO separator -- the break
    * can fall inside a word -- while genuine line breaks become spaces.
    tempname fh
    local hay ""
    file open `fh' using "`logfile'", read text
    file read `fh' line
    while r(eof) == 0 {
        local head = substr(`"`macval(line)'"', 1, 2)
        if `"`head'"' == "> " {
            local rest = substr(`"`macval(line)'"', 3, .)
            local hay `"`macval(hay)'`macval(rest)'"'
        }
        else {
            local hay `"`macval(hay)' `macval(line)'"'
        }
        file read `fh' line
    }
    file close `fh'

    foreach frag of local fragments {
        local frag : subinstr local frag "~" " ", all
        if strpos(`"`hay'"', `"`frag'"') == 0 {
            display as error "expected fragment not found: `frag'"
            exit 9
        }
    }
    foreach frag of local absent {
        local frag : subinstr local frag "~" " ", all
        if strpos(`"`hay'"', `"`frag'"') > 0 {
            display as error "fragment should be absent: `frag'"
            exit 9
        }
    }
end

tempfile lg
import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
tempfile mp
quietly save "`mp'", replace

* ---------------------------------------------------------------------------
* 1. Seeded bootstrap, clustered: the aggregation header names the method, the
*    replication count, the seed, the cluster variable and the level it was
*    actually given -- level(90), which used to be parsed and thrown away.
* ---------------------------------------------------------------------------
quietly use "`mp'", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) notyet ///
    wboot(reps(199) rseed(20260806)) cluster(countyreal)
capture log close _all
log using "`lg'", text replace
csdid_stats event, level(90)
log close
f069_expect, logfile("`lg'") ///
    fragments("multiplier~bootstrap,~199~reps" "rseed(20260806)" ///
              "clustered~on~countyreal" "90%~simultaneous~bands") ///
    absent("no~seed~set")

* ---------------------------------------------------------------------------
* 2. Unseeded bootstrap: the header has to say so. This is the case the
*    estimation-side header was added for.
* ---------------------------------------------------------------------------
quietly use "`mp'", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) notyet ///
    wboot(reps(199))
capture log close _all
log using "`lg'", text replace
csdid_stats simple
log close
f069_expect, logfile("`lg'") ///
    fragments("multiplier~bootstrap,~199~reps" "no~seed~set~(not~reproducible)") ///
    absent("rseed(")

* ---------------------------------------------------------------------------
* 3. Analytical: named as such, and not described as a bootstrap.
* ---------------------------------------------------------------------------
quietly use "`mp'", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) notyet analytical
capture log close _all
log using "`lg'", text replace
csdid_stats group
log close
f069_expect, logfile("`lg'") ///
    fragments("analytical~(influence~function)" "95%~pointwise~bands") ///
    absent("multiplier~bootstrap")

display as text "test-f069: aggregation header reports method, reps, seed, clustering and level"

* ---------------------------------------------------------------------------
* 4. The estimation-side header, same facts, previously untested too.
* ---------------------------------------------------------------------------
quietly use "`mp'", clear
capture log close _all
log using "`lg'", text replace
csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) notyet ///
    wboot(reps(199)) level(90)
log close
f069_expect, logfile("`lg'") ///
    fragments("multiplier~bootstrap,~199~reps" "no~seed~set~(not~reproducible)" ///
              "90%") ///
    absent("rseed(")

quietly use "`mp'", clear
capture log close _all
log using "`lg'", text replace
csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) notyet analytical
log close
f069_expect, logfile("`lg'") ///
    fragments("analytical~(influence~function)") ///
    absent("multiplier~bootstrap")

display as text "test-f069: estimation header reports the same facts"
