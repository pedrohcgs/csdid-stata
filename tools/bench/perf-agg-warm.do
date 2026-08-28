* ---------------------------------------------------------------------------
* perf-agg-warm.do -- repeated AGGREGATIONS in one warmed session, which is the
* shape none of the other timing instruments has.
*
*   stata-mp -b do tools/bench/perf-agg-warm.do <srcroot> <out.csv> <tag> <arm> <round> [nunits]
*
* <srcroot>  directory holding src/ado and src/mata (normally the repo root).
* <out.csv>  appended: tag,arm,round,cell,position,block,nunits,reps,seconds.
* <arm>      free label for the tree being timed; the driver swaps src/ under
*            one directory and names each tree here.
* <round>    1-based; decides the cell order (see ROTATION below) and is
*            written into every row, so no round is ever averaged away.
* [nunits]   default 5000.
*
* WHAT IT IS FOR. perf-differential.do proves a change moves no NUMBER;
* perf-scale.do proves it moves no CLOCK at increasing n; session-warmup.do
* proves a fresh session does not pay more to go and find the engine. All three
* are dominated by an ESTIMATION. The aggregation is a few milliseconds beside
* it, so a change that costs the aggregation ten per cent moves those
* instruments by less than their noise, and the stage that gave the aggregation
* an object had no cell that could see it. perf-scale.do gained three
* aggregation cells for that reason, but each of them re-estimates inside the
* replicate; this one estimates ONCE and then aggregates, which is both the
* documented postestimation workflow (estat event, then estat group, then estat
* calendar, each reading the same stored results back) and the only shape in
* which the aggregation is most of what is being measured.
*
* THE FIGURE. reps() consecutive aggregations under ONE timer, divided by
* reps(): Stata's timer resolves to 1 ms and one aggregation on this design is
* 4-14 ms, so a single one is unmeasurable and a block of twenty-five is not.
* Three such blocks are timed per cell per round and all three are written; the
* driver reads the smallest, because interference only adds time. Every
* cell is warmed with discarded aggregations of its own type first, so no
* block carries a first-call name lookup -- that cost is real, it is what
* session-warmup.do exists to measure, and it does not belong in a figure about
* the aggregation's arrangement.
*
* THE ROWS ARE RAW. One row per (arm, round, cell, block). Nothing is
* averaged, ranked or dropped in this file; the driver reads the csv back and
* reports every round. An instrument that emits only a median cannot be re-read after the
* fact, and a reading it produced cannot be checked by anyone who did not run
* it.
*
* ROTATION. The four lean cells rotate their order by round, and the storeall
* block changes places with them on even rounds, so a machine that drifts
* during a campaign drifts across the cells rather than into one. The storeall
* block cannot simply join the rotation: it needs its own estimation, and the
* estimation is what settles which route the aggregations then read, so each
* block re-estimates for itself. Both estimations sit outside every timer, and
* each block asserts the route it got.
*
* WHY storeall IS A CELL OF ITS OWN. Under lean storage the influence functions
* stay in Mata and the aggregation reads the engine's cache; under storeall
* they were posted to a Stata matrix and are read back across the classic
* matrix layer, which is quadratic in the unit count (measured in
* csdid__Agg::store: 4s at 25,000 units, 148s at 100,000). Those are two
* different routes into the same aggregation and only one of them is the
* default, so they are timed separately, the storeall block takes fewer reps,
* and its caller keeps the unit count where the crossing is a fraction of the
* aggregation rather than all of it.
*
* THE ENGINE COMES FROM SOURCE, on every arm, by adopath. A campaign that
* compared a built library against a built library would have to rebuild per
* arm, and the build is not what this measures; loading from source puts the
* library walk in none of these numbers, which is what session-warmup.do is
* for.
* ---------------------------------------------------------------------------

version 15
clear all
set more off

args srcroot out tag arm round nunits
if "`srcroot'" == "" | "`out'" == "" | "`tag'" == "" | "`arm'" == "" | "`round'" == "" {
    display as error "usage: do perf-agg-warm.do <srcroot> <out.csv> <tag> <arm> <round> [nunits]"
    exit 198
}
if "`nunits'" == "" local nunits 5000

adopath ++ "`srcroot'/src/ado"
adopath ++ "`srcroot'/src/mata"

* Reps per block. The lean aggregations are 4-14 ms each on the default
* design and the storeall one is about 100 ms, so the two carry different
* counts and every block lands between 0.1 s and 0.6 s against a 1 ms clock.
local reps       25
local reps_store 6

* ---------------------------------------------------------------------------
* Frozen design, no rnormal(): every value is an explicit function of (id,
* time), so the design cannot drift with a Stata RNG change and the same
* numbers appear on any machine. Five cohorts and a never-treated group, which
* is what gives the calendar and group aggregations something to aggregate.
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
tempfile d
quietly save "`d'"

local est_lean  "csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical pointwise"
local est_store "csdid y, ivar(id) time(time) gvar(g) method(reg) notyet analytical pointwise storeall"

tempname fh
file open `fh' using "`out'", write append text

* Every type, aggregated once and thrown away. The block below warms its own
* type too, but the FIRST block of a session would otherwise carry what the
* session pays to reach the aggregation at all, and that cost belongs to
* session-warmup.do rather than here.
capture program drop paw_warm
program define paw_warm
    version 15
    foreach t in simple group dynamic calendar {
        quietly csdid_stats, type(`t')
    }
end

* One aggregation type, timed the way the header describes: three discarded
* aggregations of the same type, then BLOCKS timed blocks of reps() each.
*
* Every block is written. The driver reads the smallest of a round's blocks,
* because interference only ever ADDS time: a block that shared the machine
* with something else is longer than the same block alone, never shorter, so
* the minimum is the estimate that a busy machine cannot inflate. Measured on
* this machine with two byte-identical arms, single blocks put a round as far
* as 13% out; the same rounds read on the minimum of three sit inside 2%.
capture program drop paw_block
program define paw_block
    version 15
    args fh tag arm round cell position nunits reps type

    local blocks 3
    forvalues w = 1/3 {
        quietly csdid_stats, type(`type')
    }
    forvalues b = 1/`blocks' {
        timer clear 9
        timer on 9
        forvalues r = 1/`reps' {
            quietly csdid_stats, type(`type')
        }
        timer off 9
        quietly timer list 9
        local secs = r(t9) / `reps'
        file write `fh' "`tag',`arm',`round',`cell',`position',`b',`nunits',`reps',`secs'" _n
    }
end

* ---------------------------------------------------------------------------
* Cell order. The four lean cells rotate by round; the storeall block leads on
* even rounds and trails on odd ones.
* ---------------------------------------------------------------------------
local lean_cells "simple group dynamic calendar"
local shift = mod(`round' - 1, 4)
forvalues s = 1/`shift' {
    gettoken first lean_cells : lean_cells
    local lean_cells "`lean_cells' `first'"
}

if mod(`round', 2) == 0 local blocks "store lean"
else                    local blocks "lean store"

local position = 1
foreach b of local blocks {
    if "`b'" == "lean" {
        quietly use "`d'", clear
        quietly `est_lean'
        * The route the block is about to time, taken from the run rather than
        * from the command line that asked for it.
        assert "`e(storage)'" == "lean"
        paw_warm
        foreach t of local lean_cells {
            paw_block `fh' `tag' `arm' `round' agg_`t' `position' `nunits' `reps' `t'
            local position = `position' + 1
        }
    }
    else {
        quietly use "`d'", clear
        quietly `est_store'
        assert "`e(storage)'" != "lean"
        paw_warm
        paw_block `fh' `tag' `arm' `round' agg_storeall `position' `nunits' `reps_store' dynamic
        local position = `position' + 1
    }
}

file close `fh'
display as text "perf-agg-warm: `tag' arm `arm' round `round' written"
