* test-agg-boot-named-route.do
* ---------------------------------------------------------------------------
* The aggregate bootstrap has two Mata routes into the same kernels, and until
* this file existed only one of them was ever run by a test.
*
* Under the DEFAULT lean storage the aggregation influence functions stay in
* the engine, and csdid_stats assembles the kernel input in Mata and calls
* csdid_bootstrap_aggte_direct -- no n_units-row object crosses into Stata's
* classic-matrix layer. Under storeall the influence functions genuinely ARE
* Stata matrices, so
* csdid_stats orders them itself and calls csdid_bootstrap_aggte or, when the
* estimation clustered, csdid_bootstrap_aggte_cluster.
*
* NOT THIS ROUTE: `csdid_stats using <riffile>' never bootstraps at all. The
* RIF reload posts no e(bstrap)/e(biters)/e(boot_*), so every kernel is skipped
* and the standard errors are analytical, as csdid_stats.sthlp:117/410 states.
*
* WHAT WAS NOT COVERED. Instrumented on 2026-08-15 by counting entries into
* each of the three kernels through a file channel (`capture' hides anything
* printed from inside them): tests/stata/test-agg-bootstrap-paths.do enters
* the direct kernel six times and the two named kernels never;
* tests/stata/test-agg-cband-parity.do, four and never. The bitwise
* differential grid does not reach them either -- it runs no storeall cell,
* and on a machine with the plugin its aggregate bootstrap is answered by the
* plugin rather than by any of the three.
*
* THE PROPERTY. Both routes hand the same kernel the same rows in the same
* order, drawn from the same seeded stream, so they must agree to the last
* bit. The order is the load-bearing half: the multipliers are drawn per row,
* so a row order that differs from R's gives every draw to the wrong unit
* (F-001/F-022), and the two routes arrive at that order by different code --
* csdid__agg_boot_assemble on the lean side, csdid_boot_reorder_r on the
* storeall side. Every channel of the aggregation is compared, not the
* headline: the five-column table, the ten-column bootstrap table, and the
* whole biters x k draw matrix, for all four aggregation types, clustered and
* not.
*
* The plugin is disabled here on purpose. It is a third implementation of the
* same draws and it has its own gate (test-agg-bootstrap-paths.do); what is
* being checked here is that the two MATA routes have not drifted apart.
*
* SEEDING THE RED, and WHAT THIS TEST CANNOT SEE, which is the same sentence
* twice. It compares two routes against each other, so a fault in anything the
* two SHARE moves both arms by the same amount and leaves the difference at
* zero. Measured, not assumed: a 1e-15 perturbation inside
* csdid__agg_assemble_bootout and one inside csdid__Agg::cluster_core each
* leave this test green, while both move a comparison of the same channels
* against another TREE. Shared-kernel arithmetic is that comparison's job and
* not this one's.
*
* What it does catch, seeded and confirmed:
*   - one argument dropped from the csdid_bootstrap_aggte call site in
*     csdid_stats.ado -- r(3254), the aggregation refuses;
*   - the lean route's draw order reversed inside csdid__agg_boot_assemble --
*     r(459), which is the F-022 property this file exists for.
* And one seeded change that is NOT a defect leaves it green, as it should:
* passing an empty cluster-vector name to csdid_bootstrap_aggte_cluster, which
* is the documented fall-back to the engine's own cluster cache.
* ---------------------------------------------------------------------------
version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* The named kernels run when the plugin does not; a seeded rademacher run is
* served by the plugin on every platform that ships one.
global CSDID_BOOT_PLUGIN_DISABLE 1

local mpdta "`root'/examples/data/mpdta.csv"
confirm file "`mpdta'"
import delimited "`mpdta'", clear asdouble varnames(1)
* A cluster variable coarser than the unit, so the clustered cells collapse to
* something smaller than n and the sqrt(nc)/n scaling is actually exercised.
quietly generate long cl = mod(countyreal, 37) + 1

tempfile channels
tempname R
postfile `R' str24 cell str24 chan long i long j double v using "`channels'", replace

* One (cell, channel) row per matrix element, so a comparison is elementwise
* and a matrix that changes SHAPE shows up as a missing row rather than as
* nothing at all.
capture program drop aggbnr_dump
program define aggbnr_dump
    args R cell chan mat
    tempname M
    capture matrix `M' = `mat'
    if _rc exit
    forvalues i = 1/`=rowsof(`M')' {
        forvalues j = 1/`=colsof(`M')' {
            post `R' ("`cell'") ("`chan'") (`i') (`j') (`M'[`i',`j'])
        }
    }
end

foreach store in lean storeall {
    local storeopt ""
    if "`store'" == "storeall" local storeopt "storeall"
    foreach clu in none cl {
        local clusteropt ""
        if "`clu'" == "cl" local clusteropt "cluster(cl)"
        quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) ///
            method(dr) notyet `clusteropt' `storeopt' ///
            wboot(reps(199) rseed(20260815))
        foreach t in simple group dynamic calendar {
            quietly csdid_stats, type(`t') dropmissing
            aggbnr_dump `R' "`clu'_`t'" "aggte_`store'"  "e(aggte)"
            aggbnr_dump `R' "`clu'_`t'" "boot_`store'"   "e(boot_aggte)"
            aggbnr_dump `R' "`clu'_`t'" "draws_`store'"  "e(agg_boot_draws)"
        }
    }
}
postclose `R'

use "`channels'", clear
* chan carries the arm as its last underscore-separated word; split it off so
* the two arms sit side by side on one row.
generate str16 arm = substr(chan, strrpos(chan, "_") + 1, .)
replace chan = substr(chan, 1, strrpos(chan, "_") - 1)

* SHAPE FIRST, and separately. A channel one arm produces and the other does
* not is a difference, and after the reshape below it would look exactly like
* a channel both arms report as missing -- which is an ordinary RESULT here,
* since type(simple) has no event time and a dimension the bootstrap dropped
* has no standard error. Judging absence and missingness with one test is how
* a first draft of this comparison called sixteen agreeing rows a difference.
quietly by cell chan i j, sort: assert _N == 2

quietly reshape wide v, i(cell chan i j) j(arm) string
quietly count
local n_channels = r(N)
if `n_channels' == 0 {
    display as error "test-agg-boot-named-route: no channels were captured, so nothing was compared"
    exit 459
}
quietly count if (vlean != vstoreall) & !(missing(vlean) & missing(vstoreall))
local n_moved = r(N)

display as text "test-agg-boot-named-route: `n_channels' channels compared, `n_moved' moved"
if `n_moved' > 0 {
    list cell chan i j vlean vstoreall ///
        if (vlean != vstoreall) & !(missing(vlean) & missing(vstoreall)) in 1/20
    display as error "the storeall aggregate bootstrap does not reproduce the lean one draw for draw"
    exit 459
}

display as text "test-agg-boot-named-route: all assertions passed"
