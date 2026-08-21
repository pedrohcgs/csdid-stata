---
title: "Speed against Version 1.82"
---

# Speed against Version 1.82

Version 1.82 is the `csdid` that SSC distributes today. The
[upgrading guide](upgrading-from-182.html) covers what changed in the
estimates; this page reports how long each version takes to produce them.
Our protocol is the median of 7 timed trials for 2.0.0 with one discarded
warmup; for Version 1.82 the trial count steps down (7, then 5, 3, 2) as
projected cost grows, and a cell projected past 120 seconds per call is
skipped and recorded. Each version is invoked in its own syntax in its own
fresh Stata process, on identical data with one covariate, at seed 20260729
throughout. To keep the comparison
about speed alone, we pin 2.0.0 to Version 1.82's defaults in every cell
(never-treated comparison group, varying base
period, and pair balancing on unbalanced panels), so that both versions
compute the same numbers and differ only in how long they take. The
workload is a doubly robust event study with clustered standard errors
throughout (the same specification in every table below). Timings depend
on the machine they were taken on, so the ratios travel better than the
seconds do. All the timings on this page were measured on 21 August 2026 with
StataNow/MP 19.5 on a 10-core Apple M1 Max, in the same session as the
[main speed tables](csdid-against-the-field.html#speed).

<div class="note" markdown="1">
Because 2.0.0 is pinned to the old defaults here, the times in the
2.0.0 column are not comparable to the shipped-defaults times in the
[main speed tables](csdid-against-the-field.html#speed), which run the
same engine under different estimand settings.
</div>

## By sample size

| n (T=10, G=4) | rows | 1.82 | 2.0.0 | gain |
| --- | ---: | ---: | ---: | ---: |
| 1,000 | 10,000 | 2.12s | 0.04s | 49x |
| 5,000 | 50,000 | 6.38s | 0.14s | 46x |
| 20,000 | 200,000 | 24.9s | 0.34s | 73x |
| 50,000 | 500,000 | 81.3s | 0.78s | **104x** |
| 100,000 | 1,000,000 | not run | 1.53s | &mdash; |

<p class="table-note" markdown="span">Version 1.82 was not timed in every cell &mdash; 100,000: skipped by the 120s cap; projection basis: measured 500k legacy call 81.3255s x 2.05 rows.</p>

The gain grows with the sample size, and then the comparison stops: at a
million rows, Version 1.82 projected past two and a half minutes per run,
so we did not run it and the last row reports 2.0.0 alone, which does the
same cell in 1.53 seconds.

## By number of periods

The number of periods is where the two versions differ most. Version
1.82's cost grows faster than linearly in the number of ATT(g,t) cells,
while 2.0.0's grows about linearly in them:

| T (n=5,000, G=4) | rows | 1.82 | 2.0.0 | gain |
| --- | ---: | ---: | ---: | ---: |
| 5 | 25,000 | 1.65s | 0.06s | 27x |
| 10 | 50,000 | 6.04s | 0.11s | 54x |
| 20 | 100,000 | 28.6s | 0.20s | 146x |
| 40 | 200,000 | 141.5s | 0.46s | **308x** |

At forty periods (a monthly panel over three and a half years), Version
1.82 takes over two minutes and 2.0.0 takes under half a second.

## By number of cohorts

| G (n=5,000, T=20) | rows | 1.82 | 2.0.0 | gain |
| --- | ---: | ---: | ---: | ---: |
| 3 | 100,000 | 22.7s | 0.21s | 106x |
| 6 | 100,000 | 47.2s | 0.24s | 194x |
| 12 | 100,000 | 103.1s | 0.44s | **232x** |

Only the number of adoption dates changes here. The data size is the same
in every row, so the growth down the Version 1.82 column is the cost of the extra
ATT(g,t) cells that more cohorts imply.

## By sampling scheme

| scheme (n=10,000, T=10, G=4) | rows | 1.82 | 2.0.0 | gain |
| --- | ---: | ---: | ---: | ---: |
| balanced panel | 100,000 | 13.3s | 0.19s | **71x** |
| unbalanced panel (15% of rows deleted) | 85,219 | 10.9s | 0.29s | 37x |
| repeated cross sections | 100,000 | 8.66s | 0.86s | 10x |

Repeated cross sections are the sampling scheme where 2.0.0 gains least,
and they set the low end of this page: 10x there against 308x at forty
periods, which are the two extremes across all four tables.

## Where the workload gains were certified

The per-workload comparison at fixed size (analytical, bootstrap,
weighted, clustered, and event-study variants, 10x to 35x) ships in the
package README with per-trial records, and it was produced by a
seven-trial A/B harness run against an installed copy of Version 1.82 at
its released commit. This page extends that comparison across sizes and
designs, and it does not replace those numbers or restate them. Neither
set of timings says anything about which version is more accurate, since
both compute the same estimates here.

[Back to the guides](../guides.html)
