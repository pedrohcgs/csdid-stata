* F071 -- the duplicate-column aggregations use the plugin, and still obey the
* single-draw rule that F-004 protects.
*
* When the aggregate influence function is one column duplicated -- type(simple)
* always, and a one-effect event window (window(0 0)) by the numeric test the
* command applies -- the effect column and the overall column are the same
* vector. R's aggte runs a SINGLE mboot whose draws serve both. The plugin
* draws the overall column from its own stream, which R never draws.
*
* type(simple) was therefore excluded from the plugin outright, which left the
* simplest aggregation as the slowest: 1.081s against 0.350s for group on
* 30,000 units and 999 replications. The Mata rule it fell back to is two lines
* -- draw column one, copy it to the overall column -- so the plugin can be
* used and the same rule applied to its output. It now runs at 0.183s.
*
* Two things have to hold, and both are asserted here:
*
*   1. the overall column IS the effect column, not a second draw. Under the
*      rule they are equal to the LAST BIT, so this is an exact test: if the
*      plugin's own overall block were ever read again, they would differ in
*      roughly the fifteenth digit and this would fail.
*   2. the plugin and the Mata kernels agree, since the Mata path is the one
*      the R-parity fixtures pin.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define f071_data
    version 15
    clear
    quietly set obs 3000
    quietly generate long id = _n
    quietly generate byte arm = mod(_n, 5)
    quietly generate double g = cond(arm == 0, 0, 2 + arm)
    quietly generate double cl = mod(id, 53) + 1
    quietly generate double ui = mod(id * 11, 23) / 23 - 0.5
    quietly expand 8
    quietly bysort id: generate double time = _n
    quietly generate double y = ui + 0.2 * time ///
        + mod(id * 5 + time * 3, 31) / 31 ///
        + cond(g > 0 & time >= g, 1.1 + 0.3 * (time - g), 0)
end

* e(aggte) is egt, att, se, overall_att, overall_se
local C_ATT 2
local C_SE 3
local C_OATT 4
local C_OSE 5

local nchecked = 0
foreach spec in "simple|notyet wboot(reps(999) rseed(20260806))|" ///
                "simple|notyet wboot(reps(499) rseed(7)) pointwise|" ///
                "simple|notyet cluster(cl) wboot(reps(499) rseed(11))|" ///
                "event|notyet wboot(reps(999) rseed(20260806))|window(0 0)" {

    gettoken agg rest : spec, parse("|")
    gettoken bar rest : rest, parse("|")
    gettoken est rest : rest, parse("|")
    gettoken bar aggopt : rest, parse("|")
    local aggopt = subinstr("`aggopt'", "|", "", .)

    * --- with the plugin -------------------------------------------------
    global CSDID_BOOT_PLUGIN_DISABLE 0
    quietly f071_data
    quietly csdid y, ivar(id) time(time) gvar(g) `est'
    quietly csdid_stats `agg', `aggopt'
    tempname P
    matrix `P' = e(aggte)
    local pacc "`e(agg_boot_accelerator)'"

    * --- with the Mata kernels -------------------------------------------
    global CSDID_BOOT_PLUGIN_DISABLE 1
    quietly f071_data
    quietly csdid y, ivar(id) time(time) gvar(g) `est'
    quietly csdid_stats `agg', `aggopt'
    tempname M
    matrix `M' = e(aggte)
    local macc "`e(agg_boot_accelerator)'"
    global CSDID_BOOT_PLUGIN_DISABLE 0

    * the plugin must actually be what ran, or the rest of this is vacuous
    assert "`pacc'" == "plugin"
    assert "`macc'" == "mata"
    assert rowsof(`P') == rowsof(`M')

    * 1. the single-draw rule, exactly
    forvalues i = 1 / `= rowsof(`P')' {
        assert `P'[`i', `C_SE'] == `P'[`i', `C_OSE']
        assert `P'[`i', `C_ATT'] == `P'[`i', `C_OATT']
    }

    * 2. the two accelerators agree
    local dmax = 0
    forvalues i = 1 / `= rowsof(`P')' {
        forvalues c = 1 / `= colsof(`P')' {
            if !missing(`P'[`i', `c']) & !missing(`M'[`i', `c']) {
                local d = abs(`P'[`i', `c'] - `M'[`i', `c'])
                local rel = cond(abs(`M'[`i', `c']) > 1e-12, ///
                    `d' / abs(`M'[`i', `c']), `d')
                local dmax = max(`dmax', `rel')
            }
        }
    }
    assert `dmax' < 1e-12
    local ++nchecked
}

assert `nchecked' == 4

display as text "test-f071: duplicate-column aggregations run on the plugin, overall column exact, plugin vs mata agree"
