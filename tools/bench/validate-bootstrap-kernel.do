version 15
clear all
set more off

args root
if `"`root'"' == "" local root "`c(pwd)'"
quietly do "`root'/src/mata/csdid.mata"

mata:
original = (0, 1, 2, 65535, 65536, 123456789, 2147483647, 2147483648, 4294967295)
values = original
reference = csdid__mt_temper_reference(values)
values = original
fast = csdid__mt_temper_fast(values)
st_matrix("TEMPER_CHECK", (original' , reference' , fast'))
st_numscalar("temper_maxdiff", max(abs(reference :- fast)))

state_reference = csdid__bmisc_rng_init(20240924)
state_fast = state_reference
csdid__bmisc_rng_twist(state_reference)
csdid__bmisc_rng_twist_fast(state_fast)
st_numscalar("twist_state_maxdiff", max(abs(state_reference :- state_fast)))
original = state_reference[2..625]
raw = original
reference = csdid__mt_temper_reference(raw)
raw = original
fast = csdid__mt_temper_fast(raw)
st_numscalar("temper_state_maxdiff", max(abs(reference :- fast)))
end

matrix list TEMPER_CHECK
display "temper_maxdiff=" %21.0g scalar(temper_maxdiff)
display "temper_state_maxdiff=" %21.0g scalar(temper_state_maxdiff)
display "twist_state_maxdiff=" %21.0g scalar(twist_state_maxdiff)
assert scalar(temper_maxdiff) == 0
assert scalar(temper_state_maxdiff) == 0
assert scalar(twist_state_maxdiff) == 0

exit 0
