---
title: Comparison groups
---

# Comparison groups: never-treated or not-yet-treated

Every ATT(g,t) compares cohort *g* against units that are untreated at time *t*.
Which units those are is your choice. It is one of the few options on this site
that can change both what you estimate and whether you can estimate it at all.

- **Not-yet-treated** (the default) uses every unit not yet treated at *t*,
  which includes cohorts treated later.
- **`nevertreated`** uses only units never treated anywhere in the sample.

<div class="note" markdown="1">
Not-yet-treated is the default because it uses more of the data, usually gives
tighter standard errors, and does not depend on a never-treated group existing
or being large enough to trust. We depart from R `did` and Stata `csdid`
Version 1.82 here; both of those default to never-treated, the older
convention. Type `nevertreated` and you get their behavior back exactly.
</div>

## The data

Let's build the balanced county sample once (the same sample used on the other
pages) and reuse it for every run below.

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

`e(control_group)` records what was used. A run says which group it had, in the
header and in the stored results. You never have to infer it from the options
you happened to type:

```stata
display "comparison group: " e(control_group)
```

`notyet` and `notyettreated` are accepted spellings of the same thing, and either
one states the default explicitly. That is what we would do in a do-file meant to
be read by somebody else. A reader who does not know the default cannot tell from
a bare command line which comparison group produced the numbers in front of them.

## Never-treated

```stata
use "jel_balanced.dta", clear
csdid mrate, ivar(county_code) time(year) gvar(gvar) nevertreated rseed(20250101)
estat event
display "comparison group: " e(control_group)
```

The two runs usually give similar answers when the never-treated group is large
and comparable, as it is here. They diverge when it is not. We would check either
way, since the second run costs nothing once the data are already in memory.

## When you have no never-treated units

Here the choice stops being cosmetic and starts deciding whether you get any
estimates at all. Drop every never-treated county
and the default still has a comparison group, because later-treated cohorts are
untreated at earlier periods:

```stata
use "jel_balanced.dta", clear
keep if gvar > 0
csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
display "return code: " _rc
estat event
```

The return code is zero. The event study prints as usual, with no error and no
warning.

Ask the same data for `nevertreated` and there is nothing to honor the request
with. `csdid` does not stop. It says what it is doing and falls back to the
latest-treated cohort. R `did` does the same thing in that situation.

```stata
use "jel_balanced.dta", clear
keep if gvar > 0
csdid mrate, ivar(county_code) time(year) gvar(gvar) nevertreated rseed(20250101)
display "comparison group: " e(control_group)
```

<div class="important" markdown="1">
Read that warning. The run succeeded with a different comparison group from the
one you asked for, and the number it returns is a not-yet-treated estimate. If
your design has no never-treated units, we would say `notyet` and mean it.
</div>

The last-treated cohort now serves as the comparison group for the earlier ones.
It gets no ATT of its own; there is nothing left to compare it against. It is
absent from the results table and still contributing as a control.

## Which to use

<div class="tip" markdown="1">
Keep the default, **not-yet-treated**, unless you have a reason not to, and in
our view that reason should be about the design rather than about the standard
errors. It uses more data and often gives tighter standard errors. The cost is
that parallel trends now has to hold against later-treated cohorts as well, over
periods in which those cohorts may already be anticipating treatment. If
anticipation is a concern, see [Anticipation](anticipation.html).
</div>

Prefer **`nevertreated`** when you have a large never-treated group that you are
willing to defend as comparable, and when you would rather rest on one fixed
comparison group whose identifying assumption is easy to state and to argue
about. Those are real advantages. It is also what you want when you are
reproducing a result computed with R `did` or with `csdid` Version 1.82.

Under `nevertreated`, a never-treated group that is too small is refused, and
`csdid` stops when it is smaller than `#covariates + 5`. Note that the guard
changes whether the command runs and never changes an estimate. The remedy it
recommends is `notyet`, which is one of the reasons that group is the default.
If you meet that message, the guard is telling you to use a different comparison
group, and loosening it would only hide the problem.

```stata
capture erase "jel_balanced.dta"
```
