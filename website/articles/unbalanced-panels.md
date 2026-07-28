---
title: Unbalanced panels
---

# Unbalanced panels

`csdid` detects an unbalanced `ivar()` panel and estimates it with the
repeated-cross-section computation and the standard-error accounting that goes
with it. **Units are never silently dropped to force balance**, because
dropping them changes the estimand — and silently changing an estimand is worse
than being slower.

## A worked example

The JEL panel is nearly balanced, so this creates the unbalancedness
deliberately and reproducibly, from the balanced sample:

## The data

Every guide on this site is self-contained: run this first and the rest of the
page follows. It is the county mortality panel from the
[JEL-DiD](https://github.com/pedrohcgs/JEL-DiD) replication package.

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
```

```stata
set seed 424242
generate double u = runiform()
drop if u < 0.15 & year >= 2012      // delete ~15% of later county-years

csdid mrate, ivar(county_code) time(year) gvar(gvar) rseed(20250101)
display "panel mode: " e(panel_mode)
display "units: "      e(N_units)
estat event
```

`e(panel_mode)` reports `allow_unbalanced`. `e(N_units)` is the number of
counties contributing — the cross-sectional unit count, which is what the
influence function and the standard errors are scaled by. `e(N)` remains the
observation count, as `e(N)` means everywhere in Stata.

## What actually changes

On a balanced panel each 2×2 cell is formed by differencing a unit over two
periods. When the panel is unbalanced that is not available for every unit, so
the estimator pools observations from both periods instead. Consequences worth
knowing:

- it is **slower** — roughly 2–4×, because each cell fits more regressions on
  more rows
- the guard on small cohorts is **stricter**, because cohort size is measured as
  observations divided by periods, which on an unbalanced panel is smaller than
  the distinct-unit count
- estimates are **not** comparable to a balanced-subset analysis: those are
  different samples answering different questions

If a run that used to work now refuses with "the never-treated group is too
small", the usual fix is `notyet`, which enlarges the comparison group.

Next: [repeated cross sections](repeated-cross-sections.html).
