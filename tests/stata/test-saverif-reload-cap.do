* ---------------------------------------------------------------------------
* A saved RIF artifact larger than this Stata's matrix limit is announced
* when it is written, and the reload refusal names a remedy that is true here.
*
* The reader (csdid_stats using) builds an n_units-row classic matrix, capped
* at c(max_matdim) from Stata 16 and at -set matsize- before; the writer has
* no cap. The write-time note sat inside the writer's quietly block and never
* printed, and the reload refusal told a Stata/MP user to use Stata/MP.
* ---------------------------------------------------------------------------
version 15
clear all
set more off
set linesize 200

local root "`c(pwd)'"
adopath ++ "`root'/src/ado"
adopath ++ "`root'/src/mata"

program define rc_log_has, rclass
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
    return scalar has = strpos(`"`body'"', `"`message'"') > 0
end

if c(stata_version) >= 16 local cap = c(max_matdim)
else local cap = c(matsize)
local n = `cap' + 1

* Two periods, one cohort treated in period 2, half never treated.
set obs `n'
generate long id = _n
generate byte g = cond(mod(id, 2), 2, 0)
expand 2
bysort id: generate byte t = _n
generate double y = mod(id, 7) / 7 + t + (g == 2 & t == 2) + mod(id * t, 5) / 10

tempfile big lg
log using "`lg'", text replace name(rc_cap)
csdid y, ivar(id) time(t) gvar(g) analytical saverif("`big'") replace
log close rc_cap
assert e(N_units) == `n'
rc_log_has using "`lg'", message("note: this artifact holds `n' unit rows")
assert r(has) == 1
* past 65,534 units no Stata can reload it, and the note must not suggest one
if `n' > 65534 {
    rc_log_has using "`lg'", message("no Stata can reload an artifact this large")
    assert r(has) == 1
}

log using "`lg'", text replace name(rc_cap)
capture noisily csdid_stats using "`big'", type(simple)
local rc = _rc
log close rc_cap
assert `rc' == 908
* the remedy must not send the user to the flavour already running
if c(MP) {
    rc_log_has using "`lg'", message("Stata/MP")
    assert r(has) == 0
}

display as text "test-saverif-reload-cap: an unreloadable artifact is announced when written"
