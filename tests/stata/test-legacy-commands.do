* Legacy and utility commands carried over from csdid 1.82.
*
* These four deprecated commands and the two supported utilities had never been
* executed by this project. Shipping four untested ado files into a package
* where everything else is gated is not defensible, so this at minimum loads
* each one, confirms it runs, and pins the contract that matters: csgvar
* produces the cohort coding csdid requires, and the deprecated commands
* announce themselves.
version 15
clear all
set more off

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/legacy"
adopath ++ "`root'/src/mata"

foreach f in csgvar _gcsgvar {
    confirm file "`root'/src/ado/`f'.ado"
}
foreach f in csdid_rif csdid_table dipt tsvmat {
    confirm file "`root'/src/legacy/`f'.ado"
}
confirm file "`root'/src/help/csdid_legacy.sthlp"

* ---- csgvar builds the cohort variable csdid expects -----------------------
import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
generate byte treated = (firsttreat > 0 & year >= firsttreat)
csgvar gvar_built = treated, tvar(year) ivar(countyreal)

* never-treated units must be 0, treated units their first treated period
assert gvar_built == 0 if firsttreat == 0
assert gvar_built == firsttreat if firsttreat > 0 & !missing(gvar_built)
quietly count if missing(gvar_built)
assert r(N) == 0

* and the result must actually drive csdid to the same answer as the original
quietly csdid lemp, ivar(countyreal) time(year) gvar(gvar_built) analytical nevertreated base_period(varying) bal(none)
matrix B = e(attgt)
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) analytical nevertreated base_period(varying) bal(none)
matrix A = e(attgt)
assert rowsof(A) == rowsof(B)
mata: st_local("d", strofreal(max(abs(st_matrix("A")[.,4] - st_matrix("B")[.,4]))))
assert `d' < 1e-12

* the egen form is the same computation -- csgvar forwards to _gcsgvar, which
* is what `egen g = csgvar(...)' dispatches to, so this is the route that a
* de-duplication could silently break
egen gvar_egen = csgvar(treated), tvar(year) ivar(countyreal)
assert gvar_egen == gvar_built
quietly count if missing(gvar_egen)
assert r(N) == 0

* csgvar refuses a treatment indicator with more than two values, with a
* documented return code rather than the old undocumented 4444
generate byte three_vals = mod(_n, 3)
capture csgvar bad = three_vals, tvar(year) ivar(countyreal)
assert _rc == 459
capture egen bad_egen = csgvar(three_vals), tvar(year) ivar(countyreal)
assert _rc == 459

* and it refuses a two-valued indicator whose untreated state is not 0. This
* one used to pass: `replace aux = 0 if exp == 0' never fired, every unit came
* back with a positive cohort, and csdid then silently coerced the latest
* treated cohort into the comparison group -- wrong sample, rc 0.
generate byte treated12 = treated + 1
capture csgvar bad12 = treated12, tvar(year) ivar(countyreal)
assert _rc == 459
capture egen bad12_egen = csgvar(treated12), tvar(year) ivar(countyreal)
assert _rc == 459

* a two-valued indicator coded 0/5 is still accepted: only the UNTREATED value
* has to be 0, and legacy do-files may rely on that
generate byte treated05 = 5 * treated
csgvar gvar05 = treated05, tvar(year) ivar(countyreal)
assert gvar05 == gvar_built
drop gvar05

* ---- an expression is an expression on both routes -------------------------
* `syntax newvarname =/exp' declares a Stata expression, and every parenthesis
* used to be stripped out of it before it was used as a VARIABLE NAME. The
* bare-variable case survived only because the strip also removed the
* parentheses csgvar's own forward adds; anything else came back as a garbled
* fragment of the user's own input (`>= invalid name', `variable treated*1 not
* found'). The expression is now evaluated once, so both routes accept one and
* give the same answer the bare variable gives.
csgvar gvar_expr = (firsttreat > 0 & year >= firsttreat), tvar(year) ivar(countyreal)
assert "`: type gvar_expr'" == "double"
assert gvar_expr == gvar_built
egen gvar_expr_egen = csgvar((treated)*(1)), tvar(year) ivar(countyreal)
assert gvar_expr_egen == gvar_built

* the label and the refusals name the expression as the user typed it -- not
* csgvar's own forwarding parentheses, and not a fragment
assert "`: variable label gvar_built'" == "Group Variable based on treated"
assert "`: variable label gvar_egen'" == "Group Variable based on treated"
assert "`: variable label gvar_expr'" == "Group Variable based on (firsttreat > 0 & year >= firsttreat)"
assert "`: variable label gvar_expr_egen'" == "Group Variable based on (treated)*(1)"
drop gvar_expr gvar_expr_egen

* the data-shape refusals still fire when the count comes from an expression
capture csgvar bad_expr = (three_vals + 0), tvar(year) ivar(countyreal)
assert _rc == 459
capture egen bad_expr_egen = csgvar(three_vals * 1), tvar(year) ivar(countyreal)
assert _rc == 459

* ---- the requested storage type is the type you get ------------------------
* `typlist' was parsed and thrown away: every route produced a float, whatever
* was asked for. A cohort code is a value on the time axis, so on a %tc or
* epoch-second axis float's 24-bit mantissa rounds it, and the rounded cohort
* is a different treatment group handed to csdid with rc 0.
foreach t in double long int {
    egen `t' gvar_`t' = csgvar(treated), tvar(year) ivar(countyreal)
    assert "`: type gvar_`t''" == "`t'"
    assert gvar_`t' == gvar_built
    drop gvar_`t'
}
csgvar float gvar_cmd_float = treated, tvar(year) ivar(countyreal)
assert "`: type gvar_cmd_float'" == "float"
drop gvar_cmd_float

* with no type asked for, the command form gives double rather than `set type',
* because the time axis is what the answer lives on
csgvar gvar_default = treated, tvar(year) ivar(countyreal)
assert "`: type gvar_default'" == "double"
drop gvar_default

* and a cohort code past float's exact range survives, to the unit
preserve
quietly replace year = 20000000 + year
quietly replace firsttreat = 20000000 + firsttreat if firsttreat > 0
quietly replace treated = (firsttreat > 0 & year >= firsttreat)
csgvar gvar_big = treated, tvar(year) ivar(countyreal)
assert "`: type gvar_big'" == "double"
assert gvar_big == firsttreat
quietly count if gvar_big > 16777216
assert r(N) > 0
drop gvar_big

* a type that cannot hold it is refused rather than rounding in silence
capture egen float gvar_narrow = csgvar(treated), tvar(year) ivar(countyreal)
assert _rc == 198
capture confirm variable gvar_narrow
assert _rc != 0
restore

* ---- the deprecated commands load and announce themselves ------------------
* Each must be loadable. A syntax error in a shipped ado is a packaging defect
* even when the command is deprecated.
foreach c in csdid_rif csdid_table dipt tsvmat {
    capture program drop `c'
    quietly capture noisily run "`root'/src/legacy/`c'.ado"
    assert _rc == 0
}

* ---- csdid_table tabulates the run it is handed ---------------------------
* It used to read its whole statistics block out of e(cband) -- a k x 5 matrix
* in csdid 1.82, a scalar flag in csdid 2.0.0. Read as a matrix, the scalar
* gave a 1x1 object, so every subscript past the first resolved to missing: an
* entirely blank t column and two blank columns under a "[95% conf. interval]"
* header, plus an r(table) -- the name esttab, coefplot and putexcel read --
* whose se/t/ll/ul rows were missing throughout. All at rc 0.
import delimited using "`root'/tests/fixtures/parity/py019/inputs/mpdta.csv", clear asdouble
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) analytical nevertreated base_period(varying) bal(none)
tempname CTB CTV CTT CTCRIT CTSE
matrix `CTB' = e(b)
matrix `CTV' = e(V)
scalar `CTCRIT' = e(crit_val)
capture noisily csdid_table
assert _rc == 0
matrix `CTT' = r(table)
local ct_k = colsof(`CTT')
assert `ct_k' == colsof(`CTB')
* the numbers are csdid's own: the coefficients, the square root of the e(V)
* diagonal, and the band at the critical value csdid itself used
forvalues j = 1/`ct_k' {
    scalar `CTSE' = sqrt(`CTV'[`j',`j'])
    assert !missing(`CTT'[1,`j'], `CTT'[2,`j'], `CTT'[3,`j'], `CTT'[5,`j'], `CTT'[6,`j'])
    assert abs(`CTT'[1,`j'] - `CTB'[1,`j']) < 1e-12
    assert abs(`CTT'[2,`j'] - `CTSE') < 1e-12
    assert abs(`CTT'[3,`j'] - `CTB'[1,`j'] / `CTSE') < 1e-9
    assert abs(`CTT'[5,`j'] - (`CTB'[1,`j'] - `CTCRIT' * `CTSE')) < 1e-12
    assert abs(`CTT'[6,`j'] - (`CTB'[1,`j'] + `CTCRIT' * `CTSE')) < 1e-12
}

* the same holds after an aggregation post, where e(b) carries the event-study
* coefficient names instead of the ATT(g,t) ones
quietly csdid lemp, ivar(countyreal) time(year) gvar(firsttreat) analytical nevertreated base_period(varying) bal(none) agg(event)
matrix `CTB' = e(b)
quietly csdid_table
matrix `CTT' = r(table)
local ct_k = colsof(`CTT')
assert `ct_k' == colsof(`CTB')
forvalues j = 1/`ct_k' {
    assert !missing(`CTT'[2,`j'], `CTT'[3,`j'], `CTT'[5,`j'], `CTT'[6,`j'])
}

* and with nothing to tabulate it refuses by name rather than printing blanks
* under a filled-in header
ereturn clear
capture noisily csdid_table
assert _rc == 459

* ---- csdid_rif does not reach into the user's namespace -------------------
* It used to hand its results out through the fixed global names bb_, VV_ and
* cln_. Two things followed. `ereturn post bb_ VV_' CONSUMES those matrices, so
* a user who happened to have a matrix called bb_ lost it outright. And an
* UNCLUSTERED run picked up whatever scalar cln_ was already lying around and
* posted it as e(N_clust): with a stray cln_ = 12345 in memory, csdid_rif
* reported 12345 clusters for a run with no cluster() at all.
*
* The estimates were never affected, and must not be now.
clear
quietly set obs 2000
quietly generate long id = _n
quietly generate double cl = mod(id, 41) + 1
quietly generate double rif1 = mod(id * 13, 97) / 97 - 0.5 + 1.2
quietly generate double rif2 = mod(id * 7, 89) / 89 - 0.5 + 0.4

matrix bb_ = J(2, 2, 42)
matrix VV_ = J(3, 3, 7)
scalar cln_ = 12345

quietly csdid_rif rif1 rif2
* no cluster() was given, so there is no cluster count to report -- and
* certainly not the user's scalar
assert missing(e(N_clust))
assert "`e(vcetype)'" == "Robust"
tempname RIFB
matrix `RIFB' = e(b)
assert colsof(`RIFB') == 2

* the estimates are posted with obs() and esample(). Without them e(N) does not
* exist and e(sample) is all zeros, so `summarize if e(sample)', estat
* summarize and the bootstrap prefix all have nothing to work with.
quietly count if e(sample)
assert r(N) == 2000
assert e(N) == 2000
* e(cmd) is the last thing stored, so it cannot certify a half-filled e()
assert "`e(cmd)'" == "csdid_rif"

quietly csdid_rif rif1 rif2, cluster(cl)
assert e(N_clust) == 41
quietly count if e(sample)
assert r(N) == 2000
assert e(N) == 2000

quietly csdid_rif rif1 rif2, wboot reps(199) seed(20260806)
assert "`e(vcetype)'" == "WBoot"

* this is the route that posts a genuine k x 5 e(cband) MATRIX, and csdid_table
* must still read it: the branch there keys on the type of e(cband), not on
* which command ran, so repairing the csdid 2.0.0 caller cannot break this one.
tempname RIFCB RIFT
matrix `RIFCB' = e(cband)
assert rowsof(`RIFCB') == 2 & colsof(`RIFCB') == 5
quietly csdid_table
matrix `RIFT' = r(table)
forvalues j = 1/2 {
    assert abs(`RIFT'[1, `j'] - `RIFCB'[`j', 1]) < 1e-12
    assert abs(`RIFT'[2, `j'] - `RIFCB'[`j', 2]) < 1e-12
    assert abs(`RIFT'[3, `j'] - `RIFCB'[`j', 3]) < 1e-12
    assert abs(`RIFT'[5, `j'] - `RIFCB'[`j', 4]) < 1e-12
    assert abs(`RIFT'[6, `j'] - `RIFCB'[`j', 5]) < 1e-12
}

* the user's own objects are exactly as they were left
assert rowsof(bb_) == 2 & colsof(bb_) == 2 & bb_[1, 1] == 42
assert rowsof(VV_) == 3 & colsof(VV_) == 3 & VV_[1, 1] == 7
assert cln_ == 12345

* ---- tsvmat carries the matrix values rather than a rounded copy -----------
* The generate line interpolated a `type' macro the program never defines, so
* it expanded to nothing on every run and the new variables took `set type' --
* float. A Stata matrix holds doubles, so every value this command exists to
* move into the data was truncated to a 24-bit mantissa.
clear
set obs 3
tempname TSM
matrix `TSM' = (1.123456789012345, 2 \ 3, 4 \ 5, 6)
tsvmat `TSM', name(tsv1 tsv2)
assert "`: type tsv1'" == "double"
assert "`: type tsv2'" == "double"
assert tsv1[1] == `TSM'[1, 1]
assert tsv1[1] == 1.123456789012345
assert tsv1[2] == 3 & tsv1[3] == 5
assert tsv2[1] == 2 & tsv2[2] == 4 & tsv2[3] == 6

* --- cold-audit LEG cells (2026-08-24): each was red by direct probe on the
* pre-fix tree before the repair below it was believed. ---

* LEG-1/LEG-2: a nondefault wboot level() completes, posts its provenance,
* and a replay under a different c(level) still labels the stored level.
clear
set obs 8
generate double lrif = _n
set level 95
csdid_rif lrif, wboot reps(99) seed(123) level(90)
assert _rc == 0
assert e(level) == 90
assert "`e(cmd)'" == "csdid_rif"
set level 95
tempfile leg2log
tempname LEG2R
log using "`leg2log'", text name(leg2)
csdid_table
* copied before `log close': log is rclass, so closing it replaces r()
matrix `LEG2R' = r(table)
log close leg2
* the header names the stored 90% level, not the session's 95, and the
* bounds are the stored e(cband) bounds untouched
mata: st_local("leg2_says90", strofreal(sum(strpos(cat(st_local("leg2log")), "90%")) > 0))
mata: st_local("leg2_says95", strofreal(sum(strpos(cat(st_local("leg2log")), "95%")) > 0))
assert `leg2_says90' == 1
assert `leg2_says95' == 0
tempname LEG2C
matrix `LEG2C' = e(cband)
assert reldif(`LEG2R'[5, 1], `LEG2C'[1, 4]) < 1e-12
assert reldif(`LEG2R'[6, 1], `LEG2C'[1, 5]) < 1e-12
* an impossible level refuses before anything runs
capture csdid_rif lrif, level(200)
assert _rc == 198

* LEG-4: an invalid replication count refuses BEFORE the RNG stream changes.
set seed 2026
scalar leg4_expected = runiform()
set seed 2026
capture csdid_rif lrif, wboot reps(0) seed(999)
assert _rc == 198
scalar leg4_observed = runiform()
assert leg4_observed == leg4_expected
scalar drop leg4_expected leg4_observed

* LEG-5: a user's own scalar under the old bridge name is neither read as a
* cluster count nor destroyed.
scalar __csdid_rif_nclust = 77
csdid_rif lrif
assert missing(e(N_clust))
confirm scalar __csdid_rif_nclust
assert __csdid_rif_nclust == 77
scalar drop __csdid_rif_nclust

* LEG-6: csdid_table refuses an unrelated estimator's results by name.
capture program drop _leg6_fake
program define _leg6_fake, eclass
    tempname b V
    matrix `b' = (10)
    matrix colnames `b' = x
    matrix `V' = (4)
    matrix rownames `V' = x
    matrix colnames `V' = x
    ereturn post `b' `V'
    ereturn scalar crit_val = 1.96
    ereturn scalar level = 95
    ereturn local cmd "_leg6_fake"
end
_leg6_fake
capture csdid_table
assert _rc == 459

* LEG-3: every tsvmat refusal fires before the dataset changes.
clear
set obs 1
generate double b = 99
tempname LGM
matrix `LGM' = (1,2 \ 3,4 \ 5,6)
capture tsvmat `LGM', name(a b)
assert _rc == 110
assert _N == 1
capture confirm variable a
assert _rc != 0
assert b[1] == 99
capture tsvmat `LGM', name(a b c)
assert _rc == 198
assert _N == 1
* fewer names than columns keeps its legacy meaning
tsvmat `LGM', name(only1)
assert _N == 3
assert only1[3] == 5

display "LEGACY OK: csgvar verified against csdid on both routes, bare and expression; four deprecated commands load; csdid_rif posts e(N)/e(sample) and leaves bb_/VV_/cln_ alone; csdid_table fills its t and CI columns from either e(cband) shape; tsvmat stores double and refuses before mutating; level provenance survives replay; the RNG stream survives a refused wboot"
