---
title: Comparison groups
---

# Comparison groups: never-treated or not-yet-treated

Every ATT(g,t) compares cohort *g* against units that are untreated at time *t*.
Which units those are is your choice, and it is one of the few choices that can
change both what you estimate and whether you can estimate it at all.

- **Not-yet-treated** (the default) uses every unit not yet treated at *t*,
  which includes cohorts treated later.
- **`nevertreated`** uses only units never treated anywhere in the sample.

Not-yet-treated is the default because it uses more of the data, usually gives
tighter standard errors, and does not depend on a never-treated group existing
or being large enough to trust. R `did` and Stata `csdid` Version 1.82 both
default to never-treated instead; this is a deliberate departure from both, and
`nevertreated` restores their behaviour exactly.

## The data

```stata
import delimited using ///
    "https://raw.githubusercontent.com/pedrohcgs/JEL-DiD/50f4f18/data/county_mortality_data.csv", ///
    clear varnames(1) bindquote(strict) stringcols(_all)
destring deaths population_20_64 year yaca county_code stfips unemp_rate poverty_rate, ///
    replace force
generate double mrate = 100000 * deaths / population_20_64
drop if missing(mrate) | population_20_64 <= 0
generate int gvar = yaca
replace gvar = 0 if missing(gvar) | gvar > 2016
bysort county_code: generate byte nyears = _N
keep if nyears == 11
save "jel_balanced.dta", replace
```

## Not-yet-treated: the default

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
estat event
```

`e(control_group)` records what was used, so a run always says which group it
had rather than leaving you to infer it from the options you happened to type:

```stata
display "control group: " e(control_group)
```

`notyet` and `notyettreated` are accepted spellings of the same thing, and
either states the default explicitly.

## Never-treated

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) nevertreated rseed(20250101)
estat event
display "control group: " e(control_group)
```

The two runs usually give similar answers when the never-treated group is large
and comparable, as it is here. They diverge when it is not.

## When you have no never-treated units

This is where the choice stops being cosmetic. Drop every never-treated county
and the default still has a comparison group, because later-treated cohorts are
untreated at earlier periods:

```stata
use "jel_balanced.dta", clear
keep if gvar > 0
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
display "return code: " _rc
estat event
```

Ask the same data for `nevertreated` and there is nothing to honour the request
with. `csdid` does not stop: it says what it is doing and falls back to the
latest-treated cohort, which is what R `did` does in the same situation.

```stata
use "jel_balanced.dta", clear
keep if gvar > 0
csdid mrate, ivar(county_code) time(year) gvar(gvar) nevertreated rseed(20250101)
display "control group: " e(control_group)
```

Read that warning. The run succeeded, but not with the comparison group you
asked for, and the number it returns is a not-yet-treated estimate wearing a
never-treated label. If your design has no never-treated units, say `notyet` and
mean it rather than relying on the fallback.

The last-treated cohort now serves as the comparison group for the earlier ones.
It gets no ATT of its own — there is nothing left to compare it against — so it
is absent from the results table while still contributing as a control.

## Which to use

Keep the default, **not-yet-treated**, unless you have a reason not to. It uses
more data and often gives tighter standard errors, at the cost of assuming
parallel trends against later-treated cohorts too — including over periods where
those cohorts may already be anticipating treatment. If anticipation is a
concern, see [Anticipation](anticipation.html).

Prefer **`nevertreated`** when you have a large never-treated group you are
willing to defend as comparable, and you would rather rest on one fixed
comparison group whose identifying assumption is easy to state and to argue
about. It is also what you want when you are reproducing a result computed with
R `did` or with `csdid` Version 1.82, both of which default to it.

Under `nevertreated`, a never-treated group that is too small is refused rather
than quietly used: `csdid` stops when it is smaller than `#covariates + 5`. That
guard changes whether the command runs, never an estimate, and `notyet` is the
remedy it recommends — which is one of the reasons it is the default.

```stata
capture erase "jel_balanced.dta"
```
