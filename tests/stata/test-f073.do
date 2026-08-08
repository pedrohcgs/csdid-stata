* F073 -- degenerate designs must succeed or refuse BY NAME. Never abort.
*
* On 2026-08-07 a seeded multiplier bootstrap on a design with one ATT(g,t)
* cell and an outcome with no within-group variation aborted with r(3200), a
* raw Mata conformability error. Not a wrong answer -- a crash, on a command a
* user had every right to run. It survived because no test drove the shapes
* where kernels run out of things to work with.
*
* This sweeps those shapes. The contract is deliberately weak and therefore
* durable: every cell must either succeed, or fail with a return code the
* package chooses. What it must never do is surface a raw Mata error.
*
* Mata's internal codes are the ones to catch: 3200 conformability, 3300
* subscript, 3001 wrong number of arguments, 3499 uninitialised, 503 non-
* symmetric, 506 not positive definite. A user cannot act on any of them.
*
* Add a row here whenever a new degenerate shape is found; the point is the
* sweep, not any single cell.

version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

* Return codes that mean "the kernel fell over", as opposed to a refusal the
* package made on purpose.
local RAW_MATA 3200 3300 3001 3499 503 506 3202 3204

program define f073_build
    version 15
    args nunits nper ncohort variation
    clear
    quietly set obs `nunits'
    quietly generate long id = _n
    quietly generate double g = 0
    if `ncohort' > 0 {
        quietly replace g = 2 + mod(_n, `ncohort') if mod(_n, 2) == 1
    }
    quietly generate double cl = mod(id, 3) + 1
    quietly generate double x = mod(id, 5) / 5
    quietly expand `nper'
    quietly bysort id: generate int time = _n
    quietly generate double y = cond(g > 0 & time >= g, 2, 0)
    if `variation' quietly replace y = y + mod(id * 7, 11) / 100
end

local nfail = 0
local ncells = 0

* -- shape ------------------------------------- units periods cohorts variation
foreach spec in "10 2 1 0" "10 2 1 1" "4 2 1 0" "6 3 1 0" ///
                "10 2 2 0" "20 2 1 0" "8 4 1 0" "10 3 3 0" ///
                "2 2 1 0" "10 2 1 0" {
    local nu : word 1 of `spec'
    local np : word 2 of `spec'
    local nc : word 3 of `spec'
    local vr : word 4 of `spec'

    foreach inference in "analytical" "wboot(reps(99) rseed(20260807))" {
        foreach meth in reg dr {
            local ++ncells
            f073_build `nu' `np' `nc' `vr'
            local cov = cond("`meth'" == "dr", "x", "")
            capture quietly csdid y `cov', time(time) gvar(g) nevertreated ///
                base_period(varying) bal(none) method(`meth') `inference'
            local rc = _rc
            local israw : list rc in RAW_MATA
            if `israw' {
                display as error "RAW MATA ERROR r(`rc'): units=`nu' periods=`np' " ///
                    "cohorts=`nc' variation=`vr' method(`meth') `inference'"
                local ++nfail
            }
        }
    }
}

display as text "test-f073: swept `ncells' degenerate cells"
if `nfail' > 0 {
    display as error "`nfail' cell(s) aborted with a raw Mata error instead of refusing by name"
    exit 9
}
display as text "test-f073: no degenerate design surfaced a raw Mata error"
