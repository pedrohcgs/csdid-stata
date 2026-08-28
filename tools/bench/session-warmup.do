* ---------------------------------------------------------------------------
* session-warmup.do -- what a csdid session pays ONCE, and what it pays every
* time, measured against the compiled library the installed package uses.
*
*   stata-mp -b do tools/bench/session-warmup.do <runtime> <out.csv> <phase> [rif]
*
* <runtime>  directory holding csdid.ado and lcsdid_v2.mlib (normally build/).
* <out.csv>  appended: phase,label,seconds.
* <phase>    `cold', `agg', `rifbuild' or `rif' -- one phase per PROCESS,
*            because each measures a cost that a session pays only once and a
*            warmed session cannot show at all.
* [rif]      where `rifbuild' writes the RIF file and `rif' reads it.
*
* WHAT IT IS FOR. Every instrument in tools/bench/ before this one estimates
* once per fresh process, or estimates repeatedly in one warmed session. Both
* are blind to anything a session pays ONCE, and a session pays a great deal
* once: Mata resolves a function it is not already holding by walking the
* library list, so the first call to each of the engine's functions costs
* whatever that walk costs, and the bill grows with the number of functions
* the engine is divided into. Splitting one routine into six therefore has a
* price that no per-cell or per-row measurement can see, and that a user
* running csdid once in a do-file pays in full.
*
* The `agg' phase is the shape the postestimation workflow actually has --
* estimate, aggregate, estimate -- and is the one that went unmeasured while
* an estimation FOLLOWING an aggregation grew by 11 per cent: the aggregation
* is not what costs, but it is what puts the second estimation on a route no
* earlier command in the session had used.
*
* The `rif' phase is the one workflow that reaches the engine with no csdid in
* front of it: `csdid_stats using <riffile>' aggregates an estimation that ran
* in an EARLIER session, so whatever the loader does for that session, it does
* on the first csdid_stats. It is measured against a file `rifbuild' wrote in
* another process, because a RIF written in the same session would be read by
* a session that had already found the engine.
*
* The verdict is a RATIO of the first run to the steady-state run of the SAME
* command in the SAME session, so it does not depend on the machine's speed.
* tools/bench/run-session-warmup.py holds the budgets and reads it.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

args runtime out phase riffile
if "`runtime'" == "" | "`out'" == "" | "`phase'" == "" {
    display as error "usage: do session-warmup.do <runtime> <out.csv> <cold|agg|rifbuild|rif> [riffile]"
    exit 198
}
adopath ++ "`runtime'"

* ---------------------------------------------------------------------------
* Frozen data, no rnormal(): every value is an explicit function of (id, time),
* so the design cannot drift with a Stata RNG change and the same numbers
* appear on any machine. 5,000 units x 10 periods, five cohorts and a never
* treated group, two covariates -- the shape the doubly-robust panel route
* takes, which is the route the decomposition split most.
*
* The `rif' phase does not build it: that phase estimates nothing, and a
* session that had built the design would have run csdid to write the file it
* is supposed to read from another process.
* ---------------------------------------------------------------------------
tempfile d
if "`phase'" != "rif" {
    quietly set obs 5000
    quietly generate long id = _n
    quietly generate byte g = cond(mod(id, 6) == 0, 0, 3 + mod(id, 5))
    quietly expand 10
    quietly bysort id: generate int time = _n
    quietly generate double x1 = 0.1 * mod(id, 7) + 0.01 * time
    quietly generate double x2 = 0.2 * mod(id, 11) - 0.02 * time
    quietly generate double y = 0.5 * x1 - 0.3 * x2 + 0.05 * time ///
        + 0.4 * (g > 0 & time >= g) * (time - g + 1) + 0.001 * mod(id, 97)
    quietly save "`d'"
}

tempname fh
file open `fh' using "`out'", write append text

local est "csdid y x1 x2, ivar(id) time(time) gvar(g) method(dr) analytical pointwise nevertreated base_period(varying) bal(none)"
local warm "csdid y, ivar(id) time(time) gvar(g) method(reg) analytical pointwise nevertreated base_period(varying) bal(none)"

capture program drop swu_time
program define swu_time
    version 15
    args fh phase label cmd
    timer clear 1
    timer on 1
    quietly `cmd'
    timer off 1
    quietly timer list 1
    file write `fh' "`phase',`label',`=r(t1)'" _n
end

* The saved-RIF aggregation gets its own timer because the file name has to
* reach the command inside quotes, which a command passed as one argument
* cannot carry.
capture program drop swu_time_rif
program define swu_time_rif
    version 15
    args fh label riffile
    timer clear 1
    timer on 1
    quietly csdid_stats using "`riffile'", type(dynamic)
    timer off 1
    quietly timer list 1
    file write `fh' "rif,`label',`=r(t1)'" _n
end

if "`phase'" == "cold" {
    * The command is the first csdid of the process, so it pays for every
    * engine function it reaches; the second run of the same command in the
    * same session pays for none of them.
    quietly use "`d'", clear
    swu_time `fh' cold first "`est'"
    quietly use "`d'", clear
    swu_time `fh' cold steady "`est'"
    quietly use "`d'", clear
    swu_time `fh' cold steady "`est'"
}
else if "`phase'" == "agg" {
    * estimate -> aggregate -> estimate, the documented postestimation
    * workflow. The timed run is the estimation that FOLLOWS the aggregation
    * and is the first of the session to take the doubly-robust panel route.
    quietly use "`d'", clear
    quietly `warm'
    quietly csdid_stats, type(dynamic)
    quietly use "`d'", clear
    swu_time `fh' agg first "`est'"
    quietly use "`d'", clear
    swu_time `fh' agg steady "`est'"
    quietly csdid_stats, type(dynamic)
    quietly use "`d'", clear
    swu_time `fh' agg steady "`est'"
}
else if "`phase'" == "rifbuild" {
    * Not timed: the file the `rif' phase reads has to come from a DIFFERENT
    * process, which is the whole of what that phase is about.
    if "`riffile'" == "" {
        display as error "rifbuild needs a file to write"
        exit 198
    }
    quietly use "`d'", clear
    quietly `est' saverif("`riffile'") replace
    confirm file "`riffile'"
}
else if "`phase'" == "rif" {
    * A session in which csdid never runs. The first aggregation pays for
    * every engine function the aggregation reaches -- and it is the first
    * command of the session, so nothing before it settled which engine that
    * is or where to find it. The second, same command same session, pays for
    * none of them.
    if "`riffile'" == "" {
        display as error "rif needs the file rifbuild wrote"
        exit 198
    }
    confirm file "`riffile'"
    swu_time_rif `fh' first "`riffile'"
    swu_time_rif `fh' steady "`riffile'"
    swu_time_rif `fh' steady "`riffile'"
}
else {
    display as error "phase must be cold, agg, rifbuild or rif"
    exit 198
}

file close `fh'
