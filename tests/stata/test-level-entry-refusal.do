* ---------------------------------------------------------------------------
* An illegal level() is refused BEFORE the aggregation runs.
*
* csdid_stats and csdid_estat take level() as a free string, so that a typed
* level can be told from an omitted one, and validated only the range. Every
* receiver downstream re-parses the same value with Level(cilevel), which also
* refuses more than two digits after the decimal point. A three-decimal level
* therefore passed the entry check, the aggregation ran, e() was REPLACED and
* any saving() file was written -- and only then did the command exit 198.
*
* A caller who wrapped that in -capture- was left holding a half-finished
* aggregation, and an exported dataset, from a command Stata reported as
* failed. csdid itself never had the defect: it declares Level(cilevel) at
* entry and refuses before doing anything.
*
* Three-decimal levels are not exotic. Any Bonferroni or Sidak adjustment
* produces one: 1 - 0.05/3 is level(98.333).
* ---------------------------------------------------------------------------
version 15
clear all
set more off
set linesize 200

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

use "`root'/src/data/mpdta.dta", clear
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical

* -- 1. csdid_stats refuses, and leaves e() exactly as csdid left it ------
capture noisily csdid_stats, type(dynamic) level(98.333)
assert _rc == 198
* the aggregation must NOT have posted: these are what it would overwrite
assert "`e(agg_type)'" == ""
assert "`e(agg_level)'" == ""
assert "`e(cmd)'" == "csdid"

* -- 2. the estat route refuses before it exports ------------------------
tempfile out
capture noisily estat event, level(98.333) saving("`out'") post
assert _rc == 198
assert "`e(agg_type)'" == ""
* nothing may have been written: a failed command that leaves a file behind
* is how a caller ends up analysing a dataset from a run that did not happen
capture confirm file "`out'.dta"
assert _rc != 0

* -- 3. a legal two-decimal level is untouched ---------------------------
capture noisily csdid_stats, type(dynamic) level(98.33)
assert _rc == 0
assert "`e(agg_type)'" == "dynamic"
assert abs(`e(agg_level)' - 98.33) < 1e-10

* -- 4. and the range check still fires, on its own message --------------
quietly csdid lemp, ivar(countyreal) time(year) gvar(first_treat) analytical
capture noisily csdid_stats, type(dynamic) level(150)
assert _rc == 198
capture noisily csdid_stats, type(dynamic) level(abc)
assert _rc == 198

display as text "test-level-entry-refusal: an illegal level is refused before any work is done"
