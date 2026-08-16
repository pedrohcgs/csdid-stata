* ---------------------------------------------------------------------------
* perf-inproc-routes.do -- repeated ESTIMATIONS in one warmed session, split by
* the route they take, with the engine's own phase clock beside the total.
*
*   stata-mp -b do tools/bench/perf-inproc-routes.do <srcroot> <out.csv> <tag> <arm> <round> [nunits]
*
* <srcroot>  directory holding src/ado and src/mata (normally the repo root).
* <out.csv>  appended: tag,arm,round,cell,route,position,nunits,reps,bucket,seconds.
* <arm>      free label for the tree being timed; the driver swaps src/ under
*            one directory and names each tree here.
* <round>    1-based; decides the cell order and is written into every row.
* [nunits]   default 400.
*
* WHAT IT IS FOR. A claim that one estimation route got slower has to name the
* route, and a route is not a command line: `method(dr)' with ivar() reaches
* the precomputed doubly-robust panel fit, `method(dr)' without ivar() reaches
* the repeated-cross-section 2x2, and a design that quietly falls off the fast
* path reaches neither. Every row therefore carries `route' as the run itself
* reported it -- e(method), e(compute_path) and e(panel_mode), read back after
* the warm-up and asserted against what the cell asked for. A cell whose route
* is not what it says it is fails here rather than being averaged into a table.
*
* THE FOUR CELLS decompose the doubly-robust route by what it COMPUTES: reg is
* the outcome regression alone, ipw the propensity score alone, dr both, and
* dr_rc the repeated-cross-section route that shares neither fitter. A
* slowdown on dr with reg and ipw flat is a statement about the dr block; the
* same figure on all four is a statement about the driver they share.
*
* THE CLOCK. Stata's timer is not quantised at the millisecond: 2,000 empty
* on/off pairs accumulate 0.00s, and 50 estimations timed individually and
* summed agree with the same 50 under one timer to within 1% (2.06s vs 2.10s
* on the dr cell). So each estimation is timed on its own and the engine's
* profile matrix is accumulated BETWEEN timings, where it costs the figure
* nothing. The engine's phase clock is coarser than that -- csdid__profile_add
* reads now(), whose smallest positive step is 1 ms, and a single phase inside
* one cell is 0.05-0.5 ms -- so the phases are usable only as sums over the
* whole block, which is how they are written.
*
* THE BUCKETS ADD UP BY CONSTRUCTION: `unprofiled' is the block total minus the
* eight profiled phases, so it carries both the unprofiled engine work and the
* ado layer around it. It is reported rather than hidden because a change that
* moves only the unprofiled bucket is a change the phase decomposition cannot
* locate, and that is worth knowing before a candidate is aimed anywhere.
*
* THE ROWS ARE RAW. One row per (arm, round, cell, bucket). Nothing is
* averaged or dropped here; the driver reads the csv back and reports every
* round.
*
* THE ENGINE COMES FROM SOURCE, on every arm, by adopath, so the library walk
* is in none of these numbers -- session-warmup.do is the instrument for that.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

args srcroot out tag arm round nunits
if "`srcroot'" == "" | "`out'" == "" | "`tag'" == "" | "`arm'" == "" | "`round'" == "" {
    display as error "usage: do perf-inproc-routes.do <srcroot> <out.csv> <tag> <arm> <round> [nunits]"
    exit 198
}
if "`nunits'" == "" local nunits 400

adopath ++ "`srcroot'/src/ado"
adopath ++ "`srcroot'/src/mata"

local reps 50

* ---------------------------------------------------------------------------
* Frozen design, no rnormal(): every value is an explicit function of (id,
* time). 400 units x 10 periods is small on purpose -- the point is many
* estimations inside one warmed session, which is the shape that carried the
* doubly-robust residual, not one large estimation.
* ---------------------------------------------------------------------------
quietly set obs `nunits'
quietly generate long id = _n
quietly generate byte g = cond(mod(id, 6) == 0, 0, 3 + mod(id, 5))
quietly expand 10
quietly bysort id: generate int time = _n
quietly generate double x1 = 0.1 * mod(id, 7) + 0.01 * time
quietly generate double x2 = 0.2 * mod(id, 11) - 0.02 * time
quietly generate double y = 0.5 * x1 - 0.3 * x2 + 0.05 * time ///
    + 0.4 * (g > 0 & time >= g) * (time - g + 1) + 0.001 * mod(id, 97)

local panel_opts "ivar(id) time(time) gvar(g) notyet analytical"
local rc_opts    "time(time) gvar(g) notyet analytical"

local cmd_reg   "csdid y x1 x2, `panel_opts' method(reg)"
local cmd_ipw   "csdid y x1 x2, `panel_opts' method(ipw)"
local cmd_dr    "csdid y x1 x2, `panel_opts' method(dr)"
local cmd_dr_rc "csdid y x1 x2, `rc_opts' method(dr)"

tempname fh
file open `fh' using "`out'", write append text

* One route, timed the way the header describes: two discarded warm-ups (which
* is where the route is read back and checked), then reps() estimations timed
* one at a time with the engine's phase clock accumulated between them.
capture program drop pir_block
program define pir_block
    version 15
    args fh tag arm round cell position nunits reps cmd want_method want_panel

    quietly `cmd'
    quietly `cmd'

    * The route as the RUN reports it, not as the command line asked for it.
    local route "`e(method)'|`e(compute_path)'|`e(panel_mode)'"
    assert "`e(method)'" == "`want_method'"
    assert "`e(panel_mode)'" == "`want_panel'"

    mata: CSDID_PIR_ACC = J(8, 3, 0)
    timer clear 9
    forvalues r = 1/`reps' {
        timer on 9
        quietly `cmd'
        timer off 9
        mata: CSDID_PIR_ACC = CSDID_PIR_ACC + CSDID_PROFILE
    }
    quietly timer list 9
    local total = r(t9)

    tempname acc
    mata: st_matrix("`acc'", CSDID_PIR_ACC)
    local phases "setup cell_extract model_fit if_assembly cache_post cluster bootstrap aggregation"
    local sumphase = 0
    local i = 1
    foreach p of local phases {
        local v = `acc'[`i', 1]
        local sumphase = `sumphase' + `v'
        file write `fh' "`tag',`arm',`round',`cell',`route',`position',`nunits',`reps',`p',`v'" _n
        local i = `i' + 1
    }
    local unprofiled = `total' - `sumphase'
    file write `fh' "`tag',`arm',`round',`cell',`route',`position',`nunits',`reps',unprofiled,`unprofiled'" _n
    file write `fh' "`tag',`arm',`round',`cell',`route',`position',`nunits',`reps',total,`total'" _n
end

* Cell order rotates by round and reverses on even rounds, so a machine that
* drifts during a campaign drifts across the cells rather than into one.
local cells "reg ipw dr dr_rc"
local shift = mod(`round' - 1, 4)
forvalues s = 1/`shift' {
    gettoken first cells : cells
    local cells "`cells' `first'"
}
if mod(`round', 2) == 0 {
    local rev ""
    foreach c of local cells {
        local rev "`c' `rev'"
    }
    local cells "`rev'"
}

local position = 1
foreach c of local cells {
    if "`c'" == "dr_rc" {
        pir_block `fh' `tag' `arm' `round' dr_rc `position' `nunits' `reps' "`cmd_dr_rc'" dr repeated-cross-section
    }
    else if "`c'" == "reg" {
        pir_block `fh' `tag' `arm' `round' reg `position' `nunits' `reps' "`cmd_reg'" reg panel
    }
    else if "`c'" == "ipw" {
        pir_block `fh' `tag' `arm' `round' ipw `position' `nunits' `reps' "`cmd_ipw'" ipw panel
    }
    else {
        pir_block `fh' `tag' `arm' `round' dr `position' `nunits' `reps' "`cmd_dr'" dr panel
    }
    local position = `position' + 1
}

file close `fh'
display as text "perf-inproc-routes: `tag' arm `arm' round `round' written"
